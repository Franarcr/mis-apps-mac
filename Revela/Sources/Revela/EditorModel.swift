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
            // Al elegir otro cielo, se ve entero (si no, se quedaba con la intensidad del anterior).
            if adjustments.skyReplacement != oldValue.skyReplacement, adjustments.skyReplacement != nil, !restoring {
                adjustments.skyAmount = 100
                // Un cielo nuevo necesita algo de bruma en el horizonte para fundirse con lo lejano.
                if oldValue.skyReplacement == nil, adjustments.skyHaze == 0 { adjustments.skyHaze = 30 }
            }
            recordUndo(oldValue)
            if adjustments.usesSubjectMask, mask == nil { computeMask() }
            if adjustments.usesFaces, faces == nil { detectFaces() }
            if adjustments.usesDepth, depth == nil { computeDepth() }
            if adjustments.selection != oldValue.selection { updateSelectionMask() }
            if adjustments.erase != oldValue.erase { updateErased() }
            if adjustments.water != oldValue.water { updateWaterMask() }
            if adjustments.usesSky || adjustments.usesWater, skyMask == nil { computeSkyMask() }
            scheduleRender()
            saveEdits()
        }
    }
    @Published private(set) var rendered: CGImage?
    @Published private(set) var original: CGImage?
    @Published var showOriginal = false
    /// Secciones de ajustes plegadas (se recuerdan entre sesiones).
    @Published var collapsedSections = Set(UserDefaults.standard.stringArray(forKey: "seccionesPlegadas") ?? []) {
        didSet { if !EditStore.readOnly { UserDefaults.standard.set(Array(collapsedSections), forKey: "seccionesPlegadas") } }
    }
    @Published private(set) var status: String?
    @Published private(set) var busy: String?
    @Published private(set) var importedLooks = Looks.imported()
    @Published var exportFormat = Exporter.Format(rawValue: UserDefaults.standard.string(forKey: "formato") ?? "") ?? .jpeg {
        didSet { UserDefaults.standard.set(exportFormat.rawValue, forKey: "formato") }
    }
    @Published var exportQuality = UserDefaults.standard.object(forKey: "calidad") as? Double ?? 0.9 {
        didSet { UserDefaults.standard.set(exportQuality, forKey: "calidad") }
    }
    /// Ampliar al exportar: 1 = tamaño original, 2 o 4 con IA.
    @Published var exportUpscale = UserDefaults.standard.object(forKey: "ampliar") as? Int ?? 1 {
        didSet { UserDefaults.standard.set(exportUpscale, forKey: "ampliar") }
    }
    @Published private(set) var upscaleInstalled = UpscaleModel.isInstalled
    /// Ajustes copiados para pegarlos en otra foto (se conservan al cerrar la app).
    @Published private(set) var copied: Adjustments? = UserDefaults.standard.data(forKey: "ajustesCopiados")
        .flatMap { try? JSONDecoder().decode(Adjustments.self, from: $0) } {
        didSet { UserDefaults.standard.set(copied.flatMap { try? JSONEncoder().encode($0) }, forKey: "ajustesCopiados") }
    }
    @Published private(set) var mySkies = Skies.mine()
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
    @Published private(set) var segmentInstalled = SegmentModel.isInstalled
    /// Modo «seleccionar con un clic»: los clics en la foto añaden puntos y se ve la zona elegida.
    @Published var selecting = false {
        didSet { if selecting { erasing = false; markingWater = false }; scheduleRender() }
    }
    /// Modo «borrar objetos»: arrastrar sobre la foto pinta lo que se borra.
    @Published var erasing = false { didSet { if erasing { selecting = false; markingWater = false } } }
    /// Modo «marcar el agua»: los clics en la foto indican dónde está el agua.
    @Published var markingWater = false {
        didSet { if markingWater { selecting = false; erasing = false }; scheduleRender() }
    }
    private var waterMask: CIImage?
    @Published var brushSize = 3.0   // % del ancho de la foto
    /// Trazo en curso, en puntos de la vista (mientras se arrastra).
    @Published var currentStroke: [CGPoint] = []
    @Published private(set) var eraseInstalled = EraseModel.isInstalled
    /// La foto con lo pintado ya borrado (vista previa); nil si no hay nada borrado.
    private var erasedPreview: CIImage?
    private var embedding: SegmentModel.Embedding?
    private var selectionMask: CIImage?
    private var skyMask: CIImage?
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
        autoLightUndo = nil
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
                    self.embedding = nil
                    self.selectionMask = nil
                    self.skyMask = nil
                    self.erasedPreview = nil
                    self.waterMask = nil
                    self.markingWater = false
                    self.selecting = false
                    self.erasing = false
                    self.undoStack = []
                    self.restoring = true
                    self.adjustments = EditStore.load(for: url) ?? Adjustments()
                    self.restoring = false
                    self.status = "\(Int(photo.fullSize.width)) × \(Int(photo.fullSize.height))" + (photo.isRAW ? " · RAW" : "")
                    if self.adjustments.usesSubjectMask { self.computeMask() }
                    if self.adjustments.usesFaces { self.detectFaces() }
                    if self.adjustments.usesDepth { self.computeDepth() }
                    if self.adjustments.usesSelection { self.updateSelectionMask() }
                    if self.adjustments.usesSky || self.adjustments.usesWater { self.computeSkyMask() }
                    if !self.adjustments.erase.isEmpty { self.updateErased() }
                    if self.adjustments.usesWater { self.updateWaterMask() }
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
        let selection = selectionMask, sky = skyMask, water = waterMask
        let overlay = selecting ? selectionMask : markingWater ? waterMask : nil
        let overlayColor = markingWater ? CIColor(red: 0.1, green: 0.6, blue: 1, alpha: 0.45) : CIColor(red: 1, green: 0.45, blue: 0.1, alpha: 0.45)
        let base = erasedPreview ?? photo.preview
        Self.queue.async {
            var output = Develop.apply(adjustments, to: base, mask: mask, faces: faces, depth: depth,
                                       selection: selection, sky: sky, water: water, scale: photo.previewScale)
            if let overlay {
                // Mientras se selecciona, la zona elegida se tiñe de naranja.
                let tint = CIImage(color: overlayColor).cropped(to: output.extent)
                let tinted = tint.composited(over: output)
                output = Develop.blend(tinted, over: output, mask: overlay)
            }
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

    /// «Automático» de Luz: corrige los seis controles midiendo la foto revelada con el resto de ajustes.
    /// Pulsado otra vez (sin haber tocado la Luz entre medias), vuelve a los valores de antes.
    @Published var autoLighting = false
    private var autoLightUndo: (before: AutoLight.Values, applied: AutoLight.Values)?
    var autoLightApplied: Bool {
        guard let undo = autoLightUndo else { return false }
        return AutoLight.Values(adjustments) == undo.applied
    }
    func autoLight() {
        guard let photo, !autoLighting else { return }
        if autoLightApplied, let undo = autoLightUndo {
            var a = adjustments
            undo.before.apply(to: &a)
            autoLightUndo = nil
            adjustments = a
            return
        }
        autoLighting = true
        let start = adjustments, mask = mask, faces = faces, depth = depth
        let selection = selectionMask, sky = skyMask, water = waterMask
        let base = erasedPreview ?? photo.preview
        Self.queue.async {
            let result = AutoLight.adjust(start, render: { a in
                Develop.apply(a, to: base, mask: mask, faces: faces, depth: depth, selection: selection, sky: sky,
                              water: water, scale: photo.previewScale)
            }, context: Self.context)
            DispatchQueue.main.async {
                self.autoLighting = false
                // Solo cambia la sección Luz (si mientras tanto se tocó otra cosa, se respeta).
                var a = self.adjustments
                let before = AutoLight.Values(a)
                AutoLight.Values(result).apply(to: &a)
                self.autoLightUndo = (before, AutoLight.Values(a))
                self.adjustments = a
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
                    if self.adjustments.usesSelection { self.updateSelectionMask() }
                    if self.adjustments.usesSky || self.adjustments.usesWater { self.computeSkyMask() }
                case .failure(let error):
                    self.status = "No se pudo descargar el modelo: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Seleccionar con un clic (SAM 2.1)

    /// El codificador de SAM se ejecuta una vez por foto; luego cada clic tarda una décima.
    private func withEmbedding(_ work: @escaping (SegmentModel.Embedding, Photo) -> Void) {
        guard let photo, segmentInstalled else { return }
        if let embedding { Self.queue.async { work(embedding, photo) }; return }
        busy = "Analizando la foto…"
        Self.queue.async {
            let embedding = SegmentModel.encode(photo.preview, context: Self.context)
            DispatchQueue.main.async {
                self.busy = nil
                guard self.photo === photo else { return }
                self.embedding = embedding
                if let embedding { Self.queue.async { work(embedding, photo) } }
                else { self.status = "No se pudo analizar la foto para seleccionar." }
            }
        }
    }

    private func updateSelectionMask() {
        let points = adjustments.selection
        guard !points.isEmpty else { selectionMask = nil; scheduleRender(); return }
        withEmbedding { embedding, photo in
            let mask = SegmentModel.objectMask(embedding, points: points, extent: photo.preview.extent)
            DispatchQueue.main.async {
                guard self.photo === photo, self.adjustments.selection == points else { return }
                self.selectionMask = mask
                self.scheduleRender()
            }
        }
    }

    private func computeSkyMask() {
        guard segmentInstalled else { return }
        withEmbedding { embedding, photo in
            let mask = SegmentModel.mask(embedding, points: SegmentModel.skyPoints, extent: photo.preview.extent,
                                         connectedToTop: true, guide: photo.preview)
            DispatchQueue.main.async {
                guard self.photo === photo else { return }
                self.skyMask = mask
                if mask == nil, self.adjustments.usesSky { self.status = "No se encontró cielo en esta foto." }
                // Con el cielo ya calculado, el agua descarta los clics que cayeron en él.
                if !self.adjustments.water.isEmpty { self.updateWaterMask() }
                self.scheduleRender()
            }
        }
    }

    /// Clic en la foto (0…1, origen abajo a la izquierda). Con ⌥ quita esa zona de la selección.
    func addSelectionPoint(x: Double, y: Double, include: Bool) {
        adjustments.selection.append(SelectionPoint(x: x, y: y, include: include))
    }

    /// Aviso junto a los controles del agua (por ejemplo, si un clic cae en el cielo).
    @Published var waterHint: String?

    /// Clic en el modo «Marcar el agua»: si cae en el cielo, no se añade (estropearía la selección).
    func addWaterPoint(_ point: SelectionPoint) {
        if point.include, let skyMask, SegmentModel.value(of: skyMask, at: point) >= 0.5 {
            waterHint = "Ese clic cayó en el cielo y no se añadió. Haz clic sobre el agua."
            return
        }
        waterHint = nil
        adjustments.water.append(point)
    }

    private func updateWaterMask() {
        let points = adjustments.water
        let sky = skyMask
        guard !points.isEmpty else { waterMask = nil; scheduleRender(); return }
        withEmbedding { embedding, photo in
            let mask = SegmentModel.objectMask(embedding, points: points, extent: photo.preview.extent, guide: photo.preview,
                                               excluding: sky)
            DispatchQueue.main.async {
                guard self.photo === photo, self.adjustments.water == points else { return }
                self.waterMask = mask
                self.scheduleRender()
            }
        }
    }

    func undoWaterClick() { if !adjustments.water.isEmpty { adjustments.water.removeLast() } }
    func undoSelectionClick() { if !adjustments.selection.isEmpty { adjustments.selection.removeLast() } }

    func clearWater() {
        adjustments.water = []
        adjustments.waterTint = 0; adjustments.waterReflection = 0; adjustments.waterLight = 0
    }

    func clearSelection() {
        adjustments.selection = []
        adjustments.selExposure = 0; adjustments.selContrast = 0; adjustments.selSaturation = 0; adjustments.selTemperature = 0
    }

    func installSegmentModel() {
        busy = "Descargando el modelo de selección… 0 %"
        Self.queue.async {
            let result = Result {
                try SegmentModel.install { progress in
                    DispatchQueue.main.async { self.busy = "Descargando el modelo de selección… \(Int(progress * 100)) %" }
                }
            }
            DispatchQueue.main.async {
                self.busy = nil
                switch result {
                case .success:
                    self.segmentInstalled = true
                    self.status = "Modelo de selección instalado"
                    if self.adjustments.usesSky || self.adjustments.usesWater { self.computeSkyMask() }
                    if self.adjustments.usesSelection { self.updateSelectionMask() }
                case .failure(let error):
                    self.status = "No se pudo descargar el modelo: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Añade fotos de cielo a «Mis cielos» (se copian a la app) y usa la última.
    func chooseSkyPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Photo.openableTypes
        panel.allowsMultipleSelection = true
        panel.message = "Elige una o varias fotos de cielo para «Mis cielos»"
        guard panel.runModal() == .OK else { return }
        var last: Skies.Sky?
        for url in panel.urls {
            do { last = try Skies.add(url) } catch { status = "No se pudo añadir \(url.lastPathComponent): \(error.localizedDescription)" }
        }
        mySkies = Skies.mine()
        if let last { adjustments.skyReplacement = last.id }
    }

    func removeSky(_ sky: Skies.Sky) {
        if adjustments.skyReplacement == sky.id { adjustments.skyReplacement = nil }
        try? FileManager.default.removeItem(atPath: sky.id)
        mySkies = Skies.mine()
    }

    // MARK: Copiar y pegar ajustes

    func copyAdjustments() {
        copied = adjustments.transferable
        status = "Ajustes copiados: abre otra foto y pulsa «Pegar ajustes»"
    }

    /// Pega los ajustes copiados, conservando lo propio de esta foto (clics, trazos y enderezado).
    func pasteAdjustments() {
        guard var pasted = copied, photo != nil else { return }
        pasted.keepPhotoSpecific(from: adjustments)
        adjustments = pasted
        status = "Ajustes pegados"
    }

    // MARK: Borrar objetos (LaMa)

    private var erasingJob = 0

    private func updateErased() {
        guard let photo else { return }
        let strokes = adjustments.erase
        guard !strokes.isEmpty, eraseInstalled else { erasedPreview = nil; scheduleRender(); return }
        erasingJob += 1
        let job = erasingJob
        busy = "Borrando…"
        Self.queue.async {
            let erased = EraseModel.inpaint(photo.preview, strokes: strokes, context: Self.context)
            DispatchQueue.main.async {
                guard self.photo === photo, job == self.erasingJob else { return }
                self.busy = nil
                self.erasedPreview = erased
                self.scheduleRender()
            }
        }
    }

    /// Un trazo terminado (puntos de 0 a 1, origen abajo a la izquierda).
    func addEraseStroke(_ points: [SelectionPoint]) {
        guard !points.isEmpty else { return }
        adjustments.erase.append(EraseStroke(points: points, radius: brushSize / 100 / 2))
    }

    func undoEraseStroke() { if !adjustments.erase.isEmpty { adjustments.erase.removeLast() } }
    func clearErase() { adjustments.erase = [] }

    func installEraseModel() {
        busy = "Descargando el modelo de borrado… 0 %"
        Self.queue.async {
            let result = Result {
                try EraseModel.install { progress in
                    DispatchQueue.main.async { self.busy = "Descargando el modelo de borrado… \(Int(progress * 100)) %" }
                }
            }
            DispatchQueue.main.async {
                self.busy = nil
                switch result {
                case .success:
                    self.eraseInstalled = true
                    self.status = "Modelo de borrado instalado"
                    self.updateErased()
                case .failure(let error):
                    self.status = "No se pudo descargar el modelo: \(error.localizedDescription)"
                }
            }
        }
    }

    func installUpscaleModel() {
        busy = "Descargando el modelo de ampliación… 0 %"
        Self.queue.async {
            let result = Result {
                try UpscaleModel.install { progress in
                    DispatchQueue.main.async { self.busy = "Descargando el modelo de ampliación… \(Int(progress * 100)) %" }
                }
            }
            DispatchQueue.main.async {
                self.busy = nil
                switch result {
                case .success:
                    self.upscaleInstalled = true
                    self.status = "Modelo de ampliación instalado"
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
        let current = photo?.url
        let upscale = upscaleInstalled ? exportUpscale : 1
        busy = photos.count == 1 ? "Exportando…" : "Exportando 1 de \(photos.count)…"
        Self.queue.async {
            var failures: [String] = []
            var lastError = ""
            for (index, url) in photos.enumerated() {
                DispatchQueue.main.async { if photos.count > 1 { self.busy = "Exportando \(index + 1) de \(photos.count)…" } }
                do {
                    let photo = try Photo(url: url)
                    let label = photos.count > 1 ? "Exportando \(index + 1) de \(photos.count)" : "Exportando"
                    // En las demás fotos no se usan los clics, trazos ni enderezado de esta.
                    let settings = url == current ? adjustments : adjustments.transferable
                    try Exporter.export(photo, adjustments: settings, to: destination(url), format: format,
                                        quality: quality, upscale: upscale, context: Self.context) { progress in
                        DispatchQueue.main.async { self.busy = "\(label) · ampliando \(Int(progress * 100)) %…" }
                    }
                } catch {
                    failures.append(url.lastPathComponent)
                    lastError = error.localizedDescription
                }
            }
            DispatchQueue.main.async {
                self.busy = nil
                let done = photos.count - failures.count
                self.status = failures.isEmpty
                    ? (done == 1 ? "Foto exportada" : "\(done) fotos exportadas")
                    : done == 0 && photos.count == 1 ? "No se pudo exportar: \(lastError)"
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

    /// En el modo de captura (pruebas) no se guarda nada, para no tocar las ediciones de las fotos.
    static var readOnly = false

    static func save(_ adjustments: Adjustments, for url: URL) {
        guard !readOnly else { return }
        all[url.path] = adjustments == .neutral ? nil : adjustments
        try? JSONEncoder().encode(all).write(to: file, options: .atomic)
    }
}
