import Foundation
import HealthKit

/// Cruces del ayuno con lo que Vital ya mide: sueño, recuperación, entreno, proteína, peso y glucosa.
/// Todo son comparaciones de tus propios datos; no prueban causa y efecto.
enum FastingInsights {

    // MARK: Sueño

    /// Horas entre la última comida y el inicio de cada noche (últimos 30 días), con la VFC y el sueño de esa noche.
    struct NightGap: Identifiable {
        var id: Date { day }
        let day: Date
        let gapHours: Double
        let hrv: Double?
        let asleepHours: Double
    }

    /// La última comida antes de dormir sale de lo que registraste en Comida o, si no, de cuándo empezaste el ayuno.
    static func nightGaps(days: [DayData], entries: [FoodEntry], sessions: [FastingSession]) -> [NightGap] {
        let mealTimes = entries.filter { $0.nutrients.kcal >= Fasting.breakingKcal }.map(\.date) + sessions.map(\.start)
        return days.suffix(30).compactMap { day in
            guard let night = day.sleep else { return nil }
            // Solo cuenta una comida de las 12 h antes de acostarse (si no, no hay registro de esa tarde).
            let window = night.start.addingTimeInterval(-12 * 3600)...night.start
            guard let last = mealTimes.filter({ window.contains($0) }).max() else { return nil }
            return NightGap(day: day.day, gapHours: night.start.timeIntervalSince(last) / 3600,
                            hrv: day.hrv, asleepHours: night.asleep / 3600)
        }
    }

    struct SleepComparison {
        let earlyNights: Int, lateNights: Int
        let earlyHRV: Double, lateHRV: Double
        let earlySleep: Double, lateSleep: Double
        var hrvChange: Double { (earlyHRV - lateHRV) / lateHRV }
    }

    /// Noches con 3 h o más entre la última comida y dormir frente a las de menos. Hacen falta 3 de cada.
    static func sleepComparison(_ gaps: [NightGap]) -> SleepComparison? {
        let early = gaps.filter { $0.gapHours >= 3 }, late = gaps.filter { $0.gapHours < 3 }
        let earlyHRV = early.compactMap(\.hrv), lateHRV = late.compactMap(\.hrv)
        guard earlyHRV.count >= 3, lateHRV.count >= 3 else { return nil }
        func mean(_ x: [Double]) -> Double { x.reduce(0, +) / Double(x.count) }
        return SleepComparison(earlyNights: early.count, lateNights: late.count,
                               earlyHRV: mean(earlyHRV), lateHRV: mean(lateHRV),
                               earlySleep: mean(early.map(\.asleepHours)), lateSleep: mean(late.map(\.asleepHours)))
    }

    /// Hora para cerrar la ventana y dejar 3 h antes de tu hora media de acostarte.
    static func lastMealTime(bedtime: DateComponents?) -> DateComponents? {
        guard let h = bedtime?.hour, let m = bedtime?.minute else { return nil }
        let total = (h * 60 + m - 180 + 1440) % 1440
        return DateComponents(hour: total / 60, minute: total % 60)
    }

    // MARK: Recuperación y entreno

    /// Una sugerencia para el ayuno de hoy según la recuperación y el entreno, o nil si no hay nada que decir.
    static func trainingAdvice(recovery: Recovery?, workouts: [Workout], active: FastingSession?, goal: Double) -> FastingTip? {
        let cal = Calendar.current
        let today = workouts.filter { cal.isDateInToday($0.start) }
        let hardToday = today.contains { TrainingModel.strain($0.load) >= 60 || ($0.effort ?? 0) >= 8 }
        if let active, let w = today.last(where: { $0.start > active.start && $0.duration >= 40 * 60 }) {
            return FastingTip(icon: "figure.strengthtraining.traditional", signal: .fair,
                              text: "Entrenaste \(Int(w.duration / 60)) min en ayunas. Rompe el ayuno en la próxima hora con proteína (25–40 g) para recuperar el músculo.")
        }
        if recovery?.signal == .poor && goal > 14 {
            return FastingTip(icon: "battery.25percent", signal: .poor,
                              text: "Recuperación baja hoy: el ayuno largo es otro estrés. Hoy vale más un ayuno de 12–14 h y dormir bien.")
        }
        if hardToday && goal >= 18 {
            return FastingTip(icon: "flame.fill", signal: .fair,
                              text: "Entreno exigente hoy y meta de \(Int(goal)) h: asegúrate de comer suficiente en la ventana, o baja a 16 h solo por hoy.")
        }
        return nil
    }

    // MARK: Proteína

    struct ProteinPlan {
        let target: Double
        let meals: Int
        var perMeal: Double { target / Double(meals) }
        /// Más de ~45 g por comida cuesta comerlo y se aprovecha peor.
        var isHard: Bool { perMeal > 45 }
    }

    /// Cuántas comidas caben en la ventana (una cada ~4 h, mínimo 2) y cuánta proteína toca en cada una.
    static func proteinPlan(weight: Double, goal: Double) -> ProteinPlan {
        let window = 24 - goal
        return ProteinPlan(target: weight * 1.8, meals: max(2, min(4, Int((window / 4).rounded(.down)) + 1)))
    }

    /// Proteína media de los últimos 14 días con comida registrada: días con ayuno cumplido frente al resto.
    static func proteinOnFastingDays(entries: [FoodEntry], sessions: [FastingSession]) -> (fasting: Double, other: Double, fastingDays: Int)? {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: .now))!
        var byDay: [Date: Double] = [:]
        for e in entries where e.date >= from && !cal.isDateInToday(e.date) {
            byDay[cal.startOfDay(for: e.date), default: 0] += e.nutrients.protein
        }
        let fastingDays = Set(sessions.filter(\.reachedGoal).compactMap { $0.end.map { cal.startOfDay(for: $0) } })
        let f = byDay.filter { fastingDays.contains($0.key) }.map(\.value)
        let o = byDay.filter { !fastingDays.contains($0.key) }.map(\.value)
        guard f.count >= 2 else { return nil }
        return (f.reduce(0, +) / Double(f.count), o.isEmpty ? 0 : o.reduce(0, +) / Double(o.count), f.count)
    }

    // MARK: Peso

    struct WeekPoint: Identifiable {
        var id: Date { week }
        let week: Date
        let weight: Double?
        let fastsMet: Int
    }

    /// Las últimas 8 semanas: peso medio y ayunos cumplidos en cada una.
    static func weeks(weights: [(date: Date, value: Double)], sessions: [FastingSession]) -> [WeekPoint] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)!.start
        return (0..<8).reversed().map { back in
            let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek)!
            let end = cal.date(byAdding: .day, value: 7, to: start)!
            let w = weights.filter { $0.date >= start && $0.date < end }.map(\.value)
            let met = sessions.filter { $0.reachedGoal && ($0.end.map { $0 >= start && $0 < end } ?? false) }.count
            return WeekPoint(week: start, weight: w.isEmpty ? nil : w.reduce(0, +) / Double(w.count), fastsMet: met)
        }
    }

    /// Cambio de peso entre la primera y la última semana con pesajes, y ayunos cumplidos por semana en ese tramo.
    static func weightSummary(_ weeks: [WeekPoint]) -> (change: Double, weeks: Int, fastsPerWeek: Double)? {
        let withWeight = weeks.filter { $0.weight != nil }
        guard let first = withWeight.first, let last = withWeight.last, first.week != last.week else { return nil }
        let span = weeks.filter { $0.week >= first.week && $0.week <= last.week }
        let n = Calendar.current.dateComponents([.weekOfYear], from: first.week, to: last.week).weekOfYear ?? 1
        return (last.weight! - first.weight!, n, Double(span.map(\.fastsMet).reduce(0, +)) / Double(span.count))
    }

    // MARK: Glucosa (si tienes un sensor que escribe en Salud)

    static func glucose(from start: Date, to end: Date) async -> [(date: Date, mgdl: Double)] {
        if ProcessInfo.processInfo.arguments.contains("-ayuno-demo") {
            // Curva de ejemplo: baja después de comer y se estabiliza.
            return stride(from: start, to: end, by: 1800).map { d in
                let h = d.timeIntervalSince(start) / 3600
                return (d, 88 + 40 * exp(-h / 1.5) - 6 * min(1, h / 14) + 3 * sin(h))
            }
        }
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let store = HKHealthStore()
        let type = HKQuantityType(.bloodGlucose)
        try? await store.requestAuthorization(toShare: [], read: [type])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let unit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.filter { $0.quantity.is(compatibleWith: unit) }.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    // MARK: Consejo para hoy

    /// El consejo de ayuno más útil ahora mismo (para la tarjeta y la pestaña Salud).
    @MainActor
    static func tip(health: VitalModel, workouts: [Workout], sessions: [FastingSession], weight: Double, goal: Double) -> FastingTip? {
        let active = sessions.last(where: \.isActive)
        if let t = trainingAdvice(recovery: health.todayRecovery, workouts: workouts, active: active, goal: goal) { return t }
        let plan = proteinPlan(weight: weight, goal: goal)
        if plan.isHard {
            return FastingTip(icon: "fork.knife", signal: .fair,
                              text: "Con \(Int(24 - goal)) h para comer te tocan \(plan.meals) comidas de \(Int(plan.perMeal)) g de proteína: es mucho. Prueba 14:10 o suma un batido.")
        }
        if active == nil, let time = lastMealTime(bedtime: health.bedtime?.average),
           let h = time.hour, let m = time.minute, Calendar.current.component(.hour, from: .now) >= 15 {
            return FastingTip(icon: "moon.zzz.fill", signal: .good,
                              text: String(format: "Para dejar 3 h antes de dormir, intenta terminar de comer a las %d:%02d.", h, m))
        }
        return nil
    }
}

struct FastingTip: Identifiable {
    let id = UUID()
    let icon: String
    let signal: Signal
    let text: String
}
