import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: NSWindow!
    let model = EditorModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Revela"
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.setFrameAutosaveName("RevelaVentana")
        if !window.setFrameUsingName("RevelaVentana") { window.center() }
        model.loadThumbnails()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Abrir una foto con «Abrir con» o arrastrándola al icono del Dock.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.open(url) }
    }

    private func buildMenu() {
        let main = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem()
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            item.submenu = submenu
            main.addItem(item)
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = self
            return item
        }
        menu("Revela", [
            NSMenuItem(title: "Acerca de Revela", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Ocultar Revela", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            NSMenuItem(title: "Salir de Revela", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ])
        menu("Archivo", [
            item("Abrir…", #selector(openPhoto), "o"),
            recentMenuItem(),
            item("Exportar…", #selector(exportPhoto), "e"),
            item("Aplicar a varias fotos…", #selector(exportBatch), "e", [.command, .shift]),
            .separator(),
            NSMenuItem(title: "Cerrar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ])
        menu("Edición", [
            item("Deshacer", #selector(undo), "z"),
            item("Ver el original", #selector(toggleOriginal), "\\", []),
            item("Restablecer ajustes", #selector(reset), "r", [.command, .shift]),
            .separator(),
            item("Copiar ajustes", #selector(copyAdjustments), "c", [.command, .shift]),
            item("Pegar ajustes", #selector(pasteAdjustments), "v", [.command, .shift]),
        ])
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!), right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        menu("Proyecto", [
            item("Nuevo proyecto…", #selector(newProject), "n", [.command, .shift]),
            item("Añadir fotos…", #selector(addPhotos), ""),
            item("Añadir carpeta…", #selector(addFolder), ""),
            .separator(),
            item("Foto siguiente", #selector(nextPhoto), right),
            item("Foto anterior", #selector(previousPhoto), left),
            item("Marcar todas", #selector(markAll), "a", [.command, .shift]),
            .separator(),
            item("Sincronizar ajustes…", #selector(syncPhotos), "s", [.command, .shift]),
            item("Luz automática en las marcadas", #selector(autoMarked), ""),
            item("Exportar las marcadas…", #selector(exportMarked), ""),
        ])
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Ventana")
        windowMenu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    /// «Abrir reciente»: el submenú se rellena cada vez que se abre.
    private func recentMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Abrir reciente", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Abrir reciente")
        submenu.delegate = self
        item.submenu = submenu
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Abrir reciente" else { return }
        menu.removeAllItems()
        let recents = model.availableRecents
        if recents.isEmpty {
            menu.addItem(NSMenuItem(title: "Sin fotos recientes", action: nil, keyEquivalent: ""))
            return
        }
        for url in recents {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            item.toolTip = url.deletingLastPathComponent().path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Borrar la lista", action: #selector(clearRecents), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc private func openRecent(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { model.open(url) } }
    @objc private func clearRecents() { model.clearRecents() }
    @objc private func openPhoto() { model.chooseFile() }
    @objc private func newProject() { model.newProject() }
    @objc private func addPhotos() { model.addPhotosToProject(folders: false) }
    @objc private func addFolder() { model.addPhotosToProject(folders: true) }
    @objc private func nextPhoto() { model.step(1) }
    @objc private func previousPhoto() { model.step(-1) }
    @objc private func markAll() { model.selectAllInProject() }
    @objc private func syncPhotos() { if model.photo != nil, !model.selectedPhotos.isEmpty { model.showingSync = true } }
    @objc private func autoMarked() { model.autoLightSelected() }
    @objc private func exportMarked() { model.exportSelected() }
    @objc private func exportPhoto() { model.export() }
    @objc private func exportBatch() { model.exportBatch() }
    @objc private func undo() { model.undo() }
    @objc private func toggleOriginal() { model.showOriginal.toggle() }
    @objc private func reset() { model.reset() }
    @objc private func copyAdjustments() { model.copyAdjustments() }
    @objc private func pasteAdjustments() { model.pasteAdjustments() }
}
