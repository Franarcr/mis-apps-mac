import AppKit
import ServiceManagement

/// Agrupa los iconos de la barra de menús. Pone dos elementos: una flecha y, a su izquierda, una línea.
/// Los iconos que el usuario arrastra (con ⌘) a la izquierda de la línea se esconden al «plegar»:
/// la línea se estira hasta 10 000 puntos y los empuja fuera de la pantalla. Los que quedan a la derecha
/// de la flecha (como Captura) se ven siempre.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let separatorLength: CGFloat = 14
    private static let collapsedLength: CGFloat = 10_000
    private static let autoCollapseDelay: TimeInterval = 10

    private var arrow: NSStatusItem!
    private var separator: NSStatusItem!
    private var isCollapsed = false
    private var autoCollapseTimer: Timer?
    private let optionsMenu = NSMenu()

    /// Volver a esconder los iconos solos unos segundos después de mostrarlos.
    private var autoCollapse: Bool {
        get { UserDefaults.standard.object(forKey: "autoCollapse") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCollapse") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Los elementos nuevos aparecen a la izquierda de los existentes: primero la flecha, luego la línea.
        // Con autosaveName, macOS recuerda dónde los deja el usuario.
        arrow = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        arrow.autosaveName = "Barra.flecha"
        arrow.button?.target = self
        arrow.button?.action = #selector(arrowClicked)
        arrow.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        separator = NSStatusBar.system.statusItem(withLength: Self.separatorLength)
        separator.autosaveName = "Barra.linea"
        separator.button?.image = Self.lineImage
        separator.button?.target = self
        separator.button?.action = #selector(arrowClicked)
        separator.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        optionsMenu.delegate = self
        updateArrow()

        if UserDefaults.standard.bool(forKey: "helpShown") {
            // Se espera a que la barra coloque los elementos antes de comprobar sus posiciones.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.setCollapsed(true) }
        } else {
            UserDefaults.standard.set(true, forKey: "helpShown")
            showHelp()
        }
    }

    // MARK: Plegar y desplegar

    @objc private func arrowClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            // El menú se asigna solo mientras se muestra; si no, el clic normal también lo abriría.
            arrow.menu = optionsMenu
            arrow.button?.performClick(nil)
            arrow.menu = nil
        } else {
            setCollapsed(!isCollapsed)
        }
    }

    @objc private func toggleCollapsed() { setCollapsed(!isCollapsed) }

    private func setCollapsed(_ collapse: Bool) {
        autoCollapseTimer?.invalidate()
        // Si la línea quedó a la derecha de la flecha, al estirarse escondería la flecha misma.
        if collapse && !separatorIsLeftOfArrow {
            isCollapsed = false
            applyLayout()
            showMisplacedWarning()
            return
        }
        isCollapsed = collapse
        applyLayout()
        if !collapse && autoCollapse {
            autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: Self.autoCollapseDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.setCollapsed(true) }
            }
        }
    }

    private func applyLayout() {
        separator.length = isCollapsed ? Self.collapsedLength : Self.separatorLength
        separator.button?.image = isCollapsed ? nil : Self.lineImage
        updateArrow()
    }

    private var separatorIsLeftOfArrow: Bool {
        guard let line = separator.button?.window?.frame, let arrowFrame = arrow.button?.window?.frame else { return true }
        return line.minX < arrowFrame.minX
    }

    private func updateArrow() {
        // Plegado: la flecha apunta hacia donde aparecerán los iconos.
        let name = isCollapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: isCollapsed ? "Mostrar iconos" : "Ocultar iconos")
        image?.isTemplate = true
        arrow.button?.image = image
    }

    /// Línea vertical fina que marca dónde empiezan los iconos agrupados.
    private static let lineImage: NSImage = {
        let image = NSImage(size: NSSize(width: 4, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1.25, y: 1, width: 1.5, height: 14), xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    // MARK: Menú de opciones (clic derecho en la flecha)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item(isCollapsed ? "Mostrar iconos agrupados" : "Ocultar iconos agrupados", #selector(toggleCollapsed)))
        let auto = item("Ocultarlos solos a los \(Int(Self.autoCollapseDelay)) segundos", #selector(toggleAutoCollapse))
        auto.state = autoCollapse ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())
        menu.addItem(item("Cómo elegir qué iconos se agrupan…", #selector(showHelp)))
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

    @objc private func toggleAutoCollapse() {
        autoCollapse.toggle()
        if autoCollapse && !isCollapsed { setCollapsed(false) } // arranca el temporizador
        if !autoCollapse { autoCollapseTimer?.invalidate() }
    }

    @objc private func showHelp() {
        setCollapsed(false)
        autoCollapseTimer?.invalidate()
        let alert = NSAlert()
        alert.messageText = "Cómo agrupar los iconos"
        alert.informativeText = """
        En la barra de menús hay una flecha › y, a su izquierda, una línea │.

        1. Mantén pulsada la tecla ⌘ y arrastra cada icono con el ratón.
        2. Los que pongas a la izquierda de la línea │ se agrupan: se esconden al hacer clic en la flecha.
        3. Los que dejes a la derecha de la flecha (por ejemplo Captura) se ven siempre.

        Clic en la flecha: mostrar u ocultar los iconos agrupados.
        Clic derecho en la flecha: opciones.
        """
        alert.addButton(withTitle: "Entendido")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showMisplacedWarning() {
        let alert = NSAlert()
        alert.messageText = "La línea quedó a la derecha de la flecha"
        alert.informativeText = "Mantén pulsada ⌘ y arrastra la línea │ a la izquierda de la flecha ›. Si no, al ocultar los iconos se escondería también la flecha."
        alert.addButton(withTitle: "Entendido")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
