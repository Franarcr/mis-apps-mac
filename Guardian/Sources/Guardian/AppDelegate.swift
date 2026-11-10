import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let state = GuardState()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var programsWindow: NSWindow?
    private var connectionsWindow: NSWindow?
    private var timer: Timer?
    private var lastStamp: Date?
    private var hadSession = false

    /// Hasta qué línea del registro de AnyDesk ya se avisó.
    private var notifiedLine: Int {
        get { UserDefaults.standard.object(forKey: "notifiedLine") as? Int ?? -1 }
        set { UserDefaults.standard.set(newValue, forKey: "notifiedLine") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        BarraLink.connect(statusItem) { [weak self] in
            if let menu = self?.menu { BarraLink.popUp(menu) }
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        state.refreshAnyDesk()
        // La primera vez no se avisa de las conexiones viejas: solo de las que lleguen desde ahora.
        if notifiedLine < 0 { notifiedLine = state.connections.last?.line ?? 0 }
        lastStamp = AnyDeskWatch.traceStamp()
        hadSession = !state.sessions.isEmpty
        updateIcon()
        state.scanPrograms()

        // Cada 5 segundos: ¿alguien entró o salió?
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watch() }
        }

        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            Task {
                try? await Task.sleep(for: .seconds(1))
                showConnections()
            }
        }
    }

    // MARK: Vigilancia

    private func watch() {
        let stamp = AnyDeskWatch.traceStamp()
        let sessions = AnyDeskWatch.activeSessions(lastIncoming: state.incoming.last?.remoteID)
        let changed = stamp != lastStamp || (sessions.isEmpty != state.sessions.isEmpty)
        guard changed else { return }
        lastStamp = stamp
        state.refreshAnyDesk()

        let fresh = state.incoming.filter { $0.line > notifiedLine }
        if let newest = fresh.last {
            notifiedLine = state.connections.last?.line ?? notifiedLine
            notifyConnection(newest, count: fresh.count)
        }
        let hasSession = !state.sessions.isEmpty
        if hadSession && !hasSession {
            notify(title: "Se cerró la conexión de AnyDesk", body: "Ya no hay nadie conectado a este Mac.", id: "fin")
        }
        hadSession = hasSession
        updateIcon()
    }

    private func notifyConnection(_ connection: Connection, count: Int) {
        let known = TrustedDevices.isTrusted(connection.remoteID)
        let who = TrustedDevices.label(connection.remoteID)
        let title = known ? "\(TrustedDevices.name(connection.remoteID) ?? "Un equipo de confianza") entró a tu Mac" : "⚠️ Un equipo desconocido entró a tu Mac"
        var body = "Por AnyDesk: \(who). \(connection.methodText)."
        if !known { body += " Si no lo esperabas, abre Guardián y pulsa «Cortar ahora»." }
        if count > 1 { body += " (\(count) conexiones nuevas)" }
        notify(title: title, body: body, id: "conexion-\(connection.line)", urgent: !known)
    }

    private func notify(title: String, body: String, id: String, urgent: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = urgent ? .defaultCritical : .default
        if urgent { content.interruptionLevel = .timeSensitive }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { showConnections() }
    }

    private func updateIcon() {
        let active = state.sessions.first
        let unknown = active.map { !TrustedDevices.isTrusted($0.remoteID ?? "") } ?? false
        let symbol = active == nil ? "checkmark.shield" : (unknown ? "exclamationmark.shield.fill" : "eye.fill")
        let description = active == nil ? "Guardián: nadie conectado" : "Guardián: hay alguien conectado por AnyDesk"
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        // En rojo si entra un desconocido; si no, el icono normal de la barra.
        if unknown, let icon, let red = icon.withSymbolConfiguration(.init(paletteColors: [.systemRed])) {
            red.isTemplate = false
            statusItem.button?.image = red
        } else {
            icon?.isTemplate = true
            statusItem.button?.image = icon
        }
        statusItem.button?.toolTip = description
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        state.refreshAnyDesk()
        updateIcon()
        menu.removeAllItems()
        let title = NSMenuItem(title: "Guardián", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if !AnyDeskWatch.installed {
            menu.addItem(info("AnyDesk no está instalado."))
        } else if let session = state.sessions.first {
            let who = TrustedDevices.label(session.remoteID ?? "?")
            menu.addItem(info("● Conectado ahora: \(who)"))
            menu.addItem(info("   desde las \(session.since.formatted(date: .omitted, time: .shortened))"))
            menu.addItem(item("Cortar la conexión y cerrar AnyDesk…", #selector(cutConnection)))
        } else {
            menu.addItem(info("Nadie conectado por AnyDesk."))
            if let last = state.incoming.last {
                let when = last.date.formatted(.dateTime.weekday(.wide).day().month().hour().minute().locale(Locale(identifier: "es")))
                menu.addItem(info("Última: \(when) · \(TrustedDevices.label(last.remoteID))"))
            }
        }
        if state.unattended {
            menu.addItem(info("⚠︎ Acceso desatendido encendido en AnyDesk"))
        }
        menu.addItem(.separator())
        menu.addItem(item("Conexiones de AnyDesk…", #selector(showConnections)))
        let review = state.programs.filter(\.needsAttention).count
        menu.addItem(item(state.scanning ? "Programas instalados (revisando…)" : "Programas instalados… (\(review) para revisar)", #selector(showPrograms)))
        for access in state.systemAccess where access.enabled {
            menu.addItem(info("⚠︎ \(access.name) de macOS encendido"))
        }
        menu.addItem(.separator())
        let login = item("Abrir al iniciar sesión", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Salir de Guardián", #selector(quit), key: "q"))
    }

    private func info(_ text: String) -> NSMenuItem {
        let entry = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // MARK: Acciones

    @objc private func cutConnection() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "¿Cortar la conexión de AnyDesk?"
        alert.informativeText = "Se cierra AnyDesk por completo: la persona conectada pierde el control de este Mac y nadie más podrá entrar hasta que vuelvas a abrir AnyDesk.\n\nSi eres tú quien maneja este Mac desde otro equipo, perderás la conexión."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cortar ahora")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task.detached {
            let closed = AnyDeskWatch.cutAll()
            await MainActor.run {
                self.state.refreshAnyDesk()
                self.hadSession = !self.state.sessions.isEmpty
                self.updateIcon()
                if self.state.sessions.isEmpty {
                    self.notify(title: "Conexión cortada", body: "AnyDesk está cerrado (\(closed) procesos). Para que no vuelvan a entrar sin permiso, revisa en AnyDesk › Ajustes › Seguridad el acceso desatendido y los accesos guardados.", id: "cortada")
                } else {
                    self.alert("No se pudo cerrar AnyDesk", "AnyDesk sigue abierto, quizás porque está instalado como servicio del sistema. Ciérralo desde su menú o apaga la conexión a internet.")
                }
            }
        }
    }

    @objc func showConnections() {
        state.refreshAnyDesk()
        connectionsWindow = show(connectionsWindow, title: "Guardián · Conexiones de AnyDesk",
                                 view: ConnectionsView(state: state, cut: { [weak self] in self?.cutConnection() }))
    }

    @objc private func showPrograms() {
        if state.programs.isEmpty { state.scanPrograms() }
        programsWindow = show(programsWindow, title: "Guardián · Programas instalados", view: ProgramsView(state: state))
    }

    private func show<V: View>(_ existing: NSWindow?, title: String, view: V) -> NSWindow {
        NSApp.activate(ignoringOtherApps: true)
        if let existing {
            existing.makeKeyAndOrderFront(nil)
            return existing
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("No se pudo cambiar el inicio automático", error.localizedDescription)
        }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
