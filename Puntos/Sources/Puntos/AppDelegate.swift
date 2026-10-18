import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = NotesStore()
    private lazy var notes = NoteWindowController(store: store)
    private let hotKeys = HotKeyManager()
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()

    /// Ventana fija: no se oculta al cambiar de app y queda encima de las demás.
    var alwaysOnTop: Bool {
        get { UserDefaults.standard.bool(forKey: "alwaysOnTop") }
        set { UserDefaults.standard.set(newValue, forKey: "alwaysOnTop") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        store.onChange = { [weak self] in self?.notes.refreshDots() }
        notes.window.level = alwaysOnTop ? .floating : .normal

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "circle.grid.3x3.fill", accessibilityDescription: "Puntos")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        // Clic: muestra u oculta la ventana. Clic derecho (o ⌃clic): menú de opciones.
        statusMenu.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        if !hotKeys.register(keyCode: kVK_ANSI_N, modifiers: UInt32(optionKey | shiftKey), handler: { [weak self] in
            self?.toggleWindow()
        }) {
            NSLog("Puntos: el atajo ⌥⇧N ya está en uso")
        }
        showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) { store.saveAll() }

    /// Como Tot: al pasar a otra app, la ventana desaparece (salvo que esté fija).
    func applicationDidResignActive(_ notification: Notification) {
        guard !alwaysOnTop, notes.window.isVisible, notes.window.attachedSheet == nil else { return }
        store.saveAll()
        notes.window.orderOut(nil)
    }

    /// Al abrir la app otra vez (desde Aplicaciones o Spotlight) se muestra la ventana.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    @objc func toggleWindow() {
        if notes.isFrontmost { notes.window.orderOut(nil) } else { showWindow() }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            // El menú se asigna solo mientras se muestra; si no, el clic normal también lo abriría.
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleWindow()
        }
    }

    /// Posición del icono de la barra de menú en pantalla.
    private var statusAnchor: NSRect? { statusItem.button?.window?.frame }

    // MARK: Menú de la barra

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let show = NSMenuItem(title: "Mostrar notas", action: #selector(showWindow), keyEquivalent: "n")
        show.keyEquivalentModifierMask = [.option, .shift]
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        for i in 0 ..< NotesStore.count {
            let item = NSMenuItem(title: store.preview(i) ?? "\(NotesStore.colorNames[i]) (vacía)",
                                  action: #selector(openNote(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.image = dotImage(NotesStore.colors[i], filled: store.preview(i) != nil)
            item.state = i == store.selected ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let onTop = NSMenuItem(title: "Mantener ventana visible", action: #selector(toggleOnTop), keyEquivalent: "")
        onTop.toolTip = "No se oculta al cambiar de app y queda encima de las demás ventanas"
        onTop.target = self
        onTop.state = alwaysOnTop ? .on : .off
        menu.addItem(onTop)
        let login = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let folder = NSMenuItem(title: "Abrir carpeta de notas", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Puntos", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func dotImage(_ color: NSColor, filled: Bool) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            if filled {
                color.setFill()
                path.fill()
            } else {
                color.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            return true
        }
    }

    @objc private func showWindow() { notes.show(below: statusAnchor) }

    @objc private func openNote(_ sender: NSMenuItem) {
        notes.select(sender.tag)
        showWindow()
    }

    @objc private func toggleOnTop() {
        alwaysOnTop.toggle()
        notes.window.level = alwaysOnTop ? .floating : .normal
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

    @objc private func openFolder() { NSWorkspace.shared.open(store.folder) }

    // MARK: Menú principal (invisible, pero da los atajos de teclado)

    @objc func selectNote(_ sender: NSMenuItem) { notes.select(sender.tag) }
    @objc func makeBold(_ sender: Any?) { notes.wrapSelection(with: "**") }
    @objc func makeItalic(_ sender: Any?) { notes.wrapSelection(with: "*") }
    @objc func makeStrikethrough(_ sender: Any?) { notes.wrapSelection(with: "~~") }
    @objc func makeCode(_ sender: Any?) { notes.wrapSelection(with: "`") }
    @objc func biggerFont(_ sender: Any?) { notes.changeFontSize(by: 1) }
    @objc func smallerFont(_ sender: Any?) { notes.changeFontSize(by: -1) }
    @objc func copyNote(_ sender: Any?) { notes.copyNote() }
    @objc func hideWindow(_ sender: Any?) { notes.window.orderOut(nil) }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            parent.submenu = menu
            main.addItem(parent)
        }
        func item(_ title: String, _ action: Selector?, _ key: String, _ mods: NSEvent.ModifierFlags = .command,
                  tag: Int = 0, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.tag = tag
            item.target = target
            return item
        }

        submenu("Puntos", [
            item("Cerrar ventana", #selector(hideWindow(_:)), "w", target: self),
            item("Salir de Puntos", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("Edición", [
            item("Deshacer", Selector(("undo:")), "z"),
            item("Rehacer", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Pegar", #selector(NSText.paste(_:)), "v"),
            item("Seleccionar todo", #selector(NSText.selectAll(_:)), "a"),
            item("Copiar toda la nota", #selector(copyNote(_:)), "c", [.command, .shift], target: self),
            .separator(),
            item("Buscar…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: Int(NSFindPanelAction.showFindPanel.rawValue)),
            item("Buscar siguiente", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: Int(NSFindPanelAction.next.rawValue)),
            item("Buscar anterior", #selector(NSTextView.performFindPanelAction(_:)), "g", [.command, .shift],
                 tag: Int(NSFindPanelAction.previous.rawValue)),
        ])
        submenu("Formato", [
            item("Negrita", #selector(makeBold(_:)), "b", target: self),
            item("Cursiva", #selector(makeItalic(_:)), "i", target: self),
            item("Tachado", #selector(makeStrikethrough(_:)), "x", [.command, .shift], target: self),
            item("Código", #selector(makeCode(_:)), "k", target: self),
            .separator(),
            item("Aumentar letra", #selector(biggerFont(_:)), "+", target: self),
            item("Aumentar letra", #selector(biggerFont(_:)), "=", target: self),
            item("Reducir letra", #selector(smallerFont(_:)), "-", target: self),
        ])
        submenu("Notas", (0 ..< NotesStore.count).map {
            item(NotesStore.colorNames[$0], #selector(selectNote(_:)), "\($0 + 1)", tag: $0, target: self)
        })
        return main
    }
}
