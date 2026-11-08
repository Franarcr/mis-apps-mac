import SwiftData
import SwiftUI
import WatchConnectivity

/// Conexión con el reloj: le pasa el resumen de Salud y las rutinas, y recibe las series hechas allá.
@MainActor
final class PhoneWatchLink: NSObject, ObservableObject {
    static let shared = PhoneWatchLink()
    var container: ModelContainer?

    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Manda al reloj lo último. Se llama al abrir Vital, al volver a ella y al terminar un entreno.
    func publish(health: VitalModel, stress: StressModel) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled, let container else { return }
        let context = container.mainContext
        let profile = TrainingProfile()
        let history = (try? context.fetch(FetchDescriptor<SetLog>())) ?? []
        let routines = (try? context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []

        let watchRoutines = routines.map { routine in
            WatchRoutine(id: String(Int(routine.createdAt.timeIntervalSince1970)), name: routine.name, items: routine.sortedItems.compactMap { item in
                guard let exercise = item.exercise else { return nil }
                let s = LoadAdvisor.suggest(for: item, history: history, bodyWeight: profile.bodyWeight, female: profile.female,
                                            level: profile.level, recovery: health.todayRecovery)
                return WatchItem(exerciseID: item.exerciseID, name: exercise.name, weighted: exercise.equipment.isWeighted,
                                 plan: s.plan.map { WatchSet(weight: $0.weight.map { (profile.unit.show($0) * 2).rounded() / 2 }, reps: $0.reps) },
                                 rest: item.restSeconds, note: s.reason)
            })
        }

        let today = health.today
        let snapshot = WatchSnapshot(
            date: .now, recovery: health.todayRecovery?.score, live: health.liveRecovery?.score,
            sleepHours: today?.sleep.map { $0.asleep / 3600 }, hrv: today?.hrv, hrvBase: health.baseline(\.hrv)?.mean,
            restingHR: today?.restingHR, restingBase: health.baseline(\.restingHR)?.mean,
            stress: stress.result?.currentStress, energy: stress.result?.currentEnergy, expiry: AppExpiry.date)

        let payload = WatchPayload(snapshot: health.state == .ready ? snapshot : nil, routines: watchRoutines, unit: profile.unit.rawValue)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? WCSession.default.updateApplicationContext([WatchKeys.payload: data, "enviado": Date.now.timeIntervalSince1970])
    }

    /// Guarda en el historial las series que llegan del reloj (el reloj ya guardó el entreno en Salud).
    fileprivate func store(_ result: WatchResult) {
        guard let context = container?.mainContext else { return }
        let unit = WeightUnit(rawValue: result.unit) ?? .kg
        let existing = (try? context.fetch(FetchDescriptor<SetLog>()))?.contains { $0.session == result.session } ?? false
        guard !existing else { return }
        for set in result.sets {
            context.insert(SetLog(exerciseID: set.exerciseID, date: result.start, session: result.session,
                                  weight: unit.store(set.weight ?? 0), reps: set.reps, index: set.index))
        }
        try? context.save()
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchKeys.result] as? Data,
              let result = try? JSONDecoder().decode(WatchResult.self, from: data) else { return }
        Task { @MainActor in PhoneWatchLink.shared.store(result) }
    }
}
