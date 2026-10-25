import Foundation
import CryptoKit
import DiskArbitration
import Security
import CGrabador

enum Log {
    private static let file: URL = {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Grabador")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("grabador.log")
    }()

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }
}

struct FlashProgress {
    enum Phase { case preparing, writing, verifying, finishing }
    var phase: Phase = .preparing
    var fraction: Double = 0
    var bytes: Int64 = 0
    var speed: Double = 0          // bytes por segundo
    var remaining: TimeInterval?   // segundos
}

struct FlashResult {
    let bytes: Int64
    let seconds: TimeInterval
    let sha256: String
    let verified: Bool
}

enum FlashError: LocalizedError {
    case cancelled, authorizationDenied, unmountFailed(String), open(String), write(String), tooLarge(Int64, Int64), verifyMismatch

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Grabación cancelada. La unidad puede haber quedado a medias: vuelve a grabarla o formatéala."
        case .authorizationDenied: return "No se concedió el permiso de administrador, así que no se ha tocado la unidad."
        case .unmountFailed(let detail): return "No se pudo expulsar el contenido de la unidad para grabarla. ¿Hay algún archivo abierto en ella? \(detail)"
        case .open(let detail): return "No se pudo abrir la unidad: \(detail)"
        case .write(let detail): return "Falló la escritura: \(detail). Prueba con otro puerto o con otra unidad."
        case .tooLarge(let image, let drive):
            return "La imagen (\(ByteCountFormatter.string(fromByteCount: image, countStyle: .file))) no cabe en la unidad (\(ByteCountFormatter.string(fromByteCount: drive, countStyle: .file)))."
        case .verifyMismatch: return "La verificación falló: lo leído de la unidad no coincide con la imagen. La unidad puede estar dañada o ser falsa."
        }
    }
}

/// Graba una imagen en una unidad (o en un archivo, para las pruebas) y luego la verifica.
final class Flasher {
    enum Target {
        case drive(Drive)
        case file(URL)   // solo para --prueba
    }

    static let chunk = 4 << 20   // 4 MB
    static let sector = 512

    private let lock = NSLock()
    private var _cancelled = false
    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); _cancelled = newValue; lock.unlock() }
    }

    var verify = true
    var eject = true

    func cancel() { cancelled = true }

    /// Hace todo el trabajo en el hilo que la llama (no en el principal). `progress` se llama a menudo.
    func run(image: DiskImage, target: Target, progress: @escaping (FlashProgress) -> Void) throws -> FlashResult {
        let start = Date()
        var state = FlashProgress()
        progress(state)

        let capacity: Int64?
        if case .drive(let drive) = target { capacity = drive.size } else { capacity = nil }
        if let capacity, let size = image.imageSize, size > capacity { throw FlashError.tooLarge(size, capacity) }

        let reader = try ImageReader(image)
        defer { reader.close() }

        // 1. Abrir el destino.
        let fd: Int32
        switch target {
        case .file(let url):
            fd = Darwin.open(url.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
            if fd < 0 { throw FlashError.open(String(cString: strerror(errno))) }
        case .drive(let drive):
            Log.write("Grabando \(image.name) en \(drive.id) (\(drive.summary))")
            try Self.unmount(drive)
            MountBlocker.shared.block(drive.id)
            fd = try Self.openWithAuthorization(drive)
        }
        defer {
            Darwin.close(fd)
            if case .drive(let drive) = target {
                MountBlocker.shared.block(nil)
                if eject {
                    let result = DiskUtil.run(["eject", drive.deviceNode])
                    Log.write("Expulsar \(drive.id): \(result.status == 0 ? "bien" : String(decoding: result.output, as: UTF8.self))")
                }
            }
        }
        if cancelled { throw FlashError.cancelled }

        var buffer: UnsafeMutableRawPointer?
        guard posix_memalign(&buffer, 4096, Self.chunk) == 0, let buffer else { throw FlashError.write("sin memoria") }
        defer { free(buffer) }

        // 2. Grabar, calculando la huella de lo que se escribe.
        var hasher = SHA256()
        var written: Int64 = 0
        let total = image.imageSize
        let speed = SpeedMeter()
        state.phase = .writing
        var lastReport = Date.distantPast
        while true {
            if cancelled { throw FlashError.cancelled }
            let n = try reader.read(into: buffer, count: Self.chunk)
            if n == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: n))
            // Los discos solo admiten escrituras de sectores completos: el final se rellena con ceros.
            let padded = (n + Self.sector - 1) / Self.sector * Self.sector
            if padded > n { memset(buffer + n, 0, padded - n) }
            if let capacity, written + Int64(padded) > capacity { throw FlashError.tooLarge(written + Int64(padded), capacity) }
            try Self.writeAll(fd, buffer, padded)
            written += Int64(n)

            if Date().timeIntervalSince(lastReport) > 0.2 {
                lastReport = Date()
                state.bytes = written
                state.speed = speed.add(written)
                state.fraction = total.map { Double(written) / Double(max($0, 1)) } ?? Double(reader.consumed) / Double(max(image.fileSize, 1))
                state.remaining = state.speed > 0 ? Double((total ?? Int64(Double(written) / max(state.fraction, 0.001))) - written) / state.speed : nil
                progress(state)
            }
        }
        _ = fcntl(fd, F_FULLFSYNC)
        fsync(fd)
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        Log.write("Escritos \(written) bytes en \(Int(Date().timeIntervalSince(start))) s · SHA-256 \(digest)")

        // 3. Verificar: volver a leer lo grabado y comparar la huella.
        var verified = false
        if verify {
            state.phase = .verifying
            state.fraction = 0
            progress(state)
            guard lseek(fd, 0, SEEK_SET) == 0 else { throw FlashError.write("no se pudo volver al principio para verificar") }
            var check = SHA256()
            var read: Int64 = 0
            let verifySpeed = SpeedMeter()
            lastReport = .distantPast
            while read < written {
                if cancelled { throw FlashError.cancelled }
                let wanted = Int(min(Int64(Self.chunk), written - read))
                let aligned = (wanted + Self.sector - 1) / Self.sector * Self.sector
                try Self.readAll(fd, buffer, aligned)
                check.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: wanted))
                read += Int64(wanted)
                if Date().timeIntervalSince(lastReport) > 0.2 {
                    lastReport = Date()
                    state.bytes = read
                    state.speed = verifySpeed.add(read)
                    state.fraction = Double(read) / Double(written)
                    state.remaining = state.speed > 0 ? Double(written - read) / state.speed : nil
                    progress(state)
                }
            }
            let readDigest = check.finalize().map { String(format: "%02x", $0) }.joined()
            Log.write("Verificación: \(readDigest == digest ? "coincide" : "NO coincide (\(readDigest))")")
            guard readDigest == digest else { throw FlashError.verifyMismatch }
            verified = true
        }

        state.phase = .finishing
        state.fraction = 1
        progress(state)
        return FlashResult(bytes: written, seconds: Date().timeIntervalSince(start), sha256: digest, verified: verified)
    }

    // MARK: Ayudas

    private static func writeAll(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) throws {
        var done = 0
        while done < count {
            let r = Darwin.write(fd, buffer + done, count - done)
            if r < 0 {
                if errno == EINTR { continue }
                throw FlashError.write(String(cString: strerror(errno)))
            }
            done += r
        }
    }

    private static func readAll(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) throws {
        var done = 0
        while done < count {
            let r = Darwin.read(fd, buffer + done, count - done)
            if r < 0 {
                if errno == EINTR { continue }
                throw FlashError.write("al leer para verificar: \(String(cString: strerror(errno)))")
            }
            if r == 0 { throw FlashError.verifyMismatch }
            done += r
        }
    }

    /// Desmonta todos los volúmenes de la unidad (no hace falta ser administrador).
    private static func unmount(_ drive: Drive) throws {
        var result = DiskUtil.run(["unmountDisk", drive.deviceNode])
        if result.status != 0 {
            Log.write("unmountDisk falló, se fuerza: \(String(decoding: result.output, as: UTF8.self))")
            result = DiskUtil.run(["unmountDisk", "force", drive.deviceNode])
        }
        guard result.status == 0 else {
            throw FlashError.unmountFailed(String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Abre /dev/rdiskN para leer y escribir. macOS pide la contraseña de administrador con su propio
    /// cuadro (la app nunca la ve) y `authopen` devuelve el archivo ya abierto por un socket.
    private static func openWithAuthorization(_ drive: Drive) throws -> Int32 {
        var authRef: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess, let authRef else {
            throw FlashError.authorizationDenied
        }
        defer { AuthorizationFree(authRef, []) }

        let right = "sys.openfile.readwrite.\(drive.rawNode)"
        let prompt = "Grabador necesita tu contraseña para borrar y grabar «\(drive.name)» (\(drive.sizeText))."
        let status: OSStatus = right.withCString { rightName in
            prompt.withCString { promptText in
                var item = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
                var promptItem = AuthorizationItem(name: kAuthorizationEnvironmentPrompt, valueLength: strlen(promptText),
                                                   value: UnsafeMutableRawPointer(mutating: promptText), flags: 0)
                return withUnsafeMutablePointer(to: &item) { itemPointer in
                    withUnsafeMutablePointer(to: &promptItem) { promptPointer in
                        var rights = AuthorizationRights(count: 1, items: itemPointer)
                        var environment = AuthorizationEnvironment(count: 1, items: promptPointer)
                        return AuthorizationCopyRights(authRef, &rights, &environment,
                                                       [.interactionAllowed, .extendRights, .preAuthorize], nil)
                    }
                }
            }
        }
        guard status == errAuthorizationSuccess else {
            Log.write("Autorización denegada (\(status))")
            throw FlashError.authorizationDenied
        }

        var external = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(authRef, &external) == errAuthorizationSuccess else { throw FlashError.authorizationDenied }

        var sockets: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { throw FlashError.open("socketpair") }
        defer { Darwin.close(sockets[0]) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/authopen")
        process.arguments = ["-stdoutpipe", "-extauth", "-o", String(O_RDWR), drive.rawNode]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
        let errors = Pipe()
        process.standardError = errors
        do { try process.run() } catch {
            Darwin.close(sockets[1])
            throw FlashError.open(error.localizedDescription)
        }
        withUnsafeBytes(of: &external) { input.fileHandleForWriting.write(Data($0)) }
        try? input.fileHandleForWriting.close()

        let fd = cg_receive_fd(sockets[0])
        process.waitUntilExit()
        if fd < 0 || process.terminationStatus != 0 {
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            Log.write("authopen falló (\(process.terminationStatus)): \(detail)")
            if fd >= 0 { Darwin.close(fd) }
            throw FlashError.open(detail.isEmpty ? "permiso denegado" : detail)
        }
        return fd
    }
}

/// Velocidad media de los últimos segundos.
private final class SpeedMeter {
    private var samples: [(time: Date, bytes: Int64)] = []

    func add(_ bytes: Int64) -> Double {
        let now = Date()
        samples.append((now, bytes))
        samples.removeAll { now.timeIntervalSince($0.time) > 5 }
        guard let first = samples.first, now.timeIntervalSince(first.time) > 0.3 else { return 0 }
        return Double(bytes - first.bytes) / now.timeIntervalSince(first.time)
    }
}

/// Mientras se graba, impide que macOS monte las particiones nuevas que van apareciendo en la unidad
/// (si no, saldría el aviso «El disco que has insertado no se puede leer» a mitad de la grabación).
final class MountBlocker {
    static let shared = MountBlocker()

    private let lock = NSLock()
    private var target: String?
    private var session: DASession?

    func block(_ disk: String?) {
        lock.lock()
        target = disk
        lock.unlock()
        guard disk != nil, session == nil else { return }
        DispatchQueue.main.sync {
            guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
            self.session = session
            DARegisterDiskMountApprovalCallback(session, nil, { disk, _ in
                guard let name = DADiskGetBSDName(disk).map({ String(cString: $0) }),
                      MountBlocker.shared.isBlocked(name) else { return nil }
                let dissenter = DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnBusy), "Grabador está grabando esta unidad" as CFString)
                return Unmanaged.passRetained(dissenter)
            }, nil)
            DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
        }
    }

    func isBlocked(_ bsdName: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let target else { return false }
        return bsdName == target || bsdName.hasPrefix(target + "s")
    }
}
