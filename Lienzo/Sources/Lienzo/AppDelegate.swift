import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // El primero que se crea pasa a ser el controlador compartido.
        _ = LienzoDocumentController()
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if NSDocumentController.shared.documents.isEmpty { WelcomeWindow.shared.show() }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WelcomeWindow.shared.show() }
        return false
    }

    @objc func showWelcome(_ sender: Any?) { WelcomeWindow.shared.show() }

    @MainActor @objc func importMiro(_ sender: Any?) { MiroImportWindow.shared.show() }

    /// Archivos abiertos desde Finder; el HTML de Miro lo atiende LienzoDocumentController.
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        Self.open(url)
        return true
    }

    static func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSAlert(error: error).runModal() }
        }
    }

    // MARK: - Menús

    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                      target: AnyObject? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.keyEquivalentModifierMask = mods
        mi.target = target
        return mi
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        mi.submenu = menu
        return mi
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let sep = { NSMenuItem.separator() }

        main.addItem(submenu("Lienzo", [
            item("Acerca de Lienzo", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            sep(),
            item("Ocultar Lienzo", #selector(NSApplication.hide(_:)), "h"),
            item("Ocultar otros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Mostrar todo", #selector(NSApplication.unhideAllApplications(_:)), ""),
            sep(),
            item("Salir de Lienzo", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("Archivo", [
            item("Nuevo tablero", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Abrir…", #selector(NSDocumentController.openDocument(_:)), "o"),
            item("Tableros recientes…", #selector(showWelcome(_:)), "o", [.command, .shift], target: self),
            sep(),
            item("Cerrar", #selector(NSWindow.performClose(_:)), "w"),
            item("Guardar", #selector(NSDocument.save(_:)), "s"),
            item("Guardar como…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift, .option]),
            item("Duplicar", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]),
            item("Cambiar nombre…", #selector(NSDocument.rename(_:)), ""),
            sep(),
            submenu("Importar", [
                item("De Miro…", #selector(importMiro(_:)), "i", [.command, .option], target: self),
                item("Imágenes o PDF…", #selector(CanvasView.insertImage(_:)), ""),
            ]),
            submenu("Exportar como", [
                item("PNG…", #selector(CanvasView.exportPNG(_:)), "e", [.command, .shift]),
                item("PDF…", #selector(CanvasView.exportPDF(_:)), "e", [.command, .option]),
                item("PDF con una página por marco…", #selector(CanvasView.exportFramesPDF(_:)), ""),
            ]),
        ]))

        main.addItem(submenu("Edición", [
            item("Deshacer", Selector(("undo:")), "z"),
            item("Rehacer", Selector(("redo:")), "z", [.command, .shift]),
            sep(),
            item("Cortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Pegar", #selector(NSText.paste(_:)), "v"),
            item("Duplicar", #selector(CanvasView.duplicateSelection(_:)), "d"),
            item("Eliminar", #selector(NSText.delete(_:)), ""),
            item("Seleccionar todo", #selector(NSText.selectAll(_:)), "a"),
            sep(),
            item("Editar texto", #selector(CanvasView.editText(_:)), ""),
            item("Traer al frente", #selector(CanvasView.bringToFront(_:)), "]"),
            item("Enviar al fondo", #selector(CanvasView.sendToBack(_:)), "["),
        ]))

        var toolItems: [NSMenuItem] = Tool.allCases.map { t in
            let mi = item("\(t.title)   (\(t.key.uppercased()))", #selector(CanvasView.chooseTool(_:)), "")
            mi.representedObject = t.rawValue
            mi.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: nil)
            return mi
        }
        toolItems.append(sep())
        toolItems.append(item("Insertar imagen…", #selector(CanvasView.insertImage(_:)), "i", [.command, .shift]))
        main.addItem(submenu("Herramientas", toolItems))

        main.addItem(submenu("Visualización", [
            item("Acercar", #selector(CanvasView.zoomIn(_:)), "+"),
            item("Alejar", #selector(CanvasView.zoomOut(_:)), "-"),
            item("Tamaño real", #selector(CanvasView.zoomActual(_:)), "0"),
            item("Ajustar a la pantalla", #selector(CanvasView.zoomFit(_:)), "1"),
            sep(),
            item("Pantalla completa", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        let window = submenu("Ventana", [
            item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:)), ""),
            sep(),
            item("Mostrar pestaña anterior", #selector(NSWindow.selectPreviousTab(_:)), "{"),
            item("Mostrar pestaña siguiente", #selector(NSWindow.selectNextTab(_:)), "}"),
            sep(),
            item("Traer todo al frente", #selector(NSApplication.arrangeInFront(_:)), ""),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu

        let help = submenu("Ayuda", [])
        main.addItem(help)
        NSApp.helpMenu = help.submenu
        return main
    }
}
