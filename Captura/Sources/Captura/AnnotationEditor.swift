import AppKit
import SwiftUI

// MARK: - Modelo

/// Una anotación sobre la captura, en píxeles de la imagen (origen arriba a la izquierda).
struct Annotation {
    enum Kind {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case highlight(CGRect)
        case text(origin: CGPoint, string: String)
    }

    var kind: Kind
    var color: Int
    var size: Int

    func moved(by d: CGSize) -> Annotation {
        var copy = self
        switch kind {
        case let .arrow(a, b):
            copy.kind = .arrow(from: CGPoint(x: a.x + d.width, y: a.y + d.height), to: CGPoint(x: b.x + d.width, y: b.y + d.height))
        case let .rectangle(r): copy.kind = .rectangle(r.offsetBy(dx: d.width, dy: d.height))
        case let .highlight(r): copy.kind = .highlight(r.offsetBy(dx: d.width, dy: d.height))
        case let .text(o, s): copy.kind = .text(origin: CGPoint(x: o.x + d.width, y: o.y + d.height), string: s)
        }
        return copy
    }
}

enum AnnotationTool: Int, CaseIterable {
    case arrow, rectangle, highlight, text

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .highlight: "highlighter"
        case .text: "textformat"
        }
    }

    var name: String {
        switch self {
        case .arrow: "Flecha"
        case .rectangle: "Rectángulo"
        case .highlight: "Resaltar"
        case .text: "Texto"
        }
    }
}

/// Estado de la barra de herramientas (en una clase porque `@State` necesita las macros de Xcode).
final class EditorModel: ObservableObject {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.95, green: 0.23, blue: 0.23, alpha: 1), // rojo
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1), // naranja
        NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1), // amarillo
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1), // verde
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1), // azul
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1), // morado
    ]

    @Published var tool = AnnotationTool.arrow
    @Published var color = 0 { didSet { onStyleChange?() } }
    @Published var size = 1 { didSet { onStyleChange?() } }

    /// Al cambiar color o grosor con una anotación seleccionada, se le aplica.
    var onStyleChange: (() -> Void)?
}

// MARK: - Dibujo (compartido por el lienzo y la exportación)

enum AnnotationRenderer {
    /// Unidad de trazo según el tamaño de la imagen, para que se vea igual en capturas grandes o pequeñas.
    static func unit(for image: CGImage) -> CGFloat { max(2, CGFloat(max(image.width, image.height)) / 500) }

    static func lineWidth(_ a: Annotation, unit: CGFloat) -> CGFloat { unit * [1.0, 1.7, 2.6][a.size] }
    static func fontSize(_ a: Annotation, unit: CGFloat) -> CGFloat { unit * [6.0, 8.0, 11.0][a.size] }

    /// Dibuja en un contexto con el origen arriba a la izquierda, en píxeles de la imagen.
    static func draw(_ a: Annotation, in ctx: CGContext, unit: CGFloat) {
        let color = EditorModel.colors[a.color]
        let width = lineWidth(a, unit: unit)
        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch a.kind {
        case let .arrow(from, to):
            let angle = atan2(to.y - from.y, to.x - from.x)
            let head = width * 4.2
            let base = CGPoint(x: to.x - cos(angle) * head * 0.8, y: to.y - sin(angle) * head * 0.8)
            ctx.setShadow(offset: .zero, blur: width * 1.5, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.setStrokeColor(color.cgColor)
            ctx.setFillColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.move(to: from)
            ctx.addLine(to: base)
            ctx.strokePath()
            let left = CGPoint(x: to.x - cos(angle - .pi / 7) * head, y: to.y - sin(angle - .pi / 7) * head)
            let right = CGPoint(x: to.x - cos(angle + .pi / 7) * head, y: to.y - sin(angle + .pi / 7) * head)
            ctx.move(to: to)
            ctx.addLine(to: left)
            ctx.addLine(to: right)
            ctx.closePath()
            ctx.fillPath()

        case let .rectangle(rect):
            ctx.setShadow(offset: .zero, blur: width * 1.5, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.addPath(CGPath(roundedRect: rect.standardized, cornerWidth: width * 1.5, cornerHeight: width * 1.5, transform: nil))
            ctx.strokePath()

        case let .highlight(rect):
            ctx.setFillColor(color.withAlphaComponent(0.35).cgColor)
            ctx.addPath(CGPath(roundedRect: rect.standardized, cornerWidth: width, cornerHeight: width, transform: nil))
            ctx.fillPath()

        case let .text(origin, string):
            guard !string.isEmpty else { return }
            let (attributed, box) = textLayout(a, origin: origin, string: string, unit: unit)
            ctx.setShadow(offset: .zero, blur: width * 1.5, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(color.cgColor)
            let radius = fontSize(a, unit: unit) * 0.3
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let padding = padding(a, unit: unit)
            attributed.draw(at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func padding(_ a: Annotation, unit: CGFloat) -> CGSize {
        let size = fontSize(a, unit: unit)
        return CGSize(width: size * 0.45, height: size * 0.22)
    }

    /// Texto blanco sobre una etiqueta del color elegido (negro sobre el amarillo, para que se lea).
    static func textLayout(_ a: Annotation, origin: CGPoint, string: String, unit: CGFloat) -> (NSAttributedString, CGRect) {
        let textColor: NSColor = a.color == 2 ? .black : .white
        let attributed = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize(a, unit: unit), weight: .semibold),
            .foregroundColor: textColor,
        ])
        let size = attributed.size()
        let pad = padding(a, unit: unit)
        return (attributed, CGRect(x: origin.x, y: origin.y, width: size.width + pad.width * 2, height: size.height + pad.height * 2))
    }

    /// Zona que ocupa la anotación (para seleccionarla con un clic).
    static func bounds(_ a: Annotation, unit: CGFloat) -> CGRect {
        let width = lineWidth(a, unit: unit)
        switch a.kind {
        case let .arrow(f, t):
            return CGRect(x: min(f.x, t.x), y: min(f.y, t.y), width: abs(t.x - f.x), height: abs(t.y - f.y))
                .insetBy(dx: -width * 4, dy: -width * 4)
        case let .rectangle(r), let .highlight(r):
            return r.standardized.insetBy(dx: -width * 2, dy: -width * 2)
        case let .text(o, s):
            return textLayout(a, origin: o, string: s.isEmpty ? " " : s, unit: unit).1
        }
    }

    static func hit(_ a: Annotation, at p: CGPoint, unit: CGFloat, tolerance: CGFloat) -> Bool {
        switch a.kind {
        case let .arrow(f, t):
            // Distancia del punto al segmento.
            let dx = t.x - f.x, dy = t.y - f.y
            let length = max(dx * dx + dy * dy, 0.0001)
            let k = max(0, min(1, ((p.x - f.x) * dx + (p.y - f.y) * dy) / length))
            let closest = CGPoint(x: f.x + k * dx, y: f.y + k * dy)
            return hypot(p.x - closest.x, p.y - closest.y) <= tolerance + lineWidth(a, unit: unit) * 2
        default:
            return bounds(a, unit: unit).insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    /// La imagen final, a resolución completa, con todas las anotaciones.
    static func render(_ image: CGImage, _ annotations: [Annotation]) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let unit = unit(for: image)
        annotations.forEach { draw($0, in: ctx, unit: unit) }
        return ctx.makeImage()
    }
}

// MARK: - Lienzo

final class AnnotationCanvas: NSView, NSTextFieldDelegate {
    let image: CGImage
    let model: EditorModel
    private(set) var annotations: [Annotation] = []
    private var selected: Int? { didSet { needsDisplay = true } }
    private var undoStack: [[Annotation]] = []
    private var drag: (index: Int, start: CGPoint, original: Annotation, creating: Bool)?
    private var editor: NSTextField?
    private var editingIndex: Int?
    private let unit: CGFloat

    /// Acciones de la ventana (copiar, guardar, terminar).
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    init(image: CGImage, model: EditorModel) {
        self.image = image
        self.model = model
        unit = AnnotationRenderer.unit(for: image)
        super.init(frame: .zero)
        model.onStyleChange = { [weak self] in self?.restyleSelection() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometría

    private var fitRect: CGRect {
        let area = bounds.insetBy(dx: 20, dy: 20)
        let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height), 1)
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private var scale: CGFloat { fitRect.width / CGFloat(image.width) }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let fit = fitRect
        return CGPoint(x: (p.x - fit.minX) / scale, y: (p.y - fit.minY) / scale)
    }

    private func viewRect(_ r: CGRect) -> CGRect {
        let fit = fitRect
        return CGRect(x: fit.minX + r.minX * scale, y: fit.minY + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    // MARK: Dibujo

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.13, alpha: 1).setFill()
        bounds.fill()
        let fit = fitRect
        NSImage(cgImage: image, size: .zero).draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1,
                                                  respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: fit)
        ctx.translateBy(x: fit.minX, y: fit.minY)
        ctx.scaleBy(x: scale, y: scale)
        for (i, a) in annotations.enumerated() where i != editingIndex {
            AnnotationRenderer.draw(a, in: ctx, unit: unit)
        }
        ctx.restoreGState()

        if let selected, selected < annotations.count, selected != editingIndex {
            let box = viewRect(AnnotationRenderer.bounds(annotations[selected], unit: unit)).insetBy(dx: -4, dy: -4)
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            path.setLineDash([5, 4], count: 2, phase: 0)
            path.lineWidth = 1.5
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.stroke()
        }
    }

    // MARK: Ratón

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitText()
        let p = imagePoint(event)

        if let i = annotations.indices.reversed().first(where: {
            AnnotationRenderer.hit(annotations[$0], at: p, unit: unit, tolerance: 6 / scale)
        }) {
            selected = i
            if event.clickCount == 2, case .text = annotations[i].kind {
                beginEditing(i)
                return
            }
            pushUndo()
            drag = (i, p, annotations[i], false)
            return
        }

        selected = nil
        guard fitRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        pushUndo()
        let kind: Annotation.Kind = switch model.tool {
        case .arrow: .arrow(from: p, to: p)
        case .rectangle: .rectangle(CGRect(origin: p, size: .zero))
        case .highlight: .highlight(CGRect(origin: p, size: .zero))
        case .text: .text(origin: p, string: "")
        }
        annotations.append(Annotation(kind: kind, color: model.color, size: model.size))
        let index = annotations.count - 1
        selected = index
        if model.tool == .text {
            beginEditing(index)
        } else {
            drag = (index, p, annotations[index], true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let p = imagePoint(event)
        if drag.creating {
            switch drag.original.kind {
            case let .arrow(from, _): annotations[drag.index].kind = .arrow(from: from, to: p)
            case .rectangle: annotations[drag.index].kind = .rectangle(CGRect(x: drag.start.x, y: drag.start.y,
                                                                               width: p.x - drag.start.x, height: p.y - drag.start.y))
            case .highlight: annotations[drag.index].kind = .highlight(CGRect(x: drag.start.x, y: drag.start.y,
                                                                               width: p.x - drag.start.x, height: p.y - drag.start.y))
            case .text: break
            }
        } else {
            annotations[drag.index] = drag.original.moved(by: CGSize(width: p.x - drag.start.x, height: p.y - drag.start.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil }
        guard let drag else { return }
        let p = imagePoint(event)
        let moved = hypot(p.x - drag.start.x, p.y - drag.start.y)
        if moved * scale < 4 {
            if drag.creating {
                // Un clic sin arrastrar no crea nada.
                annotations.remove(at: drag.index)
                selected = nil
            }
            undoStack.removeLast()
        }
        needsDisplay = true
    }

    // MARK: Texto

    private func beginEditing(_ index: Int) {
        guard case let .text(origin, string) = annotations[index].kind else { return }
        editingIndex = index
        let a = annotations[index]
        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = EditorModel.colors[a.color]
        field.textColor = a.color == 2 ? .black : .white
        field.font = .systemFont(ofSize: AnnotationRenderer.fontSize(a, unit: unit) * scale, weight: .semibold)
        field.focusRingType = .none
        field.placeholderString = "Escribe…"
        field.delegate = self
        field.cell?.isScrollable = true
        let fit = fitRect
        field.frame.origin = CGPoint(x: fit.minX + origin.x * scale, y: fit.minY + origin.y * scale)
        resizeEditor(field)
        addSubview(field)
        window?.makeFirstResponder(field)
        editor = field
        needsDisplay = true
    }

    private func resizeEditor(_ field: NSTextField) {
        field.sizeToFit()
        field.frame.size.width = max(field.frame.width + 12, 80)
    }

    func controlTextDidChange(_ obj: Notification) {
        if let editor { resizeEditor(editor) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
            commitText()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    private func commitText() {
        guard let field = editor, let index = editingIndex else { return }
        editor = nil
        editingIndex = nil
        field.removeFromSuperview()
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if case let .text(origin, _) = annotations[index].kind {
            if text.isEmpty {
                annotations.remove(at: index)
                selected = nil
            } else {
                annotations[index].kind = .text(origin: origin, string: text)
            }
        }
        needsDisplay = true
    }

    // MARK: Edición

    private func pushUndo() {
        undoStack.append(annotations)
        if undoStack.count > 100 { undoStack.removeFirst() }
    }

    @objc func undo(_ sender: Any?) {
        commitText()
        guard let previous = undoStack.popLast() else { NSSound.beep(); return }
        annotations = previous
        selected = nil
        needsDisplay = true
    }

    @objc func delete(_ sender: Any?) {
        guard let selected else { return }
        pushUndo()
        annotations.remove(at: selected)
        self.selected = nil
    }

    @objc func copy(_ sender: Any?) { onCopy?() }
    @objc func saveImage(_ sender: Any?) { onSave?() }

    private func restyleSelection() {
        guard let selected, selected < annotations.count else { return }
        pushUndo()
        annotations[selected].color = model.color
        annotations[selected].size = model.size
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: delete(nil) // borrar
        case 53: selected = nil   // Esc
        default: super.keyDown(with: event)
        }
    }

    func finalImage() -> CGImage? {
        commitText()
        return AnnotationRenderer.render(image, annotations)
    }
}

// MARK: - Ventana

private struct EditorToolbar: View {
    @ObservedObject var model: EditorModel
    let onUndo: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Picker("", selection: $model.tool) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    Image(systemName: tool.symbol).help(tool.name).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)

            HStack(spacing: 6) {
                ForEach(EditorModel.colors.indices, id: \.self) { i in
                    Circle()
                        .fill(Color(nsColor: EditorModel.colors[i]))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white, lineWidth: model.color == i ? 2.5 : 0))
                        .shadow(radius: model.color == i ? 2 : 0)
                        .onTapGesture { model.color = i }
                }
            }

            Picker("", selection: $model.size) {
                Text("S").tag(0)
                Text("M").tag(1)
                Text("L").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 96)
            .help("Grosor y tamaño del texto")

            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }.help("Deshacer (⌘Z)")
            Spacer()
            Button("Copiar", action: onCopy).help("Copiar la imagen anotada (⌘C)")
            Button("Guardar", action: onSave).help("Guardar en la carpeta de capturas (⌘S)")
            Button("Listo", action: onDone)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Copiar y cerrar (⌘↩)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

@MainActor
final class AnnotationEditor: NSObject, NSWindowDelegate {
    private static var open: [AnnotationEditor] = []

    private let window: NSWindow
    private let canvas: AnnotationCanvas
    private let model = EditorModel()
    private let fileURL: URL?

    /// Abre el editor con una captura. Al pulsar "Listo" se copia la imagen anotada y,
    /// si había archivo, se reemplaza por la versión anotada.
    static func open(image: CGImage, fileURL: URL?) {
        let editor = AnnotationEditor(image: image, fileURL: fileURL)
        open.append(editor)
        NSApp.activate(ignoringOtherApps: true)
        editor.window.makeKeyAndOrderFront(nil)
        editor.window.makeFirstResponder(editor.canvas)
    }

    private init(image: CGImage, fileURL: URL?) {
        self.fileURL = fileURL
        canvas = AnnotationCanvas(image: image, model: model)
        // Tamaño inicial: la captura a su tamaño en puntos, sin pasar del 85 % de la pantalla.
        let screen = NSScreen.underMouse.visibleFrame
        let pointScale = NSScreen.underMouse.backingScaleFactor
        let imageSize = CGSize(width: CGFloat(image.width) / pointScale, height: CGFloat(image.height) / pointScale)
        let width = min(max(imageSize.width + 40, 720), screen.width * 0.85)
        let height = min(max(imageSize.height + 100, 420), screen.height * 0.85)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()

        window.title = "Anotar captura"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 360)
        window.delegate = self
        window.center()

        let toolbar = NSHostingView(rootView: EditorToolbar(
            model: model,
            onUndo: { [weak self] in self?.canvas.undo(nil) },
            onCopy: { [weak self] in self?.copy() },
            onSave: { [weak self] in self?.save() },
            onDone: { [weak self] in self?.done() }))
        canvas.onCopy = { [weak self] in self?.copy() }
        canvas.onSave = { [weak self] in self?.save() }

        let content = window.contentView!
        for view in [toolbar, canvas] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func png() -> Data? {
        guard let image = canvas.finalImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func copy() {
        guard let png = png() else { return }
        Clipboard.copy(png: png)
        Toast.show("Captura anotada copiada")
    }

    private func save() {
        guard let png = png() else { return }
        let folder = Settings.saveFolder
        let name = (fileURL?.deletingPathExtension().lastPathComponent ?? "Captura") + " (anotada).png"
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url)
            Toast.show("Captura anotada guardada", detail: folder.path)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func done() {
        guard let png = png() else { return }
        Clipboard.copy(png: png)
        if let fileURL { try? png.write(to: fileURL) }
        Toast.show("Captura anotada copiada")
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}
