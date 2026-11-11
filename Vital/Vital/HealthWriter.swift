import Foundation
import HealthKit

/// Lo que Vital escribe en Salud: cada comida registrada (calorías, macros, azúcar, fibra, sodio)
/// y los entrenos de las rutinas que no grabó el reloj.
enum HealthWriter {
    private static let store = HKHealthStore()
    /// Marca de cada registro de Vital en Salud, para poder cambiarlo o borrarlo después.
    private static let entryKey = "VitalRegistro"

    private static let food: [(HKQuantityTypeIdentifier, HKUnit, (Nutrients) -> Double?)] = [
        (.dietaryEnergyConsumed, .kilocalorie(), { $0.kcal }),
        (.dietaryProtein, .gram(), { $0.protein }),
        (.dietaryCarbohydrates, .gram(), { $0.carbs }),
        (.dietaryFatTotal, .gram(), { $0.fat }),
        (.dietaryFatSaturated, .gram(), { $0.saturated }),
        (.dietaryFiber, .gram(), { $0.fiber }),
        (.dietarySugar, .gram(), { $0.sugar }),
        (.dietarySodium, .gramUnit(with: .milli), { $0.sodium }),
    ]

    private static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    private static func authorize() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), !isDemo else { return false }
        let share: Set<HKSampleType> = Set(food.map { HKQuantityType($0.0) }).union([HKObjectType.workoutType()])
        return (try? await store.requestAuthorization(toShare: share, read: [HKObjectType.workoutType()])) != nil
    }

    // MARK: Comida

    /// Escribe (o reescribe, si ya estaba) un registro de comida. `id` identifica el registro en Vital.
    static func saveFood(id: String, name: String, date: Date, nutrients: Nutrients) async {
        guard await authorize() else { return }
        await deleteFood(id: id)
        let metadata: [String: Any] = [entryKey: id, HKMetadataKeyFoodType: name]
        let samples: [HKQuantitySample] = food.compactMap { type, unit, value in
            guard let v = value(nutrients), v > 0 else { return nil }
            return HKQuantitySample(type: HKQuantityType(type), quantity: HKQuantity(unit: unit, doubleValue: v),
                                    start: date, end: date, metadata: metadata)
        }
        guard !samples.isEmpty else { return }
        let meal = HKCorrelation(type: HKCorrelationType(.food), start: date, end: date, objects: Set(samples), metadata: metadata)
        do { try await store.save(meal) } catch { print("Salud: no se pudo guardar la comida:", error.localizedDescription) }
    }

    static func deleteFood(id: String) async {
        guard await authorize() else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: entryKey, allowedValues: [id])
        _ = try? await store.deleteObjects(of: HKCorrelationType(.food), predicate: predicate)
        for (type, _, _) in food {
            _ = try? await store.deleteObjects(of: HKQuantityType(type), predicate: predicate)
        }
    }

    // MARK: Entrenos

    enum WorkoutResult { case saved(Double?), watchHadIt, failed }

    private static let energyType = HKQuantityType(.activeEnergyBurned)
    /// Entrenos del reloj que pueden ser la misma sesión de pesas.
    static let strengthTypes: Set<HKWorkoutActivityType> = [.traditionalStrengthTraining, .functionalStrengthTraining,
                                                            .coreTraining, .crossTraining, .highIntensityIntervalTraining]

    private static func authorizeWorkouts() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), !isDemo else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), energyType]
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), energyType, HKQuantityType(.heartRate)]
        return (try? await store.requestAuthorization(toShare: share, read: read)) != nil
    }

    /// Calorías activas que tu reloj registró entre `start` y `end` (las que mide todo el día, aunque no
    /// inicies un entreno). Las muestras que cruzan los bordes cuentan solo por la parte de dentro.
    static func watchActiveEnergy(from start: Date, to end: Date) async -> Double? {
        let range = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: energyType, predicate: range)], sortDescriptors: [])
        let samples = (try? await descriptor.result(for: store)) ?? []
        let own = Bundle.main.bundleIdentifier
        let total = samples.filter { $0.sourceRevision.source.bundleIdentifier != own }.reduce(0.0) { sum, s in
            let length = s.endDate.timeIntervalSince(s.startDate)
            let inside = min(end, s.endDate).timeIntervalSince(max(start, s.startDate))
            let share = length <= 0 ? 1 : max(0, inside) / length
            return sum + s.quantity.doubleValue(for: .kilocalorie()) * share
        }
        return total > 0 ? total : nil
    }

    /// Guarda la sesión de la rutina como entrenamiento de fuerza, salvo que el reloj ya haya grabado
    /// un entreno en ese rato (así no se duplica: el del reloj trae pulso y calorías reales).
    /// Las calorías son las que tu reloj midió en ese rato; Salud no las suma dos veces (elige una fuente).
    @discardableResult
    static func saveStrengthWorkout(name: String, start: Date, end: Date, sets: Int, volumeKg: Double) async -> WorkoutResult {
        guard await authorizeWorkouts(), end > start else { return .failed }
        // Solo cuenta un entreno de fuerza del reloj que cubra buena parte de la sesión (una caminata antes no).
        let overlap = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(overlap)], sortDescriptors: [])
        let existing = (try? await descriptor.result(for: store)) ?? []
        let session = end.timeIntervalSince(start)
        if existing.contains(where: { w in
            guard w.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier,
                  strengthTypes.contains(w.workoutActivityType) else { return false }
            let shared = min(end, w.endDate).timeIntervalSince(max(start, w.startDate))
            return shared >= session * 0.5
        }) { return .watchHadIt }
        let kcal = await watchActiveEnergy(from: start, to: end)
        let metadata: [String: Any] = [HKMetadataKeyIndoorWorkout: true, HKMetadataKeyWorkoutBrandName: name, "Rutina": name,
                                       "Series": sets, "VolumenKg": Int(volumeKg.rounded())]
        do {
            try await write(start: start, end: end, kcal: kcal, metadata: metadata)
            return .saved(kcal)
        } catch {
            print("Salud: no se pudo guardar el entreno:", error.localizedDescription)
            return .failed
        }
    }

    private static func write(start: Date, end: Date, kcal: Double?, metadata: [String: Any]) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.addMetadata(metadata)
        if let kcal {
            let sample = HKQuantitySample(type: energyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                          start: start, end: end)
            try await builder.addSamples([sample])
        }
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    /// Para depurar: pulso medio y calorías activas del reloj cada 5 minutos entre dos horas.
    static func morningTrace(from start: Date, to end: Date) async -> [String] {
        guard await authorizeWorkouts() else { return [] }
        let hrType = HKQuantityType(.heartRate)
        let range = HKQuery.predicateForSamples(withStart: start, end: end)
        let hr = (try? await HKSampleQueryDescriptor(predicates: [.quantitySample(type: hrType, predicate: range)], sortDescriptors: []).result(for: store)) ?? []
        let energy = (try? await HKSampleQueryDescriptor(predicates: [.quantitySample(type: energyType, predicate: range)], sortDescriptors: []).result(for: store)) ?? []
        var lines: [String] = []
        let workouts = (try? await HKSampleQueryDescriptor(predicates: [.workout(range)], sortDescriptors: []).result(for: store)) ?? []
        for w in workouts {
            let kcal = w.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            lines.append("ENTRENO \(w.workoutActivityType.rawValue) \(w.sourceRevision.source.name) \(w.startDate.formatted(date: .omitted, time: .standard))–\(w.endDate.formatted(date: .omitted, time: .standard)) \(Int(kcal)) kcal")
        }
        var t = start
        while t < end {
            let next = t.addingTimeInterval(300)
            let bpm = hr.filter { $0.startDate >= t && $0.startDate < next }.map { $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())) }
            let kcal = energy.filter { $0.startDate >= t && $0.startDate < next && $0.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier }
                .reduce(0.0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
            lines.append("\(t.formatted(date: .omitted, time: .shortened)) pulso \(bpm.isEmpty ? "—" : String(Int(bpm.reduce(0, +) / Double(bpm.count)))) (\(bpm.count)) kcal \(String(format: "%.1f", kcal))")
            t = next
        }
        return lines
    }

    /// Corrige la hora de inicio del entreno de fuerza de Vital de hoy (versiones anteriores la guardaban mal)
    /// y lo reescribe con las calorías que el reloj midió desde esa hora.
    static func fixTodayStart(_ newStart: Date) async -> String {
        guard await authorizeWorkouts() else { return "sin permiso" }
        let day = Calendar.current.startOfDay(for: newStart)
        let range = HKQuery.predicateForSamples(withStart: day, end: day.addingTimeInterval(86400))
        let own = Bundle.main.bundleIdentifier
        let mine = ((try? await HKSampleQueryDescriptor(predicates: [.workout(range)], sortDescriptors: []).result(for: store)) ?? [])
            .filter { $0.sourceRevision.source.bundleIdentifier == own && $0.workoutActivityType == .traditionalStrengthTraining }
        guard let workout = mine.first, newStart < workout.endDate else { return "no hay entreno de Vital hoy" }
        let kcal = await watchActiveEnergy(from: newStart, to: workout.endDate)
        var metadata = workout.metadata ?? [:]
        if metadata[HKMetadataKeyWorkoutBrandName] == nil, let name = metadata["Rutina"] { metadata[HKMetadataKeyWorkoutBrandName] = name }
        do {
            try await write(start: newStart, end: workout.endDate, kcal: kcal, metadata: metadata)
            try await store.delete(workout)
            return "reescrito \(newStart.formatted(date: .omitted, time: .shortened))–\(workout.endDate.formatted(date: .omitted, time: .shortened)) con \(Int((kcal ?? 0).rounded())) kcal"
        } catch { return "error \(error.localizedDescription)" }
    }

    /// Los entrenos de fuerza que Vital guardó sin calorías (versiones anteriores): se reescriben con
    /// las calorías que tu reloj midió en ese rato. Devuelve una línea por entreno revisado.
    static func repairStrengthWorkouts(days: Int = 14) async -> [String] {
        guard await authorizeWorkouts() else { return [] }
        let from = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let range = HKQuery.predicateForSamples(withStart: from, end: .now)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(range)], sortDescriptors: [])
        let own = Bundle.main.bundleIdentifier
        let mine = ((try? await descriptor.result(for: store)) ?? []).filter {
            $0.sourceRevision.source.bundleIdentifier == own && $0.workoutActivityType == .traditionalStrengthTraining
        }
        var log: [String] = []
        for workout in mine {
            let had = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            let when = "\(workout.startDate.formatted(date: .abbreviated, time: .shortened))–\(workout.endDate.formatted(date: .omitted, time: .shortened))"
            guard had == 0 else { log.append("\(when): ya tenía \(Int(had)) kcal"); continue }
            guard workout.duration >= 5 * 60 else { log.append("\(when): dura menos de 5 min, falta la hora real de inicio"); continue }
            guard let kcal = await watchActiveEnergy(from: workout.startDate, to: workout.endDate) else {
                log.append("\(when): el reloj no midió calorías en ese rato"); continue
            }
            var metadata = workout.metadata ?? [:]
            if metadata[HKMetadataKeyWorkoutBrandName] == nil, let name = metadata["Rutina"] { metadata[HKMetadataKeyWorkoutBrandName] = name }
            do {
                try await write(start: workout.startDate, end: workout.endDate, kcal: kcal, metadata: metadata)
                try await store.delete(workout)
                log.append("\(when): reescrito con \(Int(kcal.rounded())) kcal")
            } catch {
                log.append("\(when): error \(error.localizedDescription)")
            }
        }
        return log
    }
}
