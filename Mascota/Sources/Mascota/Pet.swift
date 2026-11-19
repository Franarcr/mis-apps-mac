import AppKit

/// Tuqui, el tucán: camina por el borde de abajo y encima de las ventanas, vuela para subirse a ellas,
/// cae si le mueves la ventana, duerme si no tocas la Mac, «trabaja» cuando tecleas mucho
/// y te pide una pausa tras una hora seguida usando la Mac.
@MainActor
final class Pet {
    enum State { case walking, idle, sleeping, falling, dragged, flying, working, reminding }

    /// La ventana es más ancha que el tucán para que quepa el globo del aviso.
    static let size = CGSize(width: 150, height: 120)
    static let footInset: CGFloat = 0
    private let window: PetWindow
    private let view: PetView
    private var timer: Timer?
    private(set) var state: State = .idle
    private var direction: CGFloat = 1
    private var velocityY: CGFloat = 0
    private var stateUntil = Date()
    private var frame = 0
    private var target: (x: CGFloat, y: CGFloat)?
    private var surfaces: [Surface] = []
    private var lastSurfaceScan = Date.distantPast
    private var keyCounts: [(Date, UInt32)] = []
    private var activeSince = Date()
    var isVisible: Bool { window.isVisible }

    /// Minutos seguidos usando la Mac antes de pedir una pausa (se reinicia tras 5 min sin tocarla).
    private var breakMinutes: Double {
        let v = UserDefaults.standard.double(forKey: "minutosPausa")
        return v > 0 ? v : 60
    }

    init() {
        view = PetView(frame: NSRect(origin: .zero, size: Self.size))
        window = PetWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.onDragStart = { [weak self] in self?.state = .dragged }
        view.onDragEnd = { [weak self] in self?.velocityY = 0; self?.state = .falling }
        view.onClick = { [weak self] in self?.clicked() }
        let screen = NSScreen.main?.visibleFrame ?? .zero
        window.setFrameOrigin(NSPoint(x: screen.midX, y: screen.minY))
        if !UserDefaults.standard.bool(forKey: "escondido") { window.orderFrontRegardless() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func setVisible(_ visible: Bool) {
        UserDefaults.standard.set(!visible, forKey: "escondido")
        visible ? window.orderFrontRegardless() : window.orderOut(nil)
    }

    func dropAtMouse() {
        let p = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: p.x - Self.size.width / 2, y: p.y))
        velocityY = 0
        state = .falling
    }

    private func clicked() {
        if state == .reminding {           // tocarlo cuando pide pausa: «ya entendí»
            activeSince = Date()
            state = .idle
            stateUntil = Date().addingTimeInterval(2)
        } else {
            view.hearts = 45               // un cariño
        }
    }

    // MARK: Superficies: el piso y el borde de arriba de las ventanas visibles

    struct Surface { let minX: CGFloat; let maxX: CGFloat; let y: CGFloat }

    private func scanSurfaces() {
        lastSurfaceScan = Date()
        let floor = screen
        var out = [Surface(minX: floor.minX, maxX: floor.maxX, y: floor.minY)]
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { surfaces = out; return }
        var above: [NSRect] = []    // ventanas que están delante (la lista va de delante hacia atrás)
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != me,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
                  w > 160, h > 100 else { continue }
            let rect = NSRect(x: x, y: primaryHeight - y - h, width: w, height: h)
            defer { above.append(rect) }
            let top = rect.maxY
            // Solo si el borde de arriba se ve (no lo tapa otra ventana) y queda bajo la barra de menús.
            let mid = NSPoint(x: rect.midX, y: top - 2)
            guard !above.contains(where: { $0.contains(mid) }),
                  NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: 0, dy: -1).contains(NSPoint(x: rect.midX, y: top - 1)) && top < $0.visibleFrame.maxY - 40 })
            else { continue }
            out.append(Surface(minX: rect.minX + 10, maxX: rect.maxX - 10, y: top))
        }
        surfaces = out
    }

    private var screen: NSRect {
        let center = NSPoint(x: window.frame.midX, y: window.frame.minY + 20)
        return (NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main)?.visibleFrame ?? .zero
    }

    private var centerX: CGFloat { window.frame.midX }

    private func support(at y: CGFloat) -> Surface? {
        surfaces.first { abs($0.y - y) < 3 && centerX >= $0.minX && centerX <= $0.maxX }
    }

    // MARK: Lo que haces en la Mac

    private var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Teclas por minuto en el último minuto.
    private func typingRate() -> Double {
        let now = Date()
        let count = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        keyCounts.append((now, count))
        keyCounts.removeAll { now.timeIntervalSince($0.0) > 60 }
        guard let first = keyCounts.first, now.timeIntervalSince(first.0) > 5 else { return 0 }
        return Double(count &- first.1) / now.timeIntervalSince(first.0) * 60
    }

    // MARK: Cada cuadro

    private func tick() {
        guard window.isVisible else { return }
        frame += 1
        if Date().timeIntervalSince(lastSurfaceScan) > 0.3 { scanSurfaces() }
        var origin = window.frame.origin
        let idle = idleSeconds
        if idle > 300 { activeSince = Date() }
        let away = idle > 120
        let needsBreak = Date().timeIntervalSince(activeSince) > breakMinutes * 60
        let typing = frame % 15 == 0 ? typingRate() : lastRate
        lastRate = typing

        switch state {
        case .dragged:
            break
        case .falling:
            velocityY = max(velocityY - 1.2, -30)
            let next = origin.y + velocityY
            // Aterriza en la superficie más alta que cruce al bajar.
            if let land = surfaces.filter({ centerX >= $0.minX && centerX <= $0.maxX && $0.y <= origin.y && $0.y >= next })
                .max(by: { $0.y < $1.y }) {
                origin.y = land.y
                state = .idle
                stateUntil = Date().addingTimeInterval(1.5)
                view.dizzyUntil = frame + 45
            } else {
                origin.y = max(next, screen.minY)
                if origin.y == screen.minY { state = .idle }
            }
        case .flying:
            guard let t = target else { state = .falling; break }
            let dx = t.x - centerX, dy = t.y - origin.y
            let dist = hypot(dx, dy)
            if dist < 4 {
                origin.x += dx; origin.y = t.y
                target = nil
                state = .idle
                stateUntil = Date().addingTimeInterval(.random(in: 2...5))
            } else {
                origin.x += dx / dist * 4; origin.y += dy / dist * 4
                direction = dx >= 0 ? 1 : -1
            }
        case .sleeping:
            if support(at: origin.y) == nil { state = .falling; velocityY = 0; break }
            if !away { state = .idle; stateUntil = Date().addingTimeInterval(2) }
        case .reminding:
            if support(at: origin.y) == nil { state = .falling; velocityY = 0; break }
            if !needsBreak || away { state = .idle }
        case .working:
            if support(at: origin.y) == nil { state = .falling; velocityY = 0; break }
            if typing < 60 { state = .idle; stateUntil = Date().addingTimeInterval(2) }
            if needsBreak { state = .reminding }
        case .idle, .walking:
            // Si le movieron o cerraron la ventana de abajo, se cae.
            guard let floor = support(at: origin.y) else { state = .falling; velocityY = 0; break }
            if away { state = .sleeping; break }
            if needsBreak { state = .reminding; break }
            if typing > 120 { state = .working; break }
            if Date() > stateUntil { pickNext(origin: origin) }
            if state == .walking {
                origin.x += direction * 1.2
                if centerX <= floor.minX || centerX >= floor.maxX {
                    if floor.y > screen.minY + 1 && Bool.random() {
                        state = .falling; velocityY = 0       // se tira de la ventana
                    } else {
                        direction *= -1
                        origin.x += direction * 3
                    }
                }
            }
        }
        if state != .dragged { window.setFrameOrigin(origin) }

        view.state = state
        view.direction = direction
        view.frameIndex = frame
        view.needsDisplay = true
    }
    private var lastRate = 0.0

    private func pickNext(origin: NSPoint) {
        let roll = Int.random(in: 0..<10)
        // A veces vuela a una ventana cercana.
        let reachable = surfaces.filter { abs($0.y - origin.y) > 40 && $0.y - origin.y < 600
            && min(abs($0.minX - centerX), abs($0.maxX - centerX), ($0.minX...$0.maxX).contains(centerX) ? 0 : .infinity) < 500 }
        if roll < 2, let s = reachable.randomElement() {
            let x = min(max(centerX + .random(in: -150...150), s.minX + 20), s.maxX - 20)
            target = (x - Self.size.width / 2 + Self.size.width / 2, s.y)
            target = (x, s.y)
            state = .flying
        } else if roll < 7 {
            state = .walking
            if Int.random(in: 0..<3) == 0 { direction *= -1 }
            stateUntil = Date().addingTimeInterval(.random(in: 3...9))
        } else {
            state = .idle
            stateUntil = Date().addingTimeInterval(.random(in: 2...6))
        }
    }
}

final class PetWindow: NSWindow {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovable = false
    }
    override var canBecomeKey: Bool { false }
}
