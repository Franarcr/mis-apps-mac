import AppKit
import SwiftUI

/// Editor de código basado en NSTextView: colores, números de línea, sangría automática y barra de búsqueda.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var model: DocModel
    @AppStorage("tamanoLetra") private var fontSize: Double = 13
    @AppStorage("ajustarLineas") private var wrapLines = true

    var font: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        let tv = NSTextView(frame: .zero, textContainer: container)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.backgroundColor = .textBackgroundColor
        tv.insertionPointColor = .controlAccentColor
        tv.font = font
        tv.string = text
        tv.delegate = context.coordinator
        scroll.documentView = tv
        let ruler = LineNumberRuler(textView: tv)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.ruler = ruler
        applyWrap(tv, scroll)

        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.didScroll(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)

        model.textView = tv
        context.coordinator.applied = (fontSize, model.lang, model.highlight, wrapLines)
        context.coordinator.rehighlight(tv)
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        model.textView = tv
        var needsHighlight = false
        if tv.string != text {
            tv.string = text
            needsHighlight = true
        }
        let current = (fontSize, model.lang, model.highlight, wrapLines)
        if context.coordinator.applied != current {
            if context.coordinator.applied.3 != wrapLines { applyWrap(tv, scroll) }
            context.coordinator.applied = current
            tv.font = font
            needsHighlight = true
        }
        if needsHighlight {
            context.coordinator.rehighlight(tv)
            context.coordinator.ruler?.invalidateLines()
        }
    }

    private func applyWrap(_ tv: NSTextView, _ scroll: NSScrollView) {
        guard let container = tv.textContainer else { return }
        if wrapLines {
            scroll.hasHorizontalScroller = false
            tv.isHorizontallyResizable = false
            tv.autoresizingMask = [.width]
            container.widthTracksTextView = true
            tv.setFrameOrigin(.zero)
            tv.setFrameSize(NSSize(width: scroll.contentSize.width, height: tv.frame.height))
        } else {
            scroll.hasHorizontalScroller = true
            container.widthTracksTextView = false
            tv.isHorizontallyResizable = true
            tv.autoresizingMask = []
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var ruler: LineNumberRuler?
        var applied: (Double, Lang, Bool, Bool) = (0, .html, true, true)

        init(_ parent: CodeEditor) { self.parent = parent }

        func rehighlight(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let sel = tv.selectedRanges
            Highlighter.highlight(storage, lang: parent.model.lang, font: parent.font, enabled: parent.model.highlight)
            tv.selectedRanges = sel
            tv.typingAttributes = [.font: parent.font, .foregroundColor: NSColor.textColor]
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let s = tv.string
            parent.text = s
            rehighlight(tv)
            ruler?.invalidateLines()
            MainActor.assumeIsolated { parent.model.textDidChange(s) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let loc = tv.selectedRange().location
            MainActor.assumeIsolated { parent.model.selectionChanged(location: loc) }
        }

        /// Al pulsar Intro se mantiene la sangría de la línea anterior.
        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let ns = tv.string as NSString
                let sel = tv.selectedRange()
                let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
                let lineText = ns.substring(with: NSRange(location: lineRange.location, length: sel.location - lineRange.location))
                let indent = String(lineText.prefix { $0 == " " || $0 == "\t" })
                tv.insertText("\n" + indent, replacementRange: sel)
                return true
            }
            return false
        }

        @objc func didScroll(_ note: Notification) {
            guard let clip = note.object as? NSClipView, let doc = clip.documentView else { return }
            ruler?.needsDisplay = true
            let range = doc.frame.height - clip.bounds.height
            let fraction = range > 0 ? Double(clip.bounds.minY / range) : 0
            MainActor.assumeIsolated { parent.model.editorScrolled(fraction: fraction) }
        }
    }
}

/// Columna con los números de línea a la izquierda del editor.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int]?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
    }

    required init(coder: NSCoder) { fatalError() }

    func invalidateLines() {
        lineStarts = nil
        let digits = max(3, String(LineIndex(textView?.string ?? "").count).count)
        let width = CGFloat(digits) * 8 + 16
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        if lineStarts == nil { lineStarts = LineIndex(tv.string).starts }
        guard let starts = lineStarts else { return }
        let ns = tv.string as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(9, (tv.font?.pointSize ?? 13) - 2), weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let visible = tv.visibleRect
        let inset = tv.textContainerInset.height
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)

        // Primera línea visible por búsqueda binaria.
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= chars.location { lo = mid } else { hi = mid - 1 }
        }
        var lineIdx = lo
        while lineIdx < starts.count {
            let start = starts[lineIdx]
            if start > NSMaxRange(chars) { break }
            var y: CGFloat
            if start >= ns.length {
                guard ns.length == 0 || ns.character(at: ns.length - 1) == 10 else { break }
                y = lm.extraLineFragmentRect.minY
                if ns.length == 0 { y = 0 }
            } else {
                let g = lm.glyphIndexForCharacter(at: start)
                y = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).minY
            }
            let p = convert(NSPoint(x: 0, y: y + inset), from: tv)
            let label = "\(lineIdx + 1)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: p.y + 2), withAttributes: attrs)
            lineIdx += 1
        }
    }
}
