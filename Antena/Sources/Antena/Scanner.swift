import AppKit
import CoreLocation
import CoreWLAN
import Foundation

/// Escanea las redes cada pocos segundos y conserva su historial de señal.
@MainActor
final class Scanner: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var networks: [String: WiFiNetwork] = [:]
    @Published var paused = false { didSet { if !paused { scanSoon(after: 0) } } }
    @Published private(set) var status = "Preparando…"
    @Published private(set) var problem: String?
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentBSSID = ""
    @Published private(set) var currentSSID = ""
    @Published private(set) var interfaceName = ""
    @Published private(set) var lastScan: Date?
    @Published private(set) var connection: Connection?
    @Published private(set) var scanning = false
    @Published var notes: [String: String] = UserDefaults.standard.dictionary(forKey: "notas") as? [String: String] ?? [:] {
        didSet {
            UserDefaults.standard.set(notes, forKey: "notas")
            NotesIndex.shared.notes = notes
        }
    }

    private let location = CLLocationManager()
    private let queue = DispatchQueue(label: "com.fran.antena.escaneo")
    private var next: DispatchWorkItem?
    private var started = false

    var interval: Double { max(2, UserDefaults.standard.object(forKey: "intervalo") as? Double ?? 3) }
    var forgetAfter: Double { UserDefaults.standard.object(forKey: "olvidarTras") as? Double ?? 120 }

    var locationAllowed: Bool {
        locationStatus == .authorizedAlways || locationStatus == .authorized
    }

    override init() {
        super.init()
        location.delegate = self
        NotesIndex.shared.notes = notes
        locationStatus = location.authorizationStatus
    }

    func start() {
        guard !started else { return }
        started = true
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        }
        scanSoon(after: 0)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.locationStatus = s
            if self.locationAllowed { self.networks = self.networks.filter { !$0.key.hasPrefix("sin-permiso-") } }
            self.scanSoon(after: 0)
        }
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func scanSoon(after seconds: Double) {
        next?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        next = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func scan() {
        guard !paused, !scanning else { return }
        scanning = true
        queue.async { [weak self] in
            let client = CWWiFiClient.shared()
            let iface = client.interface()
            var result: Result<[CWNetwork], Error>
            var name = "", bssid = "", ssid = ""
            var noise = 0
            var conn: Connection? = nil
            if let iface {
                name = iface.interfaceName ?? ""
                bssid = iface.bssid()?.uppercased() ?? ""
                ssid = iface.ssid() ?? ""
                noise = iface.noiseMeasurement()
                if let ch = iface.wlanChannel(), iface.rssiValue() != 0 {
                    conn = Connection(ssid: ssid, bssid: bssid, channel: ch.channelNumber,
                                      band: ch.channelBand == .band2GHz ? .b24 : ch.channelBand == .band6GHz ? .b6 : .b5,
                                      width: [.width40MHz: 40, .width80MHz: 80, .width160MHz: 160][ch.channelWidth] ?? 20,
                                      rssi: iface.rssiValue(), noise: noise, txRate: iface.transmitRate(),
                                      phy: Connection.phyName(iface.activePHYMode()))
                }
                if !iface.powerOn() {
                    result = .failure(NSError(domain: "Antena", code: 1,
                                              userInfo: [NSLocalizedDescriptionKey: "El Wi-Fi está apagado."]))
                } else {
                    do { result = .success(Array(try iface.scanForNetworks(withName: nil, includeHidden: true))) }
                    catch { result = .failure(error) }
                }
            } else {
                result = .failure(NSError(domain: "Antena", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "Este Mac no tiene interfaz Wi-Fi."]))
            }
            let now = Date()
            let parsed: [WiFiNetwork]? = try? result.get().enumerated().map { WiFiNetwork.make(from: $0.element, index: $0.offset, now: now, interfaceNoise: noise, interfaceBand: conn?.band) }
            var error: String? = nil
            if case .failure(let e) = result { error = e.localizedDescription }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.interfaceName = name
                    self.currentBSSID = bssid
                    self.currentSSID = ssid
                    self.connection = conn
                    if let parsed { self.merge(parsed, now: now) }
                    self.problem = error
                    self.scanning = false
                    self.lastScan = now
                    self.scanSoon(after: self.interval)
                }
            }
        }
    }

    private func merge(_ list: [WiFiNetwork], now: Date) {
        // Las filas sin BSSID (de antes de tener permiso) no se pueden seguir: se cambian en cada escaneo.
        var all = networks.filter { !$0.key.hasPrefix("sin-permiso-") }
        for var n in list {
            if let old = all[n.id] {
                n.firstSeen = old.firstSeen
                n.history = old.history + n.history
                let limit = now.addingTimeInterval(-15 * 60)
                if let firstKept = n.history.firstIndex(where: { $0.date >= limit }), firstKept > 0 {
                    n.history.removeFirst(firstKept)
                }
            }
            all[n.id] = n
        }
        // Las redes que dejan de verse se olvidan pasado un rato.
        all = all.filter { now.timeIntervalSince($0.value.lastSeen) <= forgetAfter }
        networks = all
        status = "\(all.count) redes"
    }

    func clear() {
        networks = [:]
        scanSoon(after: 0)
    }

    // MARK: Avisos

    func warnings(for n: WiFiNetwork) -> [(level: Int, text: String)] {
        var w: [(Int, String)] = []
        if n.rssi < -80 { w.append((2, "Señal muy débil (\(n.rssi) dBm)")) }
        else if n.rssi < -70 { w.append((1, "Señal débil (\(n.rssi) dBm)")) }
        if n.noise == 0 {
        } else if n.snr < 15 { w.append((2, "Relación señal/ruido baja (\(n.snr) dB)")) }
        else if n.snr < 25 { w.append((1, "Relación señal/ruido justa (\(n.snr) dB)")) }
        if n.band == .b24 && ![1, 6, 11].contains(n.channel) {
            w.append((1, "Canal \(n.channel) se solapa con los canales 1, 6 y 11"))
        }
        if n.band == .b24 && n.width == 40 { w.append((1, "Canal de 40 MHz en 2,4 GHz: ocupa casi toda la banda")) }
        if n.utilization >= 70 { w.append((2, "Canal muy ocupado (\(n.utilization) %)")) }
        else if n.utilization >= 50 { w.append((1, "Canal bastante ocupado (\(n.utilization) %)")) }
        if n.security == "Abierta" { w.append((2, "Red abierta, sin cifrado")) }
        if n.security == "WEP" { w.append((2, "WEP es inseguro")) }
        else if n.weakCipher { w.append((1, "Usa WPA/TKIP, un cifrado antiguo")) }
        let same = networks.values.filter { $0.id != n.id && $0.band == n.band && abs($0.centerChannel - n.centerChannel) * 5 < Double($0.width + n.width) / 2 }
        if same.count >= 4 { w.append((1, "\(same.count) redes más comparten el mismo espacio de canal")) }
        if n.wps { w.append((1, "WPS activado")) }
        return w
    }
}


/// La conexión actual del Mac.
struct Connection: Equatable {
    var ssid: String
    var bssid: String
    var channel: Int
    var band: Band
    var width: Int
    var rssi: Int
    var noise: Int
    var txRate: Double
    var phy: String

    static func phyName(_ m: CWPHYMode) -> String {
        switch m {
        case .mode11a: return "802.11a"
        case .mode11b: return "802.11b"
        case .mode11g: return "802.11g"
        case .mode11n: return "Wi-Fi 4"
        case .mode11ac: return "Wi-Fi 5"
        case .mode11ax: return "Wi-Fi 6"
        default: return m.rawValue == 7 ? "Wi-Fi 7" : ""
        }
    }
}
