import AppKit
import Quartz
import SwiftUI

/// Estado de la ventana de un comprimido.
final class ArchiveModel: ObservableObject {
    let url: URL
    @Published var listing: ArchiveListing?
    @Published var query = ""
    @Published var selection = Set<Int>()
    var password: String?

    init(url: URL) { self.url = url }

    var visibleItems: [ArchiveItem] {
        guard let items = listing?.items else { return [] }
        guard !query.isEmpty else { return items }
        return items.filter { $0.path.localizedStandardContains(query) }
    }

    /// Índices seleccionados más todo lo que hay dentro de las carpetas seleccionadas.
    var selectionWithChildren: Set<Int> {
        guard let items = listing?.items else { return selection }
        var result = selection
        for item in items where selection.contains(item.id) && item.isDirectory {
            let prefix = item.path.hasSuffix("/") ? item.path : item.path + "/"
            items.filter { $0.path.hasPrefix(prefix) }.forEach { result.insert($0.id) }
        }
        return result
    }
}

@MainActor
final class ArchiveWindowController: NSWindowController, NSWindowDelegate, QLPreviewPanelDataSource {
    private static var open: [ArchiveWindowController] = []

    let model: ArchiveModel
    private var previewURLs: [URL] = []
    private let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("Compresor-\(UUID().uuidString)")

    static func show(_ url: URL) {
        if let existing = open.first(where: { $0.model.url == url }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = ArchiveWindowController(url: url)
        open.append(controller)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.load()
    }

    private init(url: URL) {
        model = ArchiveModel(url: url)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        window.representedURL = url
        window.minSize = NSSize(width: 520, height: 320)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("ArchiveWindow")
        let view = ArchiveView(model: model,
                               onExtractHere: { [weak self] in self?.extractHere() },
                               onExtractTo: { [weak self] in self?.extractTo() },
                               onPreview: { [weak self] in self?.togglePreview() },
                               onOpenItem: { [weak self] id in self?.openItem(id) })
        window.contentView = NSHostingView(rootView: view)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func load() {
        let url = model.url
        Operation.run("Leyendo \(url.lastPathComponent)", work: { _ in try ArchiveEngine.list(url) }) { [weak self] result in
            switch result {
            case .success(let listing): self?.model.listing = listing
            case .failure(let error):
                Operation.report(error)
                self?.close()
            }
        }
    }

    // MARK: Extraer

    private func extractHere() {
        let url = model.url
        let selection = model.selection.isEmpty ? nil : model.selectionWithChildren
        if let selection {
            extract(selection, to: ArchiveEngine.uniqueURL(in: url.deletingLastPathComponent(),
                                                     name: ArchiveEngine.baseName(url), extension: nil))
            return
        }
        Operation.extractAsking(url, password: model.password, work: { password, progress in
            try ArchiveActions.extractHere(url, password: password, progress: progress)
        }) { [weak self] result, password in
            self?.model.password = password
            if let result { NSWorkspace.shared.activateFileViewerSelecting([result]) }
        }
    }

    private func extractTo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Extraer aquí"
        panel.directoryURL = model.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let target = ArchiveEngine.uniqueURL(in: folder, name: ArchiveEngine.baseName(model.url), extension: nil)
        extract(model.selection.isEmpty ? nil : model.selectionWithChildren, to: target)
    }

    private func extract(_ only: Set<Int>?, to target: URL) {
        let url = model.url
        Operation.extractAsking(url, password: model.password, work: { password, progress in
            try ArchiveEngine.extract(url, to: target, only: only, password: password, progress: progress)
            return target
        }) { [weak self] result, password in
            self?.model.password = password
            if let result { NSWorkspace.shared.activateFileViewerSelecting([result]) }
        }
    }

    /// Extrae a una carpeta temporal los elementos indicados (para abrirlos o previsualizarlos).
    private func extractTemporarily(_ ids: Set<Int>, then: @escaping ([URL]) -> Void) {
        guard let items = model.listing?.items else { return }
        let files = items.filter { ids.contains($0.id) && !$0.isDirectory }
        guard !files.isEmpty else { return }
        let url = model.url
        let folder = tempFolder.appendingPathComponent(UUID().uuidString)
        Operation.extractAsking(url, password: model.password, work: { password, progress in
            try ArchiveEngine.extract(url, to: folder, only: Set(files.map(\.id)), password: password, progress: progress)
            return folder
        }) { [weak self] folder, password in
            self?.model.password = password
            guard let folder else { return }
            then(files.compactMap { ArchiveEngine.safeRelativePath($0.path).map { folder.appendingPathComponent($0) } })
        }
    }

    private func openItem(_ id: Int) {
        guard let item = model.listing?.items.first(where: { $0.id == id }) else { return }
        if item.isDirectory {
            model.query = item.path
            return
        }
        extractTemporarily([id]) { urls in urls.forEach { NSWorkspace.shared.open($0) } }
    }

    // MARK: Vista rápida

    private func togglePreview() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
            return
        }
        extractTemporarily(model.selection) { [weak self] urls in
            self?.previewURLs = urls
            self?.window?.makeFirstResponder(nil)
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { previewURLs.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { previewURLs[index] as NSURL }
    }

    func windowWillClose(_ notification: Notification) {
        try? FileManager.default.removeItem(at: tempFolder)
        Self.open.removeAll { $0 === self }
    }
}

// MARK: - Vista

private struct ArchiveView: View {
    @ObservedObject var model: ArchiveModel
    let onExtractHere: () -> Void
    let onExtractTo: () -> Void
    let onPreview: () -> Void
    let onOpenItem: (Int) -> Void

    private let dateFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated).year().hour().minute()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onExtractHere) {
                    Label(model.selection.isEmpty ? "Extraer todo" : "Extraer selección", systemImage: "arrow.down.doc")
                }
                .keyboardShortcut("e", modifiers: .command)
                .help("Extrae junto al comprimido (⌘E)")
                Button(action: onExtractTo) { Label("Extraer en…", systemImage: "folder") }
                    .help("Elige la carpeta de destino")
                Button(action: onPreview) { Label("Vista rápida", systemImage: "eye") }
                    .keyboardShortcut("y", modifiers: .command)
                    .disabled(model.selection.isEmpty)
                    .help("Previsualiza lo seleccionado (⌘Y)")
                Spacer()
                TextField("Buscar", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            .padding(10)
            Divider()

            if model.listing == nil {
                SwiftUI.ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.visibleItems, selection: $model.selection) {
                    TableColumn("Nombre") { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                                .foregroundStyle(item.isDirectory ? Color.accentColor : .secondary)
                            Text(item.path).lineLimit(1).truncationMode(.middle)
                            if item.encrypted { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                        }
                    }
                    TableColumn("Tamaño") { item in
                        Text(item.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: item.size ?? 0, countStyle: .file))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(90)
                    TableColumn("Modificado") { item in
                        Text(item.modified.map { $0.formatted(dateFormat) } ?? "").foregroundStyle(.secondary)
                    }
                    .width(150)
                }
                .contextMenu(forSelectionType: Int.self) { _ in
                    Button("Abrir", action: { model.selection.first.map(onOpenItem) })
                    Button("Vista rápida", action: onPreview)
                    Button("Extraer selección", action: onExtractHere)
                } primaryAction: { ids in
                    ids.first.map(onOpenItem)
                }
            }

            Divider()
            HStack {
                if let listing = model.listing {
                    let files = listing.items.filter { !$0.isDirectory }.count
                    Text("\(files) archivos · \(ByteCountFormatter.string(fromByteCount: listing.totalSize, countStyle: .file)) sin comprimir · \(listing.format)")
                    if listing.hasEncryptedItems { Label("Con contraseña", systemImage: "lock.fill") }
                }
                Spacer()
                if !model.selection.isEmpty { Text("\(model.selection.count) seleccionados") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
