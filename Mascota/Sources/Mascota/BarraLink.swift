import AppKit

/// Conexión con la app Barra, que puede esconder el icono de esta app en la barra de menús
/// y abrir su menú desde el suyo. La app sigue funcionando igual con el icono escondido
/// (atajos de teclado incluidos). Este archivo es igual en todas las apps de barra de menús.
@MainActor
enum BarraLink {
    static let setHiddenNotification = Notification.Name("com.fran.barra.setHidden")
    static let showMenuNotification = Notification.Name("com.fran.barra.showMenu")

    /// Barra guarda aquí si el icono va escondido, también cuando la app está cerrada.
    static var isHidden: Bool { UserDefaults.standard.bool(forKey: "iconHidden") }

    /// Aplica el estado guardado y queda atento a Barra. `showMenu` abre el menú de la app.
    static func connect(_ statusItem: NSStatusItem, showMenu: @escaping () -> Void) {
        statusItem.isVisible = !isHidden
        let id = Bundle.main.bundleIdentifier
        let center = DistributedNotificationCenter.default()
        _ = center.addObserver(forName: setHiddenNotification, object: id, queue: .main) { note in
            let hidden = note.userInfo?["hidden"] as? Bool ?? false
            MainActor.assumeIsolated {
                UserDefaults.standard.set(hidden, forKey: "iconHidden")
                statusItem.isVisible = !hidden
            }
        }
        _ = center.addObserver(forName: showMenuNotification, object: id, queue: .main) { _ in
            MainActor.assumeIsolated { showMenu() }
        }
    }

    /// Muestra un menú donde está el puntero (el icono puede estar escondido).
    static func popUp(_ menu: NSMenu) {
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
