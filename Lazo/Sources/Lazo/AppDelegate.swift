import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = LayoutStore()
    private lazy var model = AppModel(store: store)
    private var window: NSWindow!
    private let hotKeys = HotKeyManager()
    private let dragMover = DragMover()
    private var lastExternalApp: pid_t?
    private var keyMonitor: Any?
    private var permissionTimer: Timer?

    /// Abrir la ventana de Lazo (configuración y vista de las pantallas).
    private let openShortcut = Shortcut(keyCode: kVK_Space, modifiers: controlKey | optionKey | cmdKey)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        buildWindow()

        // Se recuerda la última app usada (no Lazo) para saber qué ventana colocar.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.lastExternalApp = app.processIdentifier }
        }
        lastExternalApp = NSWorkspace.shared.runningApplications
            .first { $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier }?.processIdentifier

        model.onPlaced = { [weak self] in self?.window.orderOut(nil) }
        model.onDragSettingChanged = { [weak self] in self?.updateDragMover() }
        model.onShortcutRecordingChanged = { [weak self] in self?.updateShortcutRecording() }
        store.onChange = { [weak self] in self?.registerShortcuts() }
        model.onGridShortcutChanged = { [weak self] in self?.registerShortcuts() }
        registerShortcuts()

        if WindowControl.isTrusted {
            updateDragMover()
        } else {
            waitForPermission()
        }
        showWindow(fromShortcut: false)
    }

    /// Clic en el icono del Dock (o abrir la app otra vez): se muestra la ventana.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(fromShortcut: false)
        return true
    }

    /// Al cerrar la ventana la app sigue abierta, para que funcionen los atajos.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Ventana

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Lazo"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainView(model: model, store: store))
        window.setFrameAutosaveName("LazoWindow")
    }

    /// Muestra la ventana preparada para colocar la ventana activa. Con el atajo, se centra sobre ella.
    private func showWindow(fromShortcut: Bool) {
        let target: AXUIElement?
        if fromShortcut {
            target = WindowControl.isTrusted ? Layout.targetWindow() : nil
        } else {
            target = lastExternalApp.flatMap { WindowControl.isTrusted ? WindowControl.focusedWindow(of: $0) : nil }
        }
        model.trusted = WindowControl.isTrusted
        model.hideAfterPlacing = fromShortcut
        if model.trusted { model.refreshWindows(preferred: target) } else { model.setTarget(nil) }
        Log.write("Abrir Lazo (\(fromShortcut ? "atajo" : "Dock")) · permiso: \(model.trusted) · ventana: \(model.targetName.isEmpty ? "ninguna" : model.targetName)")
        if fromShortcut, let frame = model.targetFrame {
            let size = window.frame.size
            let screen = WindowControl.screen(for: frame).visibleFrame
            let origin = NSPoint(x: min(max(frame.midX - size.width / 2, screen.minX), screen.maxX - size.width),
                                 y: min(max(frame.midY - size.height / 2, screen.minY), screen.maxY - size.height))
            window.setFrameOrigin(origin)
        } else if !window.isVisible, window.frame.origin == .zero {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        model.recordingShortcutFor = nil
    }

    // MARK: Atajos

    private func registerShortcuts() {
        hotKeys.unregisterAll()
        guard model.recordingShortcutFor == nil else { return } // mientras se graba un atajo, ninguno actúa
        var failed: [String] = []
        func register(_ shortcut: Shortcut, _ name: String, _ run: @escaping () -> Void) {
            if !hotKeys.register(keyCode: shortcut.keyCode, modifiers: UInt32(shortcut.modifiers), handler: run) {
                failed.append("\(shortcut.display) (\(name))")
            }
        }
        let grid = model.gridShortcut
        register(grid, "cuadrícula") { [weak self] in
            guard let self else { return }
            Log.write("Atajo \(grid.display) pulsado")
            GridOverlay.show(model: self.model)
        }
        register(openShortcut, "abrir Lazo") { [weak self] in self?.showWindow(fromShortcut: true) }
        for layout in store.layouts {
            guard let shortcut = layout.shortcut else { continue }
            let id = layout.id
            register(shortcut, layout.name) { [weak self] in
                guard let layout = self?.store.layouts.first(where: { $0.id == id }) else { return }
                Layout.apply(layout)
            }
        }
        for action in QuickAction.allCases {
            register(action.shortcut, action.title) { Layout.perform(action) }
        }
        Log.write("Atajos registrados · cuadrícula \(grid.display)" + (failed.isEmpty ? "" : " · en uso por otra app: \(failed.joined(separator: ", "))"))
        model.shortcutProblem = failed.isEmpty ? nil
            : "Estos atajos los está usando otra app o macOS: \(failed.joined(separator: ", ")). Cámbialos o cierra esa app (por ejemplo, Lasso)."
    }

    /// Mientras se graba un atajo, se escucha el teclado de la ventana (Esc cancela, ⌫ lo quita).
    private func updateShortcutRecording() {
        registerShortcuts()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard model.recordingShortcutFor != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let id = self.model.recordingShortcutFor else { return event }
                // Atajo de la cuadrícula
                if id == AppModel.gridRecordingID {
                    let mods = Shortcut.carbonModifiers(event.modifierFlags)
                    if Int(event.keyCode) != kVK_Escape {
                        guard mods & (controlKey | optionKey | cmdKey) != 0 else { NSSound.beep(); return nil }
                        self.model.gridShortcut = Shortcut(keyCode: Int(event.keyCode), modifiers: mods)
                    }
                    self.model.recordingShortcutFor = nil
                    return nil
                }
                guard let index = self.store.layouts.firstIndex(where: { $0.id == id }) else { return event }
                switch Int(event.keyCode) {
                case kVK_Escape:
                    self.model.recordingShortcutFor = nil
                case kVK_Delete, kVK_ForwardDelete where event.modifierFlags.intersection([.command, .control, .option]).isEmpty:
                    self.store.layouts[index].shortcut = nil
                    self.model.recordingShortcutFor = nil
                default:
                    let mods = Shortcut.carbonModifiers(event.modifierFlags)
                    guard mods & (controlKey | optionKey | cmdKey) != 0 else { NSSound.beep(); return nil }
                    let shortcut = Shortcut(keyCode: Int(event.keyCode), modifiers: mods)
                    // Un atajo solo puede tener una distribución.
                    for i in self.store.layouts.indices where self.store.layouts[i].shortcut == shortcut {
                        self.store.layouts[i].shortcut = nil
                    }
                    self.store.layouts[index].shortcut = shortcut
                    self.model.recordingShortcutFor = nil
                }
                return nil
            }
        }
    }

    // MARK: Permiso y arrastre

    private func waitForPermission() {
        WindowControl.requestAccess()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard WindowControl.isTrusted else { return }
                timer.invalidate()
                self?.model.trusted = true
                self?.model.refreshWindows()
                self?.updateDragMover()
            }
        }
    }

    private func updateDragMover() {
        if Settings.dragWithModifiers { dragMover.start() } else { dragMover.stop() }
    }

    // MARK: Menú

    @objc private func exportLayouts() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Distribuciones de Lazo.json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.export(to: url) } catch { NSAlert(error: error).runModal() }
        }
    }

    @objc private func importLayouts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.importLayouts(from: url) } catch { NSAlert(error: error).runModal() }
        }
    }

    @objc private func resetLayouts() { store.layouts = SavedLayout.defaults }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSAlert(error: error).runModal() }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            parent.submenu = menu
            main.addItem(parent)
        }
        func item(_ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            return item
        }
        let login = item("Abrir al iniciar sesión", #selector(toggleLogin(_:)), target: self)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        submenu("Lazo", [
            item("Acerca de Lazo", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(), login, .separator(),
            item("Ocultar Lazo", #selector(NSApplication.hide(_:)), "h"),
            item("Salir de Lazo", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("Distribuciones", [
            item("Importar…", #selector(importLayouts), "o", target: self),
            item("Exportar…", #selector(exportLayouts), "s", target: self),
            .separator(),
            item("Restablecer las de serie", #selector(resetLayouts), target: self),
        ])
        submenu("Edición", [
            item("Deshacer", Selector(("undo:")), "z"),
            item("Cortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Pegar", #selector(NSText.paste(_:)), "v"),
            item("Seleccionar todo", #selector(NSText.selectAll(_:)), "a"),
        ])
        submenu("Ventana", [
            item("Cerrar", #selector(NSWindow.performClose(_:)), "w"),
            item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ])
        return main
    }
}
