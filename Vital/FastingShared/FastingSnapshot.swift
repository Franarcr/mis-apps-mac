import ActivityKit
import Foundation

/// Lo mínimo del ayuno que necesitan los widgets. La app lo guarda en el grupo compartido
/// cada vez que algo cambia; los widgets solo lo leen.
struct FastingSnapshot: Codable, Equatable {
    var enabled: Bool
    /// Inicio del ayuno en curso, o nil si la ventana para comer está abierta.
    var activeStart: Date?
    var goalHours: Double
    /// Cuándo terminó el último ayuno (para saber cuándo cierra la ventana).
    var lastEnd: Date?
    var streak: Int

    static let appGroup = "group.com.francho.vital"
    private static let key = "ayunoWidget"

    var goalDate: Date? { activeStart?.addingTimeInterval(goalHours * 3600) }
    /// La ventana para comer dura 24 h − meta desde que se rompió el último ayuno.
    var windowCloses: Date? { lastEnd?.addingTimeInterval((24 - goalHours) * 3600) }

    static func load() -> FastingSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FastingSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}

/// La Actividad en vivo del ayuno (pantalla bloqueada y Dynamic Island).
/// Solo lleva el inicio y la meta: el tiempo lo cuenta el sistema con temporizadores.
struct FastingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var goalHours: Double
        var goalDate: Date { start.addingTimeInterval(goalHours * 3600) }
    }
}
