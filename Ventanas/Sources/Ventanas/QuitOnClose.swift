import AppKit
import ApplicationServices

/// Al cerrar con el botón rojo la última ventana de una app, cierra también la app,
/// en lugar de dejarla abierta en el Dock sin ventanas.
@MainActor
final class QuitOnClose {
    /// En todas las apps (salvo el Finder) o solo en las elegidas.
    var allApps: Bool {
        get { UserDefaults.standard.object(forKey: "quitOnCloseAll") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "quitOnCloseAll") }
    }

    /// Identificadores de las apps elegidas cuando no es en todas.
    private(set) var chosen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "quitOnClose") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "quitOnClose") }
    }

    func toggle(_ bundleID: String) {
        if chosen.contains(bundleID) { chosen.remove(bundleID) } else { chosen.insert(bundleID) }
    }

    func applies(to bundleID: String) -> Bool {
        bundleID != "com.apple.finder" && (allApps || chosen.contains(bundleID))
    }

    /// Se ha pulsado el botón rojo de una ventana de la app `pid`. La ventana tarda un momento en cerrarse,
    /// o más si la app pregunta antes si quieres guardar, así que se comprueba varias veces.
    func closeClicked(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid),
              applies(to: app.bundleIdentifier ?? "") else { return }
        check(app, attemptsLeft: 20)
    }

    private func check(_ app: NSRunningApplication, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard !app.isTerminated else { return }
            if AXUIElementCreateApplication(app.processIdentifier).standardWindows.isEmpty {
                app.terminate()
            } else if attemptsLeft > 1 {
                self?.check(app, attemptsLeft: attemptsLeft - 1)
            }
        }
    }
}
