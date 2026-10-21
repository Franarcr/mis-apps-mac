import AppKit
import CoreAudio
import CoreAudioTaps

/// Una app que usa el audio, con todos sus procesos de sonido.
struct AudioApp {
    let bundleID: String
    let name: String
    let icon: NSImage?
    var objectIDs: [AudioObjectID]
    var isPlaying: Bool
}

/// Guarda el volumen elegido para cada app y mantiene un tap para cada una que no esté al 100 %.
/// Las apps al 100 % no se tocan: su sonido va directo a la salida, como siempre.
@MainActor
final class VolumeController {
    static let maxVolume: Float = 1.5

    private var taps: [String: VOLAppTap] = [:]
    /// Último error al crear un tap, para mostrarlo en el menú.
    private(set) var lastError: String?

    /// Volumen de cada app que no está al 100 %, por identificador del paquete.
    private var volumes: [String: Float] {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: "volumes") ?? [:]
            return stored.compactMapValues { ($0 as? NSNumber)?.floatValue }
        }
        set { UserDefaults.standard.set(newValue.mapValues(Double.init), forKey: "volumes") }
    }

    var hasChanges: Bool { !volumes.isEmpty }

    func start() {
        VOLSystem.observeChanges { [weak self] in
            MainActor.assumeIsolated { self?.apply() }
        }
        apply()
    }

    func volume(for bundleID: String) -> Float { volumes[bundleID] ?? 1 }

    func setVolume(_ volume: Float, for bundleID: String) {
        var all = volumes
        all[bundleID] = abs(volume - 1) < 0.02 ? nil : volume
        volumes = all
        if let tap = taps[bundleID], let volume = all[bundleID] {
            tap.volume = volume
        } else {
            apply()
        }
    }

    func resetAll() {
        volumes = [:]
        apply()
    }

    func stopAll() {
        taps.values.forEach { $0.invalidate() }
        taps = [:]
    }

    /// Apps con procesos de audio, ordenadas por nombre.
    func apps() -> [AudioApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var apps: [String: AudioApp] = [:]
        for process in VOLSystem.processes() where process.pid != ownPID {
            guard let owner = owner(of: process, among: running), let id = owner.bundleIdentifier else { continue }
            var app = apps[id] ?? AudioApp(bundleID: id, name: owner.localizedName ?? id, icon: owner.icon,
                                           objectIDs: [], isPlaying: false)
            app.objectIDs.append(process.objectID)
            app.isPlaying = app.isPlaying || process.isRunningOutput
            apps[id] = app
        }
        return apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// La app a la que pertenece un proceso de audio: ella misma o, si es un proceso auxiliar
    /// (com.google.Chrome.helper, com.apple.WebKit.GPU…), la app cuyo identificador encaja.
    private func owner(of process: VOLProcess, among apps: [NSRunningApplication]) -> NSRunningApplication? {
        if let app = apps.first(where: { $0.processIdentifier == process.pid }) { return app }
        let id = process.bundleID
        if id.hasPrefix("com.apple.WebKit") { return apps.first { $0.bundleIdentifier == "com.apple.Safari" } }
        return apps.filter { app in app.bundleIdentifier.map { id.hasPrefix($0 + ".") } ?? false }
            .max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }
    }

    /// Crea, rehace o quita los taps según los volúmenes, los procesos de cada app y la salida de sonido.
    /// Se llama al cambiar un volumen, al abrirse o cerrarse procesos con audio y al cambiar de salida.
    func apply() {
        let output = VOLSystem.defaultOutputDeviceUID()
        let volumes = self.volumes
        let current = Dictionary(uniqueKeysWithValues: apps().map { ($0.bundleID, $0) })
        func processes(_ id: String) -> [NSNumber]? {
            current[id].map { $0.objectIDs.sorted().map { NSNumber(value: $0) } }
        }

        for (id, tap) in taps where volumes[id] == nil || processes(id) != tap.processes || tap.outputDeviceUID != output {
            tap.invalidate()
            taps[id] = nil
        }
        guard let output else { return }
        for (id, volume) in volumes where taps[id] == nil {
            guard let objectIDs = processes(id), let app = current[id] else { continue }
            do {
                let tap = try VOLAppTap(processes: objectIDs, outputDeviceUID: output)
                tap.volume = volume
                taps[id] = tap
                lastError = nil
            } catch {
                lastError = "\(app.name): \(error.localizedDescription)"
            }
        }
    }
}
