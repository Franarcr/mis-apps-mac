import AppKit
import ApplicationServices

/// ⌃⌥ + arrastrar mueve la ventana bajo el ratón desde cualquier punto; ⌃⌥⇧ + arrastrar la redimensiona.
/// Usa un "event tap" del sistema para recibir esos clics antes que la app (y que no le lleguen).
@MainActor
final class DragMover {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private enum Mode { case move, resize }
    private var drag: (window: AXUIElement, mode: Mode, mouse: CGPoint, frame: CGRect)?

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil, WindowControl.isTrusted else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let mover = Unmanaged<DragMover>.fromOpaque(userInfo).takeUnretainedValue()
            let consumed = MainActor.assumeIsolated { mover.handle(type, event) }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }, userInfo: me) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        drag = nil
    }

    /// Devuelve `true` si el evento se queda aquí (no llega a la app de debajo).
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS desactiva el tap si tarda; se vuelve a activar.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false

        case .leftMouseDown:
            let flags = event.flags
            guard flags.contains(.maskControl), flags.contains(.maskAlternate), !flags.contains(.maskCommand),
                  let window = WindowControl.window(at: event.location),
                  let frame = WindowControl.axFrame(of: window) else { return false }
            WindowControl.raise(window)
            FrameHistory.remember(window)
            drag = (window, flags.contains(.maskShift) ? .resize : .move, event.location, frame)
            return true

        case .leftMouseDragged:
            guard let drag else { return false }
            let dx = event.location.x - drag.mouse.x, dy = event.location.y - drag.mouse.y
            switch drag.mode {
            case .move:
                WindowControl.setPosition(CGPoint(x: drag.frame.minX + dx, y: drag.frame.minY + dy), of: drag.window)
            case .resize:
                // Desde la esquina inferior derecha (en Accesibilidad, y crece hacia abajo).
                WindowControl.setSize(CGSize(width: max(200, drag.frame.width + dx), height: max(120, drag.frame.height + dy)),
                                      of: drag.window)
            }
            return true

        case .leftMouseUp:
            guard drag != nil else { return false }
            drag = nil
            return true

        default:
            return false
        }
    }
}
