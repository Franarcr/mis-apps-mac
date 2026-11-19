import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var pet: Pet!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Mascota")
        statusItem.menu = menu
        BarraLink.connect(statusItem) { [weak self] in
            guard let self else { return }
            self.rebuildMenu()
            BarraLink.popUp(self.menu)
        }
        pet = Pet()
        rebuildMenu()
        menu.delegate = self
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(item(pet.isVisible ? "Esconder a Tuqui" : "Mostrar a Tuqui", #selector(toggleVisible)))
        menu.addItem(item("Traerlo aquí", #selector(bringHere)))
        menu.addItem(.separator())
        let login = item("Abrir al iniciar sesión", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Salir de Mascota", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func toggleVisible() { pet.setVisible(!pet.isVisible) }
    @objc private func bringHere() { pet.setVisible(true); pet.dropAtMouse() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        else { try? SMAppService.mainApp.register() }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }
}
