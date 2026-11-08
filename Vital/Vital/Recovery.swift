import Foundation
import SwiftUI

/// Recuperación del día (0–100), comparando la noche con tu propia línea base de los 30 días anteriores.
/// Pesa sobre todo la VFC (más alta que lo normal = mejor recuperado) y el pulso en reposo (más bajo = mejor).
/// Restan puntos: dormir menos de la meta, la temperatura de la muñeca fuera de tu rango, respirar más
/// rápido que lo normal y la SpO₂ baja (señales típicas de cansancio o de que te estás enfermando).
struct Recovery {
    let score: Int

    static let baselineDays = 30
    static let minimumBaseline = 7
    static let sleepGoal: TimeInterval = 7.5 * 3600

    var signal: Signal { score >= 67 ? .good : score >= 34 ? .fair : .poor }

    var title: String {
        switch signal {
        case .good: "Bien recuperado"
        case .fair: "Recuperación media"
        case .poor: "Poco recuperado"
        }
    }

    var advice: String {
        switch signal {
        case .good: "Buen día para entrenar fuerte."
        case .fair: "Entrena, pero sin buscar marcas."
        case .poor: "Mejor algo suave o descanso activo."
        }
    }

    /// `nil` si ese día no hay VFC o aún no hay suficientes días para tener una base.
    static func compute(for index: Int, in days: [DayData]) -> Recovery? {
        let day = days[index]
        guard let hrv = day.hrv else { return nil }
        let previous = Array(days[max(0, index - baselineDays)..<index])
        let hrvBase = previous.compactMap(\.hrv)
        guard hrvBase.count >= minimumBaseline else { return nil }

        let (hrvMean, hrvSD) = stats(hrvBase)
        // La VFC varía mucho de un día a otro: la desviación nunca se toma menor que el 5 % de la media.
        // Pesos ajustados a Bevel con 8 días de tus datos (29 oct – 5 nov 2026; error medio ±4 puntos):
        // la VFC es lo que más pesa, el pulso en reposo ayuda poco y dormir menos de la meta resta.
        let raw = clamp((hrv - hrvMean) / max(hrvSD, hrvMean * 0.05), -2, 2)
        var score = 55 + 31 * raw
        if let resting = day.restingHR, let base = baseline(previous, \.restingHR) {
            score -= 8 * clamp((resting - base.mean) / max(base.sd, 1), -2, 2)
        }
        if let sleep = day.sleep {
            // Dormir menos de la meta resta (hasta 26 puntos sin dormir nada); dormir de más no suma.
            score -= 26 * max(0, 1 - sleep.asleep / sleepGoal)
        }
        if let temp = day.wristTemperature, let mean = baseline(previous, \.wristTemperature)?.mean {
            // Solo la temperatura alta (posible fiebre o infección): desde +0,3 °C sobre tu base, hasta 15 puntos.
            score -= clamp((temp - mean - 0.3) * 25, 0, 15)
        }
        if let rate = day.respiratoryRate, let mean = baseline(previous, \.respiratoryRate)?.mean {
            score -= clamp((rate - mean - 0.5) * 8, 0, 10)
        }
        if let oxygen = day.oxygen, let mean = baseline(previous, \.oxygen)?.mean {
            // SpO₂ más de 1,5 puntos por debajo de tu normal (no de un valor fijo: el reloj de noche suele marcar 92–95 %).
            score -= clamp((mean - oxygen - 1.5) * 4, 0, 10)
        }
        if index >= days.count - 8, ProcessInfo.processInfo.arguments.contains("-depurar") {
            let rhrBase = baseline(previous, \.restingHR), tBase = baseline(previous, \.wristTemperature), rBase = baseline(previous, \.respiratoryRate)
            print("RECUP \(day.day.formatted(.dateTime.day().month())) vfc \(hrv) base \(hrvMean)±\(hrvSD) n=\(hrvBase.count) | fcr \(day.restingHR ?? -1) base \(rhrBase?.mean ?? -1)±\(rhrBase?.sd ?? -1) | raw \(raw) | sueño \((day.sleep?.asleep ?? -1) / 3600) | temp \(day.wristTemperature ?? -1) base \(tBase?.mean ?? -1) | fr \(day.respiratoryRate ?? -1) base \(rBase?.mean ?? -1) | spo2 \(day.oxygen ?? -1) | final \(score)")
        }
        return Recovery(score: Int(clamp(score, 1, 99).rounded()))
    }

    static func baseline(_ days: [DayData], _ metric: KeyPath<DayData, Double?>) -> (mean: Double, sd: Double)? {
        let values = days.compactMap { $0[keyPath: metric] }
        return values.count >= minimumBaseline ? stats(values) : nil
    }

    static func stats(_ values: [Double]) -> (mean: Double, sd: Double) {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(1, values.count - 1))
        return (mean, variance.squareRoot())
    }

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
}

@MainActor
final class VitalModel: ObservableObject {
    enum State: Equatable {
        case loading, ready, unavailable, failed(String)
    }

    @Published var state: State = .loading
    @Published var days: [DayData] = []
    @Published var recoveries: [Date: Recovery] = [:]
    /// En el simulador no hay datos del reloj: se muestran unos de ejemplo.
    @Published var isDemo = false
    @Published var heartRate: HeartRateToday?
    @Published var alerts: [WatchAlert] = []

    private let reader = HealthReader()
    static let historyDays = 60

    var today: DayData? { days.last }
    /// La de hoy es la primera lectura después de despertar (queda fija todo el día).
    var todayRecovery: Recovery? { today.flatMap { recoveries[$0.day] } }
    /// La de hoy calculada con los datos de este momento (cambia si el reloj sigue pasando medidas de la noche).
    @Published var liveRecovery: Recovery?
    var daysWithHRV: Int { days.compactMap(\.hrv).count }

    /// Media y desviación de los 30 días anteriores a hoy, o `nil` si hay menos de 7 días con ese dato.
    func baseline(_ metric: KeyPath<DayData, Double?>) -> (mean: Double, sd: Double)? {
        Recovery.baseline(Array(days.dropLast().suffix(Recovery.baselineDays)), metric)
    }

    /// Lo que te faltó dormir en los últimos 7 días respecto a la meta (dormir de más no compensa).
    var sleepDebt: TimeInterval {
        days.suffix(7).compactMap(\.sleep).map { max(0, Recovery.sleepGoal - $0.asleep) }.reduce(0, +)
    }

    /// Hora media de acostarse en los últimos 14 días y cuánto varía (desviación en minutos).
    var bedtime: (average: DateComponents, spread: Double)? {
        let calendar = Calendar.current
        // Minutos desde las 18 h, para que las 11 p.m. y la 1 a.m. queden cerca.
        let minutes = days.suffix(14).compactMap(\.sleep).map { night -> Double in
            let c = calendar.dateComponents([.hour, .minute], from: night.start)
            return Double(((c.hour ?? 0) + 6) % 24 * 60 + (c.minute ?? 0))
        }
        guard minutes.count >= 3 else { return nil }
        let (mean, sd) = Recovery.stats(minutes)
        let total = (Int(mean.rounded()) + 18 * 60) % (24 * 60)
        return (DateComponents(hour: total / 60, minute: total % 60), sd)
    }

    func load() async {
        // `-demo` al abrirla (solo para probar en el simulador): datos de ejemplo sin pasar por Salud.
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            showDemo()
            return
        }
        guard HealthReader.isAvailable else { state = .unavailable; return }
        do {
            try await reader.requestAccess()
            let loaded = try await reader.load(days: Self.historyDays)
            #if targetEnvironment(simulator)
            if loaded.allSatisfy({ $0.hrv == nil && $0.sleep == nil }) {
                showDemo()
                return
            }
            #endif
            heartRate = try await reader.heartRateToday()
            alerts = try await reader.alerts(days: 30)
            show(loaded, demo: false)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Guarda la primera recuperación del día, una vez terminada la noche, y la devuelve desde entonces.
    /// `-fijar-recuperacion 60` (al abrirla desde el Mac) fija a mano la de hoy.
    private func fixedScore(for today: DayData, live: Int) -> Int {
        let key = "recuperacionFijada"
        let day = ISO8601DateFormatter.dayFormatter.string(from: today.day)
        var saved = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-fijar-recuperacion"), i + 1 < args.count, let value = Int(args[i + 1]) {
            saved[day] = value
        }
        if saved[day] == nil, let end = today.sleep?.end, end < .now { saved[day] = live }
        // Solo se guardan las últimas semanas.
        saved = saved.filter { $0.key >= ISO8601DateFormatter.dayFormatter.string(from: .now.addingTimeInterval(-30 * 86400)) }
        UserDefaults.standard.set(saved, forKey: key)
        return saved[day] ?? live
    }

    private func showDemo() {
        heartRate = HeartRateToday(latest: 68, latestDate: .now.addingTimeInterval(-300), minimum: 52, maximum: 131, average: 71)
        alerts = []
        show(DemoData.days(Self.historyDays), demo: true)
    }

    private func show(_ loaded: [DayData], demo: Bool) {
        isDemo = demo
        days = loaded
        var result: [Date: Recovery] = [:]
        for index in loaded.indices {
            if let recovery = Recovery.compute(for: index, in: loaded) { result[loaded[index].day] = recovery }
        }
        liveRecovery = loaded.last.flatMap { result[$0.day] }
        if !demo, let today = loaded.last, let live = liveRecovery { result[today.day] = Recovery(score: fixedScore(for: today, live: live.score)) }
        recoveries = result
        state = .ready
    }
}

/// Datos inventados con forma realista, solo para el simulador.
enum DemoData {
    static func days(_ count: Int) -> [DayData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var generator = SeededGenerator(seed: 42)
        return (0..<count).map { i in
            let day = calendar.date(byAdding: .day, value: i - count + 1, to: today)!
            let hours = Double.random(in: 5.6...8.4, using: &generator)
            let start = calendar.date(byAdding: .minute, value: -Int.random(in: 60...110, using: &generator), to: day)!
            let asleep = hours * 3600
            var night = SleepNight(start: start, end: start.addingTimeInterval(asleep + 1800))
            night.deep = asleep * 0.16; night.rem = asleep * 0.22; night.core = asleep * 0.62; night.awake = 1800
            let hrv = 48 + 6 * sin(Double(i) / 4) + Double.random(in: -7...7, using: &generator)
            let resting = 57 - (hrv - 48) * 0.25 + Double.random(in: -1.5...1.5, using: &generator)
            return DayData(day: day, sleep: night, hrv: hrv, restingHR: resting,
                           respiratoryRate: Double.random(in: 14...16, using: &generator),
                           oxygen: Double.random(in: 95...98, using: &generator),
                           wristTemperature: 35.4 + Double.random(in: -0.3...0.3, using: &generator),
                           breathingDisturbances: Double.random(in: 2...6, using: &generator))
        }
    }

    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
}
