import AppKit
import ApplicationServices

/// Cierra del todo las apps elegidas cuando se cierra su última ventana (con el botón rojo o ⌘W),
/// en lugar de dejarlas abiertas en el Dock sin ventanas.
@MainActor
final class QuitOnClose {
    /// Identificadores de las apps elegidas.
    private(set) var bundleIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "quitOnClose") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "quitOnClose") }
    }

    private var observers: [pid_t: AXObserver] = [:]

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func contains(_ bundleID: String) -> Bool { bundleIDs.contains(bundleID) }

    func toggle(_ bundleID: String) {
        if bundleIDs.contains(bundleID) { bundleIDs.remove(bundleID) } else { bundleIDs.insert(bundleID) }
        refresh()
    }

    /// Vigila las apps elegidas que están abiertas y deja de vigilar las demás.
    func refresh() {
        guard Accessibility.isTrusted else { return }
        let chosen = bundleIDs
        let apps = NSWorkspace.shared.runningApplications.filter { chosen.contains($0.bundleIdentifier ?? "") }
        let pids = Set(apps.map(\.processIdentifier))
        for (pid, observer) in observers where !pids.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = nil
        }
        for app in apps where observers[app.processIdentifier] == nil {
            watch(app.processIdentifier)
        }
    }

    private func watch(_ pid: pid_t) {
        var created: AXObserver?
        guard AXObserverCreate(pid, quitOnCloseCallback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let app = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon)
        for window in app.windows {
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    fileprivate func handle(_ notification: String, element: AXUIElement, observer: AXObserver) {
        guard let pid = observers.first(where: { $0.value === observer })?.key else { return }
        if notification == kAXWindowCreatedNotification {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
        } else if notification == kAXUIElementDestroyedNotification {
            // Se espera un poco: algunas apps cierran una ventana y abren otra enseguida.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.quitIfWindowless(pid)
            }
        }
    }

    private func quitIfWindowless(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              contains(app.bundleIdentifier ?? ""),
              AXUIElementCreateApplication(pid).standardWindows.isEmpty else { return }
        app.terminate()
    }
}

/// Las notificaciones de Accesibilidad llegan por el bucle principal, así que ya están en el hilo principal.
private let quitOnCloseCallback: AXObserverCallback = { observer, element, notification, refcon in
    guard let refcon else { return }
    let quitter = Unmanaged<QuitOnClose>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated {
        quitter.handle(notification as String, element: element, observer: observer)
    }
}
