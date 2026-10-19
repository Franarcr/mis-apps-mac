import AppKit

/// Una ventana por cómic: barra de herramientas con los modos de lectura, la página y un deslizador abajo.
@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let url: URL
    var onClose: (() -> Void)?
    var onOpenFiles: (([URL]) -> Void)?

    private var fit = Preferences.fit
    private var doublePage = Preferences.doublePage
    private var rightToLeft = Preferences.rightToLeft
    private var coverAlone = Preferences.coverAlone

    private var pages: [ComicPage] = []
    /// Grupos de páginas que se ven juntas: [0], [1, 2], [3, 4]… en doble página, o una por grupo.
    private var spreads: [[Int]] = []
    private var spreadIndex = 0
    private var currentPage: Int { spreads.indices.contains(spreadIndex) ? spreads[spreadIndex][0] : 0 }

    /// Imágenes ya descomprimidas de las páginas cercanas a la actual.
    private var cache: [Int: NSImage] = [:]
    private var decoding: Set<Int> = []

    private let scrollView = NSScrollView()
    private let pageView = PageView()
    private let slider = NSSlider()
    private let loadingBar = NSProgressIndicator()
    private var fitControl: NSSegmentedControl!
    private var layoutControl: NSSegmentedControl!
    private var directionControl: NSSegmentedControl!

    init(url: URL) {
        self.url = url
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height = (visible.height * 0.9).rounded()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(visible.width * 0.9, height * 0.75), height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = url.deletingPathExtension().lastPathComponent
        window.representedURL = url
        window.minSize = NSSize(width: 360, height: 300)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        window.center()
        startLoading()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no está implementado") }

    // MARK: Interfaz

    private func buildUI() {
        guard let window, let content = window.contentView else { return }

        scrollView.documentView = pageView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = PageView.background
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 8
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged(_:)),
                                               name: NSView.frameDidChangeNotification, object: scrollView)

        pageView.onClick = { [weak self] x in
            guard let self else { return }
            if x < 1.0 / 3 { self.turn(towardsRight: false) } else if x > 2.0 / 3 { self.turn(towardsRight: true) }
        }
        pageView.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        pageView.onFilesDropped = { [weak self] urls in self?.onOpenFiles?(urls) }

        slider.minValue = 0
        slider.maxValue = 0
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isEnabled = false
        slider.controlSize = .small

        let bottomBar = NSView()
        bottomBar.addSubview(slider)

        loadingBar.style = .bar
        loadingBar.isIndeterminate = false
        loadingBar.minValue = 0
        loadingBar.maxValue = 1

        for view in [scrollView, bottomBar, loadingBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        slider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 30),
            slider.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            slider.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            slider.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            loadingBar.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            loadingBar.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            loadingBar.widthAnchor.constraint(equalToConstant: 220),
        ])

        fitControl = NSSegmentedControl(labels: ["Página", "Ancho", "Real"], trackingMode: .selectOne,
                                        target: self, action: #selector(fitControlChanged(_:)))
        fitControl.setToolTip("Ver la página entera", forSegment: 0)
        fitControl.setToolTip("Ajustar al ancho de la ventana", forSegment: 1)
        fitControl.setToolTip("Tamaño real de la imagen", forSegment: 2)

        layoutControl = NSSegmentedControl(images: [symbol("doc"), symbol("book")], trackingMode: .selectOne,
                                           target: self, action: #selector(layoutControlChanged(_:)))
        layoutControl.setToolTip("Una página", forSegment: 0)
        layoutControl.setToolTip("Doble página", forSegment: 1)

        directionControl = NSSegmentedControl(images: [symbol("arrow.right"), symbol("arrow.left")], trackingMode: .selectOne,
                                              target: self, action: #selector(directionControlChanged(_:)))
        directionControl.setToolTip("De izquierda a derecha", forSegment: 0)
        directionControl.setToolTip("De derecha a izquierda (manga)", forSegment: 1)

        let toolbar = NSToolbar(identifier: "Lector")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        syncControls()
    }

    private func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    private func syncControls() {
        fitControl.selectedSegment = fit.rawValue
        layoutControl.selectedSegment = doublePage ? 1 : 0
        directionControl.selectedSegment = rightToLeft ? 1 : 0
        // En manga el principio queda a la derecha también en el deslizador.
        slider.userInterfaceLayoutDirection = rightToLeft ? .rightToLeft : .leftToRight
    }

    // MARK: Barra de herramientas

    private static let fitItem = NSToolbarItem.Identifier("fit")
    private static let layoutItem = NSToolbarItem.Identifier("layout")
    private static let directionItem = NSToolbarItem.Identifier("direction")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.fitItem, Self.layoutItem, Self.directionItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .space, Self.fitItem, Self.layoutItem, Self.directionItem]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case Self.fitItem:
            item.view = fitControl
            item.label = "Ajuste"
        case Self.layoutItem:
            item.view = layoutControl
            item.label = "Páginas"
        case Self.directionItem:
            item.view = directionControl
            item.label = "Sentido"
        default:
            return nil
        }
        return item
    }

    // MARK: Carga

    private func startLoading() {
        let url = self.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try ComicArchive.load(url) { fraction in
                    DispatchQueue.main.async { self?.loadingBar.doubleValue = fraction }
                }
            }
            DispatchQueue.main.async { self?.finishLoading(result) }
        }
    }

    private func finishLoading(_ result: Result<[ComicPage], Error>) {
        loadingBar.isHidden = true
        switch result {
        case .failure(let error):
            guard let window else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "No se pudo abrir «\(url.lastPathComponent)»"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window) { [weak self] _ in self?.close() }
        case .success(let pages):
            self.pages = pages
            slider.maxValue = Double(pages.count - 1)
            slider.isEnabled = pages.count > 1
            rebuildSpreads(showing: min(Preferences.lastPage(for: url), pages.count - 1))
            window?.makeFirstResponder(pageView)
        }
    }

    // MARK: Páginas

    private func rebuildSpreads(showing page: Int) {
        spreads = []
        var i = 0
        while i < pages.count {
            // Van solas: la portada (si se pide), la última, las apaisadas y la anterior a una apaisada.
            let alone = !doublePage || pages[i].isWide || (coverAlone && i == 0)
                || i == pages.count - 1 || pages[i + 1].isWide
            spreads.append(alone ? [i] : [i, i + 1])
            i += alone ? 1 : 2
        }
        spreadIndex = spreads.firstIndex { $0.contains(page) } ?? 0
        showCurrent()
    }

    /// Muestra el grupo actual. Al volver hacia atrás con ⇧Espacio se empieza por el final de la página.
    private func showCurrent(atBottom: Bool = false) {
        guard spreads.indices.contains(spreadIndex) else { return }
        let indices = spreads[spreadIndex]
        let images = indices.compactMap(image(at:))
        scrollView.magnification = 1
        pageView.show(rightToLeft ? images.reversed() : images, in: scrollView.contentSize, fit: fit)
        scroll(toY: atBottom ? .greatestFiniteMagnitude : 0)

        slider.doubleValue = Double(indices[0])
        if indices.count == 2 {
            window?.subtitle = "Páginas \(indices[0] + 1)–\(indices[1] + 1) de \(pages.count)"
        } else {
            window?.subtitle = "Página \(indices[0] + 1) de \(pages.count)"
        }
        Preferences.setLastPage(indices[0], for: url)
        prefetch()
    }

    private func image(at index: Int) -> NSImage? {
        if let image = cache[index] { return image }
        guard let cgImage = ComicArchive.decode(pages[index]) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache[index] = image
        return image
    }

    /// Páginas que conviene tener listas: el grupo anterior, el actual y los dos siguientes.
    private var nearbyPages: Set<Int> {
        guard !spreads.isEmpty else { return [] }
        let range = max(0, spreadIndex - 1) ... min(spreads.count - 1, spreadIndex + 2)
        return Set(range.flatMap { spreads[$0] })
    }

    /// Descomprime en segundo plano las páginas cercanas para que pasar página sea instantáneo.
    private func prefetch() {
        let wanted = nearbyPages
        cache = cache.filter { wanted.contains($0.key) }
        for index in wanted where cache[index] == nil && !decoding.contains(index) {
            decoding.insert(index)
            let page = pages[index]
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let cgImage = ComicArchive.decode(page)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.decoding.remove(index)
                    if let cgImage, self.cache[index] == nil, self.nearbyPages.contains(index) {
                        self.cache[index] = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    }
                }
            }
        }
    }

    private func go(toSpread index: Int, atBottom: Bool = false) {
        guard spreads.indices.contains(index) else {
            NSSound.beep()
            return
        }
        spreadIndex = index
        showCurrent(atBottom: atBottom)
    }

    private func go(toPage page: Int) {
        guard !pages.isEmpty else { return }
        let page = min(max(page, 0), pages.count - 1)
        if let index = spreads.firstIndex(where: { $0.contains(page) }), index != spreadIndex { go(toSpread: index) }
    }

    /// Flechas y clics en los lados: hacia la derecha avanza, salvo en manga.
    private func turn(towardsRight: Bool) {
        go(toSpread: spreadIndex + (towardsRight != rightToLeft ? 1 : -1))
    }

    // MARK: Desplazamiento y teclado

    private func scroll(toY y: CGFloat) {
        let clip = scrollView.contentView
        let maxY = max(0, pageView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Espacio: baja por la página y, al llegar al final, pasa a la siguiente.
    private func pageDown() {
        let clip = scrollView.contentView
        if clip.bounds.maxY < pageView.frame.height - 1 {
            scroll(toY: clip.bounds.origin.y + clip.bounds.height * 0.9)
        } else {
            go(toSpread: spreadIndex + 1)
        }
    }

    private func pageUp() {
        let clip = scrollView.contentView
        if clip.bounds.origin.y > 1 {
            scroll(toY: clip.bounds.origin.y - clip.bounds.height * 0.9)
        } else {
            go(toSpread: spreadIndex - 1, atBottom: true)
        }
    }

    private enum Key {
        static let space: UInt16 = 49, escape: UInt16 = 53
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        static let home: UInt16 = 115, pageUp: UInt16 = 116, end: UInt16 = 119, pageDown: UInt16 = 121
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard !pages.isEmpty, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case Key.left: turn(towardsRight: false)
        case Key.right: turn(towardsRight: true)
        case Key.up: scroll(toY: scrollView.contentView.bounds.origin.y - 80)
        case Key.down: scroll(toY: scrollView.contentView.bounds.origin.y + 80)
        case Key.space: event.modifierFlags.contains(.shift) ? pageUp() : pageDown()
        case Key.pageDown: pageDown()
        case Key.pageUp: pageUp()
        case Key.home: go(toSpread: 0)
        case Key.end: go(toSpread: spreads.count - 1)
        case Key.escape:
            guard let window, window.styleMask.contains(.fullScreen) else { return false }
            window.toggleFullScreen(nil)
        default: return false
        }
        return true
    }

    @objc private func viewportChanged(_ notification: Notification) {
        guard !spreads.isEmpty else { return }
        let clip = scrollView.contentView
        let relativeY = clip.bounds.origin.y / max(pageView.frame.height, 1)
        pageView.show(pageView.images, in: scrollView.contentSize, fit: fit)
        scroll(toY: relativeY * pageView.frame.height)
    }

    // MARK: Acciones (barra de herramientas, deslizador y menús)

    @objc private func sliderMoved(_ sender: NSSlider) { go(toPage: Int(sender.doubleValue.rounded())) }
    @objc private func fitControlChanged(_ sender: NSSegmentedControl) { setFit(FitMode(rawValue: sender.selectedSegment) ?? .page) }
    @objc private func layoutControlChanged(_ sender: NSSegmentedControl) { setDoublePage(sender.selectedSegment == 1) }
    @objc private func directionControlChanged(_ sender: NSSegmentedControl) { setRightToLeft(sender.selectedSegment == 1) }

    @objc func fitPage(_ sender: Any?) { setFit(.page) }
    @objc func fitWidth(_ sender: Any?) { setFit(.width) }
    @objc func fitOriginal(_ sender: Any?) { setFit(.original) }
    @objc func toggleDoublePage(_ sender: Any?) { setDoublePage(!doublePage) }
    @objc func toggleRightToLeft(_ sender: Any?) { setRightToLeft(!rightToLeft) }

    @objc func toggleCoverAlone(_ sender: Any?) {
        coverAlone.toggle()
        Preferences.coverAlone = coverAlone
        rebuildSpreads(showing: currentPage)
    }

    @objc func nextPage(_ sender: Any?) { go(toSpread: spreadIndex + 1) }
    @objc func previousPage(_ sender: Any?) { go(toSpread: spreadIndex - 1) }
    @objc func firstPage(_ sender: Any?) { go(toSpread: 0) }
    @objc func lastPage(_ sender: Any?) { go(toSpread: spreads.count - 1) }

    @objc func zoomIn(_ sender: Any?) { scrollView.animator().magnification = min(scrollView.magnification * 1.25, 8) }
    @objc func zoomOut(_ sender: Any?) { scrollView.animator().magnification = max(scrollView.magnification / 1.25, 0.25) }
    @objc func resetZoom(_ sender: Any?) { scrollView.animator().magnification = 1 }

    @objc func goToPage(_ sender: Any?) {
        guard let window, !pages.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Ir a la página"
        alert.informativeText = "Escribe un número del 1 al \(pages.count)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = "\(currentPage + 1)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Ir")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let number = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
            self?.go(toPage: number - 1)
        }
    }

    private func setFit(_ mode: FitMode) {
        fit = mode
        Preferences.fit = mode
        syncControls()
        showCurrent()
    }

    private func setDoublePage(_ on: Bool) {
        doublePage = on
        Preferences.doublePage = on
        syncControls()
        rebuildSpreads(showing: currentPage)
    }

    private func setRightToLeft(_ on: Bool) {
        rightToLeft = on
        Preferences.rightToLeft = on
        syncControls()
        showCurrent()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(fitPage(_:)): menuItem.state = fit == .page ? .on : .off
        case #selector(fitWidth(_:)): menuItem.state = fit == .width ? .on : .off
        case #selector(fitOriginal(_:)): menuItem.state = fit == .original ? .on : .off
        case #selector(toggleDoublePage(_:)): menuItem.state = doublePage ? .on : .off
        case #selector(toggleRightToLeft(_:)): menuItem.state = rightToLeft ? .on : .off
        case #selector(toggleCoverAlone(_:)):
            menuItem.state = coverAlone ? .on : .off
            return doublePage
        case #selector(nextPage(_:)): return spreadIndex < spreads.count - 1
        case #selector(previousPage(_:)), #selector(firstPage(_:)): return spreadIndex > 0
        case #selector(lastPage(_:)): return spreadIndex < spreads.count - 1
        default: break
        }
        return !pages.isEmpty
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        onClose?()
    }
}
