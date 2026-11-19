import Foundation
import SwiftUI

/// Una cuenta de días: «Desde» cuenta hacia arriba (p. ej. sin azúcar) y «Hasta» hacia atrás (p. ej. un viaje).
/// Se guardan en el grupo compartido para que el widget las lea.
struct Counter: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable { case since, until }

    /// Un intento anterior de una cuenta «Desde» que se reinició.
    struct Attempt: Codable, Hashable {
        var start: Date
        var end: Date
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var date: Date
    /// Si es false, solo cuenta días (la hora no importa).
    var useTime = false
    var icon = "star.fill"
    var color = "indigo"
    /// La que muestra el widget.
    var inWidget = false
    var attempts: [Attempt] = []

    static let colors = ["indigo", "blue", "teal", "green", "yellow", "orange", "red", "pink", "purple"]
    static let icons = ["star.fill", "cube.fill", "nosign", "drop.fill", "wineglass.fill", "smoke.fill", "fork.knife",
                        "figure.run", "dumbbell.fill", "airplane", "gift.fill", "birthday.cake.fill", "heart.fill",
                        "calendar", "flag.checkered", "graduationcap.fill", "briefcase.fill", "house.fill", "leaf.fill", "moon.fill"]

    var tint: Color {
        switch color {
        case "blue": .blue
        case "teal": .teal
        case "green": .green
        case "yellow": .yellow
        case "orange": .orange
        case "red": .red
        case "pink": .pink
        case "purple": .purple
        default: .indigo
        }
    }

    /// Días enteros de calendario entre la fecha y `now` (siempre positivo).
    func days(at now: Date = .now) -> Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: date), b = cal.startOfDay(for: now)
        return abs(cal.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    /// Una «Hasta» ya llegó (o una «Desde» todavía no empieza).
    func isPast(at now: Date = .now) -> Bool {
        useTime ? date <= now : Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: now)
    }

    var isFinished: Bool { kind == .until && isPast() && days() > 0 }

    /// El número grande: «12».
    func number(at now: Date = .now) -> String {
        if useTime {
            let seconds = abs(now.timeIntervalSince(date))
            if seconds < 86400 { return "\(Int(seconds / 3600))" }
        }
        return "\(days(at: now))"
    }

    /// Lo que va debajo del número: «días sin azúcar», «días para Viaje», «¡Hoy!».
    func caption(at now: Date = .now) -> String {
        let seconds = abs(now.timeIntervalSince(date))
        let unit: String
        if useTime && seconds < 86400 { unit = Int(seconds / 3600) == 1 ? "hora" : "horas" }
        else { unit = days(at: now) == 1 ? "día" : "días" }
        switch kind {
        case .since:
            return isPast(at: now) ? unit : "\(unit) para empezar"
        case .until:
            if !useTime && days(at: now) == 0 { return "¡Es hoy!" }
            return isPast(at: now) ? "\(unit) desde que llegó" : "\(unit) para que llegue"
        }
    }

    /// «12 d 4 h 3 min» para las que usan hora.
    func detail(at now: Date = .now) -> String {
        let seconds = Int(abs(now.timeIntervalSince(date)))
        let d = seconds / 86400, h = seconds % 86400 / 3600, m = seconds % 3600 / 60
        return d > 0 ? "\(d) d \(h) h \(m) min" : "\(h) h \(m) min"
    }

    /// Mejor racha de una «Desde», contando la actual.
    var best: TimeInterval {
        let current = kind == .since && isPast() ? Date.now.timeIntervalSince(date) : 0
        return max(current, attempts.map(\.duration).max() ?? 0)
    }

    // MARK: Guardado

    static let appGroup = "group.com.francho.vital"
    private static let key = "cuentas"

    static func load() -> [Counter] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Counter].self, from: data)) ?? []
    }

    static func save(_ counters: [Counter]) {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
    }
}
