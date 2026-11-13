import AppKit
import SwiftUI
import WebKit

enum RefreshMode: String, CaseIterable, Identifiable {
    case instant, delayed, manual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .instant: return "Al instante"
        case .delayed: return "Con espera"
        case .manual: return "A mano"
        }
    }
}

/// Ancho con el que se dibuja la página: así se ven los menús de escritorio aunque la vista previa sea estrecha.
enum PageWidth: Int, CaseIterable, Identifiable {
    case fit = 0, desktop = 1280, laptop = 1024, tablet = 768, phone = 390
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .fit: return "Igual que el panel"
        case .desktop: return "Escritorio (1280 px)"
        case .laptop: return "Portátil (1024 px)"
        case .tablet: return "Tablet (768 px)"
        case .phone: return "Móvil (390 px)"
        }
    }
    var symbol: String {
        switch self {
        case .fit: return "arrow.left.and.right"
        case .desktop: return "desktopcomputer"
        case .laptop: return "laptopcomputer"
        case .tablet: return "ipad"
        case .phone: return "iphone"
        }
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case options, snippets, files, problems, console
    var id: String { rawValue }
    var title: String {
        switch self {
        case .options: return "Opciones"
        case .snippets: return "Fragmentos"
        case .files: return "Archivos"
        case .problems: return "Problemas"
        case .console: return "Consola"
        }
    }
    var symbol: String {
        switch self {
        case .options: return "slider.horizontal.3"
        case .snippets: return "text.badge.plus"
        case .files: return "doc.on.doc"
        case .problems: return "exclamationmark.triangle"
        case .console: return "terminal"
        }
    }
}

struct ConsoleLine: Identifiable {
    let id = UUID()
    var kind: String
    var text: String
}

struct LinkedFile: Identifiable, Hashable {
    var id: URL { url }
    var url: URL
    var manual: Bool
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// Estado de una ventana de Batido: modo, vista previa, archivos vinculados, problemas y consola.
@MainActor
final class DocModel: ObservableObject {
    // Ajustes del documento
    @Published var modeChoice: Lang? = nil { didSet { modeDidChange() } }
    @Published var refreshMode: RefreshMode
    @Published var delay: Double
    @Published var highlight = true
    @Published var syncScroll = false
    @Published var liveValidation = true { didSet { validate() } }
    @Published var zoom: Double = 1 { didSet { hosts.allObjects.forEach { $0.applyZoom() } } }
    @Published var pageWidth: PageWidth { didSet { hosts.allObjects.forEach { $0.applyZoom() } } }

    // Disposición
    @Published var panoramic = false
    @Published var showEditor = true
    @Published var showPreview = true
    @Published var showInspector = true
    @Published var inspectorTab: InspectorTab = .options
    @Published var detached = false
    @Published var showGoToLine = false
    @Published var showNewSnippet = false

    // Resultados
    @Published var problems: [Problem] = []
    @Published var runtimeProblems: [Problem] = []
    @Published var console: [ConsoleLine] = []
    @Published var linked: [LinkedFile] = []
    @Published var phpOutput = ""
    @Published var line = 1
    @Published var column = 1
    @Published var dirtyPreview = false

    private(set) var text = ""
    private(set) var fileURL: URL?
    weak var textView: NSTextView?

    private let hosts = NSHashTable<PreviewHost>.weakObjects()
    private var renderWork: DispatchWorkItem?
    private var validateWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var mtimes: [URL: Date] = [:]
    private var manualLinks: [URL] = []
    private var generation = 0
    private var currentPreview: URL?
    private var detachedWindow: NSWindow?
    private var windowDelegate: WindowCloseDelegate?
    private let previewDir: URL
    private var problemCursor = -1

    var lang: Lang { modeChoice ?? Lang.from(url: fileURL) }
    var allProblems: [Problem] { problems + runtimeProblems }
    var displayName: String { fileURL?.lastPathComponent ?? "Sin título" }

    init() {
        let d = UserDefaults.standard
        refreshMode = RefreshMode(rawValue: d.string(forKey: "refrescoPorOmision") ?? "") ?? .instant
        delay = d.object(forKey: "esperaPorOmision") as? Double ?? 0.5
        pageWidth = PageWidth(rawValue: d.object(forKey: "anchoPagina") as? Int ?? PageWidth.laptop.rawValue) ?? .laptop
        previewDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Batido", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: previewDir)
    }

    func setup(text: String, fileURL: URL?) {
        self.text = text
        self.fileURL = fileURL
        updateLinks()
        validate()
        render()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollLinkedFiles() }
        }
    }

    func fileURLChanged(_ url: URL?) {
        fileURL = url
        updateLinks()
        modeDidChange()
    }

    func close() {
        pollTimer?.invalidate()
        detachedWindow?.close()
    }

    // MARK: Cambios del texto

    func textDidChange(_ newText: String) {
        text = newText
        if liveValidation { scheduleValidation() }
        switch refreshMode {
        case .instant: scheduleRender(after: 0.12)
        case .delayed: scheduleRender(after: delay)
        case .manual: dirtyPreview = true
        }
    }

    private func modeDidChange() {
        validate()
        render()
        objectWillChange.send()
    }

    private func scheduleRender(after seconds: Double) {
        renderWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.render() }
        }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func scheduleValidation() {
        validateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.validate()
                self?.updateLinks()
            }
        }
        validateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func validate() {
        problems = liveValidation ? Validator.validate(text, lang: lang) : []
    }

    func validateNow() {
        problems = Validator.validate(text, lang: lang)
        inspectorTab = .problems
        showInspector = true
    }

    // MARK: Vista previa

    func register(_ host: PreviewHost) {
        hosts.add(host)
        host.applyZoom()
        if let currentPreview { host.load(currentPreview, readAccess: URL(fileURLWithPath: "/")) }
    }

    func render() {
        renderWork?.cancel()
        dirtyPreview = false
        generation += 1
        let gen = generation
        let source = text
        let lang = self.lang
        let dir = fileURL?.deletingLastPathComponent()
        if lang == .php {
            let path = UserDefaults.standard.string(forKey: "rutaPHP") ?? ""
            Task.detached {
                let output = PHPRunner.run(source, workingDirectory: dir, customPath: path)
                await MainActor.run {
                    guard gen == self.generation else { return }
                    self.phpOutput = output.text
                    self.runtimeProblems = output.problems
                    self.show(html: output.html, gen: gen)
                }
            }
        } else {
            show(html: PreviewBuilder.page(for: source, lang: lang), gen: gen)
        }
    }

    private func show(html: String, gen: Int) {
        var page = html
        if let dir = fileURL?.deletingLastPathComponent() {
            page = PreviewBuilder.addBase(dir, to: page)
        }
        let url = previewDir.appendingPathComponent("vista-\(gen).html")
        do {
            try page.write(to: url, atomically: true, encoding: .utf8)
        } catch { return }
        if let old = currentPreview { try? FileManager.default.removeItem(at: old) }
        currentPreview = url
        console.removeAll()
        if lang != .php { runtimeProblems.removeAll() }
        for host in hosts.allObjects {
            host.load(url, readAccess: URL(fileURLWithPath: "/"))
        }
    }

    func receive(kind: String, message: String, line: Int?) {
        console.append(ConsoleLine(kind: kind, text: message))
        if console.count > 500 { console.removeFirst(console.count - 500) }
        if kind == "error" {
            runtimeProblems.append(Problem(kind: .error, message: message, line: line ?? 0, column: 1, source: "Vista previa"))
        }
    }

    /// Zoom real: el que elige Fran por el ancho de página. En escritorio solo se reduce (nunca agranda).
    func effectiveZoom(paneWidth: Double) -> Double {
        guard pageWidth != .fit, paneWidth > 50 else { return zoom }
        let ratio = paneWidth / Double(pageWidth.rawValue)
        let fit = pageWidth.rawValue >= 1024 ? min(1, ratio) : ratio
        return max(0.25, fit * zoom)
    }

    func editorScrolled(fraction: Double) {
        guard syncScroll else { return }
        let f = max(0, min(1, fraction))
        for host in hosts.allObjects {
            host.webView.evaluateJavaScript(
                "window.scrollTo(0, \(f) * (document.documentElement.scrollHeight - window.innerHeight))")
        }
    }

    func toggleDetached() {
        if let w = detachedWindow {
            w.close()
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Vista previa — \(displayName)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: PreviewView(model: self))
        let delegate = WindowCloseDelegate { [weak self] in
            self?.detachedWindow = nil
            self?.detached = false
        }
        windowDelegate = delegate
        w.delegate = delegate
        w.center()
        w.makeKeyAndOrderFront(nil)
        detachedWindow = w
        detached = true
    }

    // MARK: Navegadores

    static let browserIDs: [(id: String, name: String)] = [
        ("com.apple.Safari", "Safari"), ("com.google.Chrome", "Chrome"), ("org.mozilla.firefox", "Firefox"),
        ("com.microsoft.edgemac", "Edge"), ("com.brave.Browser", "Brave"), ("company.thebrowser.Browser", "Arc"),
    ]

    static var installedBrowsers: [(name: String, url: URL)] {
        browserIDs.compactMap { b in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.id).map { (b.name, $0) }
        }
    }

    func openInBrowser(_ app: URL?) {
        var target: URL? = currentPreview
        // Si el archivo guardado coincide con lo que hay en pantalla, se abre el original.
        if lang == .html, let fileURL, let saved = try? String(contentsOf: fileURL, encoding: .utf8), saved == text {
            target = fileURL
        }
        guard let target else { return }
        if let app {
            NSWorkspace.shared.open([target], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    // MARK: Archivos vinculados

    func updateLinks() {
        var urls: [URL] = []
        if let dir = fileURL?.deletingLastPathComponent() {
            let re = Highlighter.re(#"(?:href|src)\s*=\s*["']([^"'#?]+)"#)
            re.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { m, _, _ in
                guard let r = m?.range(at: 1) else { return }
                let ref = (self.text as NSString).substring(with: r).trimmingCharacters(in: .whitespaces)
                let lower = ref.lowercased()
                if ref.isEmpty || lower.contains(":") || lower.hasPrefix("//") { return }
                let url = ref.hasPrefix("/") ? URL(fileURLWithPath: ref)
                    : URL(fileURLWithPath: ref.removingPercentEncoding ?? ref, relativeTo: dir).standardizedFileURL
                if !urls.contains(url) { urls.append(url) }
            }
        }
        let list = urls.map { LinkedFile(url: $0, manual: false) }
            + manualLinks.filter { !urls.contains($0) }.map { LinkedFile(url: $0, manual: true) }
        if list != linked { linked = list }
    }

    func addLinkedFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.message = "Elige archivos que Batido debe vigilar para recargar la vista previa"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !manualLinks.contains(url) { manualLinks.append(url) }
        updateLinks()
    }

    func removeLinked(_ file: LinkedFile) {
        manualLinks.removeAll { $0 == file.url }
        updateLinks()
    }

    private func pollLinkedFiles() {
        var changed = false
        for file in linked {
            let date = (try? file.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date {
                if let old = mtimes[file.url], old != date { changed = true }
                mtimes[file.url] = date
            }
        }
        if changed {
            if refreshMode == .manual { dirtyPreview = true } else { render() }
        }
    }

    // MARK: Edición

    func insert(_ snippet: Snippet) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: sel)
        var full = snippet.before + (snippet.replacesSelection ? "" : selected) + snippet.after
        var caret: Int
        if let r = full.range(of: "${caret}") {
            caret = full[..<r.lowerBound].utf16.count
            full.removeSubrange(r)
            full = full.replacingOccurrences(of: "${caret}", with: "")
        } else {
            caret = (snippet.before + (snippet.replacesSelection ? "" : selected)).utf16.count
        }
        replace(sel, with: full, in: tv)
        caret = min(caret, full.utf16.count)
        tv.setSelectedRange(NSRange(location: sel.location + caret, length: 0))
        tv.window?.makeFirstResponder(tv)
    }

    private func replace(_ range: NSRange, with string: String, in tv: NSTextView) {
        if tv.shouldChangeText(in: range, replacementString: string) {
            tv.textStorage?.replaceCharacters(in: range, with: string)
            tv.didChangeText()
        }
    }

    func transformSelection(_ f: (String) -> String) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { return }
        let new = f((tv.string as NSString).substring(with: sel))
        replace(sel, with: new, in: tv)
        tv.setSelectedRange(NSRange(location: sel.location, length: new.utf16.count))
    }

    func toggleComment() {
        guard let tv = textView else { return }
        var sel = tv.selectedRange()
        let ns = tv.string as NSString
        if sel.length == 0 { sel = ns.lineRange(for: sel) }
        var body = ns.substring(with: sel)
        var trailing = ""
        if body.hasSuffix("\n") { body.removeLast(); trailing = "\n" }
        let (open, close): (String, String) = {
            switch lang {
            case .html: return ("<!-- ", " -->")
            case .css, .js: return ("/* ", " */")
            case .php: return ("/* ", " */")
            }
        }()
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        let new: String
        if trimmed.hasPrefix(open.trimmingCharacters(in: .whitespaces)) && trimmed.hasSuffix(close.trimmingCharacters(in: .whitespaces)) {
            var t = trimmed
            t.removeFirst(open.trimmingCharacters(in: .whitespaces).count)
            t.removeLast(close.trimmingCharacters(in: .whitespaces).count)
            let lead = String(body.prefix { $0 == " " || $0 == "\t" })
            new = lead + t.trimmingCharacters(in: .whitespaces) + trailing
        } else {
            let lead = String(body.prefix { $0 == " " || $0 == "\t" })
            new = lead + open + body.dropFirst(lead.count) + close + trailing
        }
        replace(sel, with: new, in: tv)
        tv.setSelectedRange(NSRange(location: sel.location, length: new.utf16.count))
    }

    func goTo(line: Int, column: Int = 1) {
        guard let tv = textView else { return }
        let index = LineIndex(tv.string)
        let start = index.offset(ofLine: line)
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: min(start, ns.length), length: 0))
        let loc = min(start + max(0, column - 1), NSMaxRange(lineRange))
        tv.setSelectedRange(column > 1 ? NSRange(location: loc, length: 0) : lineRange)
        tv.scrollRangeToVisible(lineRange)
        tv.showFindIndicator(for: lineRange)
        tv.window?.makeFirstResponder(tv)
    }

    func jumpToProblem(forward: Bool) {
        let list = allProblems.filter { $0.line > 0 }
        guard !list.isEmpty else { NSSound.beep(); return }
        problemCursor = forward ? (problemCursor + 1) % list.count : (problemCursor - 1 + list.count) % list.count
        let p = list[problemCursor]
        goTo(line: p.line, column: p.column)
    }

    func selectionChanged(location: Int) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let loc = min(location, ns.length)
        var l = 1
        var lastStart = 0
        for i in 0..<loc where ns.character(at: i) == 10 {
            l += 1
            lastStart = i + 1
        }
        line = l
        column = loc - lastStart + 1
    }
}

final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
