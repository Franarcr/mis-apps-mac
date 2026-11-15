import AppKit
import AVFoundation
import OidoAudio

/// Graba una llamada en dos pistas: el micrófono («Yo») y el sonido de la app («Ellos»).
@MainActor
final class Recorder: ObservableObject {
    static let shared = Recorder()

    @Published private(set) var current: Call? = nil
    @Published private(set) var currentApp: CallApp? = nil
    @Published private(set) var lastError: String? = nil

    private var engine: AVAudioEngine?
    private var micFile: AVAudioFile?
    private var tap: OIDTapRecorder?
    private var startedAt = Date()

    var isRecording: Bool { current != nil }
    var elapsed: Double { isRecording ? Date().timeIntervalSince(startedAt) : 0 }

    func start(_ app: CallApp) {
        guard !isRecording else { return }
        lastError = nil
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                Task { @MainActor in if ok { self.start(app) } else { self.lastError = Self.micDenied } }
            }
            return
        case .denied, .restricted:
            lastError = Self.micDenied
            return
        default: break
        }

        let now = Date()
        let id = Self.folderName(now)
        var call = Call(id: id, title: app.prefixes.isEmpty ? "Grabación" : "Llamada de \(app.name)", app: app.name, start: now)
        try? FileManager.default.createDirectory(at: call.folder, withIntermediateDirectories: true)

        // Sonido de la app (o de todo el Mac si es manual o no se encuentra la app).
        let ids = OIDSystem.processes()
            .filter { app.matches($0.bundleID) && $0.pid != getpid() }
            .map { NSNumber(value: $0.objectID) }
        do {
            tap = try OIDTapRecorder(processes: ids, fileURL: call.appURL)
        } catch {
            lastError = error.localizedDescription
        }

        // Micrófono.
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noMic }
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                           AVSampleRateKey: format.sampleRate,
                                           AVNumberOfChannelsKey: format.channelCount]
            let file = try AVAudioFile(forWriting: call.micURL, settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                try? file.write(from: buffer)
            }
            try engine.start()
            self.engine = engine
            self.micFile = file
        } catch {
            lastError = "No se pudo usar el micrófono: \(error.localizedDescription)"
        }

        guard tap != nil || engine != nil else {
            try? FileManager.default.removeItem(at: call.folder)
            return
        }
        startedAt = now
        call.status = .recording
        Store.shared.save(call)
        current = call
        currentApp = app
    }

    func stop() {
        guard var call = current else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        micFile = nil          // al soltarlo se cierra el archivo
        tap?.stop()
        tap = nil
        call.duration = Date().timeIntervalSince(startedAt)
        Store.shared.save(call)
        current = nil
        currentApp = nil
        Store.shared.process(call.id)
    }

    private static func folderName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: date)
    }

    private static let micDenied = "Oído no tiene permiso para el micrófono. Actívalo en Ajustes del Sistema › Privacidad y seguridad › Micrófono."

    enum RecorderError: LocalizedError {
        case noMic
        var errorDescription: String? { "no hay micrófono disponible" }
    }
}
