import Foundation
import SwiftData

// MARK: - Fechas

extension Calendar {
    static var hecho: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_CR")
        c.firstWeekday = 2  // la semana empieza el lunes
        return c
    }
}

extension Date {
    var startOfDay: Date { Calendar.hecho.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.hecho.date(byAdding: .day, value: days, to: self) ?? self }
    func adding(months: Int) -> Date { Calendar.hecho.date(byAdding: .month, value: months, to: self) ?? self }
    /// El mismo día, a la hora y minutos de `time`.
    func at(_ time: DateComponents) -> Date {
        Calendar.hecho.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: self) ?? self
    }
    var timeComponents: DateComponents { Calendar.hecho.dateComponents([.hour, .minute], from: self) }
    func days(until other: Date) -> Int {
        Calendar.hecho.dateComponents([.day], from: startOfDay, to: other.startOfDay).day ?? 0
    }
}

enum Fmt {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CR")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    private static let short = formatter("EEEdMMM")
    private static let shortYear = formatter("EEEdMMMy")
    private static let weekdayF = formatter("EEEE")
    private static let monthF = formatter("MMMM")
    private static let monthYearF = formatter("MMMMy")
    private static let longF = formatter("EEEEdMMMM")

    /// «hoy», «mañana», «vie 14 nov».
    static func day(_ d: Date, today: Date = Date().startOfDay) -> String {
        switch today.days(until: d) {
        case 0: return "Hoy"
        case 1: return "Mañana"
        case -1: return "Ayer"
        default:
            let sameYear = Calendar.hecho.component(.year, from: d) == Calendar.hecho.component(.year, from: today)
            return (sameYear ? short : shortYear).string(from: d)
        }
    }
    static func weekday(_ d: Date) -> String { weekdayF.string(from: d).capitalized }
    static func long(_ d: Date) -> String { longF.string(from: d) }
    static func month(_ d: Date, today: Date) -> String {
        let sameYear = Calendar.hecho.component(.year, from: d) == Calendar.hecho.component(.year, from: today)
        return (sameYear ? monthF : monthYearF).string(from: d).capitalized
    }
    static func dayNumber(_ d: Date) -> String { String(Calendar.hecho.component(.day, from: d)) }
    private static let timeF: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CR")
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
    /// «3:00 p. m.»
    static func time(_ d: Date) -> String { timeF.string(from: d) }

    /// Texto para una fecha límite: «Vence hoy», «Quedan 3 días», «Venció hace 2 días».
    static func deadline(_ d: Date, today: Date) -> String {
        let n = today.days(until: d)
        switch n {
        case 0: return "Vence hoy"
        case 1: return "Vence mañana"
        case 2...: return "Quedan \(n) días"
        case -1: return "Venció ayer"
        default: return "Venció hace \(-n) días"
        }
    }
}

// MARK: - Cuándo

/// Lo que se elige en el selector «¿Cuándo?».
enum WhenChoice: Equatable {
    case today, evening, date(Date), anytime, someday, inbox
}

// MARK: - Tareas

extension TodoItem {
    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .open }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .open ? nil : Date()
        }
    }
    var start: StartBucket {
        get { StartBucket(rawValue: startRaw) ?? .inbox }
        set { startRaw = newValue.rawValue }
    }
    var isDone: Bool { status != .open }
    var homeArea: Area? { project?.area ?? area }
    /// Nombre del proyecto o área donde está, para mostrarlo debajo del título.
    var contextName: String? { project?.title ?? area?.title }
    var sortedChecklist: [ChecklistItem] { checklist.sorted { $0.order < $1.order } }
    var sortedTags: [TagItem] { tags.sorted { $0.order < $1.order } }
    var displayTitle: String { title.isEmpty ? "Nueva tarea" : title }

    /// El proyecto que la contiene sigue abierto y no está en la papelera.
    var parentActive: Bool {
        guard let p = project else { return true }
        return p.status == .open && !p.trashed
    }
    /// Su proyecto está guardado para algún día o programado para más adelante.
    func parentDeferred(today: Date) -> Bool {
        guard let p = project else { return false }
        if let d = p.startDate { return d >= today.adding(days: 1) }
        return p.start == .someday
    }

    func setWhen(_ choice: WhenChoice, today: Date) {
        switch choice {
        case .today:
            schedule(today, today: today)
        case .evening:
            schedule(today, today: today)
            evening = true
        case .date(let d):
            schedule(max(d.startOfDay, today), today: today)
        case .anytime:
            startDate = nil
            evening = false
            start = .anytime
        case .someday:
            startDate = nil
            evening = false
            start = .someday
        case .inbox:
            startDate = nil
            evening = false
            start = (project == nil && area == nil) ? .inbox : .anytime
        }
        // El aviso sigue a la fecha: misma hora en el nuevo día, o se quita si ya no hay día.
        if let r = reminderAt {
            reminderAt = startDate.map { $0.at(r.timeComponents) }
        }
    }

    /// Fija la fecha y el aviso a la vez (desde el selector «¿Cuándo?»). `time` nil quita el aviso.
    func setWhen(_ choice: WhenChoice, reminder time: DateComponents?, today: Date) {
        setWhen(choice, today: today)
        reminderAt = time.flatMap { t in startDate.map { $0.at(t) } }
    }

    var repeatRule: RepeatRule? {
        get { RepeatRule(raw: repeatRaw) }
        set { repeatRaw = newValue?.raw }
    }

    private func schedule(_ day: Date, today: Date) {
        let wasToday = startDate.map { $0 < today.adding(days: 1) } ?? false
        startDate = day
        evening = false
        start = .anytime
        // Al entrar a Hoy se pone al final.
        if day == today && !wasToday { todayOrder = Date().timeIntervalSinceReferenceDate }
    }

    func toggleDone(_ state: AppState?) {
        if status == .open {
            finish(.completed, state: state)
        } else {
            reopen()
        }
    }

    /// Completa o cancela. Si la tarea se repite, crea la siguiente.
    func finish(_ newStatus: ItemStatus, state: AppState?) {
        status = newStatus
        state?.recentlyDone.insert(persistentModelID)
        guard let rule = repeatRule, let context = modelContext else { return }
        let next = duplicate(in: context)
        let day = rule.nextDate(scheduled: startDate, completed: Date())
        if let d = deadline {
            next.deadline = day.adding(days: (startDate ?? Date().startOfDay).days(until: d))
        }
        next.startDate = day
        next.start = .anytime
        next.evening = evening
        next.reminderAt = reminderAt.map { day.at($0.timeComponents) }
        next.repeatRaw = repeatRaw
        next.todayOrder = todayOrder
        nextUID = next.uid
        repeatRaw = nil
    }

    /// Vuelve a abrirla. Si al completarla se creó la siguiente repetición y nadie la tocó, se deshace.
    func reopen() {
        status = .open
        if let id = nextUID, let context = modelContext {
            let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.uid == id })
            if let next = try? context.fetch(descriptor).first, next.status == .open, !next.trashed {
                repeatRaw = next.repeatRaw
                context.delete(next)
            }
        }
        nextUID = nil
    }

    /// Lo mueve a un proyecto (y encabezado), a un área, o lo deja suelto.
    func move(project newProject: Project?, heading newHeading: Heading? = nil, area newArea: Area?) {
        project = newProject
        heading = newProject == nil ? nil : newHeading
        area = newProject == nil ? newArea : nil
        if (newProject != nil || newArea != nil) && start == .inbox { start = .anytime }
        if newProject == nil && newArea == nil && startDate == nil && start == .anytime { start = .inbox }
        order = Date().timeIntervalSinceReferenceDate
    }

    func duplicate(in context: ModelContext) -> TodoItem {
        let copy = TodoItem(title: title)
        context.insert(copy)
        copy.notes = notes
        copy.startRaw = startRaw
        copy.startDate = startDate
        copy.evening = evening
        copy.deadline = deadline
        copy.reminderAt = reminderAt
        copy.project = project
        copy.area = area
        copy.heading = heading
        copy.tags = tags
        for step in sortedChecklist {
            let s = ChecklistItem(title: step.title, order: step.order)
            context.insert(s)
            s.todo = copy
        }
        return copy
    }
}

// MARK: - Proyectos

extension Project {
    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .open }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .open ? nil : Date()
        }
    }
    var start: StartBucket {
        get { StartBucket(rawValue: startRaw) ?? .anytime }
        set { startRaw = newValue.rawValue }
    }
    var displayTitle: String { title.isEmpty ? "Nuevo proyecto" : title }
    var liveTodos: [TodoItem] { todos.filter { !$0.trashed } }
    var sortedHeadings: [Heading] { headings.sorted { $0.order < $1.order } }
    var openCount: Int { liveTodos.filter { $0.status == .open }.count }

    /// Fracción hecha, para el círculo de progreso (las canceladas no cuentan).
    var progress: Double {
        let counted = liveTodos.filter { $0.status != .canceled }
        guard !counted.isEmpty else { return 0 }
        return Double(counted.filter { $0.status == .completed }.count) / Double(counted.count)
    }

    func setWhen(_ choice: WhenChoice, today: Date) {
        switch choice {
        case .today, .evening:
            startDate = today
            start = .anytime
        case .date(let d):
            startDate = max(d.startOfDay, today)
            start = .anytime
        case .someday:
            startDate = nil
            start = .someday
        case .anytime, .inbox:
            startDate = nil
            start = .anytime
        }
    }

    /// Completa el proyecto y las tareas que quedaban abiertas.
    func complete() {
        for t in liveTodos where t.status == .open { t.status = .completed }
        status = .completed
    }
}

extension Area {
    var displayTitle: String { title.isEmpty ? "Nueva área" : title }
}

// MARK: - Qué tareas van en cada lista

/// Reglas de pertenencia a las listas. `recent` son las tareas completadas en esta visita, que siguen
/// a la vista (tachadas) hasta que se cambia de lista.
struct ListRules {
    let today: Date
    let recent: Set<PersistentIdentifier>
    var tomorrow: Date { today.adding(days: 1) }

    func visible(_ t: TodoItem) -> Bool {
        !t.trashed && t.parentActive && (t.status == .open || recent.contains(t.persistentModelID))
    }
    func inbox(_ t: TodoItem) -> Bool {
        visible(t) && t.start == .inbox && t.startDate == nil && t.project == nil && t.area == nil
    }
    func inToday(_ t: TodoItem) -> Bool {
        guard visible(t) else { return false }
        if let s = t.startDate, s < tomorrow { return true }
        if let d = t.deadline, d < tomorrow { return true }
        return false
    }
    func isEvening(_ t: TodoItem) -> Bool {
        guard t.evening, let s = t.startDate else { return false }
        return s >= today && s < tomorrow
    }
    /// Día en que aparece en Próximo (su fecha de inicio, o su fecha límite si no tiene inicio).
    func upcomingDate(_ t: TodoItem) -> Date? {
        guard visible(t) else { return nil }
        if let s = t.startDate { return s >= tomorrow ? s : nil }
        if let d = t.deadline, d >= tomorrow { return d }
        return nil
    }
    func anytime(_ t: TodoItem) -> Bool {
        guard visible(t), t.start == .anytime, !t.parentDeferred(today: today) else { return false }
        if let s = t.startDate { return s < tomorrow }
        return true
    }
    func someday(_ t: TodoItem) -> Bool {
        visible(t) && t.start == .someday && t.startDate == nil
    }
    /// Tareas abiertas que se muestran dentro de un proyecto o área.
    func inContainer(_ t: TodoItem) -> Bool {
        !t.trashed && (t.status == .open || recent.contains(t.persistentModelID))
    }
}
