import CoreWLAN
import Foundation

enum Band: Double, CaseIterable, Identifiable, Comparable {
    case b24 = 2.4, b5 = 5, b6 = 6
    var id: Double { rawValue }
    var title: String {
        switch self {
        case .b24: return "2,4 GHz"
        case .b5: return "5 GHz"
        case .b6: return "6 GHz"
        }
    }
    static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue }

    func frequency(channel ch: Int) -> Int {
        switch self {
        case .b24: return ch == 14 ? 2484 : 2407 + 5 * ch
        case .b5: return 5000 + 5 * ch
        case .b6: return 5950 + 5 * ch
        }
    }
}

struct SignalSample: Hashable {
    var date: Date
    var rssi: Int
}

/// Una red (un punto de acceso) vista en el escaneo.
struct WiFiNetwork: Identifiable, Hashable {
    var id: String
    var ssid: String
    var bssid: String
    var vendor: String
    var rssi: Int
    var noise: Int
    var channel: Int
    var band: Band
    var width: Int
    var centerChannel: Double
    var centerFrequency: Int
    var security: String
    var weakCipher: Bool
    var generation: Int
    var generationName: String
    var phyModes: String
    var maxRate: Double
    var minRate: Double
    var basicRates: String
    var streams: Int
    var stations: Int
    var utilization: Int
    var country: String
    var beaconInterval: Int
    var fastTransition: Bool
    var wps: Bool
    var deviceName: String
    var htProtection: String
    var adHoc: Bool
    var elements: [InfoElements.Element]
    var firstSeen: Date
    var lastSeen: Date
    var history: [SignalSample] = []

    /// Señal/ruido. macOS solo mide el ruido del canal de la red conectada; si no hay medida, vale -999.
    var snr: Int { noise != 0 ? rssi - noise : -999 }
    var snrLabel: String { noise != 0 ? "\(snr) dB" : "—" }
    var noiseLabel: String { noise != 0 ? "\(noise) dBm" : "—" }
    var signalPercent: Int { quality }
    /// Para ordenar por nota (se rellena al mostrar la tabla).
    var noteKey: String { NotesIndex.shared[id] }
    var streamsLabel: String { "\(streams)" }
    var channelLabel: String { "\(channel)" }
    var frequencyLabel: String { "\(centerFrequency) MHz" }
    var stationsLabel: String { stations >= 0 ? "\(stations)" : "—" }
    var displayName: String { ssid.isEmpty ? "Red oculta" : ssid }
    var quality: Int { max(0, min(100, 2 * (rssi + 100))) }
    var widthLabel: String { "\(width) MHz" }
    var maxRateLabel: String { maxRate > 0 ? "\(Int(maxRate.rounded())) Mbps" : "—" }

    static func == (a: WiFiNetwork, b: WiFiNetwork) -> Bool {
        a.id == b.id && a.rssi == b.rssi && a.lastSeen == b.lastSeen && a.channel == b.channel
    }
    func hash(into h: inout Hasher) { h.combine(id) }

    static func make(from n: CWNetwork, index: Int, now: Date, interfaceNoise: Int, interfaceBand: Band?) -> WiFiNetwork {
        let ie = InfoElements.parse(n.informationElementData)
        // El nombre puede venir vacío en `ssid` pero estar en los datos crudos o en la baliza.
        let ssid: String = {
            if let s = n.ssid, !s.isEmpty { return s }
            if let d = n.ssidData, !d.isEmpty, d.contains(where: { $0 != 0 }) { return String(decoding: d, as: UTF8.self) }
            if let e = ie.elements.first(where: { $0.number == 0 && $0.ext == nil }),
               !e.summary.trimmingCharacters(in: .controlCharacters).isEmpty { return e.summary }
            return ""
        }()
        let bssid = (n.bssid ?? "").uppercased()
        let ch = n.wlanChannel
        let channel = ch?.channelNumber ?? ie.dsChannel ?? 0
        let band: Band = {
            switch ch?.channelBand {
            case .band2GHz: return .b24
            case .band6GHz: return .b6
            default: return channel <= 14 ? .b24 : .b5
            }
        }()
        var width: Int = {
            switch ch?.channelWidth {
            case .width40MHz: return 40
            case .width80MHz: return 80
            case .width160MHz: return 160
            default: return 20
            }
        }()
        if let w = ie.ehtWidth, w == 4 { width = 320 }

        // Canal central según el ancho.
        var center = Double(channel)
        if width == 40 {
            if ie.htSecondaryOffset == 1 { center += 2 } else if ie.htSecondaryOffset == 3 { center -= 2 }
            else if band != .b24 { center = Double(((channel - (band == .b6 ? 1 : 36)) / 8) * 8 + (band == .b6 ? 1 : 36) + 2) }
        } else if width >= 80 {
            if width == 320, ie.ehtCenter > 0 { center = Double(ie.ehtCenter) }
            else if band == .b6, ie.he6Seg0 > 0 { center = Double(width == 160 && ie.he6Seg1 > 0 ? ie.he6Seg1 : ie.he6Seg0) }
            else if ie.vhtSeg0 > 0 {
                if width == 160 && ie.vhtSeg1 > 0 { center = Double(ie.vhtSeg1) }
                else if width == 160 && ie.vhtWidth == 2 { center = Double(ie.vhtSeg0) }
                else { center = Double(ie.vhtSeg0) }
            } else if ie.ehtCenter > 0 { center = Double(ie.ehtCenter) }
        }
        let centerFreq = band.frequency(channel: Int(center.rounded()))

        // Generación y modos.
        let generation = ie.eht ? 7 : ie.he ? 6 : ie.vht ? 5 : ie.ht ? 4 : 0
        var modes: [String] = []
        if band == .b24 {
            if ie.rates.contains(where: { [1, 2, 5.5, 11].contains($0) }) { modes.append("b") }
            if ie.rates.contains(where: { $0 > 11 && $0 != 22 }) { modes.append("g") }
        } else if band == .b5 { modes.append("a") }
        if ie.ht { modes.append("n") }
        if ie.vht { modes.append("ac") }
        if ie.he { modes.append("ax") }
        if ie.eht { modes.append("be") }
        let generationName: String = {
            switch generation {
            case 7: return "Wi-Fi 7"
            case 6: return band == .b6 ? "Wi-Fi 6E" : "Wi-Fi 6"
            case 5: return "Wi-Fi 5"
            case 4: return "Wi-Fi 4"
            default: return modes.last.map { "802.11\($0)" } ?? "802.11"
            }
        }()

        let streams = max(1, ie.eht || ie.he ? ie.heStreams : ie.vht ? ie.vhtStreams : ie.htStreams)
        let maxRate: Double = {
            let perStream: Double
            switch generation {
            case 7: perStream = [20: 172.1, 40: 344.1, 80: 720.6, 160: 1441.2, 320: 2882.4][width] ?? 172.1
            case 6: perStream = [20: 143.4, 40: 286.8, 80: 600.5, 160: 1201.0][width] ?? 143.4
            case 5:
                let sgi = ie.vhtSGI80
                perStream = [20: sgi ? 86.7 : 78, 40: sgi ? 200 : 180, 80: sgi ? 433.3 : 390, 160: sgi ? 866.7 : 780][width] ?? 86.7
            case 4:
                perStream = width >= 40 ? (ie.htSGI40 ? 150 : 135) : (ie.htSGI20 ? 72.2 : 65)
            default:
                return ie.rates.max() ?? 0
            }
            return perStream * Double(streams)
        }()

        // Seguridad.
        var security = "Abierta"
        let akms = Set(ie.akms)
        if ie.hasRSN {
            if akms.contains(18) { security = "Abierta mejorada (OWE)" }
            else if akms.contains(12) || akms.contains(13) { security = "WPA3 Empresarial" }
            else if !akms.isDisjoint(with: [8, 9, 24, 25]) {
                security = !akms.isDisjoint(with: [2, 4, 6]) ? "WPA2/WPA3 Personal" : "WPA3 Personal"
            } else if !akms.isDisjoint(with: [2, 4, 6]) { security = ie.hasWPA ? "WPA/WPA2 Personal" : "WPA2 Personal" }
            else if !akms.isDisjoint(with: [1, 3, 5]) { security = ie.hasWPA ? "WPA/WPA2 Empresarial" : "WPA2 Empresarial" }
            else { security = "WPA2" }
        } else if ie.hasWPA {
            security = "WPA"
        } else if n.supportsSecurity(.WEP) || n.supportsSecurity(.dynamicWEP) {
            security = "WEP"
        }
        let weakCipher = security == "WEP" || ie.hasWPA || ie.pairwise.contains(2)

        let protection: String = {
            switch ie.htProtection {
            case 0: return "Ninguna"
            case 1: return "Miembro no HT"
            case 2: return "20 MHz"
            case 3: return "Mixta"
            default: return ""
            }
        }()

        let rssi = n.rssiValue
        return WiFiNetwork(
            id: bssid.isEmpty ? "sin-permiso-\(index)" : bssid,
            ssid: ssid,
            bssid: bssid,
            vendor: bssid.isEmpty ? "" : Vendors.shared.lookup(bssid),
            rssi: rssi,
            noise: n.noiseMeasurement != 0 ? n.noiseMeasurement : (interfaceBand == band ? interfaceNoise : 0),
            channel: channel,
            band: band,
            width: width,
            centerChannel: center,
            centerFrequency: centerFreq,
            security: security,
            weakCipher: weakCipher,
            generation: generation,
            generationName: generationName,
            phyModes: modes.joined(separator: "/"),
            maxRate: maxRate,
            minRate: ie.rates.min() ?? 0,
            basicRates: ie.basicRates.map { InfoElements.rate($0) }.joined(separator: ", "),
            streams: streams,
            stations: ie.stations ?? -1,
            utilization: ie.utilization ?? -1,
            country: ie.country ?? n.countryCode ?? "",
            beaconInterval: n.beaconInterval,
            fastTransition: ie.mobilityDomain || !Set(ie.akms).isDisjoint(with: [3, 4, 9]),
            wps: ie.wps,
            deviceName: ie.wpsDeviceName ?? ie.wpsModel ?? "",
            htProtection: protection,
            adHoc: n.ibss,
            elements: ie.elements,
            firstSeen: now,
            lastSeen: now,
            history: [SignalSample(date: now, rssi: rssi)]
        )
    }
}

/// Acceso rápido a las notas para ordenar la columna «Nota».
final class NotesIndex {
    static let shared = NotesIndex()
    var notes: [String: String] = [:]
    subscript(id: String) -> String { notes[id] ?? "" }
}
