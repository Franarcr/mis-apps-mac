import AVFoundation
import Foundation
import Speech

/// Pasa a texto las dos pistas en esta Mac, sin internet, y las intercala por tiempo.
enum Transcriber {
    struct Piece { var start: Double; var end: Double; var text: String }

    static func transcribe(me: URL, them: URL) async throws -> [Line] {
        var lines: [Line] = []
        for (url, speaker) in [(me, Line.Speaker.me), (them, .them)] {
            guard FileManager.default.fileExists(atPath: url.path), try await hasSound(url) else { continue }
            let pieces = try await transcribe(url)
            lines += pieces.map { Line(speaker: speaker, start: $0.start, text: $0.text) }
        }
        lines.sort { $0.start < $1.start }
        // Junta frases seguidas de la misma persona.
        var merged: [Line] = []
        for line in lines {
            if var last = merged.last, last.speaker == line.speaker, line.start - last.start < 20 {
                last.text += " " + line.text
                merged[merged.count - 1] = last
            } else {
                merged.append(line)
            }
        }
        return merged
    }

    private static func transcribe(_ url: URL) async throws -> [Piece] {
        if #available(macOS 26.0, *) {
            return try await ModernTranscriber.transcribe(url)
        }
        return try await LegacyTranscriber.transcribe(url)
    }

    /// Evita transcribir pistas vacías (por ejemplo, una llamada sin sonido del otro lado).
    private static func hasSound(_ url: URL) async throws -> Bool {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return false }
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 48_000
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return true }
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunk)
            guard let data = buffer.floatChannelData else { return true }
            for c in 0..<Int(format.channelCount) {
                for f in 0..<Int(buffer.frameLength) where abs(data[c][f]) > 0.01 { return true }
            }
        }
        return false
    }
}

@available(macOS 26.0, *)
private enum ModernTranscriber {
    static func transcribe(_ url: URL) async throws -> [Transcriber.Piece] {
        var locale: Locale? = nil
        for id in ["es-CR", "es-419", "es-MX", "es-US", "es-ES"] {
            if let l = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) { locale = l; break }
        }
        guard let locale else { throw TranscribeError.noSpanish }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        // La primera vez macOS descarga el modelo de español (una sola vez, luego funciona sin internet).
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        let collector = Task {
            var pieces: [Transcriber.Piece] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                pieces.append(.init(start: result.range.start.seconds, end: result.range.end.seconds, text: text))
            }
            return pieces
        }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value
    }
}

/// Para macOS 14 y 15: el reconocimiento de voz de siempre, en el dispositivo.
private enum LegacyTranscriber {
    static func transcribe(_ url: URL) async throws -> [Transcriber.Piece] {
        let status = await withCheckedContinuation { (done: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscribeError.notAllowed }
        guard let recognizer = ["es-CR", "es-419", "es-MX", "es-ES"].lazy
            .compactMap({ SFSpeechRecognizer(locale: Locale(identifier: $0)) }).first(where: { $0.isAvailable })
        else { throw TranscribeError.noSpanish }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.shouldReportPartialResults = false

        let segments: [SFTranscriptionSegment] = try await withCheckedThrowingContinuation { done in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    done.resume(returning: result.bestTranscription.segments)
                } else if let error {
                    finished = true
                    done.resume(throwing: error)
                }
            }
        }
        // Las palabras se agrupan en frases cuando hay una pausa de más de un segundo.
        var pieces: [Transcriber.Piece] = []
        for segment in segments {
            let end = segment.timestamp + segment.duration
            if var last = pieces.last, segment.timestamp - last.end < 1 {
                last.text += " " + segment.substring
                last.end = end
                pieces[pieces.count - 1] = last
            } else {
                pieces.append(.init(start: segment.timestamp, end: end, text: segment.substring))
            }
        }
        return pieces
    }
}

enum TranscribeError: LocalizedError {
    case noSpanish, notAllowed
    var errorDescription: String? {
        switch self {
        case .noSpanish: "Esta Mac no tiene el reconocimiento de voz en español."
        case .notAllowed: "Oído no tiene permiso de Reconocimiento de voz (Ajustes del Sistema › Privacidad y seguridad)."
        }
    }
}
