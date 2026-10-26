import AppKit
import CoreLocation
import CoreWLAN
import SystemConfiguration

/// Por dónde sale el Mac a internet: Wi-Fi (con el nombre de la red), cable u otra.
struct ConnectionInfo: Equatable {
    enum Kind { case wifi, ethernet, other, none }

    var kind: Kind
    /// Nombre de la red Wi-Fi. macOS solo lo da a las apps con permiso de ubicación.
    var name: String?
    /// "5 GHz · Wi-Fi 6 · señal excelente"
    var detail: String = ""

    /// Texto de una línea para el widget.
    var summary: String {
        switch kind {
        case .wifi:
            let network = name.map { "Wi-Fi «\($0)»" } ?? "Wi-Fi (nombre oculto: falta permiso de Localización)"
            return ([network] + (detail.isEmpty ? [] : [detail])).joined(separator: " · ")
        case .ethernet: return "Por cable" + (detail.isEmpty ? "" : " · \(detail)")
        case .other: return detail.isEmpty ? "Otra conexión" : detail
        case .none: return "Sin conexión"
        }
    }
}

@MainActor
final class ConnectionReader: NSObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()
    /// Se llama cuando cambia el permiso (para volver a leer el nombre de la red).
    var onAuthorizationChange: (() -> Void)?

    override init() {
        super.init()
        location.delegate = self
    }

    var canReadNetworkName: Bool {
        let status = location.authorizationStatus
        return status == .authorizedAlways || status == .authorized
    }

    /// macOS pide la ubicación para dar el nombre de la red Wi-Fi (por él se puede saber dónde estás).
    /// Monitor no usa ni guarda la ubicación.
    func requestNetworkNameAccess() {
        if location.authorizationStatus == .notDetermined {
            // Una app sin Dock tiene que estar activa para que macOS muestre la pregunta.
            NSApp.activate(ignoringOtherApps: true)
            location.requestWhenInUseAuthorization()
        }
    }

    /// Para el menú: pedir el permiso o, si ya se negó, abrir Ajustes en Localización.
    func openNetworkNameSettings() {
        if location.authorizationStatus == .notDetermined {
            requestNetworkNameAccess()
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onAuthorizationChange?() }
    }

    func read() -> ConnectionInfo {
        let primary = Self.primaryInterface()
        let wifi = CWWiFiClient.shared().interface()
        guard let primary else { return ConnectionInfo(kind: .none) }

        if let wifi, wifi.interfaceName == primary, wifi.ssid() != nil || wifi.wlanChannel() != nil {
            return ConnectionInfo(kind: .wifi, name: wifi.ssid(), detail: Self.wifiDetail(wifi))
        }
        if primary.hasPrefix("en") { return ConnectionInfo(kind: .ethernet) }
        if primary.hasPrefix("utun") || primary.hasPrefix("ipsec") || primary.hasPrefix("ppp") {
            return ConnectionInfo(kind: .other, detail: "VPN")
        }
        if primary.hasPrefix("bridge") || primary.hasPrefix("ap") {
            return ConnectionInfo(kind: .other, detail: "Compartida desde el iPhone")
        }
        return ConnectionInfo(kind: .other, detail: primary)
    }

    /// Interfaz por la que sale el tráfico ahora ("en0"…).
    private static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Monitor" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return value["PrimaryInterface"] as? String
    }

    private static func wifiDetail(_ wifi: CWInterface) -> String {
        var parts: [String] = []
        switch wifi.wlanChannel()?.channelBand {
        case .band2GHz: parts.append("2,4 GHz")
        case .band5GHz: parts.append("5 GHz")
        case .band6GHz: parts.append("6 GHz")
        default: break
        }
        // CWPHYMode: 4 = 802.11n, 5 = ac, 6 = ax, 7 = be.
        switch wifi.activePHYMode().rawValue {
        case 7: parts.append("Wi-Fi 7")
        case 6: parts.append("Wi-Fi 6")
        case 5: parts.append("Wi-Fi 5")
        case 4: parts.append("Wi-Fi 4")
        default: break
        }
        let rssi = wifi.rssiValue()
        if rssi != 0 {
            parts.append(rssi >= -60 ? "señal excelente" : rssi >= -70 ? "señal buena" : rssi >= -80 ? "señal débil" : "señal muy débil")
        }
        return parts.joined(separator: " · ")
    }
}
