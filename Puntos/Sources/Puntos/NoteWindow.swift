import AppKit

/// Fila de 7 puntos de colores. Relleno = la nota tiene texto; anillo = la nota abierta.
/// Fuera de los puntos, arrastrar mueve la ventana.
final class DotBarView: NSView {
    var selected = 0 { didSet { needsDisplay = true } }
    var filled = Array(repeating: false, count: NotesStore.count) { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?

    private let size: CGFloat = 14
    private let spacing: CGFloat = 14

    private func dotRect(_ i: Int) -> NSRect {
        let total = CGFloat(NotesStore.count) * size + CGFloat(NotesStore.count - 1) * spacing
        let x = bounds.midX - total / 2 + CGFloat(i) * (size + spacing)
        return NSRect(x: x, y: bounds.midY - size / 2, width: size, height: size)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for i in 0 ..< NotesStore.count {
            let color = NotesStore.colors[i]
            let rect = dotRect(i)
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            if filled[i] {
                color.setFill()
                dot.fill()
            } else {
                color.withAlphaComponent(0.15).setFill()
                dot.fill()
                color.setStroke()
                dot.lineWidth = 2
                dot.stroke()
            }
            if i == selected {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -4, dy: -4))
                ring.lineWidth = 2
                color.withAlphaComponent(0.55).setStroke()
                ring.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let i = (0 ..< NotesStore.count).first(where: { dotRect($0).insetBy(dx: -6, dy: -8).contains(point) }) {
            onSelect?(i)
        } else {
            window?.performDrag(with: event)
        }
    }

    override func layout() {
        super.layout()
        removeAllToolTips()
        for i in 0 ..< NotesStore.count {
            addToolTip(dotRect(i).insetBy(dx: -6, dy: -8), owner: self, userData: nil)
        }
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
                    userData data: UnsafeMutableRawPointer?) -> String {
        guard let i = (0 ..< NotesStore.count).first(where: { dotRect($0).insetBy(dx: -6, dy: -8).contains(point) })
        else { return "" }
        return "\(NotesStore.colorNames[i]) · ⌘\(i + 1)"
    }
}

/// Ventana con los puntos arriba, el editor y una barra inferior con el contador y "Copiar".
@MainActor
final class NoteWindowController: NSObject, NSWindowDelegate, NSTextViewDelegate, NSTextStorageDelegate {
    let window: NSWindow
    let textView: NSTextView
    private let store: NotesStore
    private let dots = DotBarView()
    private let counter = NSTextField(labelWithString: "")
    private var selections = Array(repeating: NSRange(location: 0, length: 0), count: NotesStore.count)
    private var loading = false

    var fontSize: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 15) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "fontSize") }
    }

    private var accent: NSColor { NotesStore.colors[store.selected] }

    init(store: NotesStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        super.init()

        window.title = "Puntos"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 280)
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.setFrameAutosaveName("PuntosWindow")
        if !window.setFrameUsingName("PuntosWindow") { window.center() }

        // Editor
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 10)
        textView.delegate = self
        textView.textStorage?.delegate = self
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        // Barra inferior
        counter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        counter.textColor = .secondaryLabelColor
        let copy = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copiar nota")!,
                            target: self, action: #selector(copyNote))
        copy.isBordered = false
        copy.toolTip = "Copiar toda la nota"
        copy.contentTintColor = .secondaryLabelColor

        dots.onSelect = { [weak self] index in self?.select(index) }

        let content = window.contentView!
        for view in [dots, scroll, counter, copy] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            // Los puntos van debajo de la barra de título (los botones de la ventana quedan encima).
            dots.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            dots.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            dots.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            dots.heightAnchor.constraint(equalToConstant: 30),
            scroll.topAnchor.constraint(equalTo: dots.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: counter.topAnchor, constant: -6),
            counter.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            counter.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -9),
            copy.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            copy.centerYAnchor.constraint(equalTo: counter.centerYAnchor),
        ])

        refreshDots()
        load(store.selected)
    }

    // MARK: Notas

    func select(_ index: Int) {
        guard index != store.selected else { return }
        selections[store.selected] = textView.selectedRange()
        store.selected = index
        load(index)
    }

    private func load(_ index: Int) {
        loading = true
        textView.string = store.texts[index]
        loading = false
        restyle()
        let saved = selections[index]
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(saved.location, length), length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        textView.insertionPointColor = accent
        textView.selectedTextAttributes = [.backgroundColor: accent.withAlphaComponent(0.3)]
        textView.linkTextAttributes = [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .cursor: NSCursor.pointingHand]
        dots.selected = index
        updateCounter()
        window.title = "Puntos · \(NotesStore.colorNames[index])"
    }

    func refreshDots() {
        dots.filled = store.texts.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func restyle() {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        MarkdownStyler.apply(to: storage, fontSize: fontSize, accent: accent)
        storage.endEditing()
        textView.typingAttributes = MarkdownStyler.baseAttributes(fontSize: fontSize)
    }

    private func updateCounter() {
        let text = textView.string
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        counter.stringValue = "\(words) \(words == 1 ? "palabra" : "palabras") · \(text.count) caracteres"
    }

    // MARK: Delegados

    func textDidChange(_ notification: Notification) {
        guard !loading else { return }
        store.update(store.selected, text: textView.string)
        updateCounter()
    }

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            MarkdownStyler.apply(to: textStorage, fontSize: fontSize, accent: accent)
        }
    }

    /// Intro en una lista continúa la lista con la misma viñeta (o la termina si la línea está vacía).
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let text = textView.string as NSString
        let caret = textView.selectedRange().location
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let current = text.substring(with: NSRange(location: line.location, length: caret - line.location))
        guard let match = try? NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d+\.)([ \t]\[[ xX]\])?[ \t]"#)
            .firstMatch(in: current, range: NSRange(location: 0, length: (current as NSString).length)) else { return false }
        let prefix = (current as NSString).substring(with: match.range)
        if (current as NSString).length == match.range.length {
            // Línea de lista vacía: se quita la viñeta.
            let range = NSRange(location: line.location, length: match.range.length)
            if textView.shouldChangeText(in: range, replacementString: "") {
                textView.replaceCharacters(in: range, with: "")
                textView.didChangeText()
            }
            return true
        }
        var next = prefix.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
        let number = (current as NSString).substring(with: match.range(at: 2))
        if let n = Int(number.dropLast()) { next = next.replacingOccurrences(of: number, with: "\(n + 1).") }
        textView.insertText("\n" + next, replacementRange: textView.selectedRange())
        return true
    }

    // MARK: Acciones

    @objc func copyNote() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        counter.stringValue = "Nota copiada"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.updateCounter() }
    }

    /// Rodea la selección con un marcador de Markdown (o lo inserta doble con el cursor en medio).
    func wrapSelection(with marker: String) {
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        let replacement = marker + selected + marker
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        let length = (marker as NSString).length
        textView.setSelectedRange(NSRange(location: range.location + length, length: (selected as NSString).length))
    }

    func changeFontSize(by delta: CGFloat) {
        fontSize = min(max(fontSize + delta, 11), 28)
        restyle()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    var isFrontmost: Bool { window.isVisible && window.isKeyWindow && NSApp.isActive }
}
