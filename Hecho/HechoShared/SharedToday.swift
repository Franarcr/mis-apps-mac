import Foundation
import WidgetKit

/// Lo que la app le pasa al widget: las tareas de hoy (y de los próximos días, para el cambio de día).
/// Se guarda en el grupo de apps compartido, así el widget no necesita abrir la base de datos.
struct SnapTask: Codable, Identifiable, Hashable {
    var uid: String
    var title: String
    var context: String?
    var evening: Bool
    var startDate: Date?
    var deadline: Date?
    var reminderAt: Date?
    var order: Double

    var id: String { uid }

    /// ¿Va en Hoy el día `today`?
    func isToday(_ today: Date) -> Bool {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: today)) ?? today
        if let s = startDate, s < tomorrow { return true }
        if let d = deadline, d < tomorrow { return true }
        return false
    }
}

enum SharedToday {
    static let appGroup = "group.com.francho.hecho"
    static let widgetKind = "HechoHoy"
    private static let tasksKey = "hecho.widget.tareas"
    private static let pendingKey = "hecho.widget.completadas"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func load() -> [SnapTask] {
        guard let data = defaults.data(forKey: tasksKey),
              let tasks = try? JSONDecoder().decode([SnapTask].self, from: data) else { return [] }
        return tasks
    }

    static func save(_ tasks: [SnapTask]) {
        let old = defaults.data(forKey: tasksKey)
        guard let data = try? JSONEncoder().encode(tasks), data != old else { return }
        defaults.set(data, forKey: tasksKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Tareas de hoy, en el orden de la lista Hoy (primero el día, luego «Esta noche»).
    static func today(_ now: Date = Date()) -> [SnapTask] {
        load().filter { $0.isToday(now) }.sorted { ($0.evening ? 1 : 0, $0.order) < ($1.evening ? 1 : 0, $1.order) }
    }

    // MARK: Completadas desde el widget

    /// El widget marca la tarea como hecha; la app lo aplica al abrirse.
    static func markDone(_ uid: String) {
        var pending = defaults.stringArray(forKey: pendingKey) ?? []
        if !pending.contains(uid) { pending.append(uid) }
        defaults.set(pending, forKey: pendingKey)
        let tasks = load().filter { $0.uid != uid }
        if let data = try? JSONEncoder().encode(tasks) { defaults.set(data, forKey: tasksKey) }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func takePending() -> [String] {
        let pending = defaults.stringArray(forKey: pendingKey) ?? []
        if !pending.isEmpty { defaults.removeObject(forKey: pendingKey) }
        return pending
    }
}
