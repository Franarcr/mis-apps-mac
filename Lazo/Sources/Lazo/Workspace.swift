import AppKit

/// "Foto" del escritorio: dónde está cada ventana, para volver a dejarlo igual (por ejemplo, tras reiniciar).
struct WorkspaceSnapshot: Codable {
    struct Entry: Codable {
        let bundleID: String
        let appName: String
        let title: String
        /// Posición dentro de su monitor, en fracciones (0…1) de la zona útil, con origen abajo a la izquierda.
        let unitFrame: CGRect
        /// Monitor por su identificador estable (si ya no está conectado, se usa la pantalla principal).
        let screenID: String
    }

    let date: Date
    let entries: [Entry]
}

@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var snapshot: WorkspaceSnapshot?
    @Published var restoreAtLogin = UserDefaults.standard.bool(forKey: "restoreAtLogin") {
        didSet { UserDefaults.standard.set(restoreAtLogin, forKey: "restoreAtLogin") }
    }
    /// Abrir las apps del escritorio guardado que no estén abiertas.
    @Published var openMissingApps = UserDefaults.standard.object(forKey: "openMissingApps") as? Bool ?? true {
        didSet { UserDefaults.standard.set(openMissingApps, forKey: "openMissingApps") }
    }
    @Published var status: String?

    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lazo")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("escritorio.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.file) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try? decoder.decode(WorkspaceSnapshot.self, from: data)
        }
    }

    // MARK: Guardar

    func save() {
        guard WindowControl.isTrusted else { return WindowControl.requestAccess() }
        var entries: [WorkspaceSnapshot.Entry] = []
        for item in WindowControl.listWindows() {
            guard let bundleID = item.app.bundleIdentifier, let frame = WindowControl.frame(of: item.window) else { continue }
            let screen = WindowControl.screen(for: frame)
            let vf = screen.visibleFrame
            let unit = CGRect(x: (frame.minX - vf.minX) / vf.width, y: (frame.minY - vf.minY) / vf.height,
                              width: frame.width / vf.width, height: frame.height / vf.height)
            entries.append(.init(bundleID: bundleID, appName: item.app.localizedName ?? bundleID, title: item.title,
                                 unitFrame: unit, screenID: screen.stableID))
        }
        let snapshot = WorkspaceSnapshot(date: Date(), entries: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(snapshot).write(to: Self.file, options: .atomic)
        self.snapshot = snapshot
        status = "Escritorio guardado: \(entries.count) ventanas"
        Log.write("Escritorio guardado: " + entries.map { "\($0.appName) «\($0.title)»" }.joined(separator: ", "))
    }

    // MARK: Restaurar

    private var pending: [WorkspaceSnapshot.Entry] = []
    private var retryTimer: Timer?

    /// Vuelve a colocar las ventanas guardadas. Las que aún no existen (apps que están abriéndose)
    /// se reintentan cada segundo durante `wait` segundos.
    func restore(wait: TimeInterval = 20) {
        guard WindowControl.isTrusted else { return WindowControl.requestAccess() }
        guard let snapshot else {
            status = "Aún no hay ningún escritorio guardado"
            return
        }
        if openMissingApps {
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            for bundleID in Set(snapshot.entries.map(\.bundleID)) where !running.contains(bundleID) {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                Log.write("Escritorio: abriendo \(url.lastPathComponent)")
            }
        }
        pending = snapshot.entries
        let total = pending.count
        placePending()
        retryTimer?.invalidate()
        let deadline = Date().addingTimeInterval(wait)
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.placePending()
                if self.pending.isEmpty || Date() > deadline {
                    timer.invalidate()
                    let missing = self.pending.map(\.appName)
                    self.status = missing.isEmpty ? "Escritorio restaurado: \(total) ventanas"
                        : "Restauradas \(total - missing.count) de \(total) · sin ventana: \(Set(missing).sorted().joined(separator: ", "))"
                    Log.write("Escritorio: " + (self.status ?? ""))
                }
            }
        }
    }

    /// Coloca las ventanas pendientes que ya existen. Primero empareja por título y luego, entre las que
    /// quedan de cada app, por orden.
    private func placePending() {
        guard !pending.isEmpty else { return }
        let windows = WindowControl.listWindows(log: false)
        var used: [AXUIElement] = []
        var stillPending: [WorkspaceSnapshot.Entry] = []

        func available(_ bundleID: String) -> [(window: AXUIElement, title: String)] {
            windows.filter { $0.app.bundleIdentifier == bundleID }
                .filter { candidate in !used.contains { CFEqual($0, candidate.window) } }
                .map { ($0.window, $0.title) }
        }

        // 1) Mismo título; 2) cualquier ventana libre de la misma app.
        var unmatched: [WorkspaceSnapshot.Entry] = []
        for entry in pending {
            if let match = available(entry.bundleID).first(where: { $0.title == entry.title && !entry.title.isEmpty }) {
                place(match.window, entry)
                used.append(match.window)
            } else {
                unmatched.append(entry)
            }
        }
        for entry in unmatched {
            if let match = available(entry.bundleID).first {
                place(match.window, entry)
                used.append(match.window)
            } else {
                stillPending.append(entry)
            }
        }
        pending = stillPending
    }

    private func place(_ window: AXUIElement, _ entry: WorkspaceSnapshot.Entry) {
        let screen = NSScreen.screens.first { $0.stableID == entry.screenID } ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let u = entry.unitFrame
        let frame = CGRect(x: vf.minX + u.minX * vf.width, y: vf.minY + u.minY * vf.height,
                           width: u.width * vf.width, height: u.height * vf.height)
        if WindowControl.isFullScreen(window) {
            WindowControl.exitFullScreen(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { WindowControl.setFrame(frame, of: window) }
        } else {
            WindowControl.setFrame(frame, of: window)
        }
    }
}
