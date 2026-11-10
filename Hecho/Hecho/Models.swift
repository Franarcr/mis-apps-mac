import Foundation
import SwiftData

/// Estado de una tarea o proyecto.
enum ItemStatus: String {
    case open, completed, canceled
}

/// Dónde «vive» una tarea cuando no tiene fecha: en la Entrada, disponible ya, o guardada para algún día.
enum StartBucket: String {
    case inbox, anytime, someday
}

/// Una parte de la vida que nunca termina (Trabajo, Familia, Salud). Agrupa proyectos y tareas sueltas.
@Model final class Area {
    /// Identificador estable y fecha del último cambio, para sincronizar entre equipos.
    var uid: String = ""
    var modifiedAt: Date = Date.distantPast
    var title: String = ""
    var order: Double = 0
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \Project.area) var projects: [Project] = []
    @Relationship(deleteRule: .cascade, inverse: \TodoItem.area) var todos: [TodoItem] = []

    init(title: String, order: Double = Date().timeIntervalSinceReferenceDate) {
        self.uid = UUID().uuidString
        self.title = title
        self.order = order
    }
}

/// Algo con final y varios pasos. Puede estar dentro de un área.
@Model final class Project {
    /// Identificador estable y fecha del último cambio, para sincronizar entre equipos.
    var uid: String = ""
    var modifiedAt: Date = Date.distantPast
    var title: String = ""
    var notes: String = ""
    var order: Double = 0
    var createdAt: Date = Date()
    var statusRaw: String = ItemStatus.open.rawValue
    var completedAt: Date?
    var startRaw: String = StartBucket.anytime.rawValue
    var startDate: Date?
    var deadline: Date?
    var trashed: Bool = false
    var area: Area?
    @Relationship(deleteRule: .cascade, inverse: \Heading.project) var headings: [Heading] = []
    @Relationship(deleteRule: .cascade, inverse: \TodoItem.project) var todos: [TodoItem] = []

    init(title: String, area: Area? = nil, order: Double = Date().timeIntervalSinceReferenceDate) {
        self.uid = UUID().uuidString
        self.title = title
        self.area = area
        self.order = order
    }
}

/// Divide un proyecto en secciones.
@Model final class Heading {
    /// Identificador estable y fecha del último cambio, para sincronizar entre equipos.
    var uid: String = ""
    var modifiedAt: Date = Date.distantPast
    var title: String = ""
    var order: Double = 0
    var project: Project?
    @Relationship(deleteRule: .nullify, inverse: \TodoItem.heading) var todos: [TodoItem] = []

    init(title: String, project: Project, order: Double = Date().timeIntervalSinceReferenceDate) {
        self.uid = UUID().uuidString
        self.title = title
        self.project = project
        self.order = order
    }
}

/// Una tarea.
@Model final class TodoItem {
    var title: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    /// Orden dentro de su lista (Entrada, proyecto, área…).
    var order: Double = 0
    /// Orden dentro de Hoy.
    var todayOrder: Double = 0
    var startRaw: String = StartBucket.inbox.rawValue
    /// Día en que la tarea aparece en Hoy. Si es futuro, la tarea está en Próximo.
    var startDate: Date?
    var evening: Bool = false
    /// Día en que tiene que estar hecha. No cambia cuándo aparece, solo avisa.
    var deadline: Date?
    var statusRaw: String = ItemStatus.open.rawValue
    var completedAt: Date?
    var trashed: Bool = false
    /// Fecha y hora del aviso (cae el mismo día que `startDate`).
    var reminderAt: Date?
    /// Regla de repetición en JSON (ver `RepeatRule`).
    var repeatRaw: String?
    /// Identificador estable, para el widget y los avisos.
    var uid: String = ""
    /// Último cambio, para sincronizar entre equipos.
    var modifiedAt: Date = Date.distantPast
    /// Tarea creada al completar esta (si se repite); sirve para deshacer.
    var nextUID: String?
    /// Calendario donde va el evento de esta tarea (si es otro distinto al de siempre).
    var calendarID: String?
    var project: Project?
    var area: Area?
    var heading: Heading?
    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.todo) var checklist: [ChecklistItem] = []
    @Relationship(inverse: \TagItem.todos) var tags: [TagItem] = []

    init(title: String = "") {
        self.title = title
        self.uid = UUID().uuidString
        let now = Date().timeIntervalSinceReferenceDate
        self.order = now
        self.todayOrder = now
    }
}

/// Un paso dentro de una tarea.
@Model final class ChecklistItem {
    /// Identificador estable y fecha del último cambio, para sincronizar entre equipos.
    var uid: String = ""
    var modifiedAt: Date = Date.distantPast
    var title: String = ""
    var done: Bool = false
    var order: Double = 0
    var todo: TodoItem?

    init(title: String, order: Double = Date().timeIntervalSinceReferenceDate) {
        self.uid = UUID().uuidString
        self.title = title
        self.order = order
    }
}

/// Etiqueta para filtrar tareas.
@Model final class TagItem {
    /// Identificador estable y fecha del último cambio, para sincronizar entre equipos.
    var uid: String = ""
    var modifiedAt: Date = Date.distantPast
    var title: String = ""
    var order: Double = 0
    var todos: [TodoItem] = []

    init(title: String, order: Double = Date().timeIntervalSinceReferenceDate) {
        self.uid = UUID().uuidString
        self.title = title
        self.order = order
    }
}
