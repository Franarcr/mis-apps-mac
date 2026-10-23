import AppKit
import ApplicationServices

/// Ventanas de otras apps a través de Accesibilidad. Las posiciones de Accesibilidad tienen el origen
/// arriba a la izquierda de la pantalla principal; las de AppKit, abajo a la izquierda.
enum WindowControl {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // MARK: Encontrar ventanas

    /// Ventana activa de la app que está delante.
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return copy(axApp, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
    }

    /// Ventana activa de una app concreta.
    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        copy(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
    }

    /// Ventanas visibles (no minimizadas) de las apps abiertas, para elegir cuál colocar.
    /// No se filtra por tipo de ventana: algunas apps (WhatsApp, por ejemplo) no declaran la ventana como
    /// "estándar". Si una app no informa de sus ventanas, se usa su ventana principal o la activa.
    static func listWindows(log: Bool = true) -> [(window: AXUIElement, app: NSRunningApplication, title: String)] {
        var result: [(AXUIElement, NSRunningApplication, String)] = []
        var report: [String] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.bundleIdentifier != Bundle.main.bundleIdentifier {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windows = (copy(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            if windows.isEmpty {
                windows = [kAXMainWindowAttribute, kAXFocusedWindowAttribute].compactMap { copy(axApp, $0).map { $0 as! AXUIElement } }
            }
            var kept = 0
            for window in windows where !result.contains(where: { CFEqual($0.0, window) }) {
                guard (copy(window, kAXMinimizedAttribute) as? Bool) != true,
                      let frame = frame(of: window), frame.width >= 150, frame.height >= 100 else { continue }
                result.append((window, app, (copy(window, kAXTitleAttribute) as? String) ?? ""))
                kept += 1
            }
            report.append("\(app.localizedName ?? "?") \(kept)/\(windows.count)")
        }
        if log { Log.write("Ventanas (incluidas/total por app): " + report.joined(separator: ", ")) }
        return result
    }

    /// Ventana bajo un punto (en coordenadas de Accesibilidad / CGEvent).
    static func window(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        if role(of: element) == kAXWindowRole { return element }
        return copy(element, kAXWindowAttribute).map { $0 as! AXUIElement }
    }

    static func appName(of window: AXUIElement) -> String? {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    // MARK: Marco

    /// Marco de la ventana en coordenadas de AppKit (origen abajo a la izquierda).
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let posValue = copy(window, kAXPositionAttribute), let sizeValue = copy(window, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return toAppKit(CGRect(origin: position, size: size))
    }

    /// Coloca la ventana en un marco de AppKit. Primero el tamaño, luego la posición y otra vez el tamaño:
    /// así funciona también al pasar a otro monitor de distinto tamaño.
    @discardableResult
    static func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        let ax = toAX(frame.integral)
        var position = ax.origin
        var size = ax.size
        var results: [AXError] = []
        withoutAnimation(window) {
            if let sizeValue = AXValueCreate(.cgSize, &size) { results.append(AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)) }
            if let posValue = AXValueCreate(.cgPoint, &position) { results.append(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)) }
            if let sizeValue = AXValueCreate(.cgSize, &size) { results.append(AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)) }
        }
        let ok = results.allSatisfy { $0 == .success }
        Log.write("Colocar \(appName(of: window) ?? "?") en \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height)) → "
            + (ok ? "OK" : "errores \(results.map(\.rawValue))") + " · resultado \(Self.frame(of: window).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height))" } ?? "?")")
        return ok
    }

    /// Ventana en pantalla completa de macOS (en su propio escritorio): así no se puede mover.
    static func isFullScreen(_ window: AXUIElement) -> Bool {
        (copy(window, "AXFullScreen") as? Bool) == true
    }

    static func exitFullScreen(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
    }

    /// Mueve sin cambiar el tamaño (para arrastrar, que es más rápido).
    static func setPosition(_ axOrigin: CGPoint, of window: AXUIElement) {
        var position = axOrigin
        if let value = AXValueCreate(.cgPoint, &position) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) }
    }

    static func setSize(_ size: CGSize, of window: AXUIElement) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) }
    }

    /// Posición y tamaño tal como los da Accesibilidad (origen arriba a la izquierda).
    static func axFrame(of window: AXUIElement) -> CGRect? {
        frame(of: window).map(toAX)
    }

    /// Pone la ventana delante; con `activate`, además pasa a su app (Lazo deja de estar delante).
    static func raise(_ window: AXUIElement, activate: Bool = true) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        guard activate else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    // MARK: Pantallas

    /// Pantalla donde está la mayor parte de la ventana.
    static func screen(for frame: CGRect) -> NSScreen {
        NSScreen.screens.max { a, b in
            a.frame.intersection(frame).area < b.frame.intersection(frame).area
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func toAX(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func toAppKit(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Utilidades

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func role(of element: AXUIElement) -> String? {
        copy(element, kAXRoleAttribute) as? String
    }

    /// Algunas apps animan cada cambio cuando "AXEnhancedUserInterface" está activo; se desactiva un momento.
    private static func withoutAnimation(_ window: AXUIElement, _ body: () -> Void) {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = AXUIElementCreateApplication(pid)
        let key = "AXEnhancedUserInterface" as CFString
        var value: CFTypeRef?
        let wasEnabled = AXUIElementCopyAttributeValue(app, key, &value) == .success && (value as? Bool) == true
        if wasEnabled { AXUIElementSetAttributeValue(app, key, kCFBooleanFalse) }
        body()
        if wasEnabled { AXUIElementSetAttributeValue(app, key, kCFBooleanTrue) }
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// Recuerda el marco anterior de cada ventana para poder deshacer la última colocación.
@MainActor
enum FrameHistory {
    private static var entries: [(window: AXUIElement, frame: CGRect)] = []

    static func remember(_ window: AXUIElement) {
        guard let frame = WindowControl.frame(of: window) else { return }
        entries.removeAll { CFEqual($0.window, window) }
        entries.append((window, frame))
        if entries.count > 50 { entries.removeFirst() }
    }

    static func previous(of window: AXUIElement) -> CGRect? {
        entries.last { CFEqual($0.window, window) }?.frame
    }
}

/// Registro sencillo en ~/Library/Logs/Lazo/lazo.log (para diagnosticar ventanas que no se mueven).
enum Log {
    private static let url: URL = {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Lazo")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("lazo.log")
    }()

    static func write(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        let data = Data("\(stamp)  \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
