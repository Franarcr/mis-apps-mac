import Foundation
import HealthKit
import SwiftUI

/// Un entrenamiento del Apple Watch (o de otra app que guarde en Salud).
struct Workout: Identifiable {
    let id: UUID
    let activity: HKWorkoutActivityType
    let start: Date
    let end: Date
    let energy: Double?          // kcal activas
    let averageHR: Double?
    let maximumHR: Double?
    /// Esfuerzo de 1 a 10: el que tú pones en el reloj, o si no, el que estima el reloj.
    var effort: Double?
    /// Carga (TRIMP): minutos ponderados por lo alto que fue el pulso respecto a tu reserva cardiaca.
    var load: Double = 0
    /// Muestras de pulso durante el entrenamiento (vacío si el reloj no lo midió).
    var heartRate: [(date: Date, bpm: Double)] = []
    /// En interiores (true), al aire libre (false) o sin dato (nil), como lo guardó el reloj.
    var indoor: Bool?
    /// Nombre propio que le puso la app que lo guardó (p. ej. la rutina en Bevel).
    var title: String?
    /// App que lo guardó, si no fue el Apple Watch.
    var app: String?

    var duration: TimeInterval { end.timeIntervalSince(start) }
    /// El nombre de la actividad como en la app Fitness: «Caminata en interiores», «Ciclismo al aire libre»…
    var activityName: String {
        let base = Self.names[activity]?.0 ?? "Entrenamiento"
        guard Self.placed.contains(activity), let indoor else { return base }
        return base + (indoor ? " en interiores" : " al aire libre")
    }
    /// Lo que se muestra: el nombre propio si lo hay (la rutina de Bevel); si no, la actividad.
    var name: String { title ?? activityName }
    /// Debajo del nombre propio: la actividad y la app («Fuerza tradicional · Bevel»).
    var subtitle: String? {
        let parts = [title == nil ? nil : activityName, app].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var icon: String {
        if activity == .cycling, indoor == false { return "figure.outdoor.cycle" }
        return Self.names[activity]?.1 ?? "figure.mixed.cardio"
    }

    /// Actividades en las que Fitness dice si fue en interiores o al aire libre.
    private static let placed: Set<HKWorkoutActivityType> = [.walking, .running, .cycling]

    private static let names: [HKWorkoutActivityType: (String, String)] = [
        .running: ("Carrera", "figure.run"),
        .walking: ("Caminata", "figure.walk"),
        .cycling: ("Ciclismo", "figure.indoor.cycle"),
        .traditionalStrengthTraining: ("Fuerza tradicional", "figure.strengthtraining.traditional"),
        .functionalStrengthTraining: ("Fuerza funcional", "figure.strengthtraining.functional"),
        .highIntensityIntervalTraining: ("HIIT", "figure.highintensity.intervaltraining"),
        .swimming: ("Natación", "figure.pool.swim"),
        .yoga: ("Yoga", "figure.yoga"),
        .hiking: ("Senderismo", "figure.hiking"),
        .elliptical: ("Elíptica", "figure.elliptical"),
        .rowing: ("Remo", "figure.rower"),
        .soccer: ("Fútbol", "figure.indoor.soccer"),
        .coreTraining: ("Core", "figure.core.training"),
        .mixedCardio: ("Cardio", "figure.mixed.cardio"),
        .stairClimbing: ("Escaladora", "figure.stair.stepper"),
        .socialDance: ("Baile", "figure.dance"),
        .cardioDance: ("Baile cardio", "figure.dance"),
        .pilates: ("Pilates", "figure.pilates"),
        .cooldown: ("Enfriamiento", "figure.cooldown"),
        .flexibility: ("Estiramientos", "figure.flexibility"),
        .tennis: ("Tenis", "figure.tennis"),
        .basketball: ("Baloncesto", "figure.basketball"),
    ]
}

/// Lectura de entrenamientos y forma física desde Salud.
final class TrainingReader {
    private let store = HKHealthStore()
    private let calendar = Calendar.current
    private let perMinute = HKUnit.count().unitDivided(by: .minute())

    private let heartRateType = HKQuantityType(.heartRate)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let vo2Type = HKQuantityType(.vo2Max)
    private let recoveryType = HKQuantityType(.heartRateRecoveryOneMinute)
    private let effortType = HKQuantityType(.workoutEffortScore)
    private let estimatedEffortType = HKQuantityType(.estimatedWorkoutEffortScore)

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [
            HKObjectType.workoutType(), heartRateType, energyType, vo2Type, recoveryType, effortType, estimatedEffortType,
            HKCharacteristicType(.dateOfBirth),
        ])
    }

    /// Frecuencia máxima estimada por la edad (Tanaka: 208 − 0,7 × edad), o 190 si no hay fecha de nacimiento.
    func maximumHeartRate() -> Double {
        guard let birth = try? store.dateOfBirthComponents(), let year = birth.year else { return 190 }
        let age = Double(calendar.component(.year, from: .now) - year)
        return 208 - 0.7 * age
    }

    func workouts(days: Int) async throws -> [Workout] {
        let from = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now))!
        let range = HKQuery.predicateForSamples(withStart: from, end: .now)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(range)], sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
        let samples = try await descriptor.result(for: store)
        let efforts = try await quantities(effortType, range)
        let estimated = try await quantities(estimatedEffortType, range)

        var list: [Workout] = []
        for w in samples {
            let hr = w.statistics(for: heartRateType)
            var workout = Workout(
                id: w.uuid, activity: w.workoutActivityType, start: w.startDate, end: w.endDate,
                energy: w.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                averageHR: hr?.averageQuantity()?.doubleValue(for: perMinute),
                maximumHR: hr?.maximumQuantity()?.doubleValue(for: perMinute))
            workout.indoor = w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool
            workout.title = (w.metadata?[HKMetadataKeyWorkoutBrandName] as? String)?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            let source = w.sourceRevision.source
            if !source.bundleIdentifier.hasPrefix("com.apple") { workout.app = source.name }
            // El esfuerzo se guarda aparte, con la hora del entrenamiento.
            let matches: (HKQuantitySample) -> Bool = { $0.startDate >= w.startDate.addingTimeInterval(-60) && $0.startDate <= w.endDate.addingTimeInterval(3600) }
            workout.effort = (efforts.first(where: matches) ?? estimated.first(where: matches))
                .map { $0.quantity.doubleValue(for: .appleEffortScore()) }
            let during = HKQuery.predicateForSamples(withStart: w.startDate, end: w.endDate)
            workout.heartRate = try await quantities(heartRateType, during)
                .map { ($0.startDate, $0.quantity.doubleValue(for: perMinute)) }
            // Entrenos guardados por apps (como Vital) sin pulso propio: el que midió el reloj en ese rato.
            if workout.averageHR == nil, !workout.heartRate.isEmpty {
                let bpm = workout.heartRate.map(\.bpm)
                workout = Workout(id: workout.id, activity: workout.activity, start: workout.start, end: workout.end,
                                  energy: workout.energy, averageHR: bpm.reduce(0, +) / Double(bpm.count), maximumHR: bpm.max(),
                                  effort: workout.effort, load: workout.load, heartRate: workout.heartRate,
                                  indoor: workout.indoor, title: workout.title, app: workout.app)
            }
            list.append(workout)
        }
        return list
    }

    /// Segundos en cada zona de pulso (1 a 5, por % de la frecuencia máxima) durante un entrenamiento.
    func zones(for workout: Workout, maximum: Double) async throws -> [TimeInterval] {
        let range = HKQuery.predicateForSamples(withStart: workout.start, end: workout.end)
        let samples = try await quantities(heartRateType, range)
        var zones = [TimeInterval](repeating: 0, count: 5)
        for (index, sample) in samples.enumerated() {
            let next = index + 1 < samples.count ? samples[index + 1].startDate : workout.end
            let seconds = min(60, next.timeIntervalSince(sample.startDate))   // huecos largos no cuentan
            let percent = sample.quantity.doubleValue(for: perMinute) / maximum
            guard percent >= 0.5 else { continue }
            zones[min(4, Int((percent - 0.5) * 10))] += seconds
        }
        return zones
    }

    /// Últimas mediciones (fecha, valor) de VO₂ máx. y de recuperación cardiaca, de los últimos `days` días.
    func fitness(days: Int) async throws -> (vo2: [(Date, Double)], recovery: [(Date, Double)]) {
        let from = calendar.date(byAdding: .day, value: -days, to: .now)!
        let range = HKQuery.predicateForSamples(withStart: from, end: .now)
        let vo2Unit = HKUnit(from: "ml/kg*min")
        let vo2 = try await quantities(vo2Type, range).map { ($0.startDate, $0.quantity.doubleValue(for: vo2Unit)) }
        let recovery = try await quantities(recoveryType, range).map { ($0.startDate, $0.quantity.doubleValue(for: perMinute)) }
        return (vo2, recovery)
    }

    private func quantities(_ type: HKQuantityType, _ predicate: NSPredicate) async throws -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }
}

@MainActor
final class TrainingModel: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var vo2: [(Date, Double)] = []
    @Published var heartRateRecovery: [(Date, Double)] = []
    @Published var loaded = false
    @Published var error: String?

    let reader = TrainingReader()
    private(set) var maximumHR: Double = 190
    private(set) var restingHR: Double = 60
    private let calendar = Calendar.current

    static let historyDays = 42

    func load(restingHR: Double?) async {
        self.restingHR = restingHR ?? 60
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            showDemo()
            return
        }
        do {
            try await reader.requestAccess()
            maximumHR = reader.maximumHeartRate()
            var list = try await reader.workouts(days: Self.historyDays)
            // Si alguna vez llegaste más alto que la estimación por edad, la estimación se queda corta.
            if let peak = list.compactMap(\.maximumHR).max(), peak > maximumHR { maximumHR = peak }
            for i in list.indices { list[i].load = load(of: list[i]) }
            workouts = list
            let fitness = try await reader.fitness(days: 180)
            vo2 = fitness.vo2
            heartRateRecovery = fitness.recovery
            if ProcessInfo.processInfo.arguments.contains("-depurar") {
                for (d, v) in vo2 { print("VO2 \(d.formatted(.iso8601.year().month().day())) \(v)") }
                for (d, v) in heartRateRecovery { print("RCF \(d.formatted(.iso8601.year().month().day())) \(v)") }
            }
            #if targetEnvironment(simulator)
            if workouts.isEmpty { showDemo() }
            #endif
            loaded = true
        } catch {
            self.error = error.localizedDescription
            loaded = true
        }
    }

    /// TRIMP de Banister: minutos × reserva de pulso usada × un factor que crece rápido con la intensidad.
    /// Se suma muestra a muestra: con el pulso medio, unos minutos en Z4 entre calentamiento y vuelta a la calma
    /// casi no contaban. Sin muestras suficientes se usa el pulso medio, y sin pulso (p. ej. un registro manual)
    /// el esfuerzo de 1 a 10, o como caminar suave.
    /// En pesas el pulso medio se queda corto (sube en cada serie y baja en los descansos), así que ahí cuenta
    /// también el esfuerzo de 1 a 10 (sRPE: minutos × esfuerzo) y se usa la mayor de las dos cargas.
    private func load(of workout: Workout) -> Double {
        let minutes = workout.duration / 60
        let weight: (Double) -> Double = { reserve in reserve * 0.64 * exp(1.92 * reserve) }
        let reserve: (Double) -> Double = { bpm in min(1, max(0, (bpm - self.restingHR) / (self.maximumHR - self.restingHR))) }
        let trimp: Double
        if let fromSamples = sampledLoad(workout, weight: { weight(reserve($0)) }) {
            trimp = fromSamples
        } else if let hr = workout.averageHR {
            trimp = minutes * weight(reserve(hr))
        } else {
            trimp = minutes * weight((workout.effort ?? 3) / 12)
        }
        guard Self.heartRateMisses.contains(workout.activity), let effort = workout.effort else { return trimp }
        return max(trimp, 0.5 * minutes * effort)
    }

    /// Carga sumando cada muestra de pulso por el tiempo hasta la siguiente (huecos de más de un minuto no cuentan),
    /// o nil si las muestras cubren menos de la mitad del entrenamiento.
    private func sampledLoad(_ workout: Workout, weight: (Double) -> Double) -> Double? {
        let samples = workout.heartRate
        var covered: TimeInterval = 0, total = 0.0
        for (index, sample) in samples.enumerated() {
            let next = index + 1 < samples.count ? samples[index + 1].date : workout.end
            let seconds = min(60, max(0, next.timeIntervalSince(sample.date)))
            covered += seconds
            total += seconds / 60 * weight(sample.bpm)
        }
        return covered >= workout.duration / 2 ? total : nil
    }

    /// Entrenamientos en los que el pulso medio no refleja el esfuerzo real.
    private static let heartRateMisses: Set<HKWorkoutActivityType> = [
        .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining,
        .highIntensityIntervalTraining, .crossTraining,
    ]

    /// Carga total de cada uno de los últimos `days` días (el último es hoy).
    func dailyLoad(days: Int) -> [(day: Date, load: Double)] {
        let today = calendar.startOfDay(for: .now)
        return (0..<days).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            let total = workouts.filter { calendar.isDate($0.start, inSameDayAs: day) }.map(\.load).reduce(0, +)
            return (day, total)
        }
    }

    /// Esfuerzo del día de 0 a 100, en escala logarítmica como Bevel o Whoop: una sesión corta pero intensa ya suma
    /// bastante, y cuesta cada vez más acercarse a 100. Ajustada a dos sesiones medidas en Bevel: 10 min de escaladora
    /// con 7 en Z4 ≈ 27 y una pierna de 55 min con esfuerzo 8 ≈ 78.
    nonisolated static func strain(_ load: Double) -> Int { Int(min(100, 21.5 * log(1 + load / 6)).rounded()) }

    var todayStrain: Int { Self.strain(dailyLoad(days: 1).first?.load ?? 0) }

    /// Carga de los últimos 7 días frente a la media semanal de las últimas 4 semanas.
    /// Entre 0,8 y 1,3 es la zona segura; por encima de 1,5 sube el riesgo de lesión.
    /// Hacen falta al menos 3 semanas de entrenos registrados: con menos, el mes parece flojo y el número sale inflado.
    var loadRatio: (acute: Double, chronic: Double, ratio: Double)? {
        guard let first = workouts.map(\.start).min(), first < calendar.date(byAdding: .day, value: -21, to: .now)! else { return nil }
        let days = dailyLoad(days: 28).map(\.load)
        let chronic = days.reduce(0, +) / 4
        guard chronic > 0 else { return nil }
        let acute = days.suffix(7).reduce(0, +)
        return (acute, chronic, acute / chronic)
    }

    static func ratioSignal(_ ratio: Double) -> Signal {
        (0.8...1.3).contains(ratio) ? .good : (ratio > 1.5 || ratio < 0.5) ? .poor : .fair
    }

    /// Rango de esfuerzo recomendado para hoy según la recuperación.
    static func target(for recovery: Recovery?) -> ClosedRange<Int> {
        switch recovery?.signal {
        case .good: 60...85
        case .fair: 35...60
        case .poor: 10...35
        case nil: 35...60
        }
    }

    private func showDemo() {
        maximumHR = 185
        let now = Date.now
        func make(_ activity: HKWorkoutActivityType, daysAgo: Int, hour: Int, minutes: Double, hr: Double, effort: Double) -> Workout {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
            let start = calendar.date(byAdding: .hour, value: hour, to: day)!
            var w = Workout(id: UUID(), activity: activity, start: start, end: start.addingTimeInterval(minutes * 60),
                            energy: minutes * hr / 18, averageHR: hr, maximumHR: hr + 25, effort: effort)
            w.load = load(of: w)
            return w
        }
        var list: [Workout] = [make(.traditionalStrengthTraining, daysAgo: 0, hour: 7, minutes: 55, hr: 118, effort: 6)]
        for d in 1..<Self.historyDays where d % 7 != 3 {
            list.append(d % 2 == 0
                ? make(.running, daysAgo: d, hour: 6, minutes: Double(30 + d % 4 * 8), hr: Double(138 + d % 5 * 4), effort: Double(5 + d % 3))
                : make(.traditionalStrengthTraining, daysAgo: d, hour: 18, minutes: 50, hr: 115, effort: 6))
        }
        workouts = list
        vo2 = (0..<12).map { (calendar.date(byAdding: .day, value: -$0 * 14, to: now)!, 42.5 - Double($0) * 0.25) }.reversed()
        heartRateRecovery = (0..<10).map { (calendar.date(byAdding: .day, value: -$0 * 4, to: now)!, 24 + Double($0 % 3)) }.reversed()
        loaded = true
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
