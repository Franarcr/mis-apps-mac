import AppKit
import PDFKit
import UniformTypeIdentifiers

/// La pizarra infinita: dibuja el tablero y atiende el ratón, el trackpad y el teclado.
final class CanvasView: NSView, NSTextViewDelegate, NSMenuItemValidation {
    unowned let document: BoardDocument
    let state: CanvasState
    let imageCache = ImageCache()

    /// Punto del tablero que está en la esquina superior izquierda de la vista.
    var origin = CGPoint.zero { didSet { needsDisplay = true } }
    var scale: CGFloat = 1 { didSet { state.zoom = scale; needsDisplay = true } }
    var selection: Set<UUID> = [] { didSet { state.selectionCount = selection.count; needsDisplay = true } }

    private enum Drag {
        case pan(last: CGPoint)
        case move(start: CGPoint, original: [UUID: Item])
        case resize(id: UUID, original: Item, anchor: CGPoint)
        case marquee(start: CGPoint, current: CGPoint, base: Set<UUID>)
        case create(id: UUID, start: CGPoint, name: String)
        case pen(id: UUID, points: [CGPoint])
        case connector(id: UUID)
        case endpoint(id: UUID, isStart: Bool)
    }

    private var drag: Drag?
    private var editor: NSTextView?
    private var editingID: UUID?
    private var editName = "Editar texto"
    private var spaceDown = false
    private var didSetInitialView = false
    private var mouseInView: CGPoint?
    private var hoverTarget: UUID?

    init(document: BoardDocument, state: CanvasState) {
        self.document = document
        self.state = state
        super.init(frame: .zero)
        state.canvas = self
        document.canvas = self
        registerForDraggedTypes([.fileURL, .png, .tiff, NSPasteboard.PasteboardType("public.jpeg")])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Datos

    var items: [Item] { document.board.items }
    var lookup: [UUID: Item] { Renderer.lookup(items) }
    func index(of id: UUID) -> Int? { document.board.items.firstIndex { $0.id == id } }
    func item(_ id: UUID) -> Item? { index(of: id).map { document.board.items[$0] } }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        if let i = index(of: id) { change(&document.board.items[i]) }
    }

    func pruneSelection() {
        let ids = Set(items.map(\.id))
        selection = selection.intersection(ids)
    }

    func refreshUndoState() {
        state.canUndo = document.undoManager?.canUndo ?? false
        state.canRedo = document.undoManager?.canRedo ?? false
    }

    // MARK: - Coordenadas

    func toBoard(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / scale + origin.x, y: p.y / scale + origin.y) }
    func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) * scale, y: (p.y - origin.y) * scale) }
    func toView(_ r: CGRect) -> CGRect {
        CGRect(origin: toView(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale))
    }
    var visibleBoardRect: CGRect {
        CGRect(origin: origin, size: CGSize(width: bounds.width / scale, height: bounds.height / scale))
    }
    var viewCenter: CGPoint {
        CGPoint(x: origin.x + bounds.width / 2 / scale, y: origin.y + bounds.height / 2 / scale)
    }
    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    func center(on p: CGPoint) {
        origin = CGPoint(x: p.x - bounds.width / 2 / scale, y: p.y - bounds.height / 2 / scale)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldCenter = didSetInitialView ? viewCenter : nil
        super.setFrameSize(newSize)
        if let c = oldCenter {
            center(on: c)
        } else if newSize.width > 10, newSize.height > 10 {
            didSetInitialView = true
            if let c = document.board.viewCenter, let s = document.board.viewScale {
                scale = clampScale(s)
                center(on: c)
            } else if !items.isEmpty {
                fit(items)
            } else {
                center(on: .zero)
            }
        }
    }

    // MARK: - Zoom

    private func clampScale(_ s: CGFloat) -> CGFloat { min(8, max(0.0005, s)) }

    func zoom(by factor: CGFloat, at v: CGPoint) {
        endEditing()
        let p = toBoard(v)
        scale = clampScale(scale * factor)
        origin = CGPoint(x: p.x - v.x / scale, y: p.y - v.y / scale)
    }

    func setZoom(_ s: CGFloat) {
        endEditing()
        let c = viewCenter
        scale = clampScale(s)
        center(on: c)
    }

    func fit(_ list: [Item]) {
        guard let r = Renderer.bounds(of: list, lookup: lookup, scale: scale), bounds.width > 0 else { return }
        let s = min((bounds.width - 140) / max(r.width, 1), (bounds.height - 120) / max(r.height, 1), 2)
        scale = clampScale(s)
        center(on: CGPoint(x: r.midX, y: r.midY))
    }

    @objc func zoomIn(_ sender: Any?) { zoom(by: 1.25, at: CGPoint(x: bounds.midX, y: bounds.midY)) }
    @objc func zoomOut(_ sender: Any?) { zoom(by: 0.8, at: CGPoint(x: bounds.midX, y: bounds.midY)) }
    @objc func zoomActual(_ sender: Any?) { setZoom(1) }
    @objc func zoomFit(_ sender: Any?) {
        endEditing()
        if items.isEmpty { scale = 1; center(on: .zero) } else { fit(selection.isEmpty ? items : selectedItems) }
    }

    override func scrollWheel(with e: NSEvent) {
        endEditing()
        let v = point(e)
        if e.modifierFlags.contains(.command) || (!e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.shift)) {
            let dy = e.scrollingDeltaY
            let factor = e.hasPreciseScrollingDeltas ? exp(dy * 0.01) : pow(1.12, dy)
            zoom(by: factor, at: v)
        } else if !e.hasPreciseScrollingDeltas {
            // Ratón con Mayúsculas: desplazamiento lateral.
            origin.x -= (e.scrollingDeltaX + e.scrollingDeltaY) * 10 / scale
        } else {
            origin.x -= e.scrollingDeltaX / scale
            origin.y -= e.scrollingDeltaY / scale
        }
    }

    override func magnify(with e: NSEvent) {
        zoom(by: 1 + e.magnification, at: point(e))
    }

    // MARK: - Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor(hex: "F4F4F1").cgColor)
        ctx.fill(bounds)
        drawGrid(ctx)
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -origin.x, y: -origin.y)
        Renderer.draw(items, images: document.board.images, cache: imageCache, ctx: ctx, scale: scale,
                      visible: visibleBoardRect, hiding: editingID)
        ctx.restoreGState()
        drawSelection(ctx)
    }

    private func drawGrid(_ ctx: CGContext) {
        var step: CGFloat = 20
        while step * scale < 16 { step *= 5 }
        let r = visibleBoardRect
        let path = CGMutablePath()
        var y = floor(r.minY / step) * step
        while y <= r.maxY {
            var x = floor(r.minX / step) * step
            while x <= r.maxX {
                let v = toView(CGPoint(x: x, y: y))
                path.addRect(CGRect(x: v.x - 0.75, y: v.y - 0.75, width: 1.5, height: 1.5))
                x += step
            }
            y += step
        }
        ctx.addPath(path)
        ctx.setFillColor(NSColor(hex: "CDCEC8").cgColor)
        ctx.fillPath()
    }

    private static let blue = NSColor(hex: "2F6FEB")

    private func drawSelection(_ ctx: CGContext) {
        let lk = lookup
        let blue = Self.blue.cgColor
        if let t = hoverTarget, let it = lk[t] {
            ctx.setStrokeColor(Self.blue.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(toView(it.rect).insetBy(dx: -4, dy: -4))
        }
        ctx.setStrokeColor(blue)
        ctx.setLineWidth(1.5)
        for id in selection {
            guard let it = lk[id] else { continue }
            if it.kind == .connector {
                let (a, b) = Renderer.endpoints(it, lk)
                for p in [a, b] { drawHandle(ctx, at: toView(p), round: true) }
                continue
            }
            ctx.setStrokeColor(blue)
            ctx.setLineWidth(1.5)
            ctx.stroke(toView(it.rect).insetBy(dx: -2, dy: -2))
        }
        if selection.count == 1, let id = selection.first, let it = lk[id], it.kind != .connector {
            for c in corners(toView(it.rect)) { drawHandle(ctx, at: c, round: false) }
        }
        if case .marquee(let s, let c, _)? = drag {
            let r = Geo.rect(toView(s), toView(c))
            ctx.setFillColor(Self.blue.withAlphaComponent(0.08).cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(blue)
            ctx.setLineWidth(1)
            ctx.stroke(r)
        }
    }

    private func drawHandle(_ ctx: CGContext, at p: CGPoint, round: Bool) {
        let r = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(Self.blue.cgColor)
        ctx.setLineWidth(1.5)
        if round {
            ctx.fillEllipse(in: r)
            ctx.strokeEllipse(in: r)
        } else {
            ctx.fill(r)
            ctx.stroke(r)
        }
    }

    /// Esquinas: arriba izquierda, arriba derecha, abajo derecha, abajo izquierda.
    private func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    // MARK: - Qué hay bajo el puntero

    /// Los marcos se agarran por el título o el borde; por dentro el clic pasa al tablero
    /// (para dibujar flechas o seleccionar con un recuadro), salvo que el marco ya esté seleccionado.
    func itemAt(_ p: CGPoint, excluding: Set<UUID> = [], onlyTargets: Bool = false, wholeFrames: Bool = false) -> Item? {
        let tol = 6 / scale
        let lk = lookup
        for item in Renderer.ordered(items).reversed() where !excluding.contains(item.id) {
            switch item.kind {
            case .connector:
                if onlyTargets { continue }
                let (a, b) = Renderer.endpoints(item, lk)
                if Geo.distance(p, a, b) <= tol + item.lineWidth / 2 { return item }
            case .pen:
                if onlyTargets { continue }
                let pts = Renderer.penPoints(item)
                guard item.rect.insetBy(dx: -tol - item.lineWidth, dy: -tol - item.lineWidth).contains(p) else { continue }
                if pts.count == 1, Geo.distance(p, pts[0], pts[0]) <= tol + item.lineWidth { return item }
                for i in pts.indices.dropFirst() where Geo.distance(p, pts[i - 1], pts[i]) <= tol + item.lineWidth / 2 {
                    return item
                }
            case .frame:
                guard Renderer.bounds(item, lk, scale: scale).insetBy(dx: -tol, dy: -tol).contains(p) else { continue }
                let inside = item.rect.insetBy(dx: tol, dy: tol).contains(p)
                if inside && (onlyTargets || (!wholeFrames && !selection.contains(item.id))) { continue }
                return item
            default:
                if item.rect.insetBy(dx: -tol, dy: -tol).contains(p) { return item }
            }
        }
        return nil
    }

    private func cornerHandle(at v: CGPoint, of r: CGRect) -> Int? {
        corners(toView(r)).firstIndex { abs($0.x - v.x) <= 7 && abs($0.y - v.y) <= 7 }
    }

    private var selectedItems: [Item] { items.filter { selection.contains($0.id) } }

    /// La selección más lo que está dentro de los marcos seleccionados.
    private func expanded(_ ids: Set<UUID>) -> Set<UUID> {
        var result = ids
        for frame in items where frame.kind == .frame && ids.contains(frame.id) {
            for it in items where it.kind != .connector && it.id != frame.id && frame.rect.contains(it.rect) {
                result.insert(it.id)
            }
        }
        return result
    }

    // MARK: - Herramientas

    func selectTool(_ tool: Tool) {
        endEditing()
        if tool == .image {
            insertImage(nil)
            return
        }
        state.tool = tool
        if tool != .select { selection = [] }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        if spaceDown || state.tool == .hand {
            cursor = .openHand
        } else if state.tool == .select {
            cursor = .arrow
        } else if state.tool == .text {
            cursor = .iBeam
        } else {
            cursor = .crosshair
        }
        addCursorRect(visibleRect, cursor: cursor)
    }

    // MARK: - Ratón

    override func mouseMoved(with e: NSEvent) { mouseInView = point(e) }
    override func mouseExited(with e: NSEvent) { mouseInView = nil }

    override func mouseDown(with e: NSEvent) {
        endEditing()
        window?.makeFirstResponder(self)
        let v = point(e), p = toBoard(v)
        mouseInView = v
        if spaceDown || state.tool == .hand || e.buttonNumber == 2 {
            drag = .pan(last: v)
            NSCursor.closedHand.set()
            return
        }
        switch state.tool {
        case .select, .hand, .image:
            selectDown(e, v, p)
        case .note:
            var it = Item(kind: .note)
            it.rect = CGRect(x: p.x - 90, y: p.y - 90, width: 180, height: 180)
            it.color = state.noteColor
            it.fontSize = 18
            insertAndEdit(it, "Añadir nota")
        case .text:
            var it = Item(kind: .text)
            it.color = "1F2329"
            it.fontSize = 18
            it.rect = CGRect(x: p.x, y: p.y - 16, width: 280, height: Renderer.textHeight("", size: 18, width: 270) + 8)
            insertAndEdit(it, "Añadir texto")
        case .comment:
            var it = Item(kind: .comment)
            it.color = "D7C4FF"
            it.fontSize = 14
            it.rect = CGRect(x: p.x, y: p.y - 80, width: 240, height: 70)
            insertAndEdit(it, "Añadir comentario")
        case .shape:
            var it = Item(kind: .shape)
            it.shape = state.shapeKind
            it.color = state.shapeColor
            it.rect = CGRect(origin: p, size: .zero)
            startCreating(it, p, "Añadir figura")
        case .frame:
            var it = Item(kind: .frame)
            it.color = "FFFFFF"
            it.text = "Marco \(items.filter { $0.kind == .frame }.count + 1)"
            it.rect = CGRect(origin: p, size: .zero)
            startCreating(it, p, "Añadir marco")
        case .pen:
            var it = Item(kind: .pen)
            it.color = state.penColor
            it.lineWidth = state.penWidth
            Self.setPen(&it, [p])
            document.begin()
            document.board.items.append(it)
            drag = .pen(id: it.id, points: [p])
        case .connector:
            var it = Item(kind: .connector)
            it.color = "1F2329"
            it.lineWidth = 2
            let from = itemAt(p, onlyTargets: true)
            it.from = from?.id
            it.start = from == nil ? p : nil
            it.end = p
            document.begin()
            document.board.items.append(it)
            drag = .connector(id: it.id)
        }
        needsDisplay = true
    }

    private func startCreating(_ it: Item, _ p: CGPoint, _ name: String) {
        document.begin()
        document.board.items.append(it)
        drag = .create(id: it.id, start: p, name: name)
    }

    private func insertAndEdit(_ it: Item, _ name: String) {
        document.begin()
        document.board.items.append(it)
        state.tool = .select
        window?.invalidateCursorRects(for: self)
        selection = [it.id]
        beginEditing(it.id, name: name)
    }

    private func selectDown(_ e: NSEvent, _ v: CGPoint, _ p: CGPoint) {
        let shift = e.modifierFlags.contains(.shift)
        if selection.count == 1, let id = selection.first, let it = item(id) {
            if it.kind == .connector {
                let (a, b) = Renderer.endpoints(it, lookup)
                for (i, end) in [a, b].enumerated() where hypot(toView(end).x - v.x, toView(end).y - v.y) <= 8 {
                    document.begin()
                    drag = .endpoint(id: id, isStart: i == 0)
                    return
                }
            } else if let c = cornerHandle(at: v, of: it.rect) {
                let opposite = corners(it.rect)[(c + 2) % 4]
                document.begin()
                drag = .resize(id: id, original: it, anchor: opposite)
                return
            }
        }
        if let hit = itemAt(p) {
            if e.clickCount == 2, Self.editable(hit.kind) {
                selection = [hit.id]
                beginEditing(hit.id)
                return
            }
            if shift {
                if selection.contains(hit.id) {
                    selection.remove(hit.id)
                    return
                }
                selection.insert(hit.id)
            } else if !selection.contains(hit.id) {
                selection = [hit.id]
            }
            let moving = expanded(selection)
            var original: [UUID: Item] = [:]
            for it in items where moving.contains(it.id) { original[it.id] = it }
            document.begin()
            drag = .move(start: p, original: original)
        } else {
            if e.clickCount == 2 {
                // Doble clic en el vacío: nota nueva, como acceso rápido.
                var it = Item(kind: .note)
                it.rect = CGRect(x: p.x - 90, y: p.y - 90, width: 180, height: 180)
                it.color = state.noteColor
                it.fontSize = 18
                insertAndEdit(it, "Añadir nota")
                return
            }
            let base = shift ? selection : []
            selection = base
            drag = .marquee(start: p, current: p, base: base)
        }
    }

    override func otherMouseDown(with e: NSEvent) {
        drag = .pan(last: point(e))
        NSCursor.closedHand.set()
    }
    override func otherMouseDragged(with e: NSEvent) { mouseDragged(with: e) }
    override func otherMouseUp(with e: NSEvent) { mouseUp(with: e) }

    override func mouseDragged(with e: NSEvent) {
        let v = point(e), p = toBoard(v)
        mouseInView = v
        guard let drag else { return }
        switch drag {
        case .pan(let last):
            origin.x -= (v.x - last.x) / scale
            origin.y -= (v.y - last.y) / scale
            self.drag = .pan(last: v)
        case .move(let start, let original):
            let dx = p.x - start.x, dy = p.y - start.y
            for i in document.board.items.indices {
                guard var o = original[document.board.items[i].id] else { continue }
                Self.offset(&o, dx, dy)
                document.board.items[i] = o
            }
        case .resize(let id, let original, let anchor):
            var r = Geo.rect(anchor, p)
            if original.kind == .image || e.modifierFlags.contains(.shift) {
                let ratio = original.rect.width / max(original.rect.height, 0.01)
                let w = max(r.width, r.height * ratio), h = w / ratio
                r = CGRect(x: p.x < anchor.x ? anchor.x - w : anchor.x, y: p.y < anchor.y ? anchor.y - h : anchor.y,
                           width: w, height: h)
            }
            r.size.width = max(r.width, 12)
            r.size.height = max(r.height, 12)
            update(id) { $0.rect = r }
        case .marquee(let start, _, let base):
            self.drag = .marquee(start: start, current: p, base: base)
            let r = Geo.rect(start, p)
            let lk = lookup
            var sel = base
            for it in items {
                let b = Renderer.bounds(it, lk, scale: scale)
                if it.kind == .frame ? r.contains(b) : r.intersects(b) { sel.insert(it.id) }
            }
            selection = sel
        case .create(let id, let start, _):
            var r = Geo.rect(start, p)
            if e.modifierFlags.contains(.shift) {
                let s = max(r.width, r.height)
                r = CGRect(x: p.x < start.x ? start.x - s : start.x, y: p.y < start.y ? start.y - s : start.y, width: s, height: s)
            }
            update(id) { $0.rect = r }
        case .pen(let id, var pts):
            if let last = pts.last, hypot(p.x - last.x, p.y - last.y) < 1.5 / scale { return }
            pts.append(p)
            update(id) { Self.setPen(&$0, pts) }
            self.drag = .pen(id: id, points: pts)
        case .connector(let id):
            let fromID = item(id)?.from
            let target = itemAt(p, excluding: Set([id] + (fromID.map { [$0] } ?? [])), onlyTargets: true)
            hoverTarget = target?.id
            update(id) { $0.end = p; $0.to = target?.id }
        case .endpoint(let id, let isStart):
            let other = isStart ? item(id)?.to : item(id)?.from
            let target = itemAt(p, excluding: Set([id] + (other.map { [$0] } ?? [])), onlyTargets: true)
            hoverTarget = target?.id
            update(id) {
                if isStart { $0.start = p; $0.from = target?.id } else { $0.end = p; $0.to = target?.id }
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        hoverTarget = nil
        switch drag {
        case .pan:
            window?.invalidateCursorRects(for: self)
        case .move:
            document.commit("Mover")
        case .resize:
            document.commit("Cambiar tamaño")
        case .marquee:
            break
        case .create(let id, let start, let name):
            if let it = item(id), it.rect.width < 6 / scale, it.rect.height < 6 / scale {
                let size = it.kind == .frame ? CGSize(width: 800, height: 560) : CGSize(width: 160, height: 110)
                update(id) {
                    $0.rect = CGRect(x: start.x - size.width / 2, y: start.y - size.height / 2,
                                     width: size.width, height: size.height)
                }
            }
            document.commit(name)
            state.tool = .select
            window?.invalidateCursorRects(for: self)
            selection = [id]
        case .pen:
            document.commit("Dibujar")
        case .connector(let id):
            if let it = item(id), it.to == nil {
                let (a, b) = Renderer.endpoints(it, lookup)
                if hypot(b.x - a.x, b.y - a.y) < 8 / scale {
                    document.board.items.removeAll { $0.id == id }
                }
            }
            document.commit("Añadir flecha")
            state.tool = .select
            window?.invalidateCursorRects(for: self)
            if item(id) != nil { selection = [id] }
        case .endpoint:
            document.commit("Mover flecha")
        }
        needsDisplay = true
    }

    static func offset(_ it: inout Item, _ dx: CGFloat, _ dy: CGFloat) {
        it.rect.origin.x += dx
        it.rect.origin.y += dy
        if let s = it.start { it.start = CGPoint(x: s.x + dx, y: s.y + dy) }
        if let s = it.end { it.end = CGPoint(x: s.x + dx, y: s.y + dy) }
    }

    static func setPen(_ it: inout Item, _ pts: [CGPoint]) {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        let w = max((xs.max() ?? 0) - minX, 1), h = max((ys.max() ?? 0) - minY, 1)
        it.rect = CGRect(x: minX, y: minY, width: w, height: h)
        it.points = pts.map { CGPoint(x: ($0.x - minX) / w, y: ($0.y - minY) / h) }
    }

    // MARK: - Edición de texto

    static func editable(_ kind: ItemKind) -> Bool {
        [.note, .text, .shape, .frame, .comment].contains(kind)
    }

    func beginEditing(_ id: UUID, name: String = "Editar texto") {
        guard let it = item(id), Self.editable(it.kind) else { return }
        endEditing()
        document.begin()
        editName = name
        editingID = id
        let tv = NSTextView(frame: editorFrame(for: it))
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = it.kind == .frame
        tv.backgroundColor = .white
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = false
        let pad = editorPadding(it)
        tv.textContainerInset = NSSize(width: pad.width, height: pad.height)
        var size = it.fontSize
        if it.kind == .note { size = Renderer.fittedSize(it.text, size: it.fontSize, box: it.rect.insetBy(dx: Renderer.notePadding(it.rect), dy: Renderer.notePadding(it.rect))) }
        tv.font = .systemFont(ofSize: it.kind == .frame ? 13 : size * scale, weight: it.kind == .frame ? .medium : .regular)
        tv.textColor = it.kind == .frame ? NSColor(hex: "3A3D42")
            : (it.kind == .text ? NSColor(hex: it.color) : .ink(on: it.color))
        tv.insertionPointColor = tv.textColor ?? .black
        tv.alignment = (it.kind == .note || it.kind == .shape) ? .center : .left
        tv.string = it.text
        tv.delegate = self
        addSubview(tv)
        editor = tv
        window?.makeFirstResponder(tv)
        tv.selectAll(nil)
        needsDisplay = true
    }

    private func editorPadding(_ it: Item) -> CGSize {
        switch it.kind {
        case .note: CGSize(width: Renderer.notePadding(it.rect) * scale, height: Renderer.notePadding(it.rect) * scale)
        case .shape: CGSize(width: 10 * scale, height: 10 * scale)
        case .comment: CGSize(width: 10 * scale, height: 8 * scale)
        case .text: CGSize(width: 4 * scale, height: 4 * scale)
        default: CGSize(width: 4, height: 2)
        }
    }

    private func editorFrame(for it: Item) -> CGRect {
        let r = toView(it.rect)
        if it.kind == .frame {
            return CGRect(x: r.minX - 4, y: r.minY - 22, width: max(220, min(r.width, 400)), height: 20)
        }
        return r
    }

    func textDidChange(_ notification: Notification) {
        guard let tv = editor, let id = editingID, let it = item(id), it.kind == .text else { return }
        // Los textos crecen hacia abajo mientras se escribe.
        let h = Renderer.textHeight(tv.string, size: it.fontSize, width: it.rect.width - 8) + 8
        if abs(h - it.rect.height) > 0.5 {
            update(id) { $0.rect.size.height = h }
            tv.frame = editorFrame(for: item(id) ?? it)
        }
    }

    func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(cancelOperation(_:)) {
            endEditing()
            return true
        }
        return false
    }

    func endEditing() {
        guard let tv = editor, let id = editingID else { return }
        editor = nil
        editingID = nil
        let text = tv.string
        tv.removeFromSuperview()
        if let it = item(id) {
            if it.kind == .text, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                document.board.items.removeAll { $0.id == id }
                selection.remove(id)
            } else {
                update(id) { $0.text = text }
                if it.kind == .text {
                    update(id) { $0.rect.size.height = Renderer.textHeight(text, size: it.fontSize, width: it.rect.width - 8) + 8 }
                }
            }
        }
        document.commit(editName)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - Teclado

    override func keyDown(with e: NSEvent) {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        switch e.keyCode {
        case 51, 117:
            delete(nil)
            return
        case 53:
            if selection.isEmpty { selectTool(.select) } else { selection = [] }
            return
        case 36, 76:
            if selection.count == 1, let id = selection.first { beginEditing(id) }
            return
        case 49:
            if !spaceDown {
                spaceDown = true
                window?.invalidateCursorRects(for: self)
                NSCursor.openHand.set()
            }
            return
        case 123, 124, 125, 126:
            guard !selection.isEmpty else { break }
            let step: CGFloat = flags.contains(.shift) ? 10 : 1
            let dx: CGFloat = e.keyCode == 123 ? -step : (e.keyCode == 124 ? step : 0)
            let dy: CGFloat = e.keyCode == 126 ? -step : (e.keyCode == 125 ? step : 0)
            let ids = expanded(selection)
            document.apply("Mover") { items in
                for i in items.indices where ids.contains(items[i].id) { Self.offset(&items[i], dx, dy) }
            }
            return
        default:
            break
        }
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.subtracting(.shift).isEmpty, let tool = Tool.allCases.first(where: { $0.key == chars }) {
            selectTool(tool)
            return
        }
        super.keyDown(with: e)
    }

    override func keyUp(with e: NSEvent) {
        if e.keyCode == 49 {
            spaceDown = false
            window?.invalidateCursorRects(for: self)
            return
        }
        super.keyUp(with: e)
    }

    // MARK: - Acciones de menú

    @objc func delete(_ sender: Any?) {
        let ids = expanded(selection)
        guard !ids.isEmpty else { return }
        document.apply("Eliminar") { items in
            items.removeAll { it in
                ids.contains(it.id) || (it.kind == .connector &&
                    ((it.from.map { ids.contains($0) } ?? false) || (it.to.map { ids.contains($0) } ?? false)))
            }
        }
        selection = []
    }

    override func selectAll(_ sender: Any?) {
        selectTool(.select)
        selection = Set(items.map(\.id))
    }

    @objc func copy(_ sender: Any?) {
        let ids = expanded(selection)
        guard !ids.isEmpty else { return }
        let clip = makeClip(ids)
        let pb = NSPasteboard.general
        pb.clearContents()
        if let data = try? JSONEncoder().encode(clip) { pb.setData(data, forType: Clip.pasteboardType) }
        let lk = lookup
        if let area = Renderer.bounds(of: clip.items, lookup: lk)?.insetBy(dx: -20, dy: -20),
           let png = Exporter.png(clip.items, lookup: lk, images: document.board.images, area: area, scale: 2) {
            pb.setData(png, forType: .png)
        }
    }

    @objc func cut(_ sender: Any?) {
        copy(sender)
        delete(sender)
    }

    @objc func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let at = pastePoint()
        if let data = pb.data(forType: Clip.pasteboardType), let clip = try? JSONDecoder().decode(Clip.self, from: data) {
            insertClip(clip, at: at, name: "Pegar")
        } else if pasteImages(from: pb, at: at) {
            return
        } else if let s = pb.string(forType: .string), !s.isEmpty {
            var it = Item(kind: .text)
            it.color = "1F2329"
            it.fontSize = 18
            it.text = s
            let w: CGFloat = 360
            it.rect = CGRect(x: at.x - w / 2, y: at.y, width: w, height: Renderer.textHeight(s, size: 18, width: w - 8) + 8)
            document.apply("Pegar texto") { $0.append(it) }
            selection = [it.id]
        } else {
            NSSound.beep()
        }
    }

    @objc func duplicateSelection(_ sender: Any?) {
        let ids = expanded(selection)
        guard !ids.isEmpty, let b = Renderer.bounds(of: items.filter { ids.contains($0.id) }, lookup: lookup) else { return }
        insertClip(makeClip(ids), at: CGPoint(x: b.midX + 30, y: b.midY + 30), name: "Duplicar")
    }

    @objc func bringToFront(_ sender: Any?) {
        let ids = selection
        document.apply("Traer al frente") { items in
            let moved = items.filter { ids.contains($0.id) }
            items.removeAll { ids.contains($0.id) }
            items.append(contentsOf: moved)
        }
    }

    @objc func sendToBack(_ sender: Any?) {
        let ids = selection
        document.apply("Enviar al fondo") { items in
            let moved = items.filter { ids.contains($0.id) }
            items.removeAll { ids.contains($0.id) }
            items.insert(contentsOf: moved, at: 0)
        }
    }

    @objc func setColor(_ sender: Any?) {
        guard let hex = (sender as? NSMenuItem)?.representedObject as? String else { return }
        applyColor(hex)
    }

    func applyColor(_ hex: String) {
        let ids = selection
        document.apply("Cambiar color") { items in
            for i in items.indices where ids.contains(items[i].id) && items[i].kind != .image { items[i].color = hex }
        }
        if let it = selectedItems.first {
            if it.kind == .note { state.noteColor = hex }
            if it.kind == .shape { state.shapeColor = hex }
        }
    }

    func changeFontSize(by factor: CGFloat) {
        let ids = selection
        document.apply("Tamaño de letra") { items in
            for i in items.indices where ids.contains(items[i].id) && Self.editable(items[i].kind) && items[i].kind != .frame {
                items[i].fontSize = min(200, max(6, (items[i].fontSize * factor).rounded()))
                if items[i].kind == .text {
                    items[i].rect.size.height = Renderer.textHeight(items[i].text, size: items[i].fontSize,
                                                                     width: items[i].rect.width - 8) + 8
                }
            }
        }
    }

    func setShape(_ kind: ShapeKind) {
        let ids = selection
        document.apply("Cambiar figura") { items in
            for i in items.indices where ids.contains(items[i].id) && items[i].kind == .shape { items[i].shape = kind }
        }
    }

    @objc func editText(_ sender: Any?) {
        if selection.count == 1, let id = selection.first { beginEditing(id) }
    }

    @objc func chooseTool(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let tool = Tool(rawValue: raw) else { return }
        selectTool(tool)
    }

    @objc func undoAction(_ sender: Any?) { endEditing(); document.undoManager?.undo() }
    @objc func redoAction(_ sender: Any?) { endEditing(); document.undoManager?.redo() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)), #selector(duplicateSelection(_:)),
             #selector(bringToFront(_:)), #selector(sendToBack(_:)), #selector(setColor(_:)):
            return !selection.isEmpty
        case #selector(editText(_:)):
            return selection.count == 1 && selectedItems.first.map { Self.editable($0.kind) } == true
        case #selector(exportPNG(_:)), #selector(exportPDF(_:)):
            return !items.isEmpty
        case #selector(exportFramesPDF(_:)):
            return items.contains { $0.kind == .frame }
        default:
            return true
        }
    }

    // MARK: - Menú contextual

    override func menu(for event: NSEvent) -> NSMenu? {
        endEditing()
        let v = point(event)
        mouseInView = v
        let p = toBoard(v)
        if let hit = itemAt(p, wholeFrames: true) {
            if !selection.contains(hit.id) { selection = [hit.id] }
        } else {
            selection = []
        }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "") {
            let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
            mi.target = self
            menu.addItem(mi)
        }
        if selection.isEmpty {
            add("Pegar", #selector(paste(_:)))
            add("Insertar imagen…", #selector(insertImage(_:)))
            menu.addItem(.separator())
            add("Seleccionar todo", #selector(selectAll(_:)))
            add("Ajustar a la pantalla", #selector(zoomFit(_:)))
            return menu
        }
        if selection.count == 1, let it = selectedItems.first, Self.editable(it.kind) {
            add(it.kind == .frame ? "Cambiar nombre del marco" : "Editar texto", #selector(editText(_:)))
            menu.addItem(.separator())
        }
        add("Cortar", #selector(cut(_:)))
        add("Copiar", #selector(copy(_:)))
        add("Duplicar", #selector(duplicateSelection(_:)))
        menu.addItem(.separator())
        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let colors = NSMenu()
        for sw in Palette.colors {
            let mi = NSMenuItem(title: sw.name, action: #selector(setColor(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = sw.hex
            mi.image = Self.swatch(sw.hex)
            colors.addItem(mi)
        }
        colorItem.submenu = colors
        menu.addItem(colorItem)
        add("Traer al frente", #selector(bringToFront(_:)))
        add("Enviar al fondo", #selector(sendToBack(_:)))
        menu.addItem(.separator())
        add("Exportar selección como PNG…", #selector(exportPNG(_:)))
        menu.addItem(.separator())
        add("Eliminar", #selector(delete(_:)))
        return menu
    }

    static func swatch(_ hex: String) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            NSColor(hex: hex).setFill()
            let path = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            path.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            path.stroke()
            return true
        }
    }

    // MARK: - Portapapeles e imágenes

    private func pastePoint() -> CGPoint {
        if let m = mouseInView, bounds.contains(m) { return toBoard(m) }
        return viewCenter
    }

    private func makeClip(_ ids: Set<UUID>) -> Clip {
        let lk = lookup
        var list = items.filter { ids.contains($0.id) }
        for i in list.indices where list[i].kind == .connector {
            let (a, b) = Renderer.endpoints(list[i], lk)
            list[i].start = a
            list[i].end = b
            if let f = list[i].from, !ids.contains(f) { list[i].from = nil }
            if let t = list[i].to, !ids.contains(t) { list[i].to = nil }
        }
        let used = Set(list.compactMap(\.imageID))
        return Clip(items: list, images: document.board.images.filter { used.contains($0.key) })
    }

    private func insertClip(_ clip: Clip, at p: CGPoint, name: String) {
        guard let b = Renderer.bounds(of: clip.items, lookup: Renderer.lookup(clip.items)) else { return }
        let dx = p.x - b.midX, dy = p.y - b.midY
        var map: [UUID: UUID] = [:]
        for it in clip.items { map[it.id] = UUID() }
        let fresh = clip.items.map { old -> Item in
            var it = old
            it.id = map[old.id] ?? UUID()
            it.from = old.from.flatMap { map[$0] }
            it.to = old.to.flatMap { map[$0] }
            Self.offset(&it, dx, dy)
            return it
        }
        for (k, v) in clip.images where document.board.images[k] == nil { document.board.images[k] = v }
        selectTool(.select)
        document.apply(name) { $0.append(contentsOf: fresh) }
        selection = Set(fresh.map(\.id))
    }

    /// Lee imágenes (archivos o datos) del portapapeles o de un arrastre.
    private func imageDatas(from pb: NSPasteboard) -> [Data] {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let datas = urls.filter { url in
                guard let t = UTType(filenameExtension: url.pathExtension) else { return false }
                return t.conforms(to: .image) || t.conforms(to: .pdf)
            }.compactMap { try? Data(contentsOf: $0) }
            if !datas.isEmpty { return datas }
        }
        for type in [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType("public.jpeg"), .tiff, .pdf] {
            if let d = pb.data(forType: type) { return [d] }
        }
        return []
    }

    @discardableResult
    private func pasteImages(from pb: NSPasteboard, at p: CGPoint) -> Bool {
        let datas = imageDatas(from: pb)
        guard !datas.isEmpty else { return false }
        addImages(datas, at: p)
        return true
    }

    private static func normalized(_ d: Data) -> Data? {
        let bytes = [UInt8](d.prefix(4))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) || bytes.starts(with: [0xFF, 0xD8]) || bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            return NSImage(data: d) != nil ? d : nil
        }
        guard let rep = NSBitmapImageRep(data: d) else { return NSImage(data: d) != nil ? d : nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Un PDF de varias páginas se separa en una imagen por página.
    private static func splitPDF(_ d: Data) -> [Data] {
        guard d.starts(with: [0x25, 0x50, 0x44, 0x46]), let pdf = PDFDocument(data: d), pdf.pageCount > 1 else { return [d] }
        return (0..<pdf.pageCount).compactMap { i in
            guard let page = pdf.page(at: i)?.copy() as? PDFPage else { return nil }
            let one = PDFDocument()
            one.insert(page, at: 0)
            return one.dataRepresentation()
        }
    }

    func addImages(_ datas: [Data], at p: CGPoint) {
        var placed: [(key: String, data: Data, size: CGSize)] = []
        for raw in datas.flatMap(Self.splitPDF) {
            guard let data = Self.normalized(raw), let img = NSImage(data: data), img.size.width > 0 else { continue }
            var size = img.size
            let longest = max(size.width, size.height)
            if longest > 800 { size = CGSize(width: size.width * 800 / longest, height: size.height * 800 / longest) }
            placed.append((UUID().uuidString, data, size))
        }
        guard !placed.isEmpty else { NSSound.beep(); return }
        // En cuadrícula de hasta 4 columnas, centrada donde se suelta.
        let cols = min(4, placed.count), gap: CGFloat = 40
        let cellW = placed.map(\.size.width).max() ?? 0, cellH = placed.map(\.size.height).max() ?? 0
        let rows = (placed.count + cols - 1) / cols
        let totalW = CGFloat(cols) * cellW + CGFloat(cols - 1) * gap
        let totalH = CGFloat(rows) * cellH + CGFloat(rows - 1) * gap
        var fresh: [Item] = []
        for (i, entry) in placed.enumerated() {
            document.board.images[entry.key] = entry.data
            var it = Item(kind: .image)
            it.imageID = entry.key
            let x = p.x - totalW / 2 + CGFloat(i % cols) * (cellW + gap)
            let y = p.y - totalH / 2 + CGFloat(i / cols) * (cellH + gap)
            it.rect = CGRect(x: x, y: y, width: entry.size.width, height: entry.size.height)
            fresh.append(it)
        }
        selectTool(.select)
        document.apply("Insertar imagen") { $0.append(contentsOf: fresh) }
        selection = Set(fresh.map(\.id))
    }

    @objc func insertImage(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Elige las imágenes para el tablero"
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let self else { return }
            self.addImages(panel.urls.compactMap { try? Data(contentsOf: $0) }, at: self.viewCenter)
        }
    }

    private func miroHTML(in pb: NSPasteboard) -> String? {
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let html = urls.first(where: { ["html", "htm"].contains($0.pathExtension.lowercased()) }) else { return nil }
        return MiroLink.boardID(fromFile: html)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if miroHTML(in: sender.draggingPasteboard) != nil { return .copy }
        return imageDatas(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let id = miroHTML(in: sender.draggingPasteboard) {
            MainActor.assumeIsolated { MiroImportWindow.shared.show(link: "https://miro.com/app/board/\(id)/") }
            return true
        }
        return pasteImages(from: sender.draggingPasteboard, at: toBoard(convert(sender.draggingLocation, from: nil)))
    }

    // MARK: - Exportar

    private var exportItems: [Item] {
        if selection.isEmpty { return items }
        let ids = expanded(selection)
        return items.filter { ids.contains($0.id) }
    }

    private var baseName: String {
        document.displayName.replacingOccurrences(of: ".lienzo", with: "")
    }

    @objc func exportPNG(_ sender: Any?) {
        endEditing()
        let list = exportItems
        let lk = lookup
        guard let window, let area = Renderer.bounds(of: list, lookup: lk)?.insetBy(dx: -40, dy: -40) else { NSSound.beep(); return }
        let images = document.board.images
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = baseName + ".png"
        panel.message = selection.isEmpty ? "Se exporta todo el tablero" : "Se exporta la selección"
        panel.beginSheetModal(for: window) { r in
            guard r == .OK, let url = panel.url else { return }
            guard let data = Exporter.png(list, lookup: lk, images: images, area: area, scale: 2) else { return }
            do { try data.write(to: url) } catch { NSAlert(error: error).runModal() }
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        endEditing()
        let list = exportItems
        let lk = lookup
        guard let area = Renderer.bounds(of: list, lookup: lk)?.insetBy(dx: -40, dy: -40) else { NSSound.beep(); return }
        savePDF(list, lk, pages: [area], suffix: "", message: selection.isEmpty ? "Se exporta todo el tablero" : "Se exporta la selección")
    }

    /// Una página por marco, en el orden en que se crearon.
    @objc func exportFramesPDF(_ sender: Any?) {
        endEditing()
        let frames = items.filter { $0.kind == .frame }
        guard !frames.isEmpty else { NSSound.beep(); return }
        savePDF(items, lookup, pages: frames.map(\.rect), suffix: " (marcos)", message: "Una página por cada marco")
    }

    private func savePDF(_ list: [Item], _ lk: [UUID: Item], pages: [CGRect], suffix: String, message: String) {
        guard let window else { return }
        let images = document.board.images
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = baseName + suffix + ".pdf"
        panel.message = message
        panel.beginSheetModal(for: window) { r in
            guard r == .OK, let url = panel.url else { return }
            guard let data = Exporter.pdf(list, lookup: lk, images: images, pages: pages) else { return }
            do { try data.write(to: url) } catch { NSAlert(error: error).runModal() }
        }
    }
}

