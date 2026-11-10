import Foundation
import SwiftData
import UserNotifications

/// Mantiene al día lo que vive fuera de la base de datos: los avisos programados y las tareas del widget.
@MainActor enum Sync {
    /// Aplica lo completado desde el widget, reprograma los avisos y actualiza el widget.
    static func run(_ context: ModelContext, state: AppState?) {
        let all = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        for t in all where t.uid.isEmpty { t.uid = UUID().uuidString }

        let pending = Set(SharedToday.takePending())
        if !pending.isEmpty {
            for t in all where pending.contains(t.uid) && t.status == .open { t.finish(.completed, state: nil) }
            try? context.save()
        }

        let now = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let live = now.filter { $0.status == .open && !$0.trashed && $0.parentActive }
        Reminders.schedule(live)
        CalendarExport.sync(now)
        writeWidget(live)
    }

    private static func writeWidget(_ live: [TodoItem]) {
        let limit = Date().startOfDay.adding(days: 3)
        let tasks = live.filter { t in
            (t.startDate.map { $0 < limit } ?? false) || (t.deadline.map { $0 < limit } ?? false)
        }.map {
            SnapTask(uid: $0.uid, title: $0.displayTitle, context: $0.contextName, evening: $0.evening,
                     startDate: $0.startDate, deadline: $0.deadline, reminderAt: $0.reminderAt, order: $0.todayOrder)
        }
        SharedToday.save(tasks)
    }
}

/// Avisos con hora.
enum Reminders {
    static let center = UNUserNotificationCenter.current()
    private static let delegate = ForegroundBanner()

    static func setUp() { center.delegate = delegate }

    /// Pide permiso para avisar (solo pregunta la primera vez).
    static func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorized() async -> Bool {
        let s = await center.notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Reemplaza todos los avisos pendientes por los de las tareas abiertas con aviso futuro.
    @MainActor static func schedule(_ live: [TodoItem]) {
        let now = Date()
        let items = live.compactMap { t -> (TodoItem, Date)? in
            guard let r = t.reminderAt, r > now else { return nil }
            return (t, r)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(60)
        .map { (uid: $0.0.uid, title: $0.0.displayTitle, body: $0.0.contextName ?? $0.0.notes, date: $0.1) }

        center.removeAllPendingNotificationRequests()
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = String(item.body.prefix(120))
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let request = UNNotificationRequest(identifier: item.uid, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(request)
        }
    }
}

/// Muestra el aviso aunque la app esté abierta.
private final class ForegroundBanner: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
