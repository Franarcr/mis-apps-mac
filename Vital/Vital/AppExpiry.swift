import SwiftUI
import UserNotifications

/// Cuándo deja de abrir Vital: el perfil de instalación gratuito de Xcode dura 7 días.
/// La fecha exacta viene dentro de la app (embedded.mobileprovision) y cambia sola con cada reinstalación.
enum AppExpiry {
    static let date: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    /// Días completos que faltan (0 = vence hoy).
    static func daysLeft(now: Date = .now) -> Int? {
        guard let date else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day
    }

    /// Programa el aviso para el día antes a las 9:00 (o en una hora si ya pasó). Se reprograma en cada apertura.
    static func scheduleReminder() async {
        guard let date else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["vital-caduca"])
        let cal = Calendar.current
        var fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: date) ?? date) ?? date
        if fire < .now { fire = .now.addingTimeInterval(3600) }
        guard fire < date else { return }
        let content = UNMutableNotificationContent()
        content.title = "Vital caduca mañana"
        content.body = "Conecta el iPhone a la Mac para reinstalarla antes del \(date.formatted(.dateTime.weekday(.wide).day().hour().minute()))."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "vital-caduca", content: content, trigger: trigger))
    }
}

/// Línea en la pantalla Salud: «Vital caduca en 5 días (jue 12 nov)».
struct AppExpiryBanner: View {
    var body: some View {
        if let date = AppExpiry.date, let days = AppExpiry.daysLeft() {
            let urgent = days <= 2
            let when = days <= 0 ? "hoy" : days == 1 ? "mañana" : "en \(days) días"
            VStack(alignment: .leading, spacing: 2) {
                Label("Vital caduca \(when) (\(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())))",
                      systemImage: urgent ? "exclamationmark.triangle.fill" : "clock")
                if urgent { Text("Conecta el iPhone a la Mac para reinstalar.").font(.caption2) }
            }
            .font(.caption)
            .foregroundStyle(urgent ? .orange : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
