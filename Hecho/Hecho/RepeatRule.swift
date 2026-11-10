import Foundation

/// Cómo se repite una tarea.
/// - `fixed`: en un calendario fijo (todos los lunes, el 15 de cada mes…).
/// - `afterCompletion`: un tiempo después de completarla (regar las plantas 3 días después).
struct RepeatRule: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable { case fixed, afterCompletion }
    enum Unit: String, Codable, CaseIterable { case day, week, month, year }

    var mode: Mode = .fixed
    var unit: Unit = .week
    var every: Int = 1
    /// Días de la semana (1 = domingo … 7 = sábado). Solo para `fixed` semanal; vacío = el mismo día de la fecha.
    var weekdays: [Int] = []

    // MARK: Guardado

    init(mode: Mode = .fixed, unit: Unit = .week, every: Int = 1, weekdays: [Int] = []) {
        self.mode = mode
        self.unit = unit
        self.every = max(1, every)
        self.weekdays = weekdays
    }

    init?(raw: String?) {
        guard let raw, let data = raw.data(using: .utf8),
              let rule = try? JSONDecoder().decode(RepeatRule.self, from: data) else { return nil }
        self = rule
    }

    var raw: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // MARK: Próxima fecha

    /// Próximo día en que toca, después de completar una vez.
    /// `scheduled` es el día que tenía la tarea; `completed`, el día en que se completó.
    func nextDate(scheduled: Date?, completed: Date) -> Date {
        let done = completed.startOfDay
        switch mode {
        case .afterCompletion:
            return add(every, to: done)
        case .fixed:
            let anchor = (scheduled ?? done).startOfDay
            // Si se completó tarde, la próxima es la siguiente después de hoy (no una que ya pasó).
            return occurrence(after: max(anchor, done), anchor: anchor)
        }
    }

    /// Próximas fechas de un calendario fijo a partir de `anchor` (sin contar `anchor`), hasta `limit`.
    func upcoming(from anchor: Date, until limit: Date) -> [Date] {
        guard mode == .fixed else { return [] }
        var result: [Date] = []
        var d = anchor.startOfDay
        while result.count < 60 {
            d = occurrence(after: d, anchor: anchor.startOfDay)
            if d > limit { break }
            result.append(d)
        }
        return result
    }

    private func add(_ n: Int, to d: Date) -> Date {
        let cal = Calendar.hecho
        switch unit {
        case .day: return d.adding(days: n)
        case .week: return d.adding(days: 7 * n)
        case .month: return cal.date(byAdding: .month, value: n, to: d) ?? d
        case .year: return cal.date(byAdding: .year, value: n, to: d) ?? d
        }
    }

    /// Primera fecha del calendario estrictamente después de `from`.
    private func occurrence(after from: Date, anchor: Date) -> Date {
        let cal = Calendar.hecho
        if unit == .week && !weekdays.isEmpty {
            let anchorWeek = cal.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
            var d = from.adding(days: 1)
            for _ in 0..<(400 * every) {
                let week = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
                let weeks = (anchorWeek.days(until: week)) / 7
                if weeks % every == 0 && weekdays.contains(cal.component(.weekday, from: d)) { return d }
                d = d.adding(days: 1)
            }
            return from.adding(days: 7 * every)
        }
        var k = 1
        var d = add(every, to: anchor)
        while d <= from && k < 5000 {
            k += 1
            d = add(every * k, to: anchor)
        }
        return d
    }

    // MARK: Texto

    var summary: String {
        let unitText: String
        switch unit {
        case .day: unitText = every == 1 ? "día" : "\(every) días"
        case .week: unitText = every == 1 ? "semana" : "\(every) semanas"
        case .month: unitText = every == 1 ? "mes" : "\(every) meses"
        case .year: unitText = every == 1 ? "año" : "\(every) años"
        }
        switch mode {
        case .afterCompletion:
            let plain: String
            switch unit {
            case .day: plain = every == 1 ? "1 día" : "\(every) días"
            case .week: plain = every == 1 ? "1 semana" : "\(every) semanas"
            case .month: plain = every == 1 ? "1 mes" : "\(every) meses"
            case .year: plain = every == 1 ? "1 año" : "\(every) años"
            }
            return "\(plain) después de completarla"
        case .fixed:
            var text = "Cada \(unitText)"
            if unit == .week && !weekdays.isEmpty {
                let names = ["", "dom", "lun", "mar", "mié", "jue", "vie", "sáb"]
                let order = [2, 3, 4, 5, 6, 7, 1]
                text += " (" + order.filter(weekdays.contains).map { names[$0] }.joined(separator: ", ") + ")"
            }
            return text
        }
    }
}
