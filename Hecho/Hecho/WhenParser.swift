import Foundation

/// Entiende fechas escritas en español: «hoy», «esta noche», «mañana», «pasado mañana», «viernes»,
/// «el próximo lunes», «en 3 días», «dentro de 2 semanas», «fin de semana», «próxima semana»,
/// «próximo mes», «algún día», «15», «15 dic», «15 de diciembre», «15/12», «15/12/2027».
enum WhenParser {
    static func parse(_ raw: String, today: Date = Date().startOfDay) -> WhenChoice? {
        var s = normalize(raw)
        guard !s.isEmpty else { return nil }
        let cal = Calendar.hecho

        switch s {
        case "hoy": return .today
        case "esta noche", "noche", "hoy en la noche", "hoy noche", "en la noche", "hoy por la noche": return .evening
        case "algun dia", "algundia", "luego", "mas adelante": return .someday
        case "cuando sea", "cualquier momento", "sin fecha": return .anytime
        case "manana": return .date(today.adding(days: 1))
        case "pasado manana", "pasadomanana": return .date(today.adding(days: 2))
        case "fin de semana", "este fin de semana", "finde", "el finde", "este finde":
            return .date(next(weekday: 7, from: today, allowToday: true))
        case "proxima semana", "la proxima semana", "semana que viene", "la semana que viene":
            return .date(next(weekday: 2, from: today, allowToday: false))
        case "proximo mes", "el proximo mes", "mes que viene", "el mes que viene":
            let first = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
            return .date(first.adding(months: 1))
        default: break
        }

        // «en 3 días», «dentro de 2 semanas», «3 días».
        for prefix in ["dentro de ", "en "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        let words = s.split(separator: " ").map(String.init)
        if words.count == 2, let n = number(words[0]) {
            switch words[1] {
            case "dia", "dias": return .date(today.adding(days: n))
            case "semana", "semanas": return .date(today.adding(days: 7 * n))
            case "mes", "meses": return .date(today.adding(months: n))
            default: break
            }
        }

        // Días de la semana: «viernes», «el viernes», «próximo viernes», «este viernes».
        var w = s
        for prefix in ["el proximo ", "la proxima ", "proximo ", "proxima ", "este ", "el "] where w.hasPrefix(prefix) {
            w = String(w.dropFirst(prefix.count))
            break
        }
        if let wd = weekdays[w] { return .date(next(weekday: wd, from: today, allowToday: false)) }

        if let d = parseDate(s, today: today) { return d == today ? .today : .date(d) }
        return nil
    }

    /// Fecha y, si se escribió, hora del aviso: «mañana 3pm», «viernes a las 9:30», «hoy 18:00», «5pm».
    static func parseWithTime(_ raw: String, today: Date = Date().startOfDay) -> (WhenChoice?, DateComponents?) {
        let s = normalize(raw)
        guard let (rest, time) = splitTime(s) else { return (parse(raw, today: today), nil) }
        if rest.isEmpty { return (.today, time) }
        guard let choice = parse(rest, today: today) else { return (nil, nil) }
        switch choice {
        case .someday, .anytime, .inbox: return (choice, nil)
        default: return (choice, time)
        }
    }

    /// Separa una hora escrita al final. Solo cuenta como hora si lleva «:», am/pm o «a las».
    private static func splitTime(_ s: String) -> (String, DateComponents)? {
        if s.hasSuffix("mediodia") {
            let rest = s.dropLast("mediodia".count).trimmingCharacters(in: .whitespaces)
            return (strip(rest), DateComponents(hour: 12, minute: 0))
        }
        let pattern = #"(?:^|\s)(a las |a la |las |@)?(\d{1,2})(?:[:h](\d{2}))?\s*(am|pm|a m|p m|de la manana|de la tarde|de la noche|hrs|h)?$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            return String(s[r])
        }
        let prefix = group(1)
        let minutes = group(3)
        let suffix = group(4)
        guard prefix != nil || minutes != nil || suffix != nil, var hour = Int(group(2) ?? "") else { return nil }
        let minute = Int(minutes ?? "0") ?? 0
        guard hour <= 23, minute <= 59 else { return nil }
        switch suffix {
        case "pm", "p m", "de la tarde", "de la noche": if hour < 12 { hour += 12 }
        case "am", "a m", "de la manana": if hour == 12 { hour = 0 }
        default: break
        }
        let rest = String(s[..<(Range(m.range, in: s)?.lowerBound ?? s.endIndex)]).trimmingCharacters(in: .whitespaces)
        return (strip(rest), DateComponents(hour: hour, minute: minute))
    }

    private static func strip(_ s: String) -> String {
        var r = s
        for suffix in [" a las", " a la", " las"] where r.hasSuffix(suffix) { r = String(r.dropLast(suffix.count)) }
        return r.trimmingCharacters(in: .whitespaces)
    }

    /// Solo fechas (para la fecha límite).
    static func parseDay(_ raw: String, today: Date = Date().startOfDay) -> Date? {
        switch parse(raw, today: today) {
        case .today, .evening: return today
        case .date(let d): return d
        default: return nil
        }
    }

    // MARK: - Ayudantes

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static let weekdays: [String: Int] = [
        "domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7,
        "dom": 1, "lun": 2, "mar": 3, "mie": 4, "jue": 5, "vie": 6, "sab": 7,
    ]

    private static let months: [String: Int] = [
        "enero": 1, "ene": 1, "febrero": 2, "feb": 2, "marzo": 3, "mar": 3, "abril": 4, "abr": 4,
        "mayo": 5, "may": 5, "junio": 6, "jun": 6, "julio": 7, "jul": 7, "agosto": 8, "ago": 8,
        "septiembre": 9, "setiembre": 9, "sep": 9, "sept": 9, "set": 9, "octubre": 10, "oct": 10,
        "noviembre": 11, "nov": 11, "diciembre": 12, "dic": 12,
    ]

    private static let numberWords: [String: Int] = [
        "un": 1, "una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6,
        "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "quince": 15, "veinte": 20, "treinta": 30,
    ]

    private static func number(_ w: String) -> Int? {
        if let n = Int(w), n >= 0, n < 1000 { return n }
        return numberWords[w]
    }

    /// Próximo día de la semana (1 = domingo … 7 = sábado).
    private static func next(weekday: Int, from today: Date, allowToday: Bool) -> Date {
        let current = Calendar.hecho.component(.weekday, from: today)
        var diff = (weekday - current + 7) % 7
        if diff == 0 && !allowToday { diff = 7 }
        return today.adding(days: diff)
    }

    /// «15», «15 dic», «15 de diciembre», «dic 15», «15/12», «15-12-27», «15/12/2027».
    private static func parseDate(_ s: String, today: Date) -> Date? {
        let cal = Calendar.hecho
        var day: Int?
        var month: Int?
        var year: Int?

        let parts = s.split(whereSeparator: { "/-".contains($0) }).map(String.init)
        if parts.count >= 2, parts.allSatisfy({ Int($0) != nil }) {
            day = Int(parts[0])
            month = Int(parts[1])
            if parts.count == 3, let y = Int(parts[2]) { year = y < 100 ? 2000 + y : y }
        } else {
            let words = s.split(separator: " ").map(String.init).filter { $0 != "de" && $0 != "del" && $0 != "el" }
            for w in words {
                if let n = Int(w) {
                    if day == nil, n >= 1, n <= 31 { day = n } else if n >= 2000 { year = n } else { return nil }
                } else if let m = months[w] {
                    month = m
                } else {
                    return nil
                }
            }
        }
        guard let d = day else { return nil }
        let thisYear = cal.component(.year, from: today)
        let thisMonth = cal.component(.month, from: today)

        if let m = month {
            guard (1...12).contains(m) else { return nil }
            var comps = DateComponents(year: year ?? thisYear, month: m, day: d)
            guard var date = cal.date(from: comps), cal.component(.day, from: date) == d else { return nil }
            if year == nil && date < today {
                comps.year = thisYear + 1
                date = cal.date(from: comps) ?? date
            }
            return date
        }
        // Solo el día: este mes, o el próximo si ya pasó.
        var comps = DateComponents(year: thisYear, month: thisMonth, day: d)
        if let date = cal.date(from: comps), cal.component(.day, from: date) == d, date >= today { return date }
        comps.month = thisMonth + 1
        guard let date = cal.date(from: comps), cal.component(.day, from: date) == d else { return nil }
        return date
    }
}
