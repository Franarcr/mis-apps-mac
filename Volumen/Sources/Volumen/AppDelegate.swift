import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = VolumeController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Volumen")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        controller.start()
    }

    /// Al salir, el sonido de todas las apps vuelve a su volumen normal.
    func applicationWillTerminate(_ notification: Notification) { controller.stopAll() }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "Volumen de cada app", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Las que suenan ahora y las que tienen un volumen cambiado.
        let apps = controller.apps().filter { $0.isPlaying || controller.volume(for: $0.bundleID) != 1 }
        if apps.isEmpty {
            let empty = NSMenuItem(title: "Ninguna app está sonando", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for app in apps {
            let row = NSMenuItem()
            row.view = VolumeRow(app: app, volume: controller.volume(for: app.bundleID)) { [weak self] volume in
                self?.controller.setVolume(volume, for: app.bundleID)
            }
            menu.addItem(row)
        }

        if let error = controller.lastError {
            menu.addItem(.separator())
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let reset = item("Restablecer todo al 100 %", #selector(resetAll))
        if !controller.hasChanges { reset.action = nil }
        menu.addItem(reset)
        menu.addItem(item("Permiso de audio del sistema…", #selector(openPermission)))
        let login = item("Abrir al iniciar sesión", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Volumen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func resetAll() { controller.resetAll() }

    /// Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla y audio del sistema.
    @objc private func openPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
