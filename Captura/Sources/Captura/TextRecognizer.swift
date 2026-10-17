import CoreGraphics
import Foundation
import Vision

enum TextRecognizer {
    /// Reconoce texto (español e inglés) y lo devuelve en orden de lectura, línea por línea.
    static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["es-ES", "en-US"]
                request.automaticallyDetectsLanguage = true
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    continuation.resume(returning: assemble(request.results ?? []))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Agrupa las observaciones en líneas (de arriba a abajo) y las ordena de izquierda a derecha.
    private static func assemble(_ observations: [VNRecognizedTextObservation]) -> String {
        let items = observations
            .compactMap { obs -> (box: CGRect, text: String)? in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                return (obs.boundingBox, text)
            }
            .sorted { $0.box.midY > $1.box.midY }

        var lines: [[(box: CGRect, text: String)]] = []
        for item in items {
            if let first = lines.last?.first,
               abs(first.box.midY - item.box.midY) < min(first.box.height, item.box.height) * 0.5 {
                lines[lines.count - 1].append(item)
            } else {
                lines.append([item])
            }
        }
        return lines
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
