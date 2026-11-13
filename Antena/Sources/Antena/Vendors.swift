import Foundation

/// Fabricantes según el registro público del IEEE (MA-L, MA-M y MA-S).
/// Se guarda como texto «PREFIJO<tab>Nombre»; la primera línea es «# fecha».
final class Vendors: ObservableObject {
    static let shared = Vendors()

    @Published private(set) var count = 0
    @Published private(set) var date = ""
    @Published var updating = false
    @Published var updateMessage = ""

    private var table: [String: String] = [:]

    static let sources = [
        "https://standards-oui.ieee.org/oui/oui.csv",
        "https://standards-oui.ieee.org/oui28/mam.csv",
        "https://standards-oui.ieee.org/oui36/oui36.csv",
    ]

    static var userFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Antena", isDirectory: true)
            .appendingPathComponent("fabricantes.tsv")
    }

    private init() { load() }

    func load() {
        var candidates: [URL] = []
        if FileManager.default.fileExists(atPath: Self.userFile.path) { candidates.append(Self.userFile) }
        if let bundled = Bundle.main.url(forResource: "fabricantes", withExtension: "tsv") { candidates.append(bundled) }
        // Se usa la copia más reciente.
        var best: (String, URL)?
        for url in candidates {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let first = text.prefix(while: { $0 != "\n" })
            let d = first.hasPrefix("# ") ? String(first.dropFirst(2)) : ""
            if best == nil || d > best!.0 { best = (d, url) }
        }
        guard let (d, url) = best, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var t: [String: String] = [:]
        t.reserveCapacity(60_000)
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            t[String(line[..<tab])] = String(line[line.index(after: tab)...])
        }
        table = t
        count = t.count
        date = d
    }

    /// Nombre del fabricante para una dirección MAC (BSSID).
    func lookup(_ mac: String) -> String {
        let hex = mac.uppercased().filter { $0.isHexDigit }
        guard hex.count >= 6 else { return "" }
        if let first = UInt8(hex.prefix(2), radix: 16), first & 0x02 != 0 {
            return "Dirección privada"
        }
        for n in [9, 7, 6] where hex.count >= n {
            if let v = table[String(hex.prefix(n))] { return v }
        }
        return ""
    }

    // MARK: Actualización desde el IEEE

    @MainActor
    func update() {
        guard !updating else { return }
        updating = true
        updateMessage = "Descargando el registro del IEEE…"
        Task.detached {
            do {
                var csvs: [String] = []
                for s in Self.sources {
                    var req = URLRequest(url: URL(string: s)!)
                    req.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
                    req.timeoutInterval = 60
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    csvs.append(String(decoding: data, as: UTF8.self))
                }
                let tsv = Self.convert(csvs: csvs)
                try FileManager.default.createDirectory(at: Self.userFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try tsv.write(to: Self.userFile, atomically: true, encoding: .utf8)
                await MainActor.run {
                    self.load()
                    self.updating = false
                    self.updateMessage = "Actualizada: \(self.count.formatted()) fabricantes."
                }
            } catch {
                await MainActor.run {
                    self.updating = false
                    self.updateMessage = "No se pudo actualizar: \(error.localizedDescription)"
                }
            }
        }
    }

    static func convert(csvs: [String]) -> String {
        var rows: [String: String] = [:]
        for csv in csvs {
            for fields in parseCSV(csv).dropFirst() where fields.count >= 3 {
                let prefix = fields[1].uppercased().filter { $0.isHexDigit }
                let name = clean(fields[2])
                if !prefix.isEmpty && !name.isEmpty { rows[prefix] = name }
            }
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        var out = "# \(f.string(from: Date()))\n"
        for key in rows.keys.sorted() { out += "\(key)\t\(rows[key]!)\n" }
        return out
    }

    /// Quita «Inc.», «Co., Ltd.» y similares para que el nombre quepa en la tabla.
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Corta en la forma jurídica aunque detrás venga más texto («Co.,Ltd.Dongguan branch»).
        let legal = try! NSRegularExpression(
            pattern: #"[\s,]+(co\.?\s*,?\s*ltd|inc\b|inc\.|incorporated|corporation|corp\b|corp\.|gmbh|llc|l\.l\.c|limited|ltd\b|ltd\.|pte\.?\s*ltd|pty\.?\s*ltd|s\.a\.s|sas\b|s\.?a\.?\b|s\.?r\.?l\.?\b|b\.v\.|ag\b|kg\b|oy\b|ab\b|plc\b|s\.?p\.?a\.?\b)[\s\S]*$"#,
            options: [.caseInsensitive])
        s = legal.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        let suffix = try! NSRegularExpression(
            pattern: #"[,\s]+(inc\.?|incorporated|corporation|corp\.?|co\.?,?\s*ltd\.?|ltd\.?|limited|llc|l\.l\.c\.|gmbh|ag|s\.?a\.?|s\.?l\.?|b\.?v\.?|pte\.?|pty\.?|plc|co\.?|company|oy|ab|srl|s\.r\.l\.|kg)$"#,
            options: [.caseInsensitive])
        var changed = true
        while changed {
            let r = NSRange(s.startIndex..., in: s)
            let new = suffix.stringByReplacingMatches(in: s, range: r, withTemplate: "")
            changed = new != s
            s = new.trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
        }
        return s.replacingOccurrences(of: "\t", with: " ")
    }

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let n = it.next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else { field.unicodeScalars.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.unicodeScalars.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
