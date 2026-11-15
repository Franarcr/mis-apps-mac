import AppKit
import OidoAudio

/// Cada 2 segundos mira qué apps de llamadas tienen el micrófono abierto.
/// Así sabe cuándo empieza una llamada y cuándo termina, sin leer nada de la llamada en sí.
@MainActor
final class Detector {
    /// Se llama cuando una app empieza a usar el micrófono.
    var onCallStarted: ((CallApp) -> Void)?
    /// Se llama cuando esa app deja de usarlo.
    var onCallEnded: ((CallApp) -> Void)?

    private(set) var active: Set<CallApp> = []
    private var timer: Timer?
    /// Segundos seguidos sin micrófono, para no cortar por una pausa breve.
    private var silence: [CallApp: Int] = [:]

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    private func check() {
        let own = getpid()
        let usingMic = OIDSystem.processes().filter { $0.isRunningInput && $0.pid != own }
        var now: Set<CallApp> = []
        for app in CallApp.all where usingMic.contains(where: { app.matches($0.bundleID) }) {
            now.insert(app)
        }
        for app in now where !active.contains(app) {
            active.insert(app)
            onCallStarted?(app)
        }
        silence = silence.filter { now.contains($0.key) == false }
        for app in active where !now.contains(app) {
            let seconds = (silence[app] ?? 0) + 2
            silence[app] = seconds
            if seconds >= 6 {
                active.remove(app)
                silence[app] = nil
                onCallEnded?(app)
            }
        }
    }
}
