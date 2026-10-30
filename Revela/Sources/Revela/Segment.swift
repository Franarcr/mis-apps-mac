import CoreImage
import CoreML
import Foundation

/// «Seleccionar con un clic» con SAM 2.1 Small (versión de Apple para Core ML, licencia Apache 2.0, ~94 MB).
enum SegmentModel {
    static let encoder = RemoteModel(repo: "apple/coreml-sam2.1-small", name: "SAM2_1SmallImageEncoderFLOAT16")
    static let prompt = RemoteModel(repo: "apple/coreml-sam2.1-small", name: "SAM2_1SmallPromptEncoderFLOAT16")
    static let decoder = RemoteModel(repo: "apple/coreml-sam2.1-small", name: "SAM2_1SmallMaskDecoderFLOAT16")
    static let all = [encoder, prompt, decoder]

    static var isInstalled: Bool { all.allSatisfy(\.isInstalled) }

    static func install(progress: @escaping (Double) -> Void) throws {
        for (index, model) in all.enumerated() where !model.isInstalled {
            // El codificador de imagen pesa casi todo (81 de 94 MB).
            let weights = [0.0, 0.87, 0.89, 1.0]
            try model.install { p in progress(weights[index] + (weights[index + 1] - weights[index]) * p) }
        }
    }
}

/// Un clic sobre la foto: posición de 0 a 1 (origen abajo a la izquierda, como Core Image) y si suma o resta.
struct SelectionPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var include = true
}

extension SegmentModel {
    /// Lo que el codificador saca de una foto. Se calcula una vez por foto y sirve para todos los clics.
    final class Embedding {
        let image: MLMultiArray
        let s0: MLMultiArray
        let s1: MLMultiArray
        init(image: MLMultiArray, s0: MLMultiArray, s1: MLMultiArray) { self.image = image; self.s0 = s0; self.s1 = s1 }
    }

    static func encode(_ image: CIImage, context: CIContext) -> Embedding? {
        guard let model = try? encoder.load() else { return nil }
        // SAM trabaja con una imagen de 1024 × 1024 (la foto se estira; las máscaras se devuelven a su forma).
        let side: CGFloat = 1024
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: side / image.extent.width, y: side / image.extent.height))
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(side), Int(side), kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard let buffer else { return nil }
        context.render(scaled, to: buffer)
        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": buffer])),
              let embedding = out.featureValue(for: "image_embedding")?.multiArrayValue,
              let s0 = out.featureValue(for: "feats_s0")?.multiArrayValue,
              let s1 = out.featureValue(for: "feats_s1")?.multiArrayValue else { return nil }
        return Embedding(image: embedding, s0: s0, s1: s1)
    }

    /// Máscara (blanco = seleccionado) del tamaño `extent` para los clics dados.
    /// `connectedToTop`: para el cielo, solo cuenta lo que está unido al borde de arriba (quita reflejos sueltos).
    static func mask(_ embedding: Embedding, points: [SelectionPoint], extent: CGRect, connectedToTop: Bool = false) -> CIImage? {
        guard !points.isEmpty, let promptModel = try? prompt.load(), let decoderModel = try? decoder.load(),
              let coords = try? MLMultiArray(shape: [1, NSNumber(value: points.count), 2], dataType: .float32),
              let labels = try? MLMultiArray(shape: [1, NSNumber(value: points.count)], dataType: .float32) else { return nil }
        for (i, p) in points.enumerated() {
            // SAM cuenta desde arriba a la izquierda, en píxeles de la imagen de 1024.
            coords[[0, NSNumber(value: i), 0]] = NSNumber(value: p.x * 1024)
            coords[[0, NSNumber(value: i), 1]] = NSNumber(value: (1 - p.y) * 1024)
            labels[[0, NSNumber(value: i)]] = NSNumber(value: p.include ? 1 : 0)
        }
        guard let encoded = try? promptModel.prediction(from: MLDictionaryFeatureProvider(dictionary: ["points": coords, "labels": labels])),
              let sparse = encoded.featureValue(for: "sparse_embeddings")?.multiArrayValue,
              let dense = encoded.featureValue(for: "dense_embeddings")?.multiArrayValue,
              let decoded = try? decoderModel.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                  "image_embedding": embedding.image, "feats_s0": embedding.s0, "feats_s1": embedding.s1,
                  "sparse_embedding": sparse, "dense_embedding": dense,
              ])),
              let masks = decoded.featureValue(for: "low_res_masks")?.multiArrayValue,
              let scores = decoded.featureValue(for: "scores")?.multiArrayValue else { return nil }

        // SAM propone 3 máscaras (parte, objeto, todo); se queda la de mejor puntuación.
        let count = masks.shape[1].intValue, height = masks.shape[2].intValue, width = masks.shape[3].intValue
        var best = 0
        for i in 0..<count where scores[[0, NSNumber(value: i)]].floatValue > scores[[0, NSNumber(value: best)]].floatValue { best = i }
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let logit = masks[[0, NSNumber(value: best), NSNumber(value: y), NSNumber(value: x)]].floatValue
                values[y * width + x] = 1 / (1 + exp(-logit * 2))   // borde suave
            }
        }
        if connectedToTop { keepConnectedToTop(&values, width: width, height: height) }
        let data = Data(bytes: values, count: values.count * 4)
        let small = CIImage(bitmapData: data, bytesPerRow: width * 4, size: CGSize(width: width, height: height),
                            format: .Rf, colorSpace: nil) // la fila 0 de los datos es la de arriba, como en SAM
        return small
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .cropped(to: extent)
    }

    /// Deja solo las zonas unidas a la fila de arriba (y su borde suave); el resto, a cero.
    private static func keepConnectedToTop(_ values: inout [Float], width: Int, height: Int) {
        var keep = [Bool](repeating: false, count: values.count)
        // Semillas: la franja de arriba (un 5 % de la altura), donde SAM a veces da valores bajos justo en el borde.
        let band = max(1, height / 20)
        var stack = (0..<(width * band)).filter { values[$0] > 0.5 }
        stack.forEach { keep[$0] = true }
        while let i = stack.popLast() {
            let x = i % width, y = i / width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let n = ny * width + nx
                if !keep[n], values[n] > 0.5 { keep[n] = true; stack.append(n) }
            }
        }
        var result = values
        for i in 0..<values.count where !keep[i] {
            let x = i % width, y = i / width
            // El borde suave junto a lo que se queda se conserva.
            let nearKept = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                let nx = x + dx, ny = y + dy
                return nx >= 0 && ny >= 0 && nx < width && ny < height && keep[ny * width + nx]
            }
            result[i] = nearKept ? min(values[i], 0.5) : 0
        }
        // SAM deja el borde de arriba algo flojo: las primeras filas toman el valor de la franja de debajo.
        for x in 0..<width {
            let below = result[band * width + x]
            for y in 0..<band { result[y * width + x] = max(result[y * width + x], below) }
        }
        values = result
    }

    /// El cielo: clics en la franja de arriba. Se descarta si lo que sale no toca el borde superior
    /// o es demasiado pequeño (en esa foto probablemente no hay cielo).
    static let skyPoints = [SelectionPoint(x: 0.5, y: 0.97), SelectionPoint(x: 0.15, y: 0.95), SelectionPoint(x: 0.85, y: 0.95)]
}
