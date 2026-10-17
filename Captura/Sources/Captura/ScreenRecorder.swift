import AVFoundation
import ScreenCaptureKit

/// Graba una zona de la pantalla en un archivo MP4 (H.264, 60 fps, con cursor) y, si se pide,
/// el sonido del sistema y el micrófono. Cada paso queda en ~/Library/Logs/Captura/video.log.
final class ScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var finished: CheckedContinuation<Void, Never>?
    private var stopping = false
    private var fileClosed = false
    private var failure: Error?
    private(set) var outputURL: URL?
    private let sampleQueue = DispatchQueue(label: "Captura.muestras")
    private let log = Logger.file("video.log")

    /// Se llama (en el hilo principal) si la grabación falla mientras está en marcha.
    var onFailure: ((Error) -> Void)?

    @MainActor
    func start(shot: DisplayShot, rect: CGRect, to url: URL, systemAudio: Bool, microphone: Bool) async throws {
        log("— Nueva grabación · zona \(Int(rect.width))×\(Int(rect.height)) pt · sonido del sistema \(systemAudio) · micrófono \(microphone)")
        let scale = shot.screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        // H.264 exige dimensiones pares.
        config.width = Int(rect.width * scale) & ~1
        config.height = Int(rect.height * scale) & ~1
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.queueDepth = 6
        config.capturesAudio = systemAudio
        config.excludesCurrentProcessAudio = true
        var mic: AVCaptureDevice?
        if microphone, let device = AVCaptureDevice.default(for: .audio) {
            config.captureMicrophone = true
            config.microphoneCaptureDeviceID = device.uniqueID
            mic = device
        }

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mp4
        recording.videoCodecType = .h264

        let filter = SCContentFilter(display: shot.display, excludingApplications: shot.ownApp, exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // Salidas que solo descartan las muestras: el archivo lo escribe SCRecordingOutput, pero
        // ScreenCaptureKit necesita un destinatario para entregar el audio.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue) }
        if mic != nil { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue) }
        try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: self))

        failure = nil
        stopping = false
        fileClosed = false
        do {
            try await stream.startCapture()
        } catch {
            log("Error al empezar: \(error.localizedDescription)")
            throw error
        }
        self.stream = stream
        outputURL = url
        log("Captura en marcha → \(url.lastPathComponent)")
    }

    /// Detiene la grabación y espera (como mucho unos segundos) a que el archivo quede cerrado.
    @MainActor
    func stop() async throws -> URL? {
        guard let stream else { return nil }
        self.stream = nil
        stopping = true
        log("Deteniendo…")
        do { try await stream.stopCapture() } catch { log("Aviso al detener: \(error.localizedDescription)") }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Puede que el archivo ya se haya cerrado (o fallado) mientras se detenía la captura.
            if fileClosed || failure != nil {
                continuation.resume()
                return
            }
            finished = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.log("Tiempo de espera agotado al cerrar el archivo")
                self?.complete()
            }
        }

        if let failure { throw failure }
        guard let url = outputURL, FileManager.default.fileExists(atPath: url.path) else {
            log("El archivo no se creó")
            throw NSError(domain: "Captura", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "La grabación no se pudo guardar. Revisa ~/Library/Logs/Captura/video.log"])
        }
        log("Guardado: \(url.lastPathComponent)")
        return url
    }

    private func complete() {
        DispatchQueue.main.async {
            guard let continuation = self.finished else { return }
            self.finished = nil
            continuation.resume()
        }
    }

    private func fail(_ error: Error, _ origin: String) {
        log("Error (\(origin)): \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.failure = error
            if self.stopping { self.complete() } else { self.onFailure?(error) }
        }
    }

    // MARK: Delegados

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) { log("Escribiendo el archivo") }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        log("Archivo cerrado")
        DispatchQueue.main.async {
            self.fileClosed = true
            self.complete()
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        fail(error, "archivo")
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { fail(error, "captura") }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}

/// Registro sencillo en ~/Library/Logs/Captura/<nombre> (se reinicia en cada sesión).
enum Logger {
    static func file(_ name: String) -> (String) -> Void {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Captura")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return { _ in } }
        handle.seekToEndOfFile()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let lock = NSLock()
        return { line in
            lock.lock()
            defer { lock.unlock() }
            handle.write(Data((formatter.string(from: Date()) + "  " + line + "\n").utf8))
        }
    }
}
