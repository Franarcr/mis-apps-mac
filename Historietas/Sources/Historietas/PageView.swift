import AppKit

/// Dibuja una página o dos enfrentadas dentro del NSScrollView del lector.
/// Su tamaño es el del contenido o el de la vista visible si este es menor, y el contenido queda centrado.
final class PageView: NSView {
    static let background = NSColor(white: 0.12, alpha: 1)

    /// Imágenes en el orden en que se ven, de izquierda a derecha. Su `size` es el tamaño en píxeles.
    private(set) var images: [NSImage] = []
    private var rects: [NSRect] = []

    /// Clic sin arrastrar; recibe la posición horizontal dentro de la zona visible (0 = borde izquierdo, 1 = derecho).
    var onClick: ((CGFloat) -> Void)?
    /// Teclas que no son atajos del menú; devuelve true si las ha usado.
    var onKey: ((NSEvent) -> Bool)?
    /// Cómics arrastrados desde el Finder.
    var onFilesDropped: (([URL]) -> Void)?

    private var dragged = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no está implementado") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Coloca las imágenes para una zona visible de `viewport` puntos.
    func show(_ images: [NSImage], in viewport: NSSize, fit: FitMode) {
        self.images = images
        // Todas las imágenes se escalan a la misma altura y se colocan una al lado de la otra.
        let aspects = images.map { $0.size.width / max($0.size.height, 1) }
        let totalAspect = aspects.reduce(0, +)
        guard totalAspect > 0 else {
            rects = []
            setFrameSize(viewport)
            needsDisplay = true
            return
        }
        let height: CGFloat
        switch fit {
        case .page: height = min(viewport.height, viewport.width / totalAspect)
        case .width: height = viewport.width / totalAspect
        case .original: height = (images.map(\.size.height).max() ?? 0) / (window?.backingScaleFactor ?? 2)
        }
        let contentWidth = height * totalAspect
        let size = NSSize(width: max(viewport.width, contentWidth.rounded(.up)),
                          height: max(viewport.height, height.rounded(.up)))
        setFrameSize(size)

        var x = ((size.width - contentWidth) / 2).rounded()
        let y = ((size.height - height) / 2).rounded()
        rects = aspects.map { aspect in
            defer { x += height * aspect }
            return NSRect(x: x, y: y, width: height * aspect, height: height)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.background.setFill()
        dirtyRect.fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        for (image, rect) in zip(images, rects) where rect.intersects(dirtyRect) {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    // MARK: Ratón: clic para pasar página, arrastrar para mover la página ampliada

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        dragged = true
        NSCursor.closedHand.set()
        var origin = clip.bounds.origin
        origin.x -= event.deltaX / scrollView.magnification
        origin.y -= event.deltaY / scrollView.magnification
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    override func mouseUp(with event: NSEvent) {
        if dragged {
            NSCursor.arrow.set()
            return
        }
        guard event.clickCount == 1, let clip = enclosingScrollView?.contentView else { return }
        let point = clip.convert(event.locationInWindow, from: nil)
        onClick?((point.x - clip.bounds.minX) / max(clip.bounds.width, 1))
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    // MARK: Arrastrar cómics desde el Finder

    private func comicURLs(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { ComicArchive.fileExtensions.contains($0.pathExtension.lowercased()) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        comicURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = comicURLs(sender)
        guard !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }
}
