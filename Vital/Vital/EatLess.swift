import Foundation
import UserNotifications

/// «Comer menos»: para los días sin ayuno. Un reto suave de calorías por debajo de lo que sueles comer,
/// una hora para cerrar la cocina y una idea práctica cada día. Nunca propone menos que tu metabolismo basal.
enum EatLess {
    /// Calorías por día (registradas en Comida), de los últimos `days` días sin contar hoy.
    static func pastDays(_ entries: [FoodEntry], days: Int = 7, now: Date = .now) -> [(day: Date, kcal: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var byDay: [Date: Double] = [:]
        let from = cal.date(byAdding: .day, value: -days, to: today)!
        for e in entries where e.date >= from && e.date < today {
            byDay[cal.startOfDay(for: e.date), default: 0] += e.nutrients.kcal
        }
        return (1...days).reversed().map { back in
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            return (day, byDay[day] ?? 0)
        }
    }

    /// Lo que sueles comer: la media de los días con un registro creíble (500 kcal o más). Hacen falta 3 días.
    static func usualIntake(_ entries: [FoodEntry], now: Date = .now) -> Double? {
        let logged = pastDays(entries, now: now).map(\.kcal).filter { $0 >= 500 }
        guard logged.count >= 3 else { return nil }
        return logged.reduce(0, +) / Double(logged.count)
    }

    /// El mínimo que Vital propone: tu metabolismo basal, y nunca menos de 1200 (mujer) o 1500 kcal (hombre).
    static func floor(bmr: Double, female: Bool) -> Double { max(bmr, female ? 1200 : 1500) }

    /// El reto del día: un `percent` menos de lo que sueles comer (o de tu gasto estimado si aún no hay registros).
    static func challenge(usual: Double?, bmr: Double, female: Bool, percent: Double) -> Double {
        let base = usual ?? bmr * 1.15 + 350
        return max(floor(bmr: bmr, female: female), (base * (1 - percent / 100) / 10).rounded() * 10)
    }

    /// Comidas de 50 kcal o más registradas después de la hora de cerrar la cocina, en los últimos 7 días.
    static func lateBites(_ entries: [FoodEntry], closeHour: Int, closeMinute: Int, now: Date = .now) -> Int {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!
        return entries.filter { e in
            guard e.date >= from, e.nutrients.kcal >= Fasting.breakingKcal else { return false }
            let c = cal.dateComponents([.hour, .minute], from: e.date)
            let minutes = c.hour! * 60 + c.minute!
            // Después del cierre y antes de las 4 de la mañana cuenta como «picar de noche».
            return minutes >= closeHour * 60 + closeMinute || minutes < 4 * 60
        }.count
    }

    struct Idea {
        let icon: String
        let title: String
        let text: String
    }

    /// Ideas con respaldo en estudios de conducta alimentaria; una distinta cada día.
    static let ideas: [Idea] = [
        Idea(icon: "circle.grid.2x1", title: "Plato más pequeño",
             text: "Sirve en un plato de postre o mediano: comes menos sin sentir que te falta."),
        Idea(icon: "leaf", title: "Verdura y proteína primero",
             text: "Empieza por la ensalada o la verdura y la proteína; el arroz y el pan, al final. Llenan antes."),
        Idea(icon: "drop", title: "Agua antes de comer",
             text: "Un vaso grande de agua 20–30 min antes de almorzar y cenar reduce lo que comes."),
        Idea(icon: "tortoise", title: "Come despacio",
             text: "Deja el tenedor entre bocados. La saciedad tarda unos 20 minutos en llegar."),
        Idea(icon: "cup.and.saucer", title: "Sin calorías líquidas",
             text: "Fresco natural, gaseosa, jugo o cerveza suman mucho sin llenar. Cámbialos por agua, té o café sin azúcar."),
        Idea(icon: "square.split.2x1", title: "Sirve una vez",
             text: "Sirve tu plato en la cocina y no lleves las ollas a la mesa: repetir es lo que más suma."),
        Idea(icon: "moon.zzz", title: "Cocina cerrada",
             text: "Después de cenar, lávate los dientes: es una señal simple de que ya terminaste de comer."),
        Idea(icon: "eye.slash", title: "Fuera de la vista",
             text: "Guarda galletas y snacks en un lugar cerrado y deja fruta a la vista. Comemos lo que vemos."),
        Idea(icon: "tv", title: "Comer sin pantalla",
             text: "Comer viendo el celular o la tele hace que comas más ahora y más tarde."),
        Idea(icon: "carrot", title: "Merienda planeada",
             text: "Si te da hambre a media tarde, ten lista fruta o un yogur natural antes de que llegue el antojo."),
    ]

    static func idea(for date: Date = .now) -> Idea {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return ideas[day % ideas.count]
    }

    // MARK: Aviso de cocina cerrada

    private static let kitchenID = "cocina-cerrada"

    /// Un aviso diario a la hora de cerrar la cocina (o ninguno si está apagado).
    static func scheduleKitchenReminder(enabled: Bool, hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [kitchenID])
        guard enabled else { return }
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Cocina cerrada"
            content.body = "Desde ahora, agua, té o café sin azúcar. Si cierras aquí, mañana llevas 12 h sin comer casi sin darte cuenta."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: kitchenID, content: content, trigger: trigger))
        }
    }
}
