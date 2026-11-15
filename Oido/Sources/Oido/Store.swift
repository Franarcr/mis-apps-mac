import AppKit
import AVFoundation
import Foundation

/// Las llamadas guardadas, en ~/Library/Application Support/Oido/Llamadas.
/// Fuera de Documentos a propósito: iCloud puede dejar los archivos sin descargar.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    nonisolated static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Oido/Llamadas", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    @Published private(set) var calls: [Call] = []

    private init() { load() }

    func load() {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        var loaded: [Call] = []
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("llamada.json")),
                  var call = try? JSONDecoder.oido.decode(Call.self, from: data) else { continue }
            // Si la app se cerró a mitad de una grabación o transcripción, se retoma.
            if call.status == .recording || call.status == .transcribing { call.status = .transcribing }
            loaded.append(call)
        }
        calls = loaded.sorted { $0.start > $1.start }
        for call in calls where call.status == .transcribing { process(call.id) }
    }

    func call(_ id: String) -> Call? { calls.first { $0.id == id } }

    func save(_ call: Call) {
        if let i = calls.firstIndex(where: { $0.id == call.id }) { calls[i] = call } else {
            calls.insert(call, at: 0)
            calls.sort { $0.start > $1.start }
        }
        try? FileManager.default.createDirectory(at: call.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.oido.encode(call) {
            try? data.write(to: call.folder.appendingPathComponent("llamada.json"), options: .atomic)
        }
    }

    func update(_ id: String, _ change: (inout Call) -> Void) {
        guard var call = call(id) else { return }
        change(&call)
        save(call)
    }

    /// A la Papelera, por si se borra sin querer.
    func delete(_ id: String) {
        guard let call = call(id) else { return }
        NSWorkspace.shared.recycle([call.folder]) { _, _ in }
        calls.removeAll { $0.id == id }
    }

    // MARK: Después de grabar: mezcla, transcripción y resumen

    private var working: Set<String> = []

    func process(_ id: String) {
        guard !working.contains(id), let call = call(id) else { return }
        working.insert(id)
        update(id) { $0.status = .transcribing; $0.error = nil }
        Task {
            defer { working.remove(id) }
            await Self.mix(call)
            do {
                let lines = try await Transcriber.transcribe(me: call.micURL, them: call.appURL)
                update(id) { $0.lines = lines }
                if lines.isEmpty {
                    update(id) { $0.status = .ready; $0.summaryNote = "No se oyó a nadie hablar en la grabación." }
                    return
                }
                let result = await Summarizer.summarize(lines)
                update(id) {
                    $0.summary = result.summary
                    $0.actions = result.actions
                    $0.summaryNote = result.note
                    $0.status = .ready
                }
            } catch {
                update(id) { $0.status = .failed; $0.error = error.localizedDescription }
            }
        }
    }

    /// Junta las dos pistas en `llamada.m4a` para escucharla de corrido.
    private static func mix(_ call: Call) async {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: call.mixURL.path) else { return }
        let composition = AVMutableComposition()
        for url in [call.micURL, call.appURL] where fm.fileExists(atPath: url.path) {
            let asset = AVURLAsset(url: url)
            guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration),
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            try? track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
        }
        guard !composition.tracks.isEmpty,
              let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { return }
        export.outputURL = call.mixURL
        export.outputFileType = .m4a
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { done.resume() }
        }
    }
}

extension JSONEncoder {
    static let oido: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let oido: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
