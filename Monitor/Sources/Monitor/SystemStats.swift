import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Uso total de CPU (0…1) a partir de los ticks acumulados entre dos lecturas.
final class CPUSampler {
    private var previous: host_cpu_load_info?

    func sample() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        defer { previous = info }
        guard let p = previous else { return nil }

        let user = Double(info.cpu_ticks.0 &- p.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- p.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- p.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- p.cpu_ticks.3)
        let total = user + system + idle + nice
        return total > 0 ? (user + system + nice) / total : nil
    }
}

enum MemoryStats {
    /// Memoria usada como la calcula el Monitor de Actividad: app + fija + comprimida.
    static func used() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - UInt64(min(stats.purgeable_count, stats.internal_page_count))
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    static let total = ProcessInfo.processInfo.physicalMemory
}

/// Convierte contadores acumulados en velocidades (bytes por segundo).
struct RateCounter {
    private var previous: (a: UInt64, b: UInt64, time: Date)?

    mutating func rates(a: UInt64, b: UInt64) -> (Double, Double)? {
        let now = Date()
        defer { previous = (a, b, now) }
        guard let p = previous else { return nil }
        let dt = now.timeIntervalSince(p.time)
        // Si un contador se reinicia (o da la vuelta), se descarta esa muestra.
        guard dt > 0, a >= p.a, b >= p.b else { return (0, 0) }
        return (Double(a - p.a) / dt, Double(b - p.b) / dt)
    }
}

enum NetworkStats {
    /// Bytes recibidos y enviados por las interfaces físicas (Wi-Fi, Ethernet).
    static func totals() -> (received: UInt64, sent: UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }

        var received: UInt64 = 0, sent: UInt64 = 0
        var cursor = list
        while let entry = cursor {
            let ifa = entry.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               String(cString: ifa.ifa_name).hasPrefix("en"),
               let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }
            cursor = ifa.ifa_next
        }
        return (received, sent)
    }
}

enum DiskStats {
    /// Bytes leídos y escritos por todos los discos desde el arranque.
    static func totals() -> (read: UInt64, written: UInt64) {
        var read: UInt64 = 0, written: UInt64 = 0
        forEachService("IOBlockStorageDriver") { service in
            if let stats = property(service, "Statistics") as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
        }
        return (read, written)
    }

    static func space() -> (free: Int64, total: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return (free, Int64(total))
    }
}

enum GPUStats {
    /// Uso de la GPU (0…1) que publica el driver gráfico; `nil` si no está disponible.
    static func utilization() -> Double? {
        var best: Double?
        forEachService("IOAccelerator") { service in
            if let perf = property(service, "PerformanceStatistics") as? [String: Any],
               let value = (perf["Device Utilization %"] as? NSNumber)?.doubleValue {
                best = max(best ?? 0, value / 100)
            }
        }
        return best
    }
}

struct BatteryInfo: Equatable {
    var percent: Int
    var charging: Bool
    var pluggedIn: Bool
}

enum BatteryStats {
    static func read() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatteryInfo(percent: current * 100 / maximum,
                               charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                               pluggedIn: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

struct ProcessUsage: Equatable {
    let name: String
    let cpu: Double
}

enum ProcessStats {
    /// Los procesos que más CPU usan ahora mismo (100 % = un núcleo completo).
    static func top(_ count: Int) -> [ProcessUsage] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pcpu=,comm=", "-r"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .prefix(count)
            .compactMap { line in
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let cpu = Double(parts[0].replacingOccurrences(of: ",", with: ".")) else { return nil }
                return ProcessUsage(name: String(parts[1]), cpu: cpu)
            }
    }
}

// MARK: - IOKit

private func forEachService(_ className: String, _ body: (io_object_t) -> Void) {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
    defer { IOObjectRelease(iterator) }
    var service = IOIteratorNext(iterator)
    while service != 0 {
        body(service)
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
}

private func property(_ service: io_object_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

// MARK: - Temperatura y consumo

/// Temperatura del chip (°C): la más alta de los sensores del procesador ("PMU tdie…").
/// macOS no tiene una API pública para esto; se usan las funciones de IOHIDEventSystem que
/// también usan otras apps de monitorización. No necesita permisos.
enum ThermalStats {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?

    private static let temperatureEvent: Int64 = 15

    private struct API {
        /// El cliente tiene que seguir vivo mientras se leen sus sensores.
        let client: AnyObject
        let copyEvent: CopyEvent
        let getFloat: GetFloat
        /// Sensores del chip, buscados una sola vez.
        let sensors: [AnyObject]
    }

    private static let api: API? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let copyServices = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let getFloat = dlsym(handle, "IOHIDEventGetFloatValue"),
              let copyProperty = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let client = unsafeBitCast(create, to: Create.self)(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        _ = unsafeBitCast(setMatching, to: SetMatching.self)(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let services = unsafeBitCast(copyServices, to: CopyServices.self)(client)?.takeRetainedValue() as? [AnyObject] ?? []
        let product = unsafeBitCast(copyProperty, to: CopyProperty.self)
        // En Apple Silicon los sensores del chip se llaman "PMU tdie1", "PMU2 tdie3"…
        var sensors = services.filter { service in
            (product(service, "Product" as CFString)?.takeRetainedValue() as? String)?.contains("tdie") == true
        }
        if sensors.isEmpty { sensors = services }   // otros modelos: el máximo de todos
        return API(client: client, copyEvent: unsafeBitCast(copyEvent, to: CopyEvent.self),
                   getFloat: unsafeBitCast(getFloat, to: GetFloat.self), sensors: sensors)
    }()

    static func chipTemperature() -> Double? {
        guard let api else { return nil }
        var hottest: Double?
        for sensor in api.sensors {
            guard let event = api.copyEvent(sensor, temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let value = api.getFloat(event, Int32(temperatureEvent << 16))
            if value > 0, value < 130 { hottest = max(hottest ?? 0, value) }
        }
        return hottest
    }

    /// Estado térmico que publica macOS: a partir de "Alto" baja la velocidad del procesador para enfriarse.
    static var state: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Templado"
        case .serious: return "Alto"
        case .critical: return "Crítico"
        @unknown default: return ""
        }
    }

    static var isThrottling: Bool { ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue }
}

enum PowerStats {
    /// Consumo total del Mac en vatios, según la batería (en Mac de sobremesa no está disponible).
    static func systemWatts() -> Double? {
        var watts: Double?
        forEachService("AppleSmartBattery") { service in
            if let telemetry = property(service, "PowerTelemetryData") as? [String: Any],
               let load = (telemetry["SystemLoad"] as? NSNumber)?.doubleValue, load > 0, load < 1_000_000 {
                watts = load / 1000
            }
        }
        return watts
    }
}
