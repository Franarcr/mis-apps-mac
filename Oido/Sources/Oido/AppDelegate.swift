import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let detector = Detector()
    private let prompt = Prompt()
    private let recorder = Recorder.shared
    private var window: NSWindow?
    private var ticker: Timer?
    /// Llamadas en las que ya se dijo «Ahora no»: no se vuelve a preguntar hasta que terminen.
    private var declined: Set<CallApp> = []

    private var autoRecord: Bool {
        get { UserDefaults.standard.bool(forKey: "autoRecord") }
        set { UserDefaults.standard.set(newValue, forKey: "autoRecord") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        BarraLink.connect(statusItem) { [weak self] in
            guard let self else { return }
            self.menuNeedsUpdate(self.menu)
            BarraLink.popUp(self.menu)
        }
        refreshIcon()
        _ = Store.shared

        detector.onCallStarted = { [weak self] app in self?.callStarted(app) }
        detector.onCallEnded = { [weak self] app in self?.callEnded(app) }
        detector.start()

        // Prueba: `open -a Oido --args --prueba 15` graba 15 segundos de todo el sonido.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--prueba"), i + 1 < args.count, let seconds = Double(args[i + 1]) {
            startRecording(.manual)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.stopRecording()
                self?.showWindow()
            }
            return
        }

        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            showWindow()
        }
    }

    // MARK: Llamadas

    private func callStarted(_ app: CallApp) {
        guard !recorder.isRecording else { return }
        if autoRecord {
            startRecording(app)
        } else if !declined.contains(app) {
            prompt.ask(app) { [weak self] in
                self?.startRecording(app)
            }
            declined.insert(app)   // solo se pregunta una vez por llamada
        }
    }

    private func callEnded(_ app: CallApp) {
        declined.remove(app)
        if recorder.currentApp == app { stopRecording() }
        else if !recorder.isRecording { prompt.close() }
    }

    private func startRecording(_ app: CallApp) {
        recorder.start(app)
        if recorder.isRecording { prompt.recordingBar(app) { [weak self] in self?.stopRecording() } }
        refreshIcon()
        if let error = recorder.lastError, !recorder.isRecording { alert(error) }
        // El micrófono puede pedir permiso primero: se vuelve a mirar en un momento.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.refreshIcon()
            if self.recorder.isRecording, !self.prompt.isShowing {
                self.prompt.recordingBar(app) { [weak self] in self?.stopRecording() }
            }
        }
    }

    private func stopRecording() {
        recorder.stop()
        prompt.close()
        refreshIcon()
    }

    // MARK: Icono y menú

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        if recorder.isRecording {
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Oído grabando")
            button.contentTintColor = .systemRed
            button.title = ""
            button.imagePosition = .imageLeading
            if ticker == nil {
                ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshIcon() }
                }
            }
        } else {
            button.image = NSImage(systemSymbolName: "ear", accessibilityDescription: "Oído")
            button.contentTintColor = nil
            button.title = ""
            ticker?.invalidate()
            ticker = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if recorder.isRecording, let app = recorder.currentApp {
            menu.addItem(disabled("Grabando \(app.name) · \(Call.clock(recorder.elapsed))"))
            menu.addItem(item("Detener grabación", #selector(stopFromMenu), key: "."))
        } else {
            let active = detector.active
            if active.isEmpty {
                menu.addItem(disabled("No hay ninguna llamada ahora"))
            }
            for app in CallApp.all where active.contains(app) {
                let i = item("Grabar llamada de \(app.name)", #selector(recordDetected(_:)))
                i.representedObject = app.name
                menu.addItem(i)
            }
            menu.addItem(item("Grabar ahora (todo el sonido)", #selector(recordManual)))
        }
        if let error = recorder.lastError {
            menu.addItem(disabled("⚠︎ " + error))
        }
        menu.addItem(.separator())
        menu.addItem(item("Ver llamadas…", #selector(openWindow), key: "l"))
        menu.addItem(.separator())
        let auto = item("Grabar automáticamente", #selector(toggleAuto))
        auto.state = autoRecord ? .on : .off
        menu.addItem(auto)
        let login = item("Abrir al iniciar sesión", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(disabled("Vigila WhatsApp, Teams, Zoom, FaceTime y Meet"))
        menu.addItem(.separator())
        menu.addItem(item("Salir de Oído", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc private func recordDetected(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let app = CallApp.all.first(where: { $0.name == name }) else { return }
        prompt.close()
        startRecording(app)
    }

    @objc private func recordManual() { startRecording(.manual) }
    @objc private func stopFromMenu() { stopRecording() }
    @objc private func openWindow() { showWindow() }
    @objc private func toggleAuto() { autoRecord.toggle() }
    @objc private func quit() {
        if recorder.isRecording { recorder.stop() }
        NSApp.terminate(nil)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert("No se pudo cambiar: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if recorder.isRecording { recorder.stop() }
    }

    // MARK: Ventana

    private func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Oído"
            w.contentView = NSHostingView(rootView: CallsView())
            w.minSize = NSSize(width: 700, height: 440)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("OidoVentana")
            if !w.setFrameUsingName("OidoVentana") { w.center() }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = "Oído"
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
