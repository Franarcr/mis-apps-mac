import Foundation
import SwiftData
import UserNotifications

/// Un ayuno: desde la última comida hasta la siguiente. Sin `end`, está en curso.
@Model
final class FastingSession {
    var start: Date
    var end: Date?
    var goalHours: Double
    /// Lo que lo terminó: "manual" o "comida" (al registrar algo de 50 kcal o más).
    var endedBy: String?

    init(start: Date, goalHours: Double) {
        self.start = start
        self.goalHours = goalHours
    }

    var isActive: Bool { end == nil }
    var hours: Double { (end ?? .now).timeIntervalSince(start) / 3600 }
    var reachedGoal: Bool { hours >= goalHours }
    var goalDate: Date { start.addingTimeInterval(goalHours * 3600) }
}

/// Planes de ayuno diario (horas de ayuno : horas de ventana para comer).
enum FastingPlan: Double, CaseIterable, Identifiable {
    case h12 = 12, h14 = 14, h16 = 16, h18 = 18
    var id: Double { rawValue }
    var title: String { "\(Int(rawValue)):\(24 - Int(rawValue))" }
    var detail: String {
        switch self {
        case .h12: "Suave: cenar y no picar de noche"
        case .h14: "Intermedio, fácil de sostener"
        case .h16: "El más estudiado"
        case .h18: "Exigente: cuida la proteína"
        }
    }
}

/// Lo que pasa en el cuerpo según las horas desde la última comida.
/// Son rangos aproximados: dependen de lo que comiste, de cuánto te moviste y de cada persona.
enum FastingPhase: Int, CaseIterable, Identifiable {
    case digestion, glycogen, fatSwitch, ketosis, prolonged
    var id: Int { rawValue }

    var startHour: Double {
        switch self {
        case .digestion: 0
        case .glycogen: 4
        case .fatSwitch: 12
        case .ketosis: 18
        case .prolonged: 24
        }
    }

    var title: String {
        switch self {
        case .digestion: "Digestión"
        case .glycogen: "Glucógeno bajando"
        case .fatSwitch: "Cambio a grasa"
        case .ketosis: "Cetosis leve"
        case .prolonged: "Ayuno prolongado"
        }
    }

    var icon: String {
        switch self {
        case .digestion: "fork.knife"
        case .glycogen: "arrow.down.circle"
        case .fatSwitch: "flame"
        case .ketosis: "bolt.heart"
        case .prolonged: "exclamationmark.triangle"
        }
    }

    var explanation: String {
        switch self {
        case .digestion: "Absorbes lo que comiste; la glucosa y la insulina están altas."
        case .glycogen: "La insulina baja y el hígado va soltando glucosa de sus reservas (glucógeno)."
        case .fatSwitch: "Con el glucógeno más bajo, usas más grasa y aparecen las primeras cetonas."
        case .ketosis: "Las cetonas suben más. El hambre suele venir en olas y pasar."
        case .prolonged: "Más de un día sin comer. Si lo haces seguido, coméntalo con tu médico."
        }
    }

    static func at(hours: Double) -> FastingPhase {
        allCases.last { hours >= $0.startHour } ?? .digestion
    }
}

/// Resumen de los ayunos terminados.
struct FastingStats {
    let finished: [FastingSession]   // del más reciente al más antiguo

    init(sessions: [FastingSession]) {
        finished = sessions.filter { !$0.isActive }.sorted { $0.start > $1.start }
    }

    /// Días seguidos (contando hacia atrás desde hoy o ayer) con al menos un ayuno que llegó a la meta.
    var streak: Int {
        let cal = Calendar.current
        let days = Set(finished.filter(\.reachedGoal).compactMap { $0.end.map { cal.startOfDay(for: $0) } })
        var day = cal.startOfDay(for: .now)
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    private var recent: [FastingSession] { Array(finished.prefix(14)) }

    /// Porcentaje de los últimos 14 ayunos que llegaron a la meta.
    var completion: Double? {
        recent.isEmpty ? nil : Double(recent.filter(\.reachedGoal).count) / Double(recent.count)
    }

    var averageHours: Double? {
        recent.isEmpty ? nil : recent.map(\.hours).reduce(0, +) / Double(recent.count)
    }

    /// Cuánto varía la hora de empezar (desviación típica en minutos). Los minutos se cuentan desde
    /// el mediodía para que una cena a las 23:30 y otra a las 00:15 queden cerca.
    var startVariability: Double? {
        guard recent.count >= 3 else { return nil }
        let cal = Calendar.current
        let minutes = recent.map { s -> Double in
            let c = cal.dateComponents([.hour, .minute], from: s.start)
            return Double(((c.hour! * 60 + c.minute!) - 12 * 60 + 1440) % 1440)
        }
        let mean = minutes.reduce(0, +) / Double(minutes.count)
        return (minutes.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(minutes.count)).squareRoot()
    }

    var regularityText: String? {
        guard let v = startVariability else { return nil }
        return v < 30 ? "Muy regular" : v < 60 ? "Regular" : "Variable"
    }

    /// Horas del ayuno más largo que terminó en cada uno de los últimos 7 días (de más antiguo a hoy).
    var lastWeek: [(day: Date, hours: Double, goal: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let best = finished.filter { $0.end.map { cal.isDate($0, inSameDayAs: day) } ?? false }.max { $0.hours < $1.hours }
            return (day, best?.hours ?? 0, best?.goalHours ?? 0)
        }
    }
}

enum Fasting {
    /// Registrar comida de 50 kcal o más rompe el ayuno; un café negro o agua con limón no.
    static let breakingKcal = 50.0

    static func active(in context: ModelContext) -> FastingSession? {
        let all = (try? context.fetch(FetchDescriptor<FastingSession>(predicate: #Predicate { $0.end == nil }))) ?? []
        return all.max { $0.start < $1.start }
    }

    static func start(at date: Date, goalHours: Double, in context: ModelContext) {
        // Solo un ayuno en curso a la vez: si quedó uno abierto, se cierra donde empieza el nuevo.
        if let current = active(in: context) {
            current.end = max(current.start, date)
            current.endedBy = "manual"
        }
        let session = FastingSession(start: date, goalHours: goalHours)
        context.insert(session)
        try? context.save()
        FastingNotifications.scheduleGoal(for: session)
    }

    static func finish(_ session: FastingSession, at date: Date = .now, by reason: String = "manual", in context: ModelContext) {
        session.end = max(session.start, date)
        session.endedBy = reason
        try? context.save()
        FastingNotifications.cancelGoal()
        FastingNotifications.scheduleWindowClosing(fastEnded: session.end!, goalHours: session.goalHours)
    }

    /// Se llama al registrar comida a la hora actual: si hay un ayuno en curso, termina en ese momento.
    @discardableResult
    static func foodLogged(at date: Date, kcal: Double, in context: ModelContext) -> FastingSession? {
        guard UserDefaults.standard.bool(forKey: "ayunoActivo"), kcal >= breakingKcal,
              let session = active(in: context), date > session.start else { return nil }
        finish(session, at: date, by: "comida", in: context)
        return session
    }
}

/// Avisos locales: «llegaste a tu meta» y «tu ventana para comer cierra pronto».
enum FastingNotifications {
    private static let goalID = "ayuno-meta"
    private static let windowID = "ayuno-ventana"
    private static var center: UNUserNotificationCenter { .current() }

    static func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func scheduleGoal(for session: FastingSession) {
        center.removePendingNotificationRequests(withIdentifiers: [goalID, windowID])
        let seconds = session.goalDate.timeIntervalSinceNow
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meta de ayuno cumplida"
        content.body = "Llevas \(Int(session.goalHours)) h. Tu ventana para comer está abierta; empieza con proteína."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: goalID, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }

    static func cancelGoal() {
        center.removePendingNotificationRequests(withIdentifiers: [goalID])
    }

    /// Media hora antes de que se cierre la ventana para comer (24 h − meta, contadas desde que rompiste el ayuno).
    static func scheduleWindowClosing(fastEnded: Date, goalHours: Double) {
        center.removePendingNotificationRequests(withIdentifiers: [windowID])
        guard UserDefaults.standard.object(forKey: "ayunoAvisoVentana") as? Bool ?? true else { return }
        let fire = fastEnded.addingTimeInterval((24 - goalHours) * 3600 - 30 * 60)
        let seconds = fire.timeIntervalSinceNow
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tu ventana para comer cierra en 30 min"
        content.body = "Si te falta proteína hoy, es buen momento para completarla."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: windowID, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }

    static func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [goalID, windowID])
    }
}
