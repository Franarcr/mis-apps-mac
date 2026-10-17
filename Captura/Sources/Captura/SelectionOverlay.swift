import AppKit

/// Ventana a pantalla completa que muestra la captura congelada y deja seleccionar un área.
final class SelectionOverlayWindow: NSWindow {
    /// `completion` recibe el área elegida (en puntos de la vista) o `nil` si se cancela.
    /// Con `allowsClick`, un clic sin arrastrar elige la pantalla completa.
    init(shot: DisplayShot, hint: String, allowsClick: Bool = false, completion: @escaping (NSRect?) -> Void) {
        super.init(contentRect: shot.screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = SelectionView(frame: NSRect(origin: .zero, size: shot.screen.frame.size),
                                 image: shot.image, hint: hint, allowsClick: allowsClick, completion: completion)
        contentView = view
        setFrame(shot.screen.frame, display: false)
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SelectionView: NSView {
    private let image: CGImage
    private let hint: String
    private let allowsClick: Bool
    private let completion: (NSRect?) -> Void
    private var start: NSPoint?
    private var current: NSPoint?
    private var mouse: NSPoint?
    private var finished = false

    /// Píxeles de la imagen por punto de pantalla (2 en Retina).
    private var scale: CGFloat { CGFloat(image.width) / bounds.width }

    init(frame: NSRect, image: CGImage, hint: String, allowsClick: Bool, completion: @escaping (NSRect?) -> Void) {
        self.image = image
        self.hint = hint
        self.allowsClick = allowsClick
        self.completion = completion
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
        if let window {
            let p = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            if bounds.contains(p) { mouse = p }
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    private var selection: NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    private func point(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil)
        return NSPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    // MARK: Ratón y teclado

    override func mouseMoved(with event: NSEvent) {
        mouse = point(event)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        start = point(event)
        current = start
        mouse = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = point(event)
        mouse = current
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let sel = selection, sel.width >= 3, sel.height >= 3 else {
            if allowsClick { finish(bounds); return }
            start = nil
            current = nil
            needsDisplay = true
            return
        }
        finish(sel)
    }

    override func rightMouseDown(with event: NSEvent) { finish(nil) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            finish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private func finish(_ result: NSRect?) {
        guard !finished else { return }
        finished = true
        completion(result)
    }

    // MARK: Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: bounds)

        let dim = NSColor.black.withAlphaComponent(0.4).cgColor
        ctx.setFillColor(dim)

        if let sel = selection, sel.width > 0, sel.height > 0 {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(sel)
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)

            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(sel.insetBy(dx: -0.5, dy: -0.5))

            let label = "\(Int((sel.width * scale).rounded())) × \(Int((sel.height * scale).rounded()))"
            var origin = NSPoint(x: sel.maxX + 8, y: sel.minY - 28)
            if origin.y < 4 { origin.y = sel.minY + 6 }
            drawLabel(label, at: origin)
        } else {
            ctx.fill(bounds)
            drawLabel(hint + "  ·  Esc para cancelar", centeredAtTop: true)
            if let m = mouse { drawCrosshair(at: m, in: ctx) }
        }

        if let m = mouse { drawLoupe(at: m, in: ctx) }
    }

    private func drawCrosshair(at p: NSPoint, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.move(to: CGPoint(x: 0, y: p.y.rounded() + 0.5))
        ctx.addLine(to: CGPoint(x: bounds.maxX, y: p.y.rounded() + 0.5))
        ctx.move(to: CGPoint(x: p.x.rounded() + 0.5, y: 0))
        ctx.addLine(to: CGPoint(x: p.x.rounded() + 0.5, y: bounds.maxY))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Lupa con zoom de píxeles junto al cursor, para seleccionar con precisión.
    private func drawLoupe(at p: NSPoint, in ctx: CGContext) {
        let n = 15
        let half = n / 2
        let px = Int(p.x * scale), py = Int((bounds.height - p.y) * scale)
        guard let zoom = image.cropping(to: CGRect(x: px - half, y: py - half, width: n, height: n)),
              zoom.width == n, zoom.height == n else { return }

        let size: CGFloat = 120
        var origin = NSPoint(x: p.x + 24, y: p.y - 24 - size)
        if origin.x + size > bounds.maxX { origin.x = p.x - 24 - size }
        if origin.y < bounds.minY + 30 { origin.y = p.y + 24 }
        let box = NSRect(origin: origin, size: NSSize(width: size, height: size))
        let shape = CGPath(roundedRect: box, cornerWidth: 10, cornerHeight: 10, transform: nil)

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.interpolationQuality = .none
        ctx.draw(zoom, in: box)
        let cell = size / CGFloat(n)
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(NSRect(x: box.minX + CGFloat(half) * cell, y: box.minY + CGFloat(half) * cell, width: cell, height: cell))
        ctx.restoreGState()

        ctx.addPath(shape)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokePath()

        drawLabel("\(px), \(py)", at: NSPoint(x: box.minX, y: box.minY - 26))
    }

    private func drawLabel(_ text: String, at origin: NSPoint? = nil, centeredAtTop: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var o = origin ?? .zero
        if centeredAtTop { o = NSPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 60) }
        let bg = NSRect(x: o.x, y: o.y, width: size.width + 14, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 6, yRadius: 6).fill()
        str.draw(at: NSPoint(x: o.x + 7, y: o.y + 4))
    }
}
