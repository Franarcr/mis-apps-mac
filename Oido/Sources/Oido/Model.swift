import AppKit
import Foundation

/// Una frase de la conversación: quién la dijo y en qué segundo.
struct Line: Codable, Hashable {
    enum Speaker: String, Codable { case me, them }
    var speaker: Speaker
    var start: Double
    var text: String
}

/// Una llamada grabada. Vive en su propia carpeta con el audio y `llamada.json`.
struct Call: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case recording, transcribing, ready, failed }

    var id: String
    var title: String
    var app: String
    var start: Date
    var duration: Double = 0
    var status: Status = .recording
    var error: String? = nil
    var lines: [Line] = []
    var summary: String? = nil
    var actions: [String] = []
    /// Apunte de cómo se hizo el resumen (o por qué no se pudo).
    var summaryNote: String? = nil

    var folder: URL { Store.root.appendingPathComponent(id, isDirectory: true) }
    var micURL: URL { folder.appendingPathComponent("yo.m4a") }
    var appURL: URL { folder.appendingPathComponent("ellos.m4a") }
    var mixURL: URL { folder.appendingPathComponent("llamada.m4a") }

    var durationText: String { Self.clock(duration) }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// La conversación en texto, para copiar o exportar.
    var plainText: String {
        var out = "\(title)\n\(app) · \(start.formatted(date: .long, time: .shortened)) · \(durationText)\n"
        if let summary, !summary.isEmpty { out += "\nRESUMEN\n\(summary)\n" }
        if !actions.isEmpty { out += "\nPENDIENTES\n" + actions.map { "- \($0)" }.joined(separator: "\n") + "\n" }
        out += "\nCONVERSACIÓN\n"
        for line in lines {
            out += "[\(Self.clock(line.start))] \(line.speaker == .me ? "Yo" : "Ellos"): \(line.text)\n"
        }
        return out
    }
}

/// Apps de llamadas que Oído vigila. El navegador cuenta porque Meet se usa desde ahí.
struct CallApp: Hashable {
    let name: String
    /// Prefijos de los identificadores: incluyen los procesos auxiliares (Chrome Helper, etc.).
    let prefixes: [String]

    func matches(_ bundleID: String) -> Bool {
        prefixes.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    static let all: [CallApp] = [
        CallApp(name: "WhatsApp", prefixes: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]),
        CallApp(name: "Teams", prefixes: ["com.microsoft.teams2", "com.microsoft.teams"]),
        CallApp(name: "Zoom", prefixes: ["us.zoom.xos"]),
        CallApp(name: "FaceTime", prefixes: ["com.apple.FaceTime", "com.apple.avconferenced"]),
        CallApp(name: "Meet (Edge)", prefixes: ["com.microsoft.edgemac"]),
        CallApp(name: "Meet (Chrome)", prefixes: ["com.google.Chrome"]),
        CallApp(name: "Meet (Arc)", prefixes: ["company.thebrowser.Browser"]),
        CallApp(name: "Meet (Firefox)", prefixes: ["org.mozilla.firefox"]),
        CallApp(name: "Meet (Safari)", prefixes: ["com.apple.Safari", "com.apple.WebKit"]),
    ]

    static let manual = CallApp(name: "Grabación manual", prefixes: [])
}
