import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Ventana")
        windowMenu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openPhoto() { model.chooseFile() }
    @objc private func exportPhoto() { model.export() }
    @objc private func exportBatch() { model.exportBatch() }
    @objc private func undo() { model.undo() }
    @objc private func toggleOriginal() { model.showOriginal.toggle() }
    @objc private func reset() { model.reset() }
    @objc private func copyAdjustments() { model.copyAdjustments() }
    @objc private func pasteAdjustments() { model.pasteAdjustments() }
}
