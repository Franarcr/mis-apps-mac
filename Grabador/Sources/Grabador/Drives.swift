import AppKit
import DiskArbitration

/// Una unidad donde se puede grabar: un disco externo entero (USB, tarjeta SD…).
struct Drive: Identifiable, Equatable {
    let id: String          // "disk4"
    let name: String        // "SanDisk Ultra"
    let size: Int64
    let bus: String         // "USB", "Secure Digital"…
    let removable: Bool
    let virtual: Bool
    let volumes: [String]   // nombres de lo que tiene dentro, para reconocerla

    var deviceNode: String { "/dev/\(id)" }
    var rawNode: String { "/dev/r\(id)" }
    var isCard: Bool { bus.localizedCaseInsensitiveContains("Secure Digital") || name.localizedCaseInsensitiveContains("SD") && removable }
    var symbol: String { virtual ? "externaldrive.badge.icloud" : isCard ? "sdcard" : "externaldrive" }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    /// "SanDisk Ultra · 32 GB · USB"
    var summary: String { [name, sizeText, bus].filter { !$0.isEmpty }.joined(separator: " · ") }
}

enum DiskUtil {
    /// Ejecuta diskutil y devuelve su salida.
    @discardableResult
    static func run(_ arguments: [String]) -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    static func plist(_ arguments: [String]) -> [String: Any]? {
        let output = run(arguments).output
        return (try? PropertyListSerialization.propertyList(from: output, format: nil)) as? [String: Any]
    }

    /// Disco físico donde está macOS (nunca se ofrece, aunque arranques desde uno externo).
    static func systemDisks() -> Set<String> {
        var disks: Set<String> = []
        guard let info = plist(["info", "-plist", "/"]) else { return disks }
        if let parent = info["ParentWholeDisk"] as? String { disks.insert(parent) }
        for store in info["APFSPhysicalStores"] as? [[String: Any]] ?? [] {
            if let id = store["APFSPhysicalStore"] as? String { disks.insert(wholeDisk(of: id)) }
        }
        return disks
    }

    /// "disk4s2" → "disk4"
    static func wholeDisk(of id: String) -> String {
        guard let range = id.range(of: #"^disk\d+"#, options: .regularExpression) else { return id }
        return String(id[range])
    }

    /// Discos externos enteros. Los internos y el del sistema no aparecen nunca.
    static func externalDrives(includeVirtual: Bool) -> [Drive] {
        guard let list = plist(["list", "-plist", "external"] + (includeVirtual ? [] : ["physical"])) else { return [] }
        let system = systemDisks()
        let entries = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        var drives: [Drive] = []
        for id in list["WholeDisks"] as? [String] ?? [] where !system.contains(id) {
            guard let info = plist(["info", "-plist", id]) else { continue }
            if info["Internal"] as? Bool == true || info["SystemImage"] as? Bool == true { continue }
            let isVirtual = (info["VirtualOrPhysical"] as? String) == "Virtual"
            // Los contenedores APFS son discos "sintetizados": se graba en su disco físico, no en ellos.
            if info["APFSPhysicalStores"] != nil { continue }
            let size = (info["TotalSize"] as? NSNumber)?.int64Value ?? (info["Size"] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { continue } // lector de tarjetas vacío
            let entry = entries.first { $0["DeviceIdentifier"] as? String == id }
            var volumes = (entry?["Partitions"] as? [[String: Any]] ?? []).compactMap { $0["VolumeName"] as? String }
            if let name = entry?["VolumeName"] as? String { volumes.append(name) }
            volumes = volumes.filter { !$0.isEmpty && $0 != "EFI" }
            let rawName = (info["MediaName"] as? String) ?? (info["IORegistryEntryName"] as? String) ?? id
            let name = rawName.replacingOccurrences(of: " Media", with: "").trimmingCharacters(in: .whitespaces)
            drives.append(Drive(id: id, name: name.isEmpty ? id : name, size: size,
                                bus: (info["BusProtocol"] as? String) ?? "",
                                removable: (info["RemovableMedia"] as? Bool) ?? (info["Removable"] as? Bool) ?? false,
                                virtual: isVirtual, volumes: volumes))
        }
        return drives
    }
}

/// Lista de unidades que se actualiza sola al conectar o quitar una (DiskArbitration).
@MainActor
final class DriveList: ObservableObject {
    @Published private(set) var drives: [Drive] = []
    @Published private(set) var loading = true

    /// Para pruebas: mostrar también imágenes de disco montadas (`defaults write com.fran.grabador mostrarVirtuales -bool YES`).
    let includeVirtual = UserDefaults.standard.bool(forKey: "mostrarVirtuales")

    private var session: DASession?
    private var pending: DispatchWorkItem?
    var paused = false

    init() {
        refresh()
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, { _, context in
            guard let context else { return }
            let list = Unmanaged<DriveList>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { list.scheduleRefresh() }
        }, context)
        DARegisterDiskDisappearedCallback(session, nil, { _, context in
            guard let context else { return }
            let list = Unmanaged<DriveList>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { list.scheduleRefresh() }
        }, context)
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
    }

    /// Varios avisos seguidos (un disco y sus particiones) se juntan en una sola lectura.
    func scheduleRefresh() {
        guard !paused else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func refresh() {
        let includeVirtual = includeVirtual
        DispatchQueue.global(qos: .userInitiated).async {
            let drives = DiskUtil.externalDrives(includeVirtual: includeVirtual)
            DispatchQueue.main.async {
                self.drives = drives
                self.loading = false
            }
        }
    }
}
