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

    enum WorkoutResult { case saved, watchHadIt, failed }

    /// Guarda la sesión de la rutina como entrenamiento de fuerza, salvo que el reloj ya haya grabado
    /// un entreno en ese rato (así no se duplica: el del reloj trae pulso y calorías reales).
    @discardableResult
    static func saveStrengthWorkout(name: String, start: Date, end: Date, sets: Int, volumeKg: Double) async -> WorkoutResult {
        guard await authorize(), end > start else { return .failed }
        let overlap = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-10 * 60), end: end.addingTimeInterval(10 * 60))
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(overlap)], sortDescriptors: [])
        let existing = (try? await descriptor.result(for: store)) ?? []
        if existing.contains(where: { $0.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier }) { return .watchHadIt }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([HKMetadataKeyIndoorWorkout: true, "Rutina": name,
                                           "Series": sets, "VolumenKg": Int(volumeKg.rounded())])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return .saved
        } catch {
            print("Salud: no se pudo guardar el entreno:", error.localizedDescription)
            return .failed
        }
    }
}
