import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyManager()
    private let capture = CaptureController()
    private var loginItem: NSMenuItem!
    private var saveItem: NSMenuItem!
    private var previewItems: [NSMenuItem] = []
    private var menu: NSMenu!
    private var recordingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        NSApp.mainMenu = buildMainMenu()
        // Borra las capturas temporales de sesiones anteriores.
        try? FileManager.default.removeItem(at: CaptureController.tempFolder)

        capture.onRecordingChanged = { [weak self] recording in self?.showRecording(recording) }

        // ⌥⇧1…5 para no chocar con los atajos del sistema (⌘⇧3/4/5).
        let mods = UInt32(optionKey | shiftKey)
        let ok = [
            hotKeys.register(keyCode: kVK_ANSI_1, modifiers: mods) { [weak self] in self?.capture.captureFullScreen() },
            hotKeys.register(keyCode: kVK_ANSI_2, modifiers: mods) { [weak self] in self?.capture.captureArea() },
            hotKeys.register(keyCode: kVK_ANSI_3, modifiers: mods) { [weak self] in self?.capture.captureText() },
            hotKeys.register(keyCode: kVK_ANSI_4, modifiers: mods) { [weak self] in self?.capture.toggleVideo() },
            hotKeys.register(keyCode: kVK_ANSI_5, modifiers: mods) { [weak self] in self?.capture.toggleScrolling() },
            hotKeys.register(keyCode: kVK_ANSI_6, modifiers: mods) { [weak self] in self?.capture.toggleGIF() },
        ]
        if ok.contains(false) {
            Toast.show("Algún atajo ya está en uso", symbol: "exclamationmark.triangle.fill",
                       detail: "Usa el menú de la barra superior para capturar.")
        }
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        showIdleIcon()

        menu = NSMenu()
        menu.addItem(item("Capturar área", "2", #selector(area)))
        menu.addItem(item("Capturar pantalla completa", "1", #selector(full)))
        menu.addItem(item("Capturar texto (OCR)", "3", #selector(ocr)))
        menu.addItem(item("Grabar vídeo", "4", #selector(video)))
        menu.addItem(item("Captura con desplazamiento", "5", #selector(scrolling)))
        menu.addItem(item("Grabar GIF", "6", #selector(gif)))
        menu.addItem(.separator())
        let annotate = item("Anotar tras capturar", "", #selector(toggleAnnotate(_:)))
        annotate.state = Settings.annotateAfterCapture ? .on : .off
        menu.addItem(annotate)
        saveItem = item("Guardar también en archivo", "", #selector(toggleSave))
        saveItem.state = Settings.saveToFile ? .on : .off
        menu.addItem(saveItem)
        menu.addItem(previewMenu())
        menu.addItem(audioMenu())
        menu.addItem(.separator())
        menu.addItem(item("Abrir carpeta de capturas", "", #selector(openFolder)))
        menu.addItem(item("Cambiar carpeta…", "", #selector(chooseFolder)))
        loginItem = item("Abrir al iniciar sesión", "", #selector(toggleLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Captura", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        BarraLink.connect(statusItem) { [weak self] in
            if let menu = self?.menu { BarraLink.popUp(menu) }
        }
    }

    private func showIdleIcon() {
        guard let button = statusItem.button else { return }
        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Captura")
        icon?.isTemplate = true
        button.image = icon
        button.title = ""
        button.contentTintColor = nil
    }

    /// Durante la grabación el icono pasa a rojo con el tiempo, y al pulsarlo se detiene.
    private func showRecording(_ recording: Bool) {
        guard let button = statusItem.button else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        if recording {
            // Mientras graba, el icono se ve aunque esté escondido con Barra: es el botón para detener.
            statusItem.isVisible = true
            statusItem.menu = nil
            button.target = self
            button.action = #selector(stopRecording)
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Detener grabación")
            button.contentTintColor = .systemRed
            button.imagePosition = .imageLeading
            let update = { [weak self] in
                guard let self, let start = self.capture.recordingStart else { return }
                button.title = " " + CaptureController.elapsed(since: start)
            }
            update()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                MainActor.assumeIsolated { update() }
            }
        } else {
            button.action = nil
            statusItem.menu = menu
            statusItem.isVisible = !BarraLink.isHidden
            showIdleIcon()
        }
    }

    @objc private func stopRecording() { capture.stopRecording() }

    private func item(_ title: String, _ key: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.option, .shift]
        item.target = self
        return item
    }

    private func previewMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Ocultar miniatura tras", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for seconds in Settings.previewOptions {
            let entry = item(seconds == 0 ? "No mostrar miniatura" : "\(seconds) segundos", "", #selector(setPreviewSeconds(_:)))
            entry.tag = seconds
            entry.state = seconds == Settings.previewSeconds ? .on : .off
            previewItems.append(entry)
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private func audioMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Audio de los vídeos", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let system = item("Sonido del sistema", "", #selector(toggleSystemAudio(_:)))
        system.state = Settings.recordSystemAudio ? .on : .off
        let mic = item("Micrófono", "", #selector(toggleMicrophone(_:)))
        mic.state = Settings.recordMicrophone ? .on : .off
        submenu.addItem(system)
        submenu.addItem(mic)
        parent.submenu = submenu
        return parent
    }

    @objc private func toggleSystemAudio(_ sender: NSMenuItem) {
        Settings.recordSystemAudio.toggle()
        sender.state = Settings.recordSystemAudio ? .on : .off
    }

    @objc private func toggleMicrophone(_ sender: NSMenuItem) {
        Settings.recordMicrophone.toggle()
        sender.state = Settings.recordMicrophone ? .on : .off
    }

    @objc private func setPreviewSeconds(_ sender: NSMenuItem) {
        Settings.previewSeconds = sender.tag
        previewItems.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
    }

    @objc private func toggleSave() {
        Settings.saveToFile.toggle()
        saveItem.state = Settings.saveToFile ? .on : .off
    }

    // Pequeña espera para que el menú desaparezca antes de capturar.
    private func afterMenuCloses(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @objc private func area() { afterMenuCloses { self.capture.captureArea() } }
    @objc private func full() { afterMenuCloses { self.capture.captureFullScreen() } }
    @objc private func ocr() { afterMenuCloses { self.capture.captureText() } }
    @objc private func video() { afterMenuCloses { self.capture.toggleVideo() } }
    @objc private func scrolling() { afterMenuCloses { self.capture.toggleScrolling() } }
    @objc private func gif() { afterMenuCloses { self.capture.toggleGIF() } }

    @objc private func toggleAnnotate(_ sender: NSMenuItem) {
        Settings.annotateAfterCapture.toggle()
        sender.state = Settings.annotateAfterCapture ? .on : .off
    }

    /// Menú principal (no se ve porque la app vive en la barra de menú), necesario para que
    /// funcionen ⌘Z, ⌘C, ⌘V, ⌘S… en el editor de anotaciones.
    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            parent.submenu = menu
            main.addItem(parent)
        }
        func entry(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            return item
        }
        submenu("Captura", [
            entry("Guardar", Selector(("saveImage:")), "s"),
            entry("Cerrar ventana", #selector(NSWindow.performClose(_:)), "w"),
        ])
        submenu("Edición", [
            entry("Deshacer", Selector(("undo:")), "z"),
            entry("Rehacer", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            entry("Cortar", #selector(NSText.cut(_:)), "x"),
            entry("Copiar", #selector(NSText.copy(_:)), "c"),
            entry("Pegar", #selector(NSText.paste(_:)), "v"),
            entry("Seleccionar todo", #selector(NSText.selectAll(_:)), "a"),
        ])
        return main
    }

    @objc private func openFolder() {
        try? FileManager.default.createDirectory(at: Settings.saveFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Settings.saveFolder)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Elegir"
        panel.directoryURL = Settings.saveFolder
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            Settings.saveFolder = url
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
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
