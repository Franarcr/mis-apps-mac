import AppKit
import ServiceManagement

/// Agrupa los iconos de la barra de menús. Pone dos elementos: una flecha y, a su izquierda, una línea.
/// Los iconos que el usuario arrastra (con ⌘) a la izquierda de la línea se esconden al «plegar»:
/// la línea se estira hasta ocupar todo el sitio libre y ya no caben. Los que quedan a la derecha
/// de la flecha (como Captura) se ven siempre.
///
/// La línea no puede medir más que el sitio libre: si no cabe, macOS la descarta a ella en lugar de
/// apartar los otros iconos. Por eso se ajusta midiendo la barra, y se vuelve a ajustar al cambiar
/// de app (cada app tiene un menú de distinto ancho y deja más o menos sitio).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let separatorLength: CGFloat = 14
    private static let autoCollapseDelay: TimeInterval = 10

    private var arrow: NSStatusItem!
    private var separator: NSStatusItem!
    private var isCollapsed = false
    private var autoCollapseTimer: Timer?
    /// Pasos que quedan para ajustar el largo de la línea plegada.
    private var fitStepsLeft = 0
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

        // Al cambiar de app o de pantalla cambia el sitio libre en la barra.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refit() }
        }
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refit() }
        }

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
        separator.button?.image = isCollapsed ? nil : Self.lineImage
        updateArrow()
        if isCollapsed {
            let screen = NSScreen.main.map { "\(Int($0.frame.width))×\(Int($0.frame.height))" } ?? "?"
            Log.write("Plegar — macOS \(ProcessInfo.processInfo.operatingSystemVersionString), pantalla \(screen), \(statusWindowSummary())")
            // Primero, lo que ocupan ahora los iconos de la izquierda; luego se corrige midiendo.
            let bar = measureBar()
            if let leftmost = bar.leftItems.map(\.minX).min(), let line = bar.line {
                separator.length = Self.separatorLength + line.minX - leftmost + 4
            }
            refit()
        } else {
            fitStepsLeft = 0
            separator.length = Self.separatorLength
        }
    }

    private func refit() {
        guard isCollapsed else { return }
        fitStepsLeft = 12
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.fitStep() }
    }

    /// Un paso del ajuste: si quedan iconos a la izquierda de la línea, la alarga lo que ocupan;
    /// si la línea no cabe (macOS la ha quitado), la acorta. Se repite hasta que no quede ninguno.
    private func fitStep() {
        guard isCollapsed, fitStepsLeft > 0 else { return }
        fitStepsLeft -= 1
        let bar = measureBar()
        Log.write("Paso \(12 - fitStepsLeft): largo \(Int(separator.length)), línea \(bar.line.map { "x=\(Int($0.minX)) ancho=\(Int($0.width))" } ?? "no visible"), iconos a la izquierda: \(bar.leftItems.count)")
        if bar.line == nil {
            separator.length = max(Self.separatorLength, separator.length - 24)
        } else if !bar.leftItems.isEmpty {
            separator.length += bar.leftItems.map(\.width).reduce(0, +) + CGFloat(bar.leftItems.count) * 4
        } else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.fitStep() }
    }

    /// Cuántas ventanas del nivel de la barra de estado hay y dónde está la línea, para el registro.
    private func statusWindowSummary() -> String {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let status = list.filter { $0[kCGWindowLayer as String] as? Int == statusLevel }
        let number = separator.button?.window?.windowNumber ?? -1
        let ownsLine = list.contains { $0[kCGWindowNumber as String] as? Int == number }
        let layers = Set(list.compactMap { $0[kCGWindowLayer as String] as? Int }).sorted()
        return "\(status.count) iconos en la barra (nivel \(statusLevel)), ventana de la línea \(number) \(ownsLine ? "encontrada" : "NO encontrada"), niveles: \(layers)"
    }

    /// Posición de la línea en la barra (nil si macOS no la muestra) y de los iconos que están a su izquierda,
    /// en coordenadas de pantalla con el origen arriba a la izquierda.
    private func measureBar() -> (line: CGRect?, leftItems: [CGRect]) {
        guard let number = separator.button?.window?.windowNumber,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return (nil, [])
        }
        func frame(_ info: [String: Any]) -> CGRect? {
            (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        }
        guard let lineInfo = list.first(where: { $0[kCGWindowNumber as String] as? Int == number }),
              let line = frame(lineInfo), line.width > 1 else { return (nil, []) }
        // Los iconos de la barra son ventanas del nivel de la barra de estado, en la misma fila que la línea.
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let left = list.filter { info in
            info[kCGWindowLayer as String] as? Int == statusLevel && info[kCGWindowNumber as String] as? Int != number
        }.compactMap(frame).filter { item in
            abs(item.minY - line.minY) < 2 && item.maxX <= line.minX + 2 && item.width < 400 && item.maxX > 0
        }
        return (line, left)
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
        menu.addItem(item("Ver registro", #selector(openLog)))
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

    @objc private func openLog() {
        if !FileManager.default.fileExists(atPath: Log.url.path) { Log.write("Registro vacío: todavía no se plegó la barra") }
        NSWorkspace.shared.open(Log.url)
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
