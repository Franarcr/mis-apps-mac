import HealthKit

/// El entreno de fuerza en el reloj: mide pulso y calorías y lo guarda en Salud al terminar.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    @Published var heartRate: Double?
    @Published var calories: Double = 0
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: share, read: read)
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        guard let session = try? HKWorkoutSession(healthStore: store, configuration: config) else { return }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        builder.delegate = self
        self.session = session
        self.builder = builder
        let start = Date.now
        session.startActivity(with: start)
        try? await builder.beginCollection(at: start)
    }

    /// Termina y guarda en Salud con el nombre de la rutina.
    func finish(name: String, sets: Int) async {
        guard let session, let builder else { return }
        session.end()
        try? await builder.endCollection(at: .now)
        try? await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Vital · \(name)", "Series": sets])
        _ = try? await builder.finishWorkout()
        self.session = nil
        self.builder = nil
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            if let hr { self.heartRate = hr }
            if let kcal { self.calories = kcal }
        }
    }
}
