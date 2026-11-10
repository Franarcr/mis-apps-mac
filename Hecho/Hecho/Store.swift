import Foundation
import SwiftData

enum Store {
    static let schema = Schema([Area.self, Project.self, Heading.self, TodoItem.self, ChecklistItem.self, TagItem.self])

    /// Base de datos en «Application Support/Hecho» (en el Mac, en tu carpeta de usuario; en el iPhone, dentro de la app).
    static let container: ModelContainer = {
        let dir = URL.applicationSupportDirectory.appending(path: "Hecho", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: dir.appending(path: "Hecho.store"))
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("No se pudo abrir la base de datos de Hecho: \(error)")
        }
    }()

    /// Borra las tareas nuevas que quedaron sin escribir (por ejemplo, si la app se cerró con la tarjeta abierta).
    @MainActor static func removeEmpty(_ context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        for t in all where t.title.trimmingCharacters(in: .whitespaces).isEmpty && t.notes.isEmpty && t.checklist.isEmpty {
            context.delete(t)
        }
        try? context.save()
    }

    /// La primera vez llena la app con una pequeña guía para aprender a usarla.
    @MainActor static func seedIfNeeded(_ context: ModelContext) {
        let key = "hecho.semillaCargada"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let existing = (try? context.fetchCount(FetchDescriptor<TodoItem>())) ?? 0
        guard existing == 0 else { return }

        let today = Date().startOfDay
        var n = 0.0
        func next() -> Double { n += 1; return n }

        let tags = ["Llamadas", "Recados", "Casa"].map { TagItem(title: $0, order: next()) }
        tags.forEach(context.insert)

        let personal = Area(title: "Personal", order: next())
        let trabajo = Area(title: "Trabajo", order: next())
        context.insert(personal)
        context.insert(trabajo)

        let guide = Project(title: "Conoce Hecho", area: personal, order: next())
        guide.notes = "Una guía corta. Complétala paso a paso y luego bórrala."
        context.insert(guide)
        let basics = Heading(title: "Lo básico", project: guide, order: next())
        let organize = Heading(title: "Organizarte", project: guide, order: next())
        context.insert(basics)
        context.insert(organize)

        func add(_ title: String, notes: String = "", heading: Heading? = nil, project: Project? = nil,
                 area: Area? = nil, when: WhenChoice? = nil) -> TodoItem {
            let t = TodoItem(title: title)
            context.insert(t)
            t.notes = notes
            t.order = next()
            t.todayOrder = t.order
            if let project { t.move(project: project, heading: heading, area: nil) }
            if let area { t.move(project: nil, area: area) }
            t.order = n
            if let when { t.setWhen(when, today: today) }
            return t
        }

        #if os(macOS)
        let gestures = "Haz clic derecho sobre una tarea para ver todo lo que puedes hacer con ella, o arrástrala para cambiarla de orden."
        #else
        let gestures = "Desliza una tarea hacia la derecha para elegir cuándo hacerla, hacia la izquierda para borrarla, y mantenla presionada para moverla de lugar."
        #endif

        let t1 = add("Toca una tarea para abrirla", notes: "Se abre como una tarjeta con sus notas, pasos, etiquetas y fechas. Toca otra vez el título o «Listo» para cerrarla.",
                     heading: basics, project: guide)
        _ = t1
        _ = add("Usa los gestos", notes: gestures, heading: basics, project: guide)
        let steps = add("Divide una tarea en pasos", notes: "Abre la tarea y toca el icono de la lista para añadir pasos.", heading: basics, project: guide)
        for (i, s) in ["Primer paso", "Segundo paso", "Tercer paso"].enumerated() {
            let c = ChecklistItem(title: s, order: Double(i))
            context.insert(c)
            c.todo = steps
        }
        _ = add("Escribe las fechas como hablas", notes: "En «¿Cuándo?» puedes escribir: mañana, viernes, en 3 días, fin de semana, 15 dic…",
                heading: basics, project: guide, when: .today)
        _ = add("Revisa «Hoy» cada mañana", notes: "Decide qué harás hoy, pospón lo demás y ordénalo arrastrando.", heading: organize, project: guide)
        _ = add("Crea tus áreas y proyectos", notes: "Un área es algo que nunca termina (Salud, Trabajo). Un proyecto tiene final y varios pasos.",
                heading: organize, project: guide)
        let tagged = add("Ponle etiquetas a tus tareas", notes: "Luego puedes filtrar cualquier lista por etiqueta.", heading: organize, project: guide)
        tagged.tags = [tags[0]]
        _ = add("Guarda ideas en «Algún día»", heading: organize, project: guide, when: .someday)

        _ = add("Anota aquí lo que se te ocurra")
        let call = add("Llamar para pedir cita", area: personal, when: .evening)
        call.tags = [tags[0]]
        let report = add("Preparar el informe del mes", area: trabajo, when: .date(today.adding(days: 3)))
        report.deadline = today.adding(days: 5)

        try? context.save()
    }
}
