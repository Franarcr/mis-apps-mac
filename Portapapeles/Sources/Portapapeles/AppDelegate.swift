import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyManager()
    private let store = ClipStore()
    private lazy var history = HistoryController(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Portapapeles")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let ok = hotKeys.register(keyCode: kVK_ANSI_V, modifiers: UInt32(optionKey | shiftKey)) { [weak self] in
            self?.history.toggle()
        }
        if !ok { Toast.show("El atajo ⌥⇧V ya está en uso", detail: "Abre el historial desde la barra de menú.") }
    }

    // El menú se reconstruye cada vez que se abre para mostrar lo último copiado.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Mostrar historial", #selector(showHistory), key: "v"))
        menu.addItem(.separator())

        let recent = store.items.prefix(10)
        if recent.isEmpty {
            let empty = NSMenuItem(title: "Historial vacío", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for clip in recent {
            var title = clip.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            if title.count > 50 { title = String(title.prefix(50)) + "…" }
            let entry = item(title, #selector(copyRecent(_:)))
            entry.representedObject = clip.id
            entry.image = store.thumbnail(clip).map { thumb in
                thumb.size = NSSize(width: 16, height: 16)
                return thumb
            }
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        let pause = item(store.paused ? "Reanudar captura" : "Pausar captura", #selector(togglePause))
        menu.addItem(pause)
        menu.addItem(item("Borrar historial…", #selector(clearHistory)))
        if !Paster.hasAccess {
            menu.addItem(item("Activar pegado automático…", #selector(enablePaste)))
        }
        let login = item("Abrir al iniciar sesión", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Portapapeles", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = [.option, .shift] }
        item.target = self
        return item
    }

    @objc private func showHistory() { history.show() }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let clip = store.items.first(where: { $0.id == id }) else { return }
        store.copy(clip)
    }

    @objc private func togglePause() { store.paused.toggle() }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "¿Borrar el historial?"
        alert.informativeText = "Se eliminarán todos los elementos excepto los fijados."
        alert.addButton(withTitle: "Borrar")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { store.clear() }
    }

    @objc private func enablePaste() { Paster.requestAccess() }

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
