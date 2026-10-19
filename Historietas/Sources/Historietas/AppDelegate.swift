import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var readers: [ReaderWindowController] = []
    private let recentMenu = NSMenu(title: "Abrir reciente")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        recentMenu.delegate = self
        // Si la app se abrió sola (no con doble clic en un cómic), se pide qué leer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if self?.readers.isEmpty == true { self?.openDocument(nil) }
        }
    }

    /// Cómics abiertos desde el Finder, arrastrados al icono del Dock o con «Abrir con».
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(open)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openDocument(nil) }
        return false
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.message = "Elige uno o más cómics (CBZ, CBR, CB7 o CBT)"
        panel.allowedContentTypes = ComicArchive.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open)
    }

    func open(_ url: URL) {
        let url = url.standardizedFileURL
        Preferences.addRecent(url)
        // Un mismo cómic solo se abre en una ventana.
        if let reader = readers.first(where: { $0.url == url }) {
            reader.showWindow(nil)
            return
        }
        let reader = ReaderWindowController(url: url)
        reader.onClose = { [weak self, weak reader] in self?.readers.removeAll { $0 === reader } }
        reader.onOpenFiles = { [weak self] urls in urls.forEach { self?.open($0) } }
        readers.append(reader)
        reader.showWindow(nil)
    }

    // MARK: Abrir reciente

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in Preferences.recents {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            menu.addItem(NSMenuItem(title: "Ninguno", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(.separator())
            let clear = NSMenuItem(title: "Borrar menú", action: #selector(clearRecents(_:)), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { open(url) }
    }

    @objc private func clearRecents(_ sender: Any?) { Preferences.clearRecents() }

    // MARK: Menú principal

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        @discardableResult
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            parent.submenu = menu
            main.addItem(parent)
            return menu
        }
        func item(_ title: String, _ action: Selector?, _ key: String, _ mods: NSEvent.ModifierFlags = .command,
                  target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            return item
        }
        func arrow(_ key: Int) -> String { String(Character(UnicodeScalar(UInt16(key))!)) }

        submenu("Historietas", [
            item("Acerca de Historietas", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Ocultar Historietas", #selector(NSApplication.hide(_:)), "h"),
            item("Ocultar otras", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Mostrar todo", #selector(NSApplication.unhideAllApplications(_:)), ""),
            .separator(),
            item("Salir de Historietas", #selector(NSApplication.terminate(_:)), "q"),
        ])

        let recent = item("Abrir reciente", nil, "")
        recent.submenu = recentMenu
        submenu("Archivo", [
            item("Abrir…", #selector(openDocument(_:)), "o", target: self),
            recent,
            .separator(),
            item("Cerrar", #selector(NSWindow.performClose(_:)), "w"),
        ])

        // Para el campo de «Ir a la página».
        submenu("Edición", [
            item("Cortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Pegar", #selector(NSText.paste(_:)), "v"),
            item("Seleccionar todo", #selector(NSText.selectAll(_:)), "a"),
        ])

        typealias Reader = ReaderWindowController
        submenu("Visualización", [
            item("Página entera", #selector(Reader.fitPage(_:)), "1"),
            item("Ajustar al ancho", #selector(Reader.fitWidth(_:)), "2"),
            item("Tamaño real", #selector(Reader.fitOriginal(_:)), "3"),
            .separator(),
            item("Doble página", #selector(Reader.toggleDoublePage(_:)), "d"),
            item("Portada sola en doble página", #selector(Reader.toggleCoverAlone(_:)), "d", [.command, .shift]),
            item("De derecha a izquierda (manga)", #selector(Reader.toggleRightToLeft(_:)), "m", [.command, .shift]),
            .separator(),
            item("Ampliar", #selector(Reader.zoomIn(_:)), "+"),
            item("Reducir", #selector(Reader.zoomOut(_:)), "-"),
            item("Tamaño normal", #selector(Reader.resetZoom(_:)), "0"),
            .separator(),
            item("Pantalla completa", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])

        submenu("Ir", [
            item("Página siguiente", #selector(Reader.nextPage(_:)), arrow(NSRightArrowFunctionKey)),
            item("Página anterior", #selector(Reader.previousPage(_:)), arrow(NSLeftArrowFunctionKey)),
            item("Primera página", #selector(Reader.firstPage(_:)), arrow(NSUpArrowFunctionKey)),
            item("Última página", #selector(Reader.lastPage(_:)), arrow(NSDownArrowFunctionKey)),
            .separator(),
            item("Ir a la página…", #selector(Reader.goToPage(_:)), "g"),
        ])

        let windowMenu = submenu("Ventana", [
            item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:)), ""),
            .separator(),
            item("Traer todo al frente", #selector(NSApplication.arrangeInFront(_:)), ""),
        ])
        NSApp.windowsMenu = windowMenu
        return main
    }
}
