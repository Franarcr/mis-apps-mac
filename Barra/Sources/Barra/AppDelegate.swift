import AppKit
import ServiceManagement

/// Lista las apps que tienen icono en la barra de menús, cada una con una marca:
/// al desmarcarla la app se cierra (y su icono desaparece); al marcarla se vuelve a abrir.
/// Las apps de barra de menús desmarcadas se cierran también si vuelven a abrirse solas.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Procesos del sistema que dibujan la barra o sus iconos fijos (reloj, Wi-Fi, Spotlight…).
    private static let systemOwners: Set<String> = [
        "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.Spotlight", "com.apple.dock",
        "com.apple.TextInputMenuAgent", "com.apple.notificationcenterui", "com.apple.WindowManager",
    ]

    private var statusItem: NSStatusItem!

    /// Apps apagadas, por identificador, con la ruta para volver a abrirlas.
    private var disabled: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "disabled") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "disabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Barra")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Si una app de barra de menús apagada se abre sola (por ejemplo al iniciar sesión), se vuelve a cerrar.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app { self?.closeIfDisabled(app) }
            }
        }
        NSWorkspace.shared.runningApplications.forEach(closeIfDisabled)
    }

    private func closeIfDisabled(_ app: NSRunningApplication) {
        // Solo las apps de barra de menús: una app normal (Edge, Mail…) se puede abrir cuando quieras.
        guard app.activationPolicy == .accessory, let id = app.bundleIdentifier, disabled[id] != nil else { return }
        app.terminate()
    }

    // MARK: Apps con icono en la barra

    private struct MenuBarApp {
        let id: String
        let name: String
        let icon: NSImage?
        let url: URL?
        let running: NSRunningApplication?
    }

    /// Apps abiertas con icono en la barra (o que son apps de barra de menús) y las apagadas.
    private func menuBarApps() -> [MenuBarApp] {
        let ownID = Bundle.main.bundleIdentifier
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownersWithIcons = Set(windows.filter { $0[kCGWindowLayer as String] as? Int == statusLevel }
            .compactMap { $0[kCGWindowOwnerPID as String] as? Int32 })

        var apps: [String: MenuBarApp] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, id != ownID, !Self.systemOwners.contains(id) else { continue }
            let hasIcon = ownersWithIcons.contains(app.processIdentifier)
            // Las apps de barra de menús de Apple sin icono (Siri, AirPlay…) son procesos internos: no se tocan.
            guard hasIcon || (app.activationPolicy == .accessory && !id.hasPrefix("com.apple.")) else { continue }
            apps[id] = MenuBarApp(id: id, name: app.localizedName ?? id, icon: app.icon, url: app.bundleURL, running: app)
        }
        for (id, path) in disabled where apps[id] == nil {
            let url = URL(fileURLWithPath: path)
            apps[id] = MenuBarApp(id: id, name: FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""),
                                  icon: NSWorkspace.shared.icon(forFile: path), url: url, running: nil)
        }
        return apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "Apps con icono en la barra", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for app in menuBarApps() {
            let entry = NSMenuItem(title: app.name, action: #selector(toggleApp(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = app.id
            entry.state = app.running != nil ? .on : .off
            if app.running?.activationPolicy == .regular {
                entry.toolTip = "Al desmarcarla se cierra la app entera, no solo su icono."
                entry.title += " (cierra la app)"
            }
            entry.image = app.icon.map { icon in
                let small = icon.copy() as! NSImage
                small.size = NSSize(width: 16, height: 16)
                return small
            }
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(item("Ocultar iconos sin cerrar las apps…", #selector(openMenuBarSettings)))
        let login = item("Abrir al iniciar sesión", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Barra", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let app = menuBarApps().first(where: { $0.id == id }) else { return }
        var all = disabled
        if let running = app.running {
            // Apagar: se cierra y se recuerda para poder volver a abrirla desde aquí.
            if let path = app.url?.path { all[id] = path }
            disabled = all
            running.terminate()
        } else if let url = app.url {
            all[id] = nil
            disabled = all
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    /// Ajustes del Sistema › Barra de menús, donde macOS deja esconder iconos sin cerrar la app.
    @objc private func openMenuBarSettings() {
        for name in ["com.apple.MenuBar-Settings.extension", "com.apple.ControlCenter-Settings.extension"] {
            if let url = URL(string: "x-apple.systempreferences:\(name)"), NSWorkspace.shared.open(url) { return }
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
