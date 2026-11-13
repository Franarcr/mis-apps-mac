import AppKit

/// Imágenes ya decodificadas, para no leerlas en cada dibujo.
final class ImageCache {
    private var cache: [String: NSImage] = [:]
    func image(_ id: String, in images: [String: Data]) -> NSImage? {
        if let img = cache[id] { return img }
        guard let data = images[id], let img = NSImage(data: data) else { return nil }
        cache[id] = img
        return img
    }
}

/// Dibuja los elementos del tablero. Espera un contexto con el eje Y hacia abajo
/// y un NSGraphicsContext actual con `isFlipped == true`.
enum Renderer {
    static let frameTitleHeight: CGFloat = 22

    static func ordered(_ items: [Item]) -> [Item] {
        items.filter { $0.kind == .frame } + items.filter { $0.kind != .frame }
    }

    static func lookup(_ items: [Item]) -> [UUID: Item] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func endpoints(_ c: Item, _ lookup: [UUID: Item]) -> (CGPoint, CGPoint) {
        let fromItem = c.from.flatMap { lookup[$0] }
        let toItem = c.to.flatMap { lookup[$0] }
        var a = fromItem.map { CGPoint(x: $0.rect.midX, y: $0.rect.midY) } ?? c.start ?? .zero
        var b = toItem.map { CGPoint(x: $0.rect.midX, y: $0.rect.midY) } ?? c.end ?? a
        if let f = fromItem { a = Geo.boundaryPoint(f.rect, toward: b) }
        if let t = toItem { b = Geo.boundaryPoint(t.rect, toward: a) }
        return (a, b)
    }

    static func penPoints(_ item: Item) -> [CGPoint] {
        let r = item.rect
        return (item.points ?? []).map { CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height) }
    }

    /// Rectángulo que ocupa un elemento (los marcos incluyen su título).
    static func bounds(_ item: Item, _ lookup: [UUID: Item], scale: CGFloat = 1) -> CGRect {
        switch item.kind {
        case .connector:
            let (a, b) = endpoints(item, lookup)
            return Geo.rect(a, b).insetBy(dx: -item.lineWidth * 3, dy: -item.lineWidth * 3)
        case .frame:
            var r = item.rect
            let t = frameTitleHeight / scale
            r.origin.y -= t
            r.size.height += t
            return r
        case .pen:
            return item.rect.insetBy(dx: -item.lineWidth, dy: -item.lineWidth)
        case .comment:
            var r = item.rect
            r.size.height += 12
            return r
        default:
            return item.rect
        }
    }

    static func bounds(of items: [Item], lookup: [UUID: Item], scale: CGFloat = 1) -> CGRect? {
        items.reduce(nil as CGRect?) { acc, it in
            let b = bounds(it, lookup, scale: scale)
            return acc.map { $0.union(b) } ?? b
        }
    }

    static func draw(_ items: [Item], lookup: [UUID: Item]? = nil, images: [String: Data], cache: ImageCache,
                     ctx: CGContext, scale: CGFloat, visible: CGRect? = nil, hiding: UUID? = nil) {
        let lk = lookup ?? Self.lookup(items)
        // Los títulos de los marcos van encima de todos los marcos, para que un marco no tape el del vecino.
        var titles: [Item] = []
        var titlesDrawn = false
        func drawTitles() {
            guard !titlesDrawn else { return }
            titlesDrawn = true
            for f in titles { drawFrameTitle(f, scale: scale) }
        }
        for item in ordered(items) {
            if item.kind != .frame { drawTitles() }
            if let vis = visible, !bounds(item, lk, scale: scale).intersects(vis) { continue }
            let showText = item.id != hiding
            switch item.kind {
            case .frame:
                drawFrame(item, ctx: ctx, scale: scale)
                if showText { titles.append(item) }
            case .note: drawNote(item, ctx: ctx, showText: showText)
            case .text:
                if showText {
                    drawText(item.text, in: item.rect.insetBy(dx: 4, dy: 4), size: item.fontSize,
                             color: NSColor(hex: item.color), align: .left, vCenter: false)
                }
            case .shape: drawShape(item, ctx: ctx, scale: scale, showText: showText)
            case .pen: drawPen(item, ctx: ctx, scale: scale)
            case .image: drawImage(item, images: images, cache: cache, ctx: ctx)
            case .comment: drawComment(item, ctx: ctx, showText: showText)
            case .connector: drawConnector(item, lk, ctx: ctx, scale: scale)
            }
        }
        drawTitles()
    }

    // MARK: - Elementos

    private static func drawFrame(_ item: Item, ctx: CGContext, scale: CGFloat) {
        let r = item.rect
        ctx.setFillColor(NSColor(hex: item.color).cgColor)
        ctx.fill(r)
        ctx.setStrokeColor(NSColor(hex: "C9CAC4").cgColor)
        ctx.setLineWidth(1 / scale)
        ctx.stroke(r)
    }

    private static func drawFrameTitle(_ item: Item, scale: CGFloat) {
        let r = item.rect
        do {
            // El título se ve a 13 puntos en pantalla, salvo que el marco sea tan pequeño que no quepa:
            // entonces se achica con el marco, y si queda ilegible no se dibuja (como en Miro).
            let title = item.text.isEmpty ? "Marco" : item.text
            let font = { (size: CGFloat) in NSFont.systemFont(ofSize: size, weight: .medium) }
            let natural = (title as NSString).size(withAttributes: [.font: font(13 / scale)]).width
            let size = 13 / scale * min(1, r.width / max(natural, 1))
            if size * scale >= 6 {
                let para = NSMutableParagraphStyle()
                para.lineBreakMode = .byTruncatingTail
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font(size), .foregroundColor: NSColor(hex: "6B6F76"), .paragraphStyle: para,
                ]
                (title as NSString).draw(with: CGRect(x: r.minX, y: r.minY - size * 1.45, width: r.width, height: size * 1.4),
                                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            }
        }
    }

    private static func drawNote(_ item: Item, ctx: CGContext, showText: Bool) {
        let r = item.rect
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor.black.withAlphaComponent(0.18).cgColor)
        ctx.setFillColor(NSColor(hex: item.color).cgColor)
        ctx.fill(r)
        ctx.restoreGState()
        if showText, !item.text.isEmpty {
            let pad = notePadding(r)
            let box = r.insetBy(dx: pad, dy: pad)
            let size = fittedSize(item.text, size: item.fontSize, box: box)
            drawText(item.text, in: box, size: size, color: .ink(on: item.color), align: .center, vCenter: true)
        }
    }

    /// Margen interior de una nota: 12 en notas normales, menos en las pequeñas.
    static func notePadding(_ r: CGRect) -> CGFloat {
        min(12, min(r.width, r.height) * 0.07)
    }

    static func shapePath(_ kind: ShapeKind, _ r: CGRect) -> CGPath {
        switch kind {
        case .rectangle: return CGPath(rect: r, transform: nil)
        case .rounded:
            let c = min(18, r.width / 4, r.height / 4)
            return CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil)
        case .ellipse: return CGPath(ellipseIn: r, transform: nil)
        case .diamond:
            let p = CGMutablePath()
            p.addLines(between: [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
                                 CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)])
            p.closeSubpath()
            return p
        case .triangle:
            let p = CGMutablePath()
            p.addLines(between: [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY),
                                 CGPoint(x: r.minX, y: r.maxY)])
            p.closeSubpath()
            return p
        }
    }

    private static func drawShape(_ item: Item, ctx: CGContext, scale: CGFloat, showText: Bool) {
        let path = shapePath(item.shape ?? .rectangle, item.rect)
        let noFill = item.color == "none"
        let fill = noFill ? NSColor(hex: "9A9CA0") : NSColor(hex: item.color)
        if !noFill {
            ctx.addPath(path)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }
        ctx.addPath(path)
        ctx.setStrokeColor((noFill ? fill : (fill.blended(withFraction: 0.5, of: .black) ?? .black)).cgColor)
        ctx.setLineWidth(max(item.lineWidth, 1 / scale))
        ctx.setLineJoin(.round)
        ctx.strokePath()
        if showText, !item.text.isEmpty {
            var box = item.rect.insetBy(dx: 10, dy: 10)
            if item.shape == .diamond || item.shape == .triangle {
                box = item.rect.insetBy(dx: item.rect.width * 0.22, dy: item.rect.height * 0.22)
                if item.shape == .triangle { box.origin.y += item.rect.height * 0.12 }
            }
            let size = fittedSize(item.text, size: item.fontSize, box: box)
            drawText(item.text, in: box, size: size, color: noFill ? NSColor(hex: "1F2329") : .ink(on: item.color), align: .center, vCenter: true)
        }
    }

    private static func drawPen(_ item: Item, ctx: CGContext, scale: CGFloat) {
        let pts = penPoints(item)
        guard let first = pts.first else { return }
        ctx.setStrokeColor(NSColor(hex: item.color).cgColor)
        ctx.setLineWidth(max(item.lineWidth, 1 / scale))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if pts.count == 1 {
            let w = item.lineWidth
            ctx.setFillColor(NSColor(hex: item.color).cgColor)
            ctx.fillEllipse(in: CGRect(x: first.x - w / 2, y: first.y - w / 2, width: w, height: w))
            return
        }
        ctx.beginPath()
        ctx.move(to: first)
        for i in 1..<pts.count {
            // Curvas suaves por los puntos medios.
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            ctx.addQuadCurve(to: mid, control: pts[i - 1])
        }
        ctx.addLine(to: pts[pts.count - 1])
        ctx.strokePath()
    }

    private static func drawImage(_ item: Item, images: [String: Data], cache: ImageCache, ctx: CGContext) {
        if let id = item.imageID, let img = cache.image(id, in: images) {
            img.draw(in: item.rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            ctx.setFillColor(NSColor(hex: "E4E4E0").cgColor)
            ctx.fill(item.rect)
        }
    }

    private static func drawComment(_ item: Item, ctx: CGContext, showText: Bool) {
        let r = item.rect
        let path = CGMutablePath()
        path.addRoundedRect(in: r, cornerWidth: 10, cornerHeight: 10)
        path.move(to: CGPoint(x: r.minX + 14, y: r.maxY - 1))
        path.addLine(to: CGPoint(x: r.minX + 10, y: r.maxY + 12))
        path.addLine(to: CGPoint(x: r.minX + 30, y: r.maxY - 1))
        path.closeSubpath()
        let fill = NSColor(hex: item.color)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: NSColor.black.withAlphaComponent(0.15).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        if showText {
            let text = item.text.isEmpty ? "Comentario" : item.text
            drawText(text, in: r.insetBy(dx: 10, dy: 8), size: item.fontSize, color: .ink(on: item.color),
                     align: .left, vCenter: false)
        }
    }

    private static func drawConnector(_ item: Item, _ lk: [UUID: Item], ctx: CGContext, scale: CGFloat) {
        let (a, b) = endpoints(item, lk)
        let color = NSColor(hex: item.color).cgColor
        let lw = max(item.lineWidth, 1.5 / scale)
        let len = hypot(b.x - a.x, b.y - a.y)
        // Punta según el grosor; visible al alejarse, pero nunca más del 20 % del largo de la flecha.
        let head = max(8 + lw * 2.5, min(10 / scale, len * 0.2))
        let angle = atan2(b.y - a.y, b.x - a.x)
        let headEnd = item.arrowEnd ?? true, headStart = item.arrowStart ?? false
        // La línea termina en la base de la punta para que no asome por delante.
        let stop = headEnd && len > head ? CGPoint(x: b.x - cos(angle) * head * 0.8, y: b.y - sin(angle) * head * 0.8) : b
        let begin = headStart && len > head ? CGPoint(x: a.x + cos(angle) * head * 0.8, y: a.y + sin(angle) * head * 0.8) : a
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: begin)
        ctx.addLine(to: stop)
        ctx.strokePath()
        guard len > 1 else { return }
        ctx.setFillColor(color)
        func arrowHead(at tip: CGPoint, angle: CGFloat) {
            ctx.beginPath()
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: tip.x - head * cos(angle - 0.42), y: tip.y - head * sin(angle - 0.42)))
            ctx.addLine(to: CGPoint(x: tip.x - head * cos(angle + 0.42), y: tip.y - head * sin(angle + 0.42)))
            ctx.closePath()
            ctx.fillPath()
        }
        if headEnd { arrowHead(at: b, angle: angle) }
        if headStart { arrowHead(at: a, angle: angle + .pi) }
    }

    // MARK: - Texto

    static func attributed(_ text: String, size: CGFloat, color: NSColor, align: NSTextAlignment) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: color,
            .paragraphStyle: para,
        ])
    }

    static func textHeight(_ text: String, size: CGFloat, width: CGFloat) -> CGFloat {
        let s = attributed(text.isEmpty ? " " : text, size: size, color: .black, align: .left)
        return ceil(s.boundingRect(with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    /// Reduce la letra hasta que el texto quepa en la caja.
    static func fittedSize(_ text: String, size: CGFloat, box: CGRect) -> CGFloat {
        var s = size
        while s > 1, textHeight(text, size: s, width: box.width) > box.height { s *= 0.9 }
        return s
    }

    static func drawText(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor, align: NSTextAlignment, vCenter: Bool) {
        guard !text.isEmpty, rect.width > 0 else { return }
        let s = attributed(text, size: size, color: color, align: align)
        var r = rect
        if vCenter {
            let h = textHeight(text, size: size, width: rect.width)
            if h < rect.height {
                r.origin.y += (rect.height - h) / 2
                r.size.height = h + 1
            }
        }
        s.draw(with: r, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
    }
}

/// Exporta partes del tablero como PNG o PDF.
enum Exporter {
    static func png(_ items: [Item], lookup: [UUID: Item], images: [String: Data], area: CGRect,
                    scale wanted: CGFloat, background: NSColor? = .white) -> Data? {
        var scale = wanted
        let longest = max(area.width, area.height) * scale
        if longest > 12000 { scale *= 12000 / longest }
        let w = max(1, Int(ceil(area.width * scale))), h = max(1, Int(ceil(area.height * scale)))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let ctx = base.cgContext
        NSGraphicsContext.saveGraphicsState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -area.minX, y: -area.minY)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        if let bg = background {
            ctx.setFillColor(bg.cgColor)
            ctx.fill(area)
        }
        Renderer.draw(items, lookup: lookup, images: images, cache: ImageCache(), ctx: ctx, scale: 1, visible: area)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Un PDF con una página por cada área.
    static func pdf(_ items: [Item], lookup: [UUID: Item], images: [String: Data], pages: [CGRect]) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }
        let cache = ImageCache()
        NSGraphicsContext.saveGraphicsState()
        for area in pages {
            var box = CGRect(origin: .zero, size: area.size)
            let info = [kCGPDFContextMediaBox as String: NSData(bytes: &box, length: MemoryLayout<CGRect>.size)]
            ctx.beginPDFPage(info as CFDictionary)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: area.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -area.minX, y: -area.minY)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(area)
            Renderer.draw(items, lookup: lookup, images: images, cache: cache, ctx: ctx, scale: 1, visible: area)
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        NSGraphicsContext.restoreGraphicsState()
        return data as Data
    }
}
