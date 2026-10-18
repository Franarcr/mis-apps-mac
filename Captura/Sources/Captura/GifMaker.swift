import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Convierte un vídeo en un GIF animado que se repite sin fin.
enum GifMaker {
    static let framesPerSecond = 12.0
    static let maxWidth: CGFloat = 1000

    /// Devuelve el primer fotograma (para la miniatura).
    @discardableResult
    static func make(from video: URL, to gif: URL) async throws -> CGImage? {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        let count = max(1, Int(duration * framesPerSecond))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 4)
        let tolerance = CMTime(seconds: 0.5 / framesPerSecond, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let destination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, count, nil)
        else { throw NSError(domain: "Captura", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear el GIF"]) }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1 / framesPerSecond,
                kCGImagePropertyGIFUnclampedDelayTime: 1 / framesPerSecond,
            ],
        ] as CFDictionary

        var first: CGImage?
        for i in 0 ..< count {
            let time = CMTime(seconds: Double(i) / framesPerSecond, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            if first == nil { first = frame }
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard first != nil, CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "Captura", code: 3, userInfo: [NSLocalizedDescriptionKey: "No se pudo escribir el GIF"])
        }
        return first
    }
}
