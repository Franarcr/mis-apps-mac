import Foundation
import IOKit.ps

/// Un dispositivo con batería: el Mac o un accesorio Bluetooth conectado.
struct DeviceBattery: Identifiable, Equatable {
    struct Level: Equatable {
        /// Parte del dispositivo ("Izq.", "Der.", "Estuche"); `nil` si solo tiene una batería.
        let label: String?
        let percent: Int
    }

    let id: String
    let name: String
    let symbol: String
    let levels: [Level]
    var charging = false
    /// Texto extra, p. ej. el tiempo restante del Mac.
    var detail: String?
}

enum DeviceBatteryReader {
    /// El Mac primero y después los accesorios Bluetooth, ordenados por nombre.
    static func readAll() -> [DeviceBattery] {
        var devices: [DeviceBattery] = []
        if let mac = macBattery() { devices.append(mac) }
        devices += bluetoothBatteries().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return devices
    }

    // MARK: Mac

    static func macBattery() -> DeviceBattery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }

            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let percent = current * 100 / maximum
            var detail: String
            if charging, let minutes = d[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
                detail = "Carga completa en \(duration(minutes))"
            } else if charging {
                detail = "Cargando"
            } else if pluggedIn {
                detail = percent >= 99 ? "Cargada" : "Conectado a la corriente"
            } else if let minutes = d[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                detail = "Quedan \(duration(minutes))"
            } else {
                detail = "Calculando tiempo restante…"
            }
            return DeviceBattery(id: "mac", name: Host.current().localizedName ?? "Mac", symbol: "laptopcomputer",
                                 levels: [.init(label: nil, percent: percent)], charging: charging, detail: detail)
        }
        return nil
    }

    private static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    // MARK: Bluetooth

    /// Accesorios conectados que informan de su batería (teclado, ratón, trackpad, AirPods, auriculares…).
    static func bluetoothBatteries() -> [DeviceBattery] {
        guard let data = run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        var devices: [DeviceBattery] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let parts: [(key: String, label: String?)] = [
                        ("device_batteryLevelMain", nil),
                        ("device_batteryLevelLeft", "Izq."),
                        ("device_batteryLevelRight", "Der."),
                        ("device_batteryLevelCase", "Estuche"),
                    ]
                    let levels = parts.compactMap { part -> DeviceBattery.Level? in
                        guard let text = info[part.key] as? String,
                              let percent = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { return nil }
                        return .init(label: part.label, percent: percent)
                    }
                    guard !levels.isEmpty else { continue }
                    let address = info["device_address"] as? String ?? name
                    devices.append(DeviceBattery(id: address, name: name,
                                                 symbol: symbol(for: name, type: info["device_minorType"] as? String),
                                                 levels: levels))
                }
            }
        }
        return devices
    }

    private static func symbol(for name: String, type: String?) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        switch type?.lowercased() ?? "" {
        case "keyboard": return "keyboard"
        case "mouse": return "magicmouse"
        case "trackpad": return "rectangle.and.hand.point.up.left"
        case "headphones", "headset": return "headphones"
        case "speaker": return "hifispeaker"
        case "gamepad", "game controller": return "gamecontroller"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    private static func run(_ path: String, _ arguments: [String]) -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? data : nil
    }
}

/// Lee las baterías cada 30 segundos en segundo plano.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var devices: [DeviceBattery] = []
    private var timer: Timer?
    private var loading = false

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let devices = DeviceBatteryReader.readAll()
            DispatchQueue.main.async {
                self.devices = devices
                self.loading = false
            }
        }
    }

    /// Lectura inmediata (para la imagen de prueba).
    func refreshNow() { devices = DeviceBatteryReader.readAll() }

    func setDevices(_ devices: [DeviceBattery]) { self.devices = devices }
}
