import AppKit
import CoreImage
import UniformTypeIdentifiers

/// Estado del editor: la foto abierta, sus ajustes y la vista previa.
@MainActor
final class EditorModel: ObservableObject {
    @Published private(set) var photo: Photo?
    @Published var adjustments = Adjustments() {
        didSet {
            guard adjustments != oldValue else { return }
            recordUndo(oldValue)
            if adjustments.usesSubjectMask, mask == nil { computeMask() }
            if adjustments.usesFaces, faces == nil { detectFaces() }
            if adjustments.usesDepth, depth == nil { computeDepth() }
            scheduleRender()
            saveEdits()
        }
    }
    @Published private(set) var rendered: CGImage?
    @Published private(set) var original: CGImage?
    @Published var showOriginal = false
    @Published private(set) var status: String?
    @Published private(set) var busy: String?
    @Published private(set) var importedLooks = Looks.imported()
    @Published var exportFormat = Exporter.Format(rawValue: UserDefaults.standard.string(forKey: "formato") ?? "") ?? .jpeg {
        didSet { UserDefaults.standard.set(exportFormat.rawValue, forKey: "formato") }
    }
    @Published var exportQuality = UserDefaults.standard.object(forKey: "calidad") as? Double ?? 0.9 {
        didSet { UserDefaults.standard.set(exportQuality, forKey: "calidad") }
    }
    /// Estado de vista (sin @State: estas herramientas de compilación no traen sus macros).
    @Published var dropTargeted = false

    /// Todo el trabajo de imagen va por esta cola, de uno en uno.
    nonisolated static let queue = DispatchQueue(label: "revela.render", qos: .userInitiated)
    nonisolated static let context = CIContext(options: [.cacheIntermediates: false])

    private var mask: CIImage?
    private var computingMask = false
    private var faces: FaceMasks?
    private var detectingFaces = false
    private var depth: DepthInfo?
    private var computingDepth = false
    @Published private(set) var depthInstalled = DepthModel.isInstalled
    private var rendering = false
    private var renderAgain = false
    private var undoStack: [Adjustments] = []
    private var lastUndoTime = Date.distantPast
    private var restoring = false

    var canUndo: Bool { !undoStack.isEmpty }

    // MARK: Abrir

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Photo.openableTypes
        panel.message = "Elige una foto (JPEG, HEIC, PNG, TIFF o RAW)"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        busy = "Abriendo \(url.lastPathComponent)…"
        Self.queue.async {
            let result = Result { try Photo(url: url) }
            let original = (try? result.get()).flatMap { Self.context.createCGImage($0.preview, from: $0.preview.extent) }
            DispatchQueue.main.async {
                self.busy = nil
                switch result {
                case .success(let photo):
                    self.photo = photo
                    self.original = original
                    self.mask = nil
                    self.faces = nil
                    self.depth = nil
                    self.undoStack = []
                    self.restoring = true
                    self.adjustments = EditStore.load(for: url) ?? Adjustments()
                    self.restoring = false
                    self.status = "\(Int(photo.fullSize.width)) × \(Int(photo.fullSize.height))" + (photo.isRAW ? " · RAW" : "")
                    if self.adjustments.usesSubjectMask { self.computeMask() }
                    if self.adjustments.usesFaces { self.detectFaces() }
                    if self.adjustments.usesDepth { self.computeDepth() }
                    self.scheduleRender()
                case .failure(let error):
                    self.status = error.localizedDescription
                }
            }
        }
    }

    // MARK: Vista previa

    func scheduleRender() {
        guard let photo else { return }
        if rendering { renderAgain = true; return }
        rendering = true
        let adjustments = adjustments, mask = mask, faces = faces, depth = depth
        Self.queue.async {
            let output = Develop.apply(adjustments, to: photo.preview, mask: mask, faces: faces, depth: depth,
                                       scale: photo.previewScale)
            let image = Self.context.createCGImage(output, from: output.extent)
            DispatchQueue.main.async {
                self.rendered = image
                self.rendering = false
                if self.renderAgain {
                    self.renderAgain = false
                    self.scheduleRender()
                }
            }
        }
    }

    // MARK: IA

    private func computeMask() {
        guard let photo, !computingMask else { return }
        computingMask = true
        busy = "Buscando el sujeto…"
        Self.queue.async {
            let mask = Intelligence.subjectMask(for: photo.preview, context: Self.context)
            DispatchQueue.main.async {
                self.computingMask = false
                self.busy = nil
                guard self.photo === photo else { return }
                self.mask = mask
                if mask == nil { self.status = "No se encontró un sujeto claro en esta foto." }
                self.scheduleRender()
            }
        }
    }

    private func detectFaces() {
        guard let photo, !detectingFaces else { return }
        detectingFaces = true
        busy = "Buscando caras…"
        Self.queue.async {
            let faces = FaceMasks.detect(in: photo.preview, context: Self.context)
            DispatchQueue.main.async {
                self.detectingFaces = false
                self.busy = nil
                guard self.photo === photo else { return }
                self.faces = faces
                self.status = faces.map { $0.count == 1 ? "1 cara encontrada" : "\($0.count) caras encontradas" }
                    ?? "No se encontraron caras en esta foto."
                self.scheduleRender()
            }
        }
    }

    /// Profundidad de la foto (y el sujeto, para saber dónde enfocar).
    private func computeDepth() {
        guard let photo, depthInstalled, !computingDepth else { return }
        computingDepth = true
        busy = "Calculando la profundidad…"
        let knownMask = mask
        Self.queue.async {
            let mask = knownMask ?? Intelligence.subjectMask(for: photo.preview, context: Self.context)
            let depth = DepthInfo.compute(for: photo.preview, subject: mask, context: Self.context)
            DispatchQueue.main.async {
                self.computingDepth = false
                self.busy = nil
                guard self.photo === photo else { return }
                if self.mask == nil { self.mask = mask }
                self.depth = depth
                if depth == nil { self.status = "No se pudo calcular la profundidad de esta foto." }
                self.scheduleRender()
            }
        }
    }

    /// Descarga el modelo de profundidad (una sola vez, ~50 MB).
    func installDepthModel() {
        busy = "Descargando el modelo de profundidad… 0 %"
        Self.queue.async {
            let result = Result {
                try DepthModel.install { progress in
                    DispatchQueue.main.async { self.busy = "Descargando el modelo de profundidad… \(Int(progress * 100)) %" }
                }
            }
            DispatchQueue.main.async {
                self.busy = nil
                switch result {
                case .success:
                    self.depthInstalled = true
                    self.status = "Modelo de profundidad instalado"
                    if self.adjustments.usesDepth { self.computeDepth() }
                case .failure(let error):
                    self.status = "No se pudo descargar el modelo: \(error.localizedDescription)"
                }
            }
        }
    }

    func straightenHorizon() {
        guard let photo else { return }
        busy = "Buscando el horizonte…"
        Self.queue.async {
            let angle = Intelligence.horizonCorrection(for: photo.preview, context: Self.context)
            DispatchQueue.main.async {
                self.busy = nil
                if let angle {
                    self.adjustments.straighten = (angle * 10).rounded() / 10
                    self.status = String(format: "Horizonte enderezado %.1f°", angle)
                } else {
                    self.status = "El horizonte ya está recto o no se encontró uno claro."
                }
            }
        }
    }

    // MARK: Looks

    func importCube() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cube") ?? .data]
        panel.allowsMultipleSelection = true
        panel.message = "Elige uno o varios LUT .cube"
        guard panel.runModal() == .OK else { return }
        var last: Looks.Look?
        for url in panel.urls {
            do { last = try Looks.importCube(url) } catch { status = error.localizedDescription }
        }
        importedLooks = Looks.imported()
        if let last { adjustments.look = last.id }
    }

    // MARK: Deshacer y restablecer

    private func recordUndo(_ previous: Adjustments) {
        guard !restoring else { return }
        // Mover un control genera muchos cambios: se agrupan los que llegan seguidos.
        if Date().timeIntervalSince(lastUndoTime) > 0.6 { undoStack.append(previous) }
        lastUndoTime = Date()
        if undoStack.count > 100 { undoStack.removeFirst() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        restoring = true
        adjustments = previous
        restoring = false
    }

    func reset() { adjustments = Adjustments() }

    private func saveEdits() {
        guard let photo, !restoring else { return }
        EditStore.save(adjustments, for: photo.url)
    }

    // MARK: Exportar

    func export() {
        guard let photo else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: exportFormat.fileExtension) ?? .image]
        panel.nameFieldStringValue = photo.url.deletingPathExtension().lastPathComponent + "-revelada." + exportFormat.fileExtension
        panel.directoryURL = photo.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run(photos: [photo.url], to: { _ in url })
    }

    /// Aplica los ajustes actuales a varias fotos y las guarda en una carpeta.
    func exportBatch() {
        let open = NSOpenPanel()
        open.allowedContentTypes = Photo.openableTypes
        open.allowsMultipleSelection = true
        open.message = "Elige las fotos a las que aplicar estos mismos ajustes"
        guard open.runModal() == .OK, !open.urls.isEmpty else { return }
        let folder = NSOpenPanel()
        folder.canChooseDirectories = true
        folder.canChooseFiles = false
        folder.canCreateDirectories = true
        folder.prompt = "Guardar aquí"
        folder.message = "¿Dónde se guardan las \(open.urls.count) fotos reveladas?"
        guard folder.runModal() == .OK, let destination = folder.url else { return }
        let ext = exportFormat.fileExtension
        run(photos: open.urls) { source in
            destination.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-revelada." + ext)
        }
    }

    private func run(photos: [URL], to destination: @escaping (URL) -> URL) {
        let adjustments = adjustments, format = exportFormat, quality = exportQuality
        busy = photos.count == 1 ? "Exportando…" : "Exportando 1 de \(photos.count)…"
        Self.queue.async {
            var failures: [String] = []
            for (index, url) in photos.enumerated() {
                DispatchQueue.main.async { if photos.count > 1 { self.busy = "Exportando \(index + 1) de \(photos.count)…" } }
                do {
                    let photo = try Photo(url: url)
                    try Exporter.export(photo, adjustments: adjustments, to: destination(url), format: format,
                                        quality: quality, context: Self.context)
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }
            DispatchQueue.main.async {
                self.busy = nil
                let done = photos.count - failures.count
                self.status = failures.isEmpty
                    ? (done == 1 ? "Foto exportada" : "\(done) fotos exportadas")
                    : "Exportadas \(done) de \(photos.count). Fallaron: \(failures.joined(separator: ", "))"
                if done > 0 {
                    NSWorkspace.shared.activateFileViewerSelecting(photos.prefix(1).map(destination))
                }
            }
        }
    }
}

/// Ajustes de cada foto en ~/Library/Application Support/Revela/ediciones.json (la foto no se toca).
enum EditStore {
    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Revela")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("ediciones.json")
    }

    private static var all: [String: Adjustments] = {
        (try? JSONDecoder().decode([String: Adjustments].self, from: Data(contentsOf: file))) ?? [:]
    }()

    static func load(for url: URL) -> Adjustments? { all[url.path] }

    static func save(_ adjustments: Adjustments, for url: URL) {
        all[url.path] = adjustments == .neutral ? nil : adjustments
        try? JSONEncoder().encode(all).write(to: file, options: .atomic)
    }
}
