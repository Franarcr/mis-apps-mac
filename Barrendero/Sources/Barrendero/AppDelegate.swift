import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

/// Estado compartido entre el menú y las ventanas.
@MainActor
final class SweepState: ObservableObject {
    @Published var rules = SweepRules.load() {
        didSet {
            guard rules != oldValue else { return }
            rules.save()
            onRulesChange?()
        }
    }
    var onRulesChange: (() -> Void)?
    /// Dejar de barrer a los remitentes que se desmarquen al revisar.
    @Published var forgetUnchecked = true
    @Published var candidates: [Candidate] = []
    /// Remitentes (o reglas) que se dejan fuera de esta barrida.
    @Published var excluded: Set<String> = []
    @Published var busy: String?
    @Published var message: String?

    var selected: [Candidate] { candidates.filter { !excluded.contains($0.reason) } }
    var unselected: [Candidate] { candidates.filter { excluded.contains($0.reason) } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let state = SweepState()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var reviewWindow: NSWindow?
    private var rulesWindow: NSWindow?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "bubbles.and.sparkles", accessibilityDescription: "Barrendero")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        menu.delegate = self
        statusItem.menu = menu
        BarraLink.connect(statusItem) { [weak self] in
            if let menu = self?.menu { BarraLink.popUp(menu) }
        }
        UNUserNotificationCenter.current().delegate = self
        state.onRulesChange = { [weak self] in self?.scheduleRuleSync() }
        if mailRulesAccepted {
            // Si cambiaron las reglas mientras la app estaba cerrada, se rehacen en Mail.
            if UserDefaults.standard.string(forKey: "syncedRules") != rulesFingerprint { scheduleRuleSync() }
        } else {
            Task {
                try? await Task.sleep(for: .seconds(1))
                askToCreateRules()
            }
        }
        // Cada 30 minutos mira si ya toca la limpieza de la semana.
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.automaticRun() }
        }
        Task {
            try? await Task.sleep(for: .seconds(20))
            await automaticRun()
        }
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Barrendero", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if let busy = state.busy {
            menu.addItem(info(busy))
        } else {
            if let last = Schedule.lastRun {
                menu.addItem(info("Última: \(last.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "es")))) · \(Schedule.lastResult ?? "")"))
            } else {
                menu.addItem(info("Todavía no ha barrido."))
            }
            if Schedule.automatic {
                menu.addItem(info("Próxima: \(Schedule.nextRun.formatted(.dateTime.weekday(.wide).day().month().hour().minute().locale(Locale(identifier: "es"))))"))
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Revisar ahora…", #selector(reviewNow), enabled: state.busy == nil))
        menu.addItem(item("Barrer también el correo viejo de la bandeja…", #selector(explainOldMail)))
        menu.addItem(.separator())
        menu.addItem(item("Barrer siempre al remitente del correo seleccionado en Mail", #selector(addSelectedSender)))
        menu.addItem(item("Reglas…", #selector(showRules)))
        if !mailRulesAccepted {
            menu.addItem(item("Crear las reglas en Mail…", #selector(askToCreateRules)))
        }
        menu.addItem(.separator())

        let weekly = item("Limpiar cada semana", #selector(toggleAutomatic))
        weekly.state = Schedule.automatic ? .on : .off
        menu.addItem(weekly)
        let day = NSMenuItem(title: "Día de la limpieza", action: nil, keyEquivalent: "")
        let days = NSMenu()
        for (index, name) in Schedule.weekdayNames.enumerated() {
            let entry = item(name.capitalized + ", 9:00", #selector(chooseDay(_:)))
            entry.tag = index + 1
            entry.state = Schedule.weekday == index + 1 ? .on : .off
            days.addItem(entry)
        }
        day.submenu = days
        menu.addItem(day)
        let ask = item("Preguntar antes de mover a la papelera", #selector(toggleAsk))
        ask.state = Schedule.askFirst ? .on : .off
        menu.addItem(ask)
        let login = item("Abrir al iniciar sesión", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Salir de Barrendero", #selector(quit), key: "q"))
    }

    private func info(_ text: String) -> NSMenuItem {
        let entry = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func item(_ title: String, _ action: Selector, enabled: Bool = true, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: key)
        entry.target = self
        return entry
    }

    @objc private func reviewNow() { Task { await review(automatic: false) } }

    @objc private func explainOldMail() {
        alert("Barrer el correo que ya estaba",
              "Las reglas de Barrendero actúan sobre el correo que va llegando. Para aplicarlas también al que ya está en la bandeja: en Mail, abre la Bandeja de entrada, elige Edición › Seleccionar todo y después Mensaje › Aplicar reglas (⌥⌘L). Mail aparta lo que coincida en «Barridos» y aquí lo revisas con «Revisar ahora…».")
    }

    // MARK: Reglas de Mail

    /// La usuaria aceptó que Barrendero cree y mantenga sus reglas en Mail.
    private var mailRulesAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: "mailRulesAccepted") }
        set { UserDefaults.standard.set(newValue, forKey: "mailRulesAccepted") }
    }

    @objc private func askToCreateRules() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "¿Crear las reglas de Barrendero en Mail?"
        alert.informativeText = "Barrendero crea en Mail la carpeta «Barridos» (en tu Mac) y reglas que apartan ahí la publicidad, los boletines, las redes y los avisos de inicio de sesión del BN en cuanto llegan (\(state.rules.senders.count) remitentes). Nada se borra sin que lo confirmes: cada semana te muestra lo apartado para mandarlo a la papelera o devolverlo. Puedes cambiar las reglas en «Reglas…»."
        alert.addButton(withTitle: "Crear las reglas")
        alert.addButton(withTitle: "Ahora no")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mailRulesAccepted = true
        scheduleRuleSync()
    }

    private var rulesFingerprint: String {
        let data = (try? JSONEncoder().encode(state.rules)) ?? Data()
        return String(data.hashValue) + "-\(state.rules.senders.count)-\(state.rules.subjectRules.count)"
    }

    private var ruleSync: Task<Void, Never>?

    /// Rehace las reglas de Mail un momento después del último cambio.
    private func scheduleRuleSync() {
        guard mailRulesAccepted else { return }
        ruleSync?.cancel()
        ruleSync = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            do {
                try await Sweeper.syncMailRules(state.rules)
                UserDefaults.standard.set(rulesFingerprint, forKey: "syncedRules")
            } catch {
                state.message = error.localizedDescription
            }
        }
    }

    @objc private func toggleAutomatic() { Schedule.automatic.toggle() }
    @objc private func toggleAsk() { Schedule.askFirst.toggle() }
    @objc private func chooseDay(_ sender: NSMenuItem) { Schedule.weekday = sender.tag }

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

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func addSelectedSender() {
        Task {
            do {
                guard let sender = try await Sweeper.selectedSender() else {
                    alert("No hay un correo seleccionado", "Selecciona en Mail un correo de ese remitente y vuelve a intentarlo.")
                    return
                }
                let address = Self.address(of: sender)
                if !state.rules.senders.contains(where: { $0.caseInsensitiveCompare(address) == .orderedSame }) {
                    state.rules.senders.append(address)
                }
                notify("Regla agregada", "Desde ahora se barren los correos de \(address).")
            } catch {
                alert("No se pudo leer Mail", error.localizedDescription)
            }
        }
    }

    /// «Tienda <ofertas@tienda.com>» → «ofertas@tienda.com».
    nonisolated static func address(of sender: String) -> String {
        if let start = sender.lastIndex(of: "<"), let end = sender.lastIndex(of: ">"), start < end {
            return String(sender[sender.index(after: start)..<end]).lowercased()
        }
        return sender.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // MARK: Revisar y barrer

    private func automaticRun() async {
        guard Schedule.automatic, state.busy == nil, Date() >= Schedule.nextRun else { return }
        // No abre Mail por su cuenta: espera a que esté abierto.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty else { return }
        await review(automatic: true)
    }

    private func review(automatic: Bool) async {
        state.busy = "Revisando el correo…"
        state.message = nil
        defer { state.busy = nil }
        do {
            let found = try await Sweeper.scan(rules: state.rules) { text in
                Task { @MainActor in self.state.busy = text }
            }
            state.candidates = found
            // Lo que coincide con «Nunca barrer» se propone devolver a la bandeja.
            state.excluded = Set(found.filter(\.isException).map(\.reason))
            if found.isEmpty {
                finish(moved: 0)
                if !automatic { alert("Todo limpio", "No hay nada apartado en «Barridos» ni correo no deseado.") }
                return
            }
            if automatic && !Schedule.askFirst {
                await sweep()
            } else {
                showReview()
                if automatic {
                    notify("Barrendero encontró \(found.count) correos para barrer", "Revisa la lista y confírmalo.")
                }
            }
        } catch {
            if automatic {
                notify("Barrendero no pudo revisar el correo", error.localizedDescription)
            } else {
                alert("No se pudo revisar el correo", error.localizedDescription)
            }
        }
    }

    func sweep() async {
        let selected = state.selected
        let kept = state.unselected
        state.busy = "Barriendo…"
        defer { state.busy = nil }
        do {
            let moved = try await Sweeper.process(selected, trash: true) { text in
                Task { @MainActor in self.state.busy = text }
            }
            // Lo desmarcado vuelve a la bandeja de entrada (el no deseado, a la de su cuenta).
            let restored = try await Sweeper.process(kept, trash: false) { text in
                Task { @MainActor in self.state.busy = text }
            }
            if state.forgetUnchecked {
                let senders = Set(kept.filter { !$0.isJunk && !$0.isException }.map { $0.reason.lowercased() })
                if !senders.isEmpty {
                    state.rules.senders.removeAll { senders.contains($0.lowercased()) }
                }
            }
            finish(moved: moved)
            state.candidates = []
            reviewWindow?.close()
            notify("Listo: \(moved) correos a la papelera" + (restored > 0 ? " y \(restored) de vuelta a la bandeja" : ""),
                   "Puedes recuperarlos desde la papelera de cada cuenta si hace falta.")
        } catch {
            alert("No se pudo terminar de barrer", error.localizedDescription)
        }
    }

    private func finish(moved: Int) {
        Schedule.lastRun = Date()
        Schedule.lastResult = moved == 0 ? "nada que barrer" : "\(moved) correos a la papelera"
    }

    // MARK: Ventanas

    private func showReview() {
        if reviewWindow == nil {
            let view = ReviewView(state: state, sweep: { [weak self] in Task { await self?.sweep() } },
                                  close: { [weak self] in self?.reviewWindow?.close() })
            reviewWindow = window("Barrendero: correos para barrer", content: view, size: NSSize(width: 720, height: 560))
        }
        NSApp.activate(ignoringOtherApps: true)
        reviewWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showRules() {
        if rulesWindow == nil {
            rulesWindow = window("Barrendero: reglas", content: RulesView(state: state), size: NSSize(width: 680, height: 600))
        }
        NSApp.activate(ignoringOtherApps: true)
        rulesWindow?.makeKeyAndOrderFront(nil)
    }

    private func window<Content: View>(_ title: String, content: Content, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private func notify(_ title: String, _ body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // Al tocar el aviso «encontró N correos», se abre la lista.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            if !self.state.candidates.isEmpty { self.showReview() }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
