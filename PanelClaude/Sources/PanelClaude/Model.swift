import Foundation

// Foto completa de lo que Claude tiene en este Mac. Es Codable para poder
// exportarla en JSON (la usa el artefacto de claude.ai).
struct Snapshot: Codable {
    var generatedAt: Date = Date()
    var chats: [Chat] = []
    var connectors: [Connector] = []
    var mcpServers: [MCPServer] = []
    var plugins: [Plugin] = []
    var skills: [Skill] = []
    var tasks: [ScheduledTask] = []
    var usage: [UsageSample] = []
    var disk: [DiskItem] = []
    var warnings: [Warning] = []

    var totalChatBytes: Int64 { chats.reduce(0) { $0 + $1.bytes } }
    var totalDiskBytes: Int64 { disk.reduce(0) { $0 + $1.bytes } }
}

struct Chat: Codable, Identifiable, Hashable {
    var id: String              // id de la sesión de Claude Code (nombre del .jsonl)
    var title: String
    var project: String         // carpeta en la que se trabajó
    var path: String            // ruta del .jsonl
    var bytes: Int64            // .jsonl + carpeta de resultados de herramientas
    var prompts: Int            // mensajes que escribiste
    var replies: Int            // respuestas de Claude
    var contextTokens: Int      // tamaño del contexto en la última respuesta
    var outputTokens: Int       // tokens que escribió Claude en total
    var model: String
    var created: Date?
    var lastActivity: Date?
    var archived: Bool
    var scheduledTask: String?  // si lo lanzó una tarea programada

    var isHeavy: Bool { bytes >= Thresholds.heavyBytes || contextTokens >= Thresholds.heavyContext }
}

struct Connector: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var url: String
    var tools: Int
}

struct MCPServer: Codable, Identifiable, Hashable {
    var id: String { source + name }
    var name: String
    var source: String    // «App de escritorio», «Claude Code», «Extensión», «Proyecto …»
    var detail: String
}

struct Plugin: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var description: String
    var enabled: Bool
    var skills: Int
    var source: String
}

struct Skill: Codable, Identifiable, Hashable {
    var id: String { source + name }
    var name: String
    var description: String
    var source: String    // «Cuenta», «Personal», o el plugin al que pertenece
    var uses: Int?        // usos registrados por Claude Code (si los hay)
}

struct ScheduledTask: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var description: String
    var runs: Int
    var lastRun: Date?
}

struct UsageSample: Codable, Hashable {
    var date: Date
    var fiveHour: Int     // % del límite de 5 horas
    var sevenDay: Int     // % del límite semanal
}

struct DiskItem: Codable, Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var bytes: Int64
    var note: String
    var cleanable: Bool   // se puede mandar a la Papelera sin perder nada
}

struct Warning: Codable, Identifiable, Hashable {
    var id: String { text }
    var level: Level
    var text: String
    enum Level: String, Codable { case info, warn, alert }
}

enum Thresholds {
    static let heavyBytes: Int64 = 100_000_000   // 100 MB
    static let heavyContext = 150_000            // tokens
    static let usageAlert = 80                   // %
    static let diskAlert: Int64 = 10_000_000_000 // 10 GB
}

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
    static func tokens(_ t: Int) -> String {
        if t >= 1_000_000 { return String(format: "%.1f M", Double(t) / 1_000_000) }
        if t >= 1_000 { return "\(t / 1_000) mil" }
        return "\(t)"
    }
    static func relative(_ d: Date?) -> String {
        guard let d else { return "—" }
        if Date().timeIntervalSince(d) < 60 { return "hace un momento" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es")
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
    static func date(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f.string(from: d)
    }
}
