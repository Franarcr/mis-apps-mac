import AppKit

/// Dibuja a Tuqui con figuras simples, sin imágenes. Mira a la derecha; si va a la izquierda se refleja.
final class PetView: NSView {
    var state: Pet.State = .idle
    var direction: CGFloat = 1
    var frameIndex = 0
    var dizzyUntil = 0
    var hearts = 0
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onClick: (() -> Void)?
    private var grab = NSPoint.zero
    private var moved = false

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Solo el tucán recibe clics; lo transparente deja pasar el mouse a tus apps.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return NSRect(x: 30, y: 0, width: 90, height: 72).contains(p) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        grab = event.locationInWindow
        moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        if !moved { moved = true; onDragStart?() }
        let p = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: p.x - grab.x, y: p.y - grab.y))
    }
    override func mouseUp(with event: NSEvent) { moved ? onDragEnd?() : onClick?() }

    // MARK: Dibujo

    private let black = NSColor(calibratedWhite: 0.1, alpha: 1)
    private let bib = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.62, alpha: 1)
    private let beakTop = NSColor(calibratedRed: 0.55, green: 0.80, blue: 0.25, alpha: 1)
    private let beakMid = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.10, alpha: 1)
    private let beakTip = NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.12, alpha: 1)
    private let eyeRing = NSColor(calibratedRed: 0.35, green: 0.70, blue: 0.95, alpha: 1)
    private let legs = NSColor(calibratedRed: 0.35, green: 0.50, blue: 0.85, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        let t = CGFloat(frameIndex)
        let sleeping = state == .sleeping, dragged = state == .dragged, flying = state == .flying
        let working = state == .working, reminding = state == .reminding
        let walking = state == .walking

        // Salta al caminar; brinca de alegría cuando pide la pausa.
        var lift: CGFloat = 0
        if walking { lift = abs(sin(t / 5)) * 5 }
        if reminding { lift = abs(sin(t / 4)) * 8 }
        let breathe = sleeping ? sin(t / 20) * 1.2 : 0

        NSGraphicsContext.saveGraphicsState()
        if direction < 0 {
            let flip = NSAffineTransform()
            flip.translateX(by: bounds.width, yBy: 0)
            flip.scaleX(by: -1, yBy: 1)
            flip.concat()
        }

        // Patas
        legs.setStroke()
        for (i, x) in [CGFloat(66), 78].enumerated() {
            let p = NSBezierPath(); p.lineWidth = 3; p.lineCapStyle = .round
            var kick: CGFloat = 0
            if dragged { kick = sin(t / 2 + CGFloat(i) * 2) * 6 }
            if flying { kick = -4 }
            p.move(to: NSPoint(x: x, y: lift + 12)); p.line(to: NSPoint(x: x + kick, y: lift + (flying ? 6 : 1)))
            if !sleeping { p.stroke() }
        }

        let base = lift + breathe + (sleeping ? -6 : 0)
        // Cola
        black.setFill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 52, y: base + 26)); tail.line(to: NSPoint(x: 34, y: base + 6))
        tail.line(to: NSPoint(x: 44, y: base + 4)); tail.line(to: NSPoint(x: 60, y: base + 18)); tail.close(); tail.fill()
        // Cuerpo
        NSBezierPath(ovalIn: NSRect(x: 48, y: base + 10, width: 42, height: 40)).fill()
        // Alas al volar
        if flying || dragged {
            let flap = sin(t / (flying ? 2 : 3)) * 14
            let wing = NSBezierPath()
            wing.move(to: NSPoint(x: 62, y: base + 38))
            wing.curve(to: NSPoint(x: 50, y: base + 40 + flap), controlPoint1: NSPoint(x: 56, y: base + 52 + flap), controlPoint2: NSPoint(x: 46, y: base + 48 + flap))
            wing.line(to: NSPoint(x: 70, y: base + 34)); wing.close()
            NSColor(calibratedWhite: 0.2, alpha: 1).setFill(); wing.fill()
        }
        // Pechera
        bib.setFill()
        NSBezierPath(ovalIn: NSRect(x: 70, y: base + 26, width: 18, height: 22)).fill()
        // Cabeza (al trabajar picotea; al dormir la esconde)
        let peck = working ? max(0, sin(t / 3)) * 6 : 0
        let head = NSRect(x: 64, y: base + 38 - peck - (sleeping ? 8 : 0), width: 26, height: 24)
        black.setFill()
        NSBezierPath(ovalIn: head).fill()
        // Pico grande
        let open: CGFloat = dragged || reminding ? 4 : 0
        let bx = head.maxX - 4, by = head.midY - 2
        let upper = NSBezierPath()
        upper.move(to: NSPoint(x: bx, y: by + 9))
        upper.curve(to: NSPoint(x: bx + 38, y: by - 2 + open), controlPoint1: NSPoint(x: bx + 20, y: by + 14), controlPoint2: NSPoint(x: bx + 34, y: by + 8))
        upper.curve(to: NSPoint(x: bx, y: by - 1), controlPoint1: NSPoint(x: bx + 28, y: by - 1 + open), controlPoint2: NSPoint(x: bx + 10, y: by - 2))
        upper.close()
        NSGraphicsContext.saveGraphicsState()
        upper.addClip()
        beakTop.setFill(); NSRect(x: bx, y: by + 5, width: 40, height: 12).fill()
        beakMid.setFill(); NSRect(x: bx, y: by - 4, width: 40, height: 9).fill()
        beakTip.setFill(); NSRect(x: bx + 31, y: by - 4, width: 10, height: 20).fill()
        NSGraphicsContext.restoreGraphicsState()
        let lower = NSBezierPath()
        lower.move(to: NSPoint(x: bx, y: by - 1 - open))
        lower.curve(to: NSPoint(x: bx + 30, y: by - 3 - open), controlPoint1: NSPoint(x: bx + 12, y: by - 6 - open), controlPoint2: NSPoint(x: bx + 24, y: by - 6 - open))
        lower.line(to: NSPoint(x: bx, y: by - 5 - open)); lower.close()
        beakMid.setFill(); lower.fill()
        // Ojo
        let eye = NSPoint(x: head.midX + 3, y: head.midY + 3)
        eyeRing.setFill()
        NSBezierPath(ovalIn: NSRect(x: eye.x - 5, y: eye.y - 5, width: 10, height: 10)).fill()
        NSColor.black.setFill(); NSColor.black.setStroke()
        let blink = frameIndex % 140 < 4
        if sleeping || blink {
            let p = NSBezierPath(); p.lineWidth = 1.5
            p.move(to: NSPoint(x: eye.x - 3, y: eye.y)); p.line(to: NSPoint(x: eye.x + 3, y: eye.y)); p.stroke()
        } else if frameIndex < dizzyUntil {
            let p = NSBezierPath(); p.lineWidth = 1.3
            p.move(to: NSPoint(x: eye.x - 2.5, y: eye.y - 2.5)); p.line(to: NSPoint(x: eye.x + 2.5, y: eye.y + 2.5))
            p.move(to: NSPoint(x: eye.x - 2.5, y: eye.y + 2.5)); p.line(to: NSPoint(x: eye.x + 2.5, y: eye.y - 2.5)); p.stroke()
        } else {
            NSBezierPath(ovalIn: NSRect(x: eye.x - 2, y: eye.y - 2, width: 4, height: 4)).fill()
        }
        // Computadorita al trabajar
        if working {
            NSColor(calibratedWhite: 0.75, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 96, y: 1, width: 30, height: 3), xRadius: 1, yRadius: 1).fill()
            let screenPath = NSBezierPath()
            screenPath.move(to: NSPoint(x: 120, y: 4)); screenPath.line(to: NSPoint(x: 126, y: 22))
            screenPath.line(to: NSPoint(x: 130, y: 22)); screenPath.line(to: NSPoint(x: 124, y: 4)); screenPath.close()
            NSColor(calibratedWhite: 0.55, alpha: 1).setFill(); screenPath.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Textos sin reflejar
        if sleeping {
            let phase = (frameIndex / 30) % 3
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            let x: CGFloat = direction > 0 ? 70 : 64
            for i in 0...phase {
                ("z" as NSString).draw(at: NSPoint(x: x + CGFloat(i) * 6, y: 46 + CGFloat(i) * 7), withAttributes: attrs)
            }
        }
        if hearts > 0 {
            hearts -= 1
            let rise = CGFloat(45 - hearts)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14),
                                                        .foregroundColor: NSColor.systemPink.withAlphaComponent(CGFloat(hearts) / 45)]
            ("♥" as NSString).draw(at: NSPoint(x: 70, y: 62 + rise * 0.6), withAttributes: attrs)
        }
        if reminding { bubble("¡Pausa! Párate un rato.\nTócame si ya.") }
    }

    private func bubble(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: NSColor.black]
        let s = text as NSString
        let size = s.boundingRect(with: NSSize(width: 130, height: 60), options: .usesLineFragmentOrigin, attributes: attrs).size
        let rect = NSRect(x: (bounds.width - size.width) / 2 - 7, y: 76, width: size.width + 14, height: size.height + 8)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).stroke()
        s.draw(in: rect.insetBy(dx: 7, dy: 4), withAttributes: attrs)
    }
}
