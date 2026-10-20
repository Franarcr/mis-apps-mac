import AppKit
import ApplicationServices

/// El botón verde agranda la ventana hasta ocupar la pantalla (sin la barra de menús ni el Dock)
/// en lugar de pasarla a pantalla completa en otro escritorio. Otro clic la devuelve a su tamaño.
/// Con ⌥ pulsada, el botón hace lo de siempre.
@MainActor
final class GreenButton {
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "greenButton") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "greenButton") }
    }

    private var tap: CFMachPort?
    private var swallowMouseUp = false
    /// Tamaño que tenía cada ventana agrandada, para devolvérselo.
    private var previousFrames: [(window: AXUIElement, frame: CGRect)] = []
    private let systemWide = AXUIElementCreateSystemWide()

    init() {
        // Si una app no responde, mejor dejar pasar el clic que congelar el ratón.
        AXUIElementSetMessagingTimeout(systemWide, 0.2)
    }

    /// Intercepta los clics del ratón. Necesita el permiso de Accesibilidad.
    func start() {
        guard tap == nil, Accessibility.isTrusted else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: greenButtonCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
    }

    /// Devuelve false si el clic se queda aquí y no llega a la app.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .leftMouseUp:
            guard swallowMouseUp else { return true }
            swallowMouseUp = false
            return false
        case .leftMouseDown:
            guard isEnabled, !event.flags.contains(.maskAlternate),
                  let window = windowOfGreenButton(at: event.location) else { return true }
            swallowMouseUp = true
            DispatchQueue.main.async { [weak self] in self?.toggleFill(window) }
            return false
        default:
            return true
        }
    }

    /// La ventana cuyo botón verde está bajo el puntero, si lo hay.
    private func windowOfGreenButton(at point: CGPoint) -> AXUIElement? {
        // Antes de preguntar por Accesibilidad (más lento), se comprueba con la lista de ventanas
        // que el clic cae en la esquina superior izquierda de una ventana.
        guard isNearWindowButtons(point) else { return nil }
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let element, (element.value(kAXSubroleAttribute) as String?) == "AXFullScreenButton",
              let window: AXUIElement = element.value(kAXWindowAttribute) else { return nil }
        // En pantalla completa, el botón verde sirve para salir: se deja como está.
        if (window.value("AXFullScreen") as Bool?) == true { return nil }
        return window
    }

    private func isNearWindowButtons(_ point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        // La lista va de delante hacia atrás: cuenta la primera ventana normal bajo el puntero.
        for info in list where info[kCGWindowLayer as String] as? Int == 0 {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.contains(point) else { continue }
            return point.x - rect.minX < 120 && point.y - rect.minY < 60
        }
        return false
    }

    private func toggleFill(_ window: AXUIElement) {
        guard let frame = window.frame, let screen = Accessibility.visibleFrame(for: frame) else { return }
        let saved = previousFrames.firstIndex { CFEqual($0.window, window) }
        if let saved, isClose(frame, screen) {
            window.setFrame(previousFrames.remove(at: saved).frame)
        } else {
            if let saved { previousFrames.remove(at: saved) }
            previousFrames.append((window, frame))
            window.setFrame(screen)
        }
    }

    /// Algunas apps redondean el tamaño (Terminal ajusta a filas y columnas), así que se admite margen.
    private func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 30 && abs(a.minY - b.minY) < 30 && abs(a.width - b.width) < 30 && abs(a.height - b.height) < 30
    }
}

/// El tap está en el bucle principal, así que se llama en el hilo principal.
private let greenButtonCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let button = Unmanaged<GreenButton>.fromOpaque(refcon).takeUnretainedValue()
    let passThrough = MainActor.assumeIsolated { button.handle(type, event) }
    return passThrough ? Unmanaged.passUnretained(event) : nil
}
