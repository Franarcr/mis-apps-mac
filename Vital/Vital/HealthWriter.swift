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

    enum WorkoutResult { case saved(Double?, estimated: Bool), watchHadIt, failed }

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

    // MARK: Calorías con tu pulso

    /// Tu relación pulso → kcal activas por minuto, sacada de los entrenos que grabó tu reloj
    /// (recta de mínimos cuadrados entre el pulso medio y las kcal por minuto de cada entreno).
    struct HeartRateCalibration { let a: Double; let b: Double; let workouts: Int; let maxHR: Double
        func perMinute(_ hr: Double) -> Double { max(0, a + b * min(hr, maxHR)) }
    }

    static func heartRateCalibration(days: Int = 120) async -> HeartRateCalibration? {
        let from = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let range = HKQuery.predicateForSamples(withStart: from, end: .now)
        let workouts = (try? await HKSampleQueryDescriptor(predicates: [.workout(range)], sortDescriptors: []).result(for: store)) ?? []
        let own = Bundle.main.bundleIdentifier
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let points: [(hr: Double, perMin: Double)] = workouts.compactMap { w in
            guard w.sourceRevision.source.bundleIdentifier != own, w.duration >= 5 * 60,
                  let hr = w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm),
                  let kcal = w.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()), kcal > 0
            else { return nil }
            return (hr, kcal / (w.duration / 60))
        }
        guard points.count >= 3 else { return nil }
        let n = Double(points.count)
        let mx = points.map(\.hr).reduce(0, +) / n, my = points.map(\.perMin).reduce(0, +) / n
        let sxx = points.reduce(0) { $0 + ($1.hr - mx) * ($1.hr - mx) }
        guard sxx > 0 else { return nil }
        let b = points.reduce(0) { $0 + ($1.hr - mx) * ($1.perMin - my) } / sxx
        guard b > 0 else { return nil }
        return HeartRateCalibration(a: my - b * mx, b: b, workouts: points.count, maxHR: points.map(\.hr).max() ?? 200)
    }

    /// Kcal activas calculadas con el pulso que midió tu reloj en ese rato. Cada medida de pulso
    /// vale hasta la mitad del camino a la siguiente. Hace falta al menos una medida cada 5 minutos.
    static func heartRateEnergy(from start: Date, to end: Date, calibration c: HeartRateCalibration) async -> Double? {
        let range = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples = ((try? await HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: range)],
                                                          sortDescriptors: [SortDescriptor(\.startDate)]).result(for: store)) ?? [])
        let minutes = end.timeIntervalSince(start) / 60
        guard samples.count >= max(2, Int(minutes / 5)) else { return nil }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var total = 0.0
        for (i, s) in samples.enumerated() {
            let from = i == 0 ? start : Date(timeIntervalSince1970: (samples[i - 1].startDate.timeIntervalSince1970 + s.startDate.timeIntervalSince1970) / 2)
            let to = i == samples.count - 1 ? end : Date(timeIntervalSince1970: (s.startDate.timeIntervalSince1970 + samples[i + 1].startDate.timeIntervalSince1970) / 2)
            total += c.perMinute(s.quantity.doubleValue(for: bpm)) * max(0, to.timeIntervalSince(from)) / 60
        }
        return total
    }

    /// Las kcal de una sesión sin entreno en el reloj: lo que el reloj anotó, o lo calculado con tu pulso
    /// si es más (sin entreno iniciado el reloj apenas anota calorías). `estimated` dice cuál se usó.
    static func sessionEnergy(from start: Date, to end: Date) async -> (kcal: Double?, estimated: Bool) {
        let measured = await watchActiveEnergy(from: start, to: end)
        guard let c = await heartRateCalibration(),
              let fromPulse = await heartRateEnergy(from: start, to: end, calibration: c),
              fromPulse > (measured ?? 0) else { return (measured, false) }
        return (fromPulse, true)
    }

    /// Guarda la sesión de la rutina como entrenamiento de fuerza, salvo que el reloj ya haya grabado
    /// un entreno en ese rato (así no se duplica: el del reloj trae pulso y calorías reales).
    /// Si terminaste otra sesión de Vital hace 10 minutos o menos, las une en un solo entreno.
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
        var start = start, name = name, sets = sets, volumeKg = volumeKg
        let previous = await ownStrengthWorkouts(from: start.addingTimeInterval(-6 * 3600), to: start)
            .last { start.timeIntervalSince($0.endDate) <= 600 && $0.endDate <= start.addingTimeInterval(60) }
        if let previous {
            start = previous.startDate
            let m = previous.metadata ?? [:]
            if let old = m["Rutina"] as? String, old != name { name = "\(old) + \(name)" }
            sets += (m["Series"] as? NSNumber)?.intValue ?? 0
            volumeKg += (m["VolumenKg"] as? NSNumber)?.doubleValue ?? 0
        }
        let energy = await sessionEnergy(from: start, to: end)
        let metadata: [String: Any] = [HKMetadataKeyIndoorWorkout: true, HKMetadataKeyWorkoutBrandName: name, "Rutina": name,
                                       "Series": sets, "VolumenKg": Int(volumeKg.rounded()), "KcalPorPulso": energy.estimated]
        do {
            try await write(start: start, end: end, kcal: energy.kcal, metadata: metadata)
            if let previous { try? await store.delete(previous) }
            return .saved(energy.kcal, estimated: energy.estimated)
        } catch {
            print("Salud: no se pudo guardar el entreno:", error.localizedDescription)
            return .failed
        }
    }

    private static func ownStrengthWorkouts(from: Date, to: Date) async -> [HKWorkout] {
        let range = HKQuery.predicateForSamples(withStart: from, end: to)
        let own = Bundle.main.bundleIdentifier
        return ((try? await HKSampleQueryDescriptor(predicates: [.workout(range)], sortDescriptors: [SortDescriptor(\.startDate)]).result(for: store)) ?? [])
            .filter { $0.sourceRevision.source.bundleIdentifier == own && $0.workoutActivityType == .traditionalStrengthTraining }
    }

    /// Rehace los entrenos de Vital de un día: une los que están separados 10 minutos o menos
    /// y les pone las kcal calculadas con tu pulso cuando el reloj anotó menos.
    static func redoDay(_ day: Date) async -> [String] {
        guard await authorizeWorkouts() else { return ["sin permiso"] }
        let dayStart = Calendar.current.startOfDay(for: day)
        let mine = await ownStrengthWorkouts(from: dayStart, to: dayStart.addingTimeInterval(86400))
        var groups: [[HKWorkout]] = []
        for w in mine {
            if let last = groups.last?.last, w.startDate.timeIntervalSince(last.endDate) <= 600 { groups[groups.count - 1].append(w) }
            else { groups.append([w]) }
        }
        var log: [String] = []
        if let c = await heartRateCalibration() {
            log.append(String(format: "calibración: %d entrenos del reloj, kcal/min = %.2f + %.4f × pulso", c.workouts, c.a, c.b))
        } else { log.append("calibración: faltan entrenos del reloj con pulso") }
        for group in groups {
            let start = group.first!.startDate, end = group.last!.endDate
            let names = group.compactMap { $0.metadata?["Rutina"] as? String }
            var unique: [String] = []
            for n in names where !unique.contains(n) { unique.append(n) }
            let name = unique.isEmpty ? "Fuerza" : unique.joined(separator: " + ")
            let sets = group.reduce(0) { $0 + (($1.metadata?["Series"] as? NSNumber)?.intValue ?? 0) }
            let volume = group.reduce(0) { $0 + (($1.metadata?["VolumenKg"] as? NSNumber)?.intValue ?? 0) }
            let had = group.reduce(0.0) { $0 + ($1.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0) }
            let energy = await sessionEnergy(from: start, to: end)
            let when = "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
            guard group.count > 1 || (energy.kcal ?? 0) > had + 1 else { log.append("\(when): sin cambios (\(Int(had)) kcal)"); continue }
            let metadata: [String: Any] = [HKMetadataKeyIndoorWorkout: true, HKMetadataKeyWorkoutBrandName: name, "Rutina": name,
                                           "Series": sets, "VolumenKg": volume, "KcalPorPulso": energy.estimated]
            do {
                try await write(start: start, end: end, kcal: energy.kcal, metadata: metadata)
                for w in group { try await store.delete(w) }
                log.append("\(when): \(group.count) → 1 entreno, \(Int(had)) → \(Int((energy.kcal ?? 0).rounded())) kcal\(energy.estimated ? " (con tu pulso)" : "")")
            } catch { log.append("\(when): error \(error.localizedDescription)") }
        }
        return log
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
