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
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        let name = app.localizedName ?? "?"
        guard applies(to: app.bundleIdentifier ?? "") else {
            Log.write("\(name): no está elegida, se deja abierta")
            return
        }
        check(app, attemptsLeft: 20)
    }

    private func check(_ app: NSRunningApplication, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard !app.isTerminated else { return }
            let name = app.localizedName ?? "?"
            let visible = Self.visibleWindowCount(app.processIdentifier)
            let minimized = Self.minimizedWindowCount(app.processIdentifier)
            if visible == 0 && minimized == 0 {
                Log.write("\(name): sin ventanas, se cierra")
                app.terminate()
            } else if attemptsLeft > 1 {
                self?.check(app, attemptsLeft: attemptsLeft - 1)
            } else {
                Log.write("\(name): le quedan \(visible) ventanas visibles y \(minimized) minimizadas, se deja abierta")
            }
        }
    }

    /// Ventanas normales de la app que se ven en pantalla. Se cuentan con la lista del sistema y no con
    /// Accesibilidad porque algunas apps solo esconden la ventana al cerrarla y siguen informando de ella.
    private static func visibleWindowCount(_ pid: pid_t) -> Int {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.filter { info in
            guard info[kCGWindowOwnerPID as String] as? Int32 == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return rect.width >= 100 && rect.height >= 60
        }.count
    }

    /// Las minimizadas no están en pantalla, pero la app sigue en uso.
    private static func minimizedWindowCount(_ pid: pid_t) -> Int {
        AXUIElementCreateApplication(pid).windows.filter { ($0.value(kAXMinimizedAttribute) as Bool?) == true }.count
    }
}
