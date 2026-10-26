import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let buttons = WindowButtons()
    private var quitOnClose: QuitOnClose { buttons.quitOnClose }
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Ventanas")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if Accessibility.isTrusted {
            buttons.start()
        } else {
            Accessibility.requestAccess()
            waitForPermission()
        }
    }

    /// Al abrir Ventanas otra vez (desde Aplicaciones o Spotlight) se muestra su icono, por si
    /// estaba oculto en la barra de menú, y su menú junto al ratón.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.isVisible = true
        if let menu = statusItem.menu {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        return false
    }

    /// Las funciones arrancan solas en cuanto se concede el permiso de Accesibilidad.
    private func waitForPermission() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard Accessibility.isTrusted, let self else { return }
                timer.invalidate()
                self.buttons.start()
            }
        }
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !Accessibility.isTrusted {
            let warning = NSMenuItem(title: "Sin permiso de Accesibilidad: funciones en pausa", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(item("Dar permiso de Accesibilidad…", #selector(requestAccess)))
            menu.addItem(.separator())
        }

        let green = item("Botón verde agranda la ventana", #selector(toggleGreenButton))
        green.toolTip = "En lugar de pantalla completa. Con ⌥ pulsada, el botón hace lo de siempre."
        green.state = buttons.isGreenEnabled ? .on : .off
        menu.addItem(green)

        let quit = item("Cerrar la app con el botón rojo", nil)
        quit.submenu = quitOnCloseMenu()
        menu.addItem(quit)

        menu.addItem(item("Ver registro del botón rojo", #selector(openLog)))

        menu.addItem(.separator())
        let login = item("Abrir al iniciar sesión", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Ventanas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// Las apps abiertas y las ya elegidas, cada una con su marca.
    private func quitOnCloseMenu() -> NSMenu {
        let menu = NSMenu()
        let all = item("En todas las apps", #selector(toggleAllApps))
        all.toolTip = "Menos el Finder"
        all.state = quitOnClose.allApps ? .on : .off
        menu.addItem(all)
        menu.addItem(.separator())
        let header = NSMenuItem(title: "Solo en estas apps:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        var apps: [String: (name: String, icon: NSImage?)] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != "com.apple.finder", id != Bundle.main.bundleIdentifier else { continue }
            apps[id] = (app.localizedName ?? id, app.icon)
        }
        for id in UserDefaults.standard.stringArray(forKey: "quitOnClose") ?? [] where apps[id] == nil {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            apps[id] = (url.map { FileManager.default.displayName(atPath: $0.path) } ?? id,
                        url.map { NSWorkspace.shared.icon(forFile: $0.path) })
        }

        for (id, app) in apps.sorted(by: { $0.value.name.localizedStandardCompare($1.value.name) == .orderedAscending }) {
            let entry = item(app.name.replacingOccurrences(of: ".app", with: ""), #selector(toggleQuitOnClose(_:)))
            entry.representedObject = id
            entry.state = quitOnClose.applies(to: id) ? .on : .off
            // Con «En todas las apps» marcado, la lista solo muestra el estado.
            if quitOnClose.allApps { entry.action = nil }
            entry.image = app.icon.map { icon in
                let small = icon.copy() as! NSImage
                small.size = NSSize(width: 16, height: 16)
                return small
            }
            menu.addItem(entry)
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func requestAccess() { Accessibility.requestAccess() }

    @objc private func toggleGreenButton() { buttons.isGreenEnabled.toggle() }

    @objc private func toggleAllApps() { quitOnClose.allApps.toggle() }

    @objc private func openLog() {
        if !FileManager.default.fileExists(atPath: Log.url.path) { Log.write("Registro vacío: todavía no se pulsó ningún botón rojo") }
        NSWorkspace.shared.open(Log.url)
    }

    @objc private func toggleQuitOnClose(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        quitOnClose.toggle(id)
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
