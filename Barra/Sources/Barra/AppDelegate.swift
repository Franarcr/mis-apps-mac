import AppKit
import ServiceManagement

/// Junta en un solo icono las demás apps de barra de menús de este repositorio. Su menú lista esas apps
/// con una marca: las desmarcadas esconden su icono pero siguen funcionando, y su menú se abre desde aquí.
/// Se comunica con ellas con notificaciones distribuidas (ver BarraLink.swift en cada app).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let apps: [(id: String, name: String)] = [
        ("com.fran.captura", "Captura"),
        ("com.fran.portapapeles", "Portapapeles"),
        ("com.fran.puntos", "Puntos"),
        ("com.fran.monitor", "Monitor"),
        ("com.fran.ventanas", "Ventanas"),
        ("com.fran.volumen", "Volumen"),
        ("com.fran.barrendero", "Barrendero"),
        ("com.fran.guardian", "Guardián"),
    ]
    /// Apps con ventana: solo se abren desde aquí.
    private static let windowApps: [(id: String, name: String)] = [
        ("com.francho.hecho", "Hecho"),
        ("com.fran.revela", "Revela"),
        ("com.fran.historietas", "Historietas"),
        ("com.fran.compresor", "Compresor"),
        ("com.fran.lazo", "Lazo"),
        ("com.fran.grabador", "Grabador"),
        ("com.fran.batido", "Batido"),
        ("com.fran.antena", "Antena"),
    ]
    private static let setHiddenNotification = Notification.Name("com.fran.barra.setHidden")
    private static let showMenuNotification = Notification.Name("com.fran.barra.showMenu")

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Barra")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Apps instaladas, con su ubicación.
    private var installed: [(id: String, name: String, url: URL)] {
        Self.apps.compactMap { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id).map { (id: app.id, name: app.name, url: $0) }
        }
    }

    /// Cada app guarda en sus propias preferencias si su icono va escondido.
    private func isHidden(_ id: String) -> Bool {
        UserDefaults(suiteName: id)?.bool(forKey: "iconHidden") ?? false
    }

    private func isRunning(_ id: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let apps = installed
        let header = NSMenuItem(title: "Iconos en la barra de menús", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for app in apps {
            let entry = item(app.name, #selector(toggleIcon(_:)))
            entry.representedObject = app.id
            entry.state = isHidden(app.id) ? .off : .on
            entry.image = smallIcon(app.url)
            entry.toolTip = "Desmarcada: el icono se esconde, pero la app sigue funcionando."
            menu.addItem(entry)
        }

        // Las escondidas se usan desde aquí.
        let hidden = apps.filter { isHidden($0.id) }
        if !hidden.isEmpty {
            menu.addItem(.separator())
            let title = NSMenuItem(title: "Abrir el menú de", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            for app in hidden {
                let entry = item("   " + app.name, #selector(openAppMenu(_:)))
                entry.representedObject = app.id
                entry.image = smallIcon(app.url)
                menu.addItem(entry)
            }
        }

        let windowApps = Self.windowApps.compactMap { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id).map { (name: app.name, url: $0) }
        }
        if !windowApps.isEmpty {
            menu.addItem(.separator())
            let title = NSMenuItem(title: "Abrir", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            for app in windowApps {
                let entry = item("   " + app.name, #selector(launchApp(_:)))
                entry.representedObject = app.url
                entry.image = smallIcon(app.url)
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Esconder iconos de otras apps…", #selector(openMenuBarSettings)))
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

    private func smallIcon(_ url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    @objc private func toggleIcon(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let hidden = !isHidden(id)
        // Se guarda en sus preferencias (vale aunque la app esté cerrada) y se le avisa si está abierta.
        UserDefaults(suiteName: id)?.set(hidden, forKey: "iconHidden")
        DistributedNotificationCenter.default().postNotificationName(
            Self.setHiddenNotification, object: id, userInfo: ["hidden": hidden], deliverImmediately: true)
    }

    @objc private func openAppMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let app = installed.first(where: { $0.id == id }) else { return }
        let post = {
            DistributedNotificationCenter.default().postNotificationName(
                Self.showMenuNotification, object: id, userInfo: nil, deliverImmediately: true)
        }
        if isRunning(id) {
            post()
        } else {
            // Si está cerrada, se abre y se le pide el menú cuando haya arrancado.
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration(),
                                               completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { post() }
        }
    }

    /// Abre (o trae al frente) una app con ventana.
    @objc private func launchApp(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// Ajustes del Sistema › Barra de menús, donde macOS deja esconder los iconos de cualquier app.
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
