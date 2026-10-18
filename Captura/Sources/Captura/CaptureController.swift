import AppKit
import AVFoundation

enum Settings {
    private static let folderKey = "saveFolder"

    static var saveFolder: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: folderKey) { return URL(fileURLWithPath: path) }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Capturas")
        }
        set { UserDefaults.standard.set(newValue.path, forKey: folderKey) }
    }

    /// Si es `false` (por defecto), la captura solo se copia al portapapeles.
    static var saveToFile: Bool {
        get { UserDefaults.standard.bool(forKey: "saveToFile") }
        set { UserDefaults.standard.set(newValue, forKey: "saveToFile") }
    }

    static let previewOptions = [0, 2, 3, 5, 8, 10, 15]

    /// Abrir el editor de anotaciones justo después de cada captura de imagen.
    static var annotateAfterCapture: Bool {
        get { UserDefaults.standard.bool(forKey: "annotateAfterCapture") }
        set { UserDefaults.standard.set(newValue, forKey: "annotateAfterCapture") }
    }

    /// Grabar en los vídeos el sonido del sistema (activado por defecto).
    static var recordSystemAudio: Bool {
        get { UserDefaults.standard.object(forKey: "recordSystemAudio") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "recordSystemAudio") }
    }

    /// Grabar en los vídeos el micrófono (desactivado por defecto).
    static var recordMicrophone: Bool {
        get { UserDefaults.standard.bool(forKey: "recordMicrophone") }
        set { UserDefaults.standard.set(newValue, forKey: "recordMicrophone") }
    }

    /// Segundos que la miniatura permanece en pantalla; 0 = no mostrarla.
    static var previewSeconds: Int {
        get { UserDefaults.standard.object(forKey: "previewSeconds") as? Int ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "previewSeconds") }
    }
}

@MainActor
final class CaptureController {
    private enum Mode { case full, area, text, video, gif, scroll }

    private var overlays: [SelectionOverlayWindow] = []
    private var busy = false

    private let recorder = ScreenRecorder()
    private var recordingUI: (border: RegionBorderWindow, panel: RegionControlPanel, timer: Timer)?
    private(set) var recordingStart: Date?
    private var recorderReady = false
    /// La grabación en curso es para un GIF (se convierte al detenerla).
    private var recordingGIF = false
    private var scrollSession: ScrollSession?

    /// Avisa al menú cuando empieza o termina una grabación.
    var onRecordingChanged: ((Bool) -> Void)?

    var isRecording: Bool { recordingStart != nil }

    func captureFullScreen() { start(.full) }
    func captureArea() { start(.area) }
    func captureText() { start(.text) }

    /// Empieza a grabar o, si ya se está grabando, detiene la grabación.
    func toggleVideo() {
        if isRecording { stopRecording() } else { start(.video) }
    }

    /// Empieza a grabar un GIF o, si ya se está grabando, detiene la grabación.
    func toggleGIF() {
        if isRecording { stopRecording() } else { start(.gif) }
    }

    /// Empieza una captura con desplazamiento o, si hay una en curso, la termina.
    func toggleScrolling() {
        if let scrollSession { scrollSession.finish() } else { start(.scroll) }
    }

    private func start(_ mode: Mode) {
        guard !busy, !isRecording, scrollSession == nil, ensurePermission() else { return }
        busy = true
        Task { @MainActor in
            do {
                let shots = try await ScreenCapturer.captureAllScreens()
                switch mode {
                case .full:
                    busy = false
                    let screen = NSScreen.underMouse
                    if let shot = shots.first(where: { $0.screen == screen }) ?? shots.first {
                        deliver(shot.image)
                    }
                case .area, .text, .video, .gif, .scroll:
                    beginSelection(shots, mode: mode)
                }
            } catch {
                busy = false
                NSAlert(error: error).runModal()
            }
        }
    }

    private func beginSelection(_ shots: [DisplayShot], mode: Mode) {
        let hint = switch mode {
        case .text: "Selecciona el texto que quieres copiar"
        case .video: "Arrastra para grabar un área · clic para grabar toda la pantalla"
        case .gif: "Arrastra para grabar un GIF · clic para toda la pantalla"
        case .scroll: "Selecciona la zona que vas a desplazar"
        default: "Arrastra para seleccionar un área"
        }
        NSApp.activate(ignoringOtherApps: true)
        let active = NSScreen.underMouse
        for shot in shots {
            let window = SelectionOverlayWindow(shot: shot, hint: hint, allowsClick: mode == .video || mode == .gif) { [weak self] rect in
                self?.finishSelection(shot: shot, rect: rect, mode: mode)
            }
            overlays.append(window)
            if shot.screen == active { window.makeKeyAndOrderFront(nil) } else { window.orderFront(nil) }
        }
    }

    private func finishSelection(shot: DisplayShot, rect: NSRect?, mode: Mode) {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        busy = false
        guard let rect else { return }
        switch mode {
        case .text: if let image = shot.crop(rect) { recognize(image) }
        case .video: startRecording(shot: shot, selection: rect, gif: false)
        case .gif: startRecording(shot: shot, selection: rect, gif: true)
        case .scroll: startScrolling(shot: shot, selection: rect)
        default: if let image = shot.crop(rect) { deliver(image) }
        }
    }

    // MARK: Vídeo

    private func startRecording(shot: DisplayShot, selection: NSRect, gif: Bool) {
        if !recorderReady {
            recorder.onFailure = { [weak self] error in self?.recordingFailed(error) }
            recorderReady = true
        }
        // El GIF se graba primero como vídeo sin audio en la carpeta temporal.
        let folder = gif ? Self.tempFolder : Settings.saveFolder
        let url = folder.appendingPathComponent(fileName(prefix: gif ? "GIF" : "Grabación", ext: "mp4"))
        recordingGIF = gif
        let global = shot.globalRect(selection)
        let fullScreen = selection.size == shot.screen.frame.size
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var microphone = !gif && Settings.recordMicrophone
                if microphone, !(await AVCaptureDevice.requestAccess(for: .audio)) {
                    microphone = false
                    Toast.show("Sin permiso de micrófono", symbol: "mic.slash.fill",
                               detail: "Se graba sin micrófono. Actívalo en Ajustes › Privacidad › Micrófono.")
                }
                do {
                    try await recorder.start(shot: shot, rect: shot.displayRect(selection), to: url,
                                             systemAudio: !gif && Settings.recordSystemAudio, microphone: microphone)
                } catch where (!gif && Settings.recordSystemAudio) || microphone {
                    // Si con audio no arranca, se graba al menos la imagen.
                    try await recorder.start(shot: shot, rect: shot.displayRect(selection), to: url,
                                             systemAudio: false, microphone: false)
                    Toast.show("Grabando sin audio", symbol: "speaker.slash.fill",
                               detail: "No se pudo capturar el audio: \(error.localizedDescription)")
                }
            } catch {
                NSAlert(error: error).runModal()
                return
            }
            let border = RegionBorderWindow(globalRect: global, color: .systemRed, dashed: false)
            if !fullScreen { border.orderFrontRegardless() }
            let panel = RegionControlPanel(symbol: "record.circle", tint: .red,
                                           primary: "Detener", onPrimary: { [weak self] in self?.stopRecording() },
                                           secondary: nil, onSecondary: nil)
            let label = gif ? "Grabando GIF" : "Grabando"
            panel.model.title = "\(label) 0:00"
            panel.model.detail = gif ? "⌥⇧6 o el botón rojo de la barra para detener"
                                     : "⌥⇧4 o el botón rojo de la barra para detener"
            panel.show(near: global, on: shot.screen)
            let start = Date()
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                MainActor.assumeIsolated { panel.model.title = "\(label) \(Self.elapsed(since: start))" }
            }
            recordingUI = (border, panel, timer)
            recordingStart = start
            onRecordingChanged?(true)
        }
    }

    /// Si la captura falla mientras está en marcha, se detiene (y `stopRecording` muestra el error).
    private func recordingFailed(_ error: Error) {
        stopRecording()
    }

    func stopRecording() {
        guard isRecording else { return }
        if let ui = recordingUI {
            ui.timer.invalidate()
            ui.border.orderOut(nil)
            ui.panel.close()
        }
        recordingUI = nil
        recordingStart = nil
        onRecordingChanged?(false)
        Task { @MainActor in
            do {
                guard let url = try await recorder.stop() else { return }
                if recordingGIF { await deliverGIF(from: url) } else { await deliverVideo(url) }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    static func elapsed(since start: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(start))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Los vídeos siempre se guardan en la carpeta de capturas; al portapapeles va el archivo.
    private func deliverVideo(_ url: URL) async {
        Clipboard.copy(file: url)
        NSSound(named: "Tink")?.play()
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        guard Settings.previewSeconds > 0, let frame = try? await generator.image(at: .zero).image else {
            Toast.show("Vídeo guardado y copiado", detail: url.lastPathComponent)
            return
        }
        QuickAccess.show(image: frame, fileURL: url, saved: true, seconds: Settings.previewSeconds,
                         onCopy: { Clipboard.copy(file: url) }, onSave: { url })
    }

    /// Convierte la grabación en GIF, lo guarda en la carpeta de capturas y lo copia (como archivo).
    private func deliverGIF(from video: URL) async {
        Toast.show("Creando el GIF…", symbol: "hourglass")
        let folder = Settings.saveFolder
        let gif = folder.appendingPathComponent(fileName(prefix: "GIF", ext: "gif"))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let first = try await GifMaker.make(from: video, to: gif)
            try? FileManager.default.removeItem(at: video)
            Clipboard.copy(file: gif)
            NSSound(named: "Tink")?.play()
            let size = ByteCountFormatter.string(fromByteCount: Int64((try? gif.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                                                 countStyle: .file)
            guard Settings.previewSeconds > 0, let first else {
                Toast.show("GIF guardado y copiado", detail: "\(gif.lastPathComponent) · \(size)")
                return
            }
            Toast.show("GIF listo", detail: size)
            QuickAccess.show(image: first, fileURL: gif, saved: true, seconds: Settings.previewSeconds,
                             onCopy: { Clipboard.copy(file: gif) }, onSave: { gif })
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: Desplazamiento

    private func startScrolling(shot: DisplayShot, selection: NSRect) {
        scrollSession = ScrollSession(shot: shot, selection: selection) { [weak self] image in
            self?.scrollSession = nil
            if let image { self?.deliver(image) }
        }
    }

    // MARK: Resultados

    private func deliver(_ image: CGImage) {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        Clipboard.copy(png: png)
        NSSound(named: "Tink")?.play()

        // Sin "Guardar también en archivo" la captura va a una carpeta temporal,
        // solo para poder arrastrarla o abrirla desde la miniatura.
        let saved = Settings.saveToFile
        let folder = saved ? Settings.saveFolder : Self.tempFolder
        let url = folder.appendingPathComponent(fileName())
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
            return
        }

        if Settings.annotateAfterCapture {
            AnnotationEditor.open(image: image, fileURL: url)
            return
        }
        guard Settings.previewSeconds > 0 else {
            Toast.show("Captura copiada")
            return
        }
        QuickAccess.show(image: image, fileURL: url, saved: saved, seconds: Settings.previewSeconds,
                         onCopy: { Clipboard.copy(png: png) },
                         onSave: { Self.saveCopy(of: url) },
                         onAnnotate: { AnnotationEditor.open(image: image, fileURL: url) })
    }

    static let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("Captura")

    /// Copia una captura temporal a la carpeta de capturas y devuelve su nueva ubicación.
    private static func saveCopy(of url: URL) -> URL? {
        let folder = Settings.saveFolder
        let target = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.copyItem(at: url, to: target)
            }
            return target
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    private func recognize(_ image: CGImage) {
        Task { @MainActor in
            do {
                let text = try await TextRecognizer.recognize(image)
                if text.isEmpty {
                    Toast.show("No se encontró texto", symbol: "text.magnifyingglass")
                } else {
                    Clipboard.copy(text: text)
                    Toast.show("Texto copiado", detail: text)
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func fileName(prefix: String = "Captura", ext: String = "png") -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'a las' HH.mm.ss"
        return "\(prefix) \(f.string(from: Date())).\(ext)"
    }

    // MARK: Permisos

    private func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if CGRequestScreenCaptureAccess() { return true }
        let alert = NSAlert()
        alert.messageText = "Captura necesita permiso de Grabación de pantalla"
        alert.informativeText = "Actívalo en Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla y audio del sistema. Después vuelve a abrir Captura."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}

enum Clipboard {
    static func copy(png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pb.writeObjects([item])
    }

    static func copy(file url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }

    static func copy(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
