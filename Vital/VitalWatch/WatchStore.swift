import SwiftUI
import WatchConnectivity

/// Lo último que mandó el iPhone (se guarda para tenerlo aunque el iPhone esté lejos).
@MainActor
final class WatchStore: NSObject, ObservableObject {
    static let shared = WatchStore()
    @Published var payload: WatchPayload?
    @Published var received: Date?

    private let key = "ultimoDelIPhone"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: key) { apply(data) }
        #if targetEnvironment(simulator)
        // En el simulador no hay iPhone: datos de ejemplo para ver las pantallas.
        if payload == nil {
            let bench = WatchItem(exerciseID: "press", name: "Press de banca", weighted: true,
                                  plan: [WatchSet(weight: 60, reps: 10), WatchSet(weight: 60, reps: 10), WatchSet(weight: 60, reps: 8)], rest: 90, note: "")
            payload = WatchPayload(snapshot: WatchSnapshot(date: .now, recovery: 60, live: 50, sleepHours: 5.34, hrv: 37.5, hrvBase: 39.6,
                                                           restingHR: 56, restingBase: 63.3, stress: 24, energy: 71, expiry: .now.addingTimeInterval(5 * 86400)),
                                   routines: [WatchRoutine(id: "1", name: "Pecho y tríceps", items: [bench])], unit: "kg")
        }
        #endif
    }

    func activate() {
        guard WCSession.isSupported(), WCSession.default.activationState != .activated else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func apply(_ data: Data) {
        guard let p = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        payload = p
        received = p.snapshot?.date
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Manda al iPhone las series hechas; llegan aunque el iPhone esté lejos o Vital cerrada (se entregan después).
    func send(_ result: WatchResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        WCSession.default.transferUserInfo([WatchKeys.result: data])
    }

    var unit: String { payload?.unit ?? "kg" }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        if let data = context[WatchKeys.payload] as? Data { Task { @MainActor in WatchStore.shared.apply(data) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        if let data = context[WatchKeys.payload] as? Data { Task { @MainActor in WatchStore.shared.apply(data) } }
    }
}
