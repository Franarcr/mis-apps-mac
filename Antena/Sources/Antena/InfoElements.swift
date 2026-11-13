import Foundation

/// Lo que se puede leer de los «elementos de información» que anuncia cada punto de acceso en sus balizas.
struct InfoElements {
    struct Element: Identifiable, Hashable {
        let id = UUID()
        var number: Int
        var ext: Int?
        var length: Int
        var name: String
        var summary: String
    }

    var elements: [Element] = []
    var rates: [Double] = []
    var basicRates: [Double] = []
    var dsChannel: Int?
    var country: String?
    var stations: Int?
    var utilization: Int?

    var ht = false
    var htStreams = 0
    var htSGI20 = false
    var htSGI40 = false
    var htSecondaryOffset = 0
    var htProtection: Int?

    var vht = false
    var vhtStreams = 0
    var vhtSGI80 = false
    var vhtWidth: Int?
    var vhtSeg0 = 0
    var vhtSeg1 = 0

    var he = false
    var heStreams = 0
    var he6Width: Int?
    var he6Seg0 = 0
    var he6Seg1 = 0

    var eht = false
    var ehtWidth: Int?
    var ehtCenter = 0

    var hasRSN = false
    var hasWPA = false
    var akms: [UInt8] = []
    var pairwise: [UInt8] = []
    var mobilityDomain = false

    var wps = false
    var wpsDeviceName: String?
    var wpsManufacturer: String?
    var wpsModel: String?

    static func parse(_ data: Data?) -> InfoElements {
        var r = InfoElements()
        guard let data else { return r }
        let b = [UInt8](data)
        var i = 0
        while i + 2 <= b.count {
            let id = Int(b[i]), len = Int(b[i + 1])
            let start = i + 2
            guard start + len <= b.count else { break }
            let p = Array(b[start..<start + len])
            r.handle(id: id, p)
            i = start + len
        }
        return r
    }

    private static func streams(fromMap lo: UInt8, _ hi: UInt8) -> Int {
        let map = UInt16(lo) | (UInt16(hi) << 8)
        var n = 0
        for ss in 0..<8 where (map >> (ss * 2)) & 0x3 != 0x3 { n = ss + 1 }
        return n
    }

    private mutating func add(_ id: Int, ext: Int? = nil, _ len: Int, _ summary: String = "") {
        elements.append(Element(number: id, ext: ext, length: len, name: Self.name(id: id, ext: ext), summary: summary))
    }

    private mutating func handle(id: Int, _ p: [UInt8]) {
        switch id {
        case 0:
            add(id, p.count, String(decoding: p, as: UTF8.self))
        case 1, 50:
            for v in p {
                let rate = Double(v & 0x7F) * 0.5
                if rate == 0 { continue }
                rates.append(rate)
                if v & 0x80 != 0 { basicRates.append(rate) }
            }
            add(id, p.count, p.map { v in
                let s = Self.rate(Double(v & 0x7F) * 0.5)
                return v & 0x80 != 0 ? s + "*" : s
            }.joined(separator: ", "))
        case 3:
            if let c = p.first { dsChannel = Int(c) }
            add(id, p.count, dsChannel.map { "Canal \($0)" } ?? "")
        case 7:
            if p.count >= 2 {
                country = String(bytes: p[0..<2], encoding: .ascii)?.trimmingCharacters(in: .whitespaces)
            }
            add(id, p.count, country ?? "")
        case 11:
            if p.count >= 3 {
                stations = Int(p[0]) | (Int(p[1]) << 8)
                utilization = Int((Double(p[2]) / 255 * 100).rounded())
            }
            add(id, p.count, stations.map { "\($0) clientes, canal ocupado \(utilization ?? 0) %" } ?? "")
        case 45:
            ht = true
            if p.count >= 2 {
                let cap = UInt16(p[0]) | (UInt16(p[1]) << 8)
                htSGI20 = cap & 0x20 != 0
                htSGI40 = cap & 0x40 != 0
            }
            if p.count >= 7 { htStreams = p[3..<7].filter { $0 != 0 }.count }
            add(id, p.count, "\(htStreams) flujo(s)")
        case 48:
            hasRSN = true
            parseRSN(p)
            add(id, p.count, Self.akmNames(akms))
        case 54:
            mobilityDomain = true
            add(id, p.count, "Roaming rápido (802.11r)")
        case 61:
            if p.count >= 4 {
                htSecondaryOffset = Int(p[1] & 0x03)
                htProtection = Int(p[2] & 0x03)
            }
            add(id, p.count, p.first.map { "Canal primario \($0)" } ?? "")
        case 191:
            vht = true
            if p.count >= 6 {
                vhtSGI80 = p[0] & 0x20 != 0
                vhtStreams = Self.streams(fromMap: p[4], p[5])
            }
            add(id, p.count, "\(vhtStreams) flujo(s)")
        case 192:
            if p.count >= 3 {
                vhtWidth = Int(p[0])
                vhtSeg0 = Int(p[1])
                vhtSeg1 = Int(p[2])
            }
            add(id, p.count, "Centro \(vhtSeg0)" + (vhtSeg1 != 0 ? " / \(vhtSeg1)" : ""))
        case 221:
            parseVendor(p)
        case 255:
            guard let ext = p.first else { add(id, 0); return }
            let q = Array(p.dropFirst())
            handleExt(ext: Int(ext), q)
        default:
            add(id, p.count)
        }
    }

    private mutating func handleExt(ext: Int, _ q: [UInt8]) {
        switch ext {
        case 35: // Capacidades HE (Wi-Fi 6)
            he = true
            if q.count >= 19 { heStreams = Self.streams(fromMap: q[17], q[18]) }
            add(255, ext: ext, q.count + 1, "\(heStreams) flujo(s)")
        case 36: // Operación HE
            if q.count >= 6 {
                let params = UInt32(q[0]) | (UInt32(q[1]) << 8) | (UInt32(q[2]) << 16)
                var off = 6
                if params & (1 << 14) != 0 { off += 3 }
                if params & (1 << 15) != 0 { off += 1 }
                if params & (1 << 17) != 0, q.count >= off + 4 {
                    he6Width = Int(q[off + 1] & 0x03)
                    he6Seg0 = Int(q[off + 2])
                    he6Seg1 = Int(q[off + 3])
                }
            }
            add(255, ext: ext, q.count + 1, he6Width != nil ? "Información de 6 GHz" : "")
        case 108:
            eht = true
            add(255, ext: ext, q.count + 1)
        case 106: // Operación EHT
            if q.count >= 8, q[0] & 0x01 != 0 {
                ehtWidth = Int(q[5] & 0x07)
                ehtCenter = Int(q[7] != 0 ? q[7] : q[6])
            }
            add(255, ext: ext, q.count + 1, ehtWidth.map { "Ancho \(Self.ehtWidthName($0))" } ?? "")
        default:
            add(255, ext: ext, q.count + 1)
        }
    }

    private mutating func parseRSN(_ p: [UInt8]) {
        guard p.count >= 8 else { return }
        var o = 2 + 4
        let pc = Int(p[o]) | (Int(p[o + 1]) << 8); o += 2
        for _ in 0..<pc where o + 4 <= p.count { pairwise.append(p[o + 3]); o += 4 }
        guard o + 2 <= p.count else { return }
        let ac = Int(p[o]) | (Int(p[o + 1]) << 8); o += 2
        for _ in 0..<ac where o + 4 <= p.count { akms.append(p[o + 3]); o += 4 }
    }

    private mutating func parseVendor(_ p: [UInt8]) {
        guard p.count >= 4 else { add(221, p.count); return }
        let oui = String(format: "%02X:%02X:%02X", p[0], p[1], p[2])
        if oui == "00:50:F2" && p[3] == 1 {
            hasWPA = true
            add(221, p.count, "WPA (Microsoft)")
        } else if oui == "00:50:F2" && p[3] == 4 {
            wps = true
            var o = 4
            while o + 4 <= p.count {
                let t = (Int(p[o]) << 8) | Int(p[o + 1])
                let l = (Int(p[o + 2]) << 8) | Int(p[o + 3])
                o += 4
                guard o + l <= p.count else { break }
                let v = String(decoding: p[o..<o + l], as: UTF8.self).trimmingCharacters(in: .controlCharacters.union(.whitespaces))
                switch t {
                case 0x1011: wpsDeviceName = v
                case 0x1021: wpsManufacturer = v
                case 0x1023: wpsModel = v
                default: break
                }
                o += l
            }
            add(221, p.count, ["WPS", wpsDeviceName, wpsModel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        } else {
            let vendor = Vendors.shared.lookup(oui + ":00:00:00")
            add(221, p.count, "\(oui)" + (vendor.isEmpty ? "" : " (\(vendor))"))
        }
    }

    static func rate(_ r: Double) -> String {
        r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    static func ehtWidthName(_ w: Int) -> String {
        ["20 MHz", "40 MHz", "80 MHz", "160 MHz", "320 MHz"][min(w, 4)]
    }

    static func akmNames(_ akms: [UInt8]) -> String {
        akms.map { a -> String in
            switch a {
            case 1: return "802.1X"
            case 2: return "PSK"
            case 3: return "FT-802.1X"
            case 4: return "FT-PSK"
            case 5: return "802.1X-SHA256"
            case 6: return "PSK-SHA256"
            case 8: return "SAE"
            case 9: return "FT-SAE"
            case 12, 13: return "802.1X Suite B"
            case 18: return "OWE"
            case 24, 25: return "SAE-EXT"
            default: return "AKM \(a)"
            }
        }.joined(separator: ", ")
    }

    static func name(id: Int, ext: Int?) -> String {
        if let ext {
            switch ext {
            case 35: return "Capacidades HE (Wi-Fi 6)"
            case 36: return "Operación HE"
            case 38: return "Parámetros MU EDCA"
            case 39: return "Reutilización espacial"
            case 59: return "Capacidades HE en 6 GHz"
            case 106: return "Operación EHT (Wi-Fi 7)"
            case 107: return "Multienlace (MLO)"
            case 108: return "Capacidades EHT (Wi-Fi 7)"
            default: return "Extensión \(ext)"
            }
        }
        switch id {
        case 0: return "Nombre de red (SSID)"
        case 1: return "Velocidades admitidas"
        case 3: return "Canal (DS)"
        case 5: return "Mapa de tráfico (TIM)"
        case 7: return "País"
        case 11: return "Carga de la red (BSS Load)"
        case 32: return "Restricción de potencia"
        case 35: return "Informe de potencia (TPC)"
        case 42: return "Información ERP"
        case 45: return "Capacidades HT (Wi-Fi 4)"
        case 48: return "Seguridad (RSN)"
        case 50: return "Velocidades extendidas"
        case 54: return "Dominio de movilidad (802.11r)"
        case 59: return "Clases de operación"
        case 61: return "Operación HT"
        case 70: return "Capacidades RM (802.11k)"
        case 107: return "Interworking (Passpoint)"
        case 108: return "Protocolo de anuncio"
        case 111: return "Roaming Consortium"
        case 127: return "Capacidades extendidas"
        case 191: return "Capacidades VHT (Wi-Fi 5)"
        case 192: return "Operación VHT"
        case 195: return "Potencia de transmisión"
        case 201: return "Perfil de red reducido (RNR)"
        case 221: return "Específico del fabricante"
        default: return "Elemento \(id)"
        }
    }
}
