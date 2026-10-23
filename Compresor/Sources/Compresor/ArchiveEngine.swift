import CArchive
import Foundation

struct ArchiveItem: Identifiable, Hashable {
    let id: Int          // posición en el archivo
    let path: String
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?
    let encrypted: Bool

    var name: String { (path as NSString).lastPathComponent }
}

struct ArchiveListing {
    let format: String
    let items: [ArchiveItem]

    var hasEncryptedItems: Bool { items.contains(where: \.encrypted) }
    var totalSize: Int64 { items.compactMap(\.size).reduce(0, +) }
}

enum CreateFormat: String, CaseIterable, Identifiable {
    case zip, sevenZip, tarGz, tarXz

    var id: String { rawValue }
    var title: String {
        switch self {
        case .zip: "ZIP"
        case .sevenZip: "7z"
        case .tarGz: "TAR.GZ"
        case .tarXz: "TAR.XZ"
        }
    }
    var fileExtension: String {
        switch self {
        case .zip: "zip"
        case .sevenZip: "7z"
        case .tarGz: "tar.gz"
        case .tarXz: "tar.xz"
        }
    }
    /// libarchive solo cifra al escribir ZIP (AES-256).
    var supportsPassword: Bool { self == .zip }
}

enum ArchiveError: LocalizedError {
    case cannotOpen(String)
    case needsPassword
    case wrongPassword
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let d): "No se pudo abrir el archivo comprimido. \(d)"
        case .needsPassword: "El archivo está protegido con contraseña."
        case .wrongPassword: "La contraseña no es correcta."
        case .failed(let d): d
        case .cancelled: "Operación cancelada."
        }
    }
}

/// Avance de una operación larga; `cancelled` se comprueba entre bloques.
final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var _fraction = 0.0
    private var _current = ""
    private var _cancelled = false

    var fraction: Double { lock.withLock { _fraction } }
    var current: String { lock.withLock { _current } }
    var cancelled: Bool {
        get { lock.withLock { _cancelled } }
        set { lock.withLock { _cancelled = newValue } }
    }

    func update(_ fraction: Double, _ current: String? = nil) {
        lock.withLock {
            _fraction = min(max(fraction, 0), 1)
            if let current { _current = current }
        }
    }
}

enum ArchiveEngine {
    /// Extensiones que se abren como archivo comprimido (el resto de archivos se comprimen).
    static let archiveExtensions: Set<String> = [
        "zip", "zipx", "7z", "rar", "r00", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "lzma", "iso",
        "cab", "lha", "lzh", "cpio", "xar", "pkg", "jar", "war", "apk", "cbz", "cbr", "cb7", "cbt",
    ]

    static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return archiveExtensions.contains(url.pathExtension.lowercased()) || name.hasSuffix(".tar.gz")
            || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tar.xz")
    }

    // MARK: Lectura

    private static func openReader(_ url: URL, password: String?) throws -> OpaquePointer {
        guard let a = archive_read_new() else { throw ArchiveError.cannotOpen("") }
        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)
        if let password, !password.isEmpty { archive_read_add_passphrase(a, password) }
        let parts = volumes(of: url)
        let status: Int32
        if parts.count > 1 {
            // RAR en varias partes: libarchive las lee como un único archivo, en orden.
            var cStrings = parts.map { strdup($0.path) }
            defer { cStrings.forEach { free($0) } }
            cStrings.append(nil)
            status = cStrings.withUnsafeMutableBufferPointer { buffer in
                buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                    archive_read_open_filenames(a, $0, 1 << 16)
                }
            }
        } else {
            status = archive_read_open_filename(a, url.path, 1 << 16)
        }
        guard status == ARCHIVE_OK else {
            let message = errorMessage(a)
            archive_read_free(a)
            throw ArchiveError.cannotOpen(friendly(message))
        }
        return a
    }

    /// Partes de un RAR dividido, en orden: "x.part1.rar, x.part2.rar…" o "x.rar, x.r00, x.r01…".
    /// Si se abre cualquier parte, se empieza por la primera. Si no está dividido, devuelve solo `url`.
    static func volumes(of url: URL) -> [URL] {
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []

        if let match = name.range(of: #"\.part\d+\.rar$"#, options: [.regularExpression, .caseInsensitive]) {
            let stem = String(name[..<match.lowerBound]).lowercased()
            let parts = siblings.compactMap { sibling -> (Int, URL)? in
                let lower = sibling.lowercased()
                guard lower.hasPrefix(stem + ".part"), lower.hasSuffix(".rar"),
                      let n = Int(lower.dropFirst(stem.count + 5).dropLast(4)) else { return nil }
                return (n, folder.appendingPathComponent(sibling))
            }
            return parts.count > 1 ? parts.sorted { $0.0 < $1.0 }.map(\.1) : [url]
        }

        let ext = url.pathExtension.lowercased()
        let isOldStyle = ext == "rar" || (ext.count == 3 && ext.hasPrefix("r") && Int(ext.dropFirst()) != nil)
        guard isOldStyle else { return [url] }
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        let numbered = siblings.compactMap { sibling -> (Int, URL)? in
            let candidate = URL(fileURLWithPath: sibling)
            let e = candidate.pathExtension.lowercased()
            guard candidate.deletingPathExtension().lastPathComponent.lowercased() == stem,
                  e.count == 3, e.hasPrefix("r"), let n = Int(e.dropFirst()) else { return nil }
            return (n, folder.appendingPathComponent(sibling))
        }
        guard !numbered.isEmpty,
              let first = siblings.first(where: { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.lowercased() == stem
                  && URL(fileURLWithPath: $0).pathExtension.lowercased() == "rar" }) else { return [url] }
        return [folder.appendingPathComponent(first)] + numbered.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Mensajes de libarchive más claros para los casos habituales.
    private static func friendly(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("encrypt") || message.localizedCaseInsensitiveContains("passphrase") {
            return rarEncryptedMessage
        }
        return message
    }

    static let rarEncryptedMessage = "Este archivo usa un cifrado que la biblioteca de compresión de macOS no puede abrir (por ejemplo, un RAR con contraseña). Ábrelo con WinRAR o The Unarchiver."

    static func list(_ url: URL) throws -> ArchiveListing {
        let a = try openReader(url, password: nil)
        defer { archive_read_free(a) }
        var items: [ArchiveItem] = []
        var entry: OpaquePointer?
        var format = ""
        while true {
            let status = archive_read_next_header(a, &entry)
            if status == ARCHIVE_EOF { break }
            if status < ARCHIVE_WARN { throw ArchiveError.failed(friendly("El archivo está dañado: \(errorMessage(a))")) }
            if format.isEmpty, let name = archive_format_name(a) { format = String(cString: name) }
            guard let entry, let path = entryPath(entry) else { continue }
            let mtime = archive_entry_mtime(entry)
            items.append(ArchiveItem(
                id: items.count,
                path: path,
                isDirectory: ca_entry_is_directory(entry) != 0 || path.hasSuffix("/"),
                size: archive_entry_size_is_set(entry) != 0 ? archive_entry_size(entry) : nil,
                modified: mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil,
                encrypted: archive_entry_is_encrypted(entry) != 0))
            archive_read_data_skip(a)
        }
        return ArchiveListing(format: format, items: items)
    }

    /// Extrae todo (o solo `only`, por índice) en `destination`. Devuelve los archivos y carpetas de primer nivel creados.
    @discardableResult
    static func extract(_ url: URL, to destination: URL, only: Set<Int>? = nil, password: String?,
                        progress: Progress) throws -> [URL] {
        let a = try openReader(url, password: password)
        defer { archive_read_free(a) }
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let total = Double((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 1)
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        var created: [URL] = []
        var entry: OpaquePointer?
        var index = -1

        while true {
            if progress.cancelled { throw ArchiveError.cancelled }
            let status = archive_read_next_header(a, &entry)
            if status == ARCHIVE_EOF { break }
            if status < ARCHIVE_WARN { throw ArchiveError.failed("El archivo está dañado: \(errorMessage(a))") }
            index += 1
            guard let entry, let raw = entryPath(entry) else { continue }
            if let only, !only.contains(index) { archive_read_data_skip(a); continue }
            guard let relative = safeRelativePath(raw) else { archive_read_data_skip(a); continue }
            let target = destination.appendingPathComponent(relative)
            progress.update(Double(archive_filter_bytes(a, -1)) / total, relative)

            let top = destination.appendingPathComponent(String(relative.split(separator: "/").first ?? ""))
            if !created.contains(top) { created.append(top) }

            if ca_entry_is_directory(entry) != 0 || raw.hasSuffix("/") {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            guard ca_entry_is_file(entry) != 0 else { archive_read_data_skip(a); continue } // enlaces: se omiten
            if archive_entry_is_encrypted(entry) != 0 {
                // libarchive no descifra RAR: pedir la contraseña no serviría de nada.
                if let format = archive_format_name(a), String(cString: format).localizedCaseInsensitiveContains("RAR") {
                    throw ArchiveError.failed(rarEncryptedMessage)
                }
                if password?.isEmpty ?? true { throw ArchiveError.needsPassword }
            }

            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: target.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: target) else {
                throw ArchiveError.failed("No se pudo escribir \(relative)")
            }
            defer { try? handle.close() }
            while true {
                if progress.cancelled { throw ArchiveError.cancelled }
                let n = buffer.withUnsafeMutableBytes { archive_read_data(a, $0.baseAddress, $0.count) }
                if n == 0 { break }
                if n < 0 {
                    let message = errorMessage(a)
                    try? fm.removeItem(at: target)
                    if archive_entry_is_encrypted(entry) != 0 { throw ArchiveError.wrongPassword }
                    throw ArchiveError.failed("Error al extraer \(relative): \(message)")
                }
                buffer.withUnsafeBytes { handle.write(Data($0.prefix(n))) }
            }
            let perm = archive_entry_perm(entry) & 0o777
            if perm != 0 { try? fm.setAttributes([.posixPermissions: perm | 0o600], ofItemAtPath: target.path) }
            let mtime = archive_entry_mtime(entry)
            if mtime > 0 {
                try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: TimeInterval(mtime))],
                                      ofItemAtPath: target.path)
            }
        }
        progress.update(1)
        return created
    }

    /// Ruta dentro del destino, sin "/" inicial ni componentes ".." (evita escribir fuera de la carpeta).
    static func safeRelativePath(_ path: String) -> String? {
        let parts = path.split(separator: "/").filter { $0 != "." && !$0.isEmpty }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        return parts.joined(separator: "/")
    }

    // MARK: Escritura

    static func create(from sources: [URL], to destination: URL, format: CreateFormat, password: String?,
                       progress: Progress) throws {
        guard let a = archive_write_new() else { throw ArchiveError.failed("No se pudo crear el archivo") }
        defer { archive_write_free(a) }
        switch format {
        case .zip:
            archive_write_set_format_zip(a)
            if let password, !password.isEmpty {
                archive_write_set_options(a, "zip:encryption=aes256")
                archive_write_set_passphrase(a, password)
            }
        case .sevenZip:
            archive_write_set_format_7zip(a)
        case .tarGz:
            archive_write_set_format_pax_restricted(a)
            archive_write_add_filter_gzip(a)
        case .tarXz:
            archive_write_set_format_pax_restricted(a)
            archive_write_add_filter_xz(a)
        }
        let partial = destination.appendingPathExtension("part")
        guard archive_write_open_filename(a, partial.path) == ARCHIVE_OK else {
            throw ArchiveError.failed("No se pudo crear \(destination.lastPathComponent): \(errorMessage(a))")
        }

        // Lista de archivos a añadir, con su ruta dentro del comprimido.
        var files: [(url: URL, path: String, isDirectory: Bool, size: Int64)] = []
        let skip: Set<String> = [".DS_Store"]
        for source in sources {
            // Las rutas se comparan ya resueltas: /var/… y /private/var/… son la misma carpeta.
            let root = source.resolvingSymlinksInPath().path
            func add(_ url: URL) {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
                guard values?.isSymbolicLink != true, !skip.contains(url.lastPathComponent) else { return }
                let inside = String(url.resolvingSymlinksInPath().path.dropFirst(root.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let relative = inside.isEmpty ? source.lastPathComponent : source.lastPathComponent + "/" + inside
                files.append((url, relative, values?.isDirectory ?? false, Int64(values?.fileSize ?? 0)))
            }
            add(source)
            if (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               let walker = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) {
                for case let url as URL in walker { add(url) }
            }
        }
        let totalBytes = max(1, files.reduce(0) { $0 + $1.size })
        var written: Int64 = 0

        do {
            for file in files {
                if progress.cancelled { throw ArchiveError.cancelled }
                progress.update(Double(written) / Double(totalBytes), file.path)
                guard let entry = archive_entry_new() else { continue }
                defer { archive_entry_free(entry) }
                archive_entry_set_pathname_utf8(entry, file.isDirectory ? file.path + "/" : file.path)
                let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path)
                let mtime = (attributes?[.modificationDate] as? Date) ?? Date()
                archive_entry_set_mtime(entry, time_t(mtime.timeIntervalSince1970), 0)
                let perm = (attributes?[.posixPermissions] as? NSNumber)?.uint16Value ?? (file.isDirectory ? 0o755 : 0o644)
                archive_entry_set_perm(entry, mode_t(perm))
                if file.isDirectory {
                    ca_entry_set_directory(entry)
                    archive_entry_set_size(entry, 0)
                } else {
                    ca_entry_set_file(entry)
                    archive_entry_set_size(entry, file.size)
                }
                guard archive_write_header(a, entry) >= ARCHIVE_WARN else {
                    throw ArchiveError.failed("Error al añadir \(file.path): \(errorMessage(a))")
                }
                if !file.isDirectory, let handle = try? FileHandle(forReadingFrom: file.url) {
                    defer { try? handle.close() }
                    while true {
                        if progress.cancelled { throw ArchiveError.cancelled }
                        let chunk = handle.readData(ofLength: 1 << 16)
                        if chunk.isEmpty { break }
                        let n = chunk.withUnsafeBytes { archive_write_data(a, $0.baseAddress, chunk.count) }
                        if n < 0 { throw ArchiveError.failed("Error al escribir \(file.path): \(errorMessage(a))") }
                        written += Int64(chunk.count)
                        progress.update(Double(written) / Double(totalBytes))
                    }
                }
                archive_write_finish_entry(a)
            }
            guard archive_write_close(a) == ARCHIVE_OK else {
                throw ArchiveError.failed("No se pudo terminar el archivo: \(errorMessage(a))")
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
            progress.update(1)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    // MARK: Utilidades

    private static func entryPath(_ entry: OpaquePointer) -> String? {
        if let utf8 = archive_entry_pathname_utf8(entry) { return String(cString: utf8) }
        if let raw = archive_entry_pathname(entry) { return String(cString: raw) }
        return nil
    }

    private static func errorMessage(_ a: OpaquePointer) -> String {
        archive_error_string(a).map { String(cString: $0) } ?? "Error desconocido"
    }

    /// "Informe.zip", "Informe 2.zip"… el primer nombre libre en la carpeta.
    static func uniqueURL(in folder: URL, name: String, extension ext: String?) -> URL {
        func candidate(_ n: Int) -> URL {
            let base = n == 1 ? name : "\(name) \(n)"
            return folder.appendingPathComponent(ext.map { "\(base).\($0)" } ?? base)
        }
        var n = 1
        while FileManager.default.fileExists(atPath: candidate(n).path) { n += 1 }
        return candidate(n)
    }

    /// Nombre base sin extensiones de comprimido ("datos.tar.gz" → "datos").
    static func baseName(_ url: URL) -> String {
        var name = url.lastPathComponent
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz"] where name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        name = (name as NSString).deletingPathExtension
        return name.isEmpty ? "Archivo" : name
    }
}
