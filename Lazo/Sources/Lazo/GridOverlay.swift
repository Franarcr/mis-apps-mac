import AppKit

/// Como en Lasso: con el ratón sobre una ventana se pulsa el atajo y aparece la cuadrícula de cada
/// monitor encima de la pantalla real. Clic o arrastre sobre las celdas coloca la ventana; Esc cancela.
@MainActor
final class GridOverlay {
    private static var current: GridOverlay?

    private var panels: [NSPanel] = []
    private let window: AXUIElement

    static func show(model: AppModel) {
        guard WindowControl.isTrusted else { return WindowControl.requestAccess() }
        current?.close()
        guard let window = Layout.targetWindow(), let frame = WindowControl.frame(of: window) else {
            Log.write("Cuadrícula: no hay ninguna ventana bajo el ratón ni activa")
            return NSSound.beep()
        }
        let name = WindowControl.appName(of: window) ?? "Ventana"
        Log.write("Cuadrícula sobre la pantalla para \(name)")
        current = GridOverlay(window: window, frame: frame, title: name, model: model)
    }

    private init(window: AXUIElement, frame: CGRect, title: String, model: AppModel) {
        self.window = window
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let vf = screen.visibleFrame
            let panel = GridPanel(frame: vf)
            let grid = model.grid(for: screen)
            // La ventana actual, en coordenadas de esta pantalla (si está en ella).
            let current = frame.intersects(vf) ? frame.offsetBy(dx: -vf.minX, dy: -vf.minY) : nil
            let view = GridView(frame: NSRect(origin: .zero, size: vf.size), columns: grid.columns, rows: grid.rows,
                                title: title, screenName: screen.localizedName, windowRect: current)
            view.onFinish = { [weak self] selection in self?.finish(selection, on: screen, model: model) }
            panel.contentView = view
            panel.orderFrontRegardless()
            if NSMouseInRect(mouse, screen.frame, false) {
                panel.makeKey()
                panel.makeFirstResponder(view)
            }
            panels.append(panel)
        }
    }

    private func finish(_ selection: NSRect?, on screen: NSScreen, model: AppModel) {
        close()
        guard let selection else { return }
        let rect = selection.offsetBy(dx: screen.visibleFrame.minX, dy: screen.visibleFrame.minY)
        Layout.place(window, in: rect, of: screen)
        WindowControl.raise(window)
        model.targetFrame = WindowControl.frame(of: window)
    }

    private func close() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        if Self.current === self { Self.current = nil }
    }
}

/// Panel que recibe teclado y ratón sin activar la app (así la ventana de destino sigue delante).
private final class GridPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

private final class GridView: NSView {
    let columns: Int
    let rows: Int
    let title: String
    let screenName: String
    let windowRect: NSRect?
    var onFinish: ((NSRect?) -> Void)?

    private var anchor: (col: Int, row: Int)?
    private var hover: (col: Int, row: Int)?

    init(frame: NSRect, columns: Int, rows: Int, title: String, screenName: String, windowRect: NSRect?) {
        self.columns = columns
        self.rows = rows
        self.title = title
        self.screenName = screenName
        self.windowRect = windowRect
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var cellSize: CGSize { CGSize(width: bounds.width / CGFloat(columns), height: bounds.height / CGFloat(rows)) }

    /// Celda bajo el ratón; las filas se cuentan desde abajo (coordenadas de AppKit).
    private func cell(at event: NSEvent) -> (col: Int, row: Int) {
        let p = convert(event.locationInWindow, from: nil)
        return (min(max(Int(p.x / cellSize.width), 0), columns - 1), min(max(Int(p.y / cellSize.height), 0), rows - 1))
    }

    private func selection(from a: (col: Int, row: Int), to b: (col: Int, row: Int)) -> NSRect {
        let c0 = min(a.col, b.col), c1 = max(a.col, b.col), r0 = min(a.row, b.row), r1 = max(a.row, b.row)
        return NSRect(x: CGFloat(c0) * cellSize.width, y: CGFloat(r0) * cellSize.height,
                      width: CGFloat(c1 - c0 + 1) * cellSize.width, height: CGFloat(r1 - r0 + 1) * cellSize.height)
    }

    override func mouseMoved(with event: NSEvent) { hover = cell(at: event); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { if anchor == nil { hover = nil; needsDisplay = true } }
    override func mouseDown(with event: NSEvent) { anchor = cell(at: event); hover = anchor; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { hover = cell(at: event); needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        guard let anchor else { return }
        onFinish?(selection(from: anchor, to: cell(at: event)))
    }

    override func rightMouseDown(with event: NSEvent) { onFinish?(nil) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) } // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        let accent = NSColor.controlAccentColor
        let chosen = anchor.flatMap { a in hover.map { selection(from: a, to: $0) } } ?? hover.map { selection(from: $0, to: $0) }

        for col in 0 ..< columns {
            for row in 0 ..< rows {
                let rect = NSRect(x: CGFloat(col) * cellSize.width, y: CGFloat(row) * cellSize.height,
                                  width: cellSize.width, height: cellSize.height).insetBy(dx: 6, dy: 6)
                let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
                let inside = chosen.map { $0.intersects(rect) } ?? false
                (inside ? accent.withAlphaComponent(0.45) : NSColor.white.withAlphaComponent(0.07)).setFill()
                path.fill()
                (inside ? accent : NSColor.white.withAlphaComponent(0.3)).setStroke()
                path.lineWidth = inside ? 3 : 1.5
                path.stroke()
            }
        }

        // La ventana actual, con línea discontinua.
        if let windowRect {
            let path = NSBezierPath(roundedRect: windowRect.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
            path.setLineDash([10, 6], count: 2, phase: 0)
            path.lineWidth = 2
            NSColor.white.withAlphaComponent(0.8).setStroke()
            path.stroke()
        }

        let text = "\(title) · \(screenName) — clic o arrastra sobre las celdas · Esc para cancelar"
        let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                                                                  .foregroundColor: NSColor.white])
        let size = label.size()
        let box = NSRect(x: bounds.midX - size.width / 2 - 16, y: bounds.maxY - size.height - 40,
                         width: size.width + 32, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        label.draw(at: NSPoint(x: box.minX + 16, y: box.minY + 8))
    }
}
