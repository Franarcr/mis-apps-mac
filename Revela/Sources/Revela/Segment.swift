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
    /// Selección hecha con clics: cada clic que suma da su propia máscara (con los clics que restan) y se
    /// juntan. Si se le pasan a SAM a la vez clics en cosas distintas (agua y cielo, por ejemplo), busca
    /// un solo objeto que lo abarque todo, se confunde y devuelve una máscara a cuadros.
    /// `guide`: la foto; para el agua, el borde se ajusta por color (llega al agua entre plantas y orillas).
    static func objectMask(_ embedding: Embedding, points: [SelectionPoint], extent: CGRect, guide: CIImage? = nil) -> CIImage? {
        let negatives = points.filter { !$0.include }
        let masks = points.filter(\.include).compactMap { mask(embedding, points: [$0] + negatives, extent: extent) }
        guard var union = masks.first else { return nil }
        for other in masks.dropFirst() {
            union = union.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: other])
        }
        union = union.cropped(to: extent)
        guard let guide else { return union }
        // El agua tiene más textura que el cielo (olas, gotas): se admite algo más de diferencia de color.
        return EdgeRefiner.refine(union, photo: guide.cropped(to: extent), cell: extent.width / 256,
                                  similar: 0.03, different: 0.08, reach: 9, greenWeight: 0.6, rejectGreener: true)
    }

    /// `guide`: la foto; para el cielo, el borde de la máscara se ajusta al color de la foto
    /// (la máscara de SAM es de 256 × 256 y, estirada a la foto completa, queda gruesa).
    static func mask(_ embedding: Embedding, points: [SelectionPoint], extent: CGRect, connectedToTop: Bool = false,
                     guide: CIImage? = nil) -> CIImage? {
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
        let coarse = small
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .cropped(to: extent)
        guard let guide else { return coarse }
        let cell = extent.width / CGFloat(width)
        let wide = EdgeRefiner.refine(coarse, photo: guide.cropped(to: extent), cell: cell)
        guard connectedToTop else { return wide }
        // Junto al horizonte, la franja ancha (para el cielo que asoma por rejillas y ramas) se come fachadas,
        // barandas y tejados lejanos que la niebla deja del color del cielo. Allí el borde se ajusta solo
        // en una franja estrecha; la ancha vale a partir de un 8 % de la altura por encima del horizonte.
        let tight = EdgeRefiner.refine(coarse, photo: guide.cropped(to: extent), cell: cell, reach: 1.5)
        // Y el borde se difumina hacia fuera: con niebla, lo lejano se funde con el cielo (las copas de los
        // árboles no quedan recortadas con la forma gruesa de la máscara de SAM).
        let soft = tight.clampedToExtent().applyingGaussianBlur(sigma: Double(cell)).cropped(to: extent)
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: tight]).cropped(to: extent)
        let horizon = Skies.horizon(of: coarse, in: extent)
        let f = CIFilter.linearGradient()
        f.point0 = CGPoint(x: 0, y: horizon + extent.height * 0.08)
        f.point1 = CGPoint(x: 0, y: horizon + extent.height * 0.03)
        f.color0 = CIColor(red: 1, green: 1, blue: 1)
        f.color1 = CIColor(red: 0, green: 0, blue: 0)
        return Develop.blend(wide, over: soft, mask: f.outputImage!.cropped(to: extent)).cropped(to: extent)
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

/// Ajusta el borde de una máscara de cielo o de agua a la foto. La máscara de SAM (256 × 256) estirada a la
/// foto completa deja una franja sin tocar alrededor de edificios, árboles o plantas, y SAM toma enteros
/// los objetos con huecos (rejillas, ramas, cañas). En esa franja se decide píxel a píxel por el color:
/// es cielo (o agua) si se parece al color del cielo (o del agua) de esa zona.
enum EdgeRefiner {
    /// `similar`…`different`: diferencia media de color hasta la que es la misma superficie, y desde la que ya no.
    static func refine(_ coarse: CIImage, photo: CIImage, cell: CGFloat,
                       similar near: CGFloat = 0.03, different far: CGFloat = 0.09, reach: CGFloat = 6,
                       greenWeight: CGFloat = 1.0 / 3, rejectGreener: Bool = false, unmix: Bool = false) -> CIImage {
        let extent = coarse.extent
        func clamp01(_ x: CIImage) -> CIImage { x.applyingFilter("CIColorClamp").cropped(to: extent) }
        func affine(_ x: CIImage, _ k: CGFloat, _ bias: CGFloat) -> CIImage {
            clamp01(x.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
            ]))
        }
        // Cielo seguro: el interior de la máscara, alejado más de una celda del borde.
        let core = affine(coarse.clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: cell * 1.5]).cropped(to: extent), 10, -8.5)
        // Franja dudosa: hasta `reach` celdas por fuera de la máscara. Ancha para llegar al cielo o al agua que se
        // ve por dentro de rejillas, ramas y cañas (SAM las toma enteras como objeto); el color protege lo demás.
        let band = affine(coarse.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: cell * reach]).cropped(to: extent), 4, -1)
        // Color de la superficie en cada zona: media de la zona segura de alrededor (convolución normalizada).
        let sigma = Double(cell * max(5, reach * 0.8))
        let weighted = photo.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: core])
        let num = weighted.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        let den = core.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
            .applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0.001, y: 0.001, z: 0.001, w: 1)])
        let skyColor = den.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: num])
        // Parecido de cada píxel al color del cielo de su zona (diferencia media de los tres canales).
        let difference = photo.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: skyColor])
        // Peso de cada canal en la diferencia; para el agua cuenta más el verde (separa agua gris de plantas).
        let side = (1 - greenWeight) / 2
        let third = CIVector(x: side, y: greenWeight, z: side, w: 0)
        // Se suaviza un poco para que el ruido de la foto no deje puntos sueltos.
        // Proporcional al tamaño: en la vista previa (2048 px) un radio fijo taparía los huecos de rejillas y ramas.
        let noise = Double(max(0.5, extent.width / 4000))
        let distance = difference.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": third, "inputGVector": third, "inputBVector": third, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).clampedToExtent().applyingGaussianBlur(sigma: noise).cropped(to: extent)
        // Para el cielo, hasta 0,03 de diferencia es cielo y desde 0,09 no (más estricto deja puntos del cielo viejo).
        let similar = affine(distance, -1 / (far - near), far / (far - near))
        var amount = similar
        if unmix {
            // En el borde, cada píxel es una mezcla de cielo y de lo que tiene delante (hojas, la bruma de un
            // edificio lejano). La proporción de cielo sale de proyectar el píxel entre el color del cielo de
            // la zona (S) y el del suelo de la zona (F): alfa = (I − F)·(S − F) / |S − F|².
            let groundWeight = affine(band, -1, 1)
            let groundNum = photo.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: groundWeight])
                .clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
            let groundDen = groundWeight.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
                .applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0.001, y: 0.001, z: 0.001, w: 1)])
            let groundColor = groundDen.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: groundNum])
            let e = Arith.sub(skyColor, groundColor), d = Arith.sub(photo, groundColor)
            let dot = Arith.sum(Arith.mul(d, e)), norm = Arith.sum(Arith.mul(e, e))
            let normSafe = norm.applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0.0001, y: 0.0001, z: 0.0001, w: 1)])
            let unmixed = clamp01(normSafe.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: dot]))
                .clampedToExtent().applyingGaussianBlur(sigma: noise).cropped(to: extent)
            // Si cielo y suelo tienen casi el mismo color la proyección no es fiable: ahí manda el parecido.
            let confidence = affine(norm, 1 / 0.004, 0)
            amount = Develop.blend(unmixed, over: similar, mask: confidence)
        }
        var fine = amount.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: band]).cropped(to: extent)
        if rejectGreener {
            // Las plantas en sombra pueden ser tan oscuras como el agua: lo que es más verde que el agua
            // de su zona (verde − media de rojo y azul) no es agua.
            let greenness = CIVector(x: -0.5, y: 1, z: -0.5, w: 0)
            func green(_ x: CIImage) -> CIImage {
                x.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": greenness, "inputGVector": greenness, "inputBVector": greenness,
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ])
            }
            // extra = verdor de la foto − verdor del agua de la zona (con signo); si es mayor que 0, deja de ser agua.
            let extra = green(skyColor).applyingFilter("CISubtractBlendMode", parameters: [kCIInputBackgroundImageKey: green(photo)])
                .clampedToExtent().applyingGaussianBlur(sigma: noise).cropped(to: extent)
            let water = affine(extra, -1 / 0.02, 1)
            fine = fine.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: water]).cropped(to: extent)
        }
        // El cielo seguro se queda siempre (por si tiene nubes de otro color); en la franja manda el color.
        let merged = clamp01(fine.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: core]))
        // Con la proporción de cielo calculada, el borde ya es suave y fiel: no se limpia más.
        if unmix { return merged }
        // Puntos aislados fuera: un cierre (máximo y luego mínimo) los rellena o los quita, y un borde de 1 px suave.
        let r = noise
        return merged.clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: r])
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: r])
            .applyingGaussianBlur(sigma: 0.8)
            .cropped(to: extent)
    }
}

/// Operaciones aritméticas por píxel con signo (Core Image trabaja en coma flotante).
enum Arith {
    static func sub(_ a: CIImage, _ b: CIImage) -> CIImage {
        let negated = b.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: -1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -1, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
        return negated.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: a]).cropped(to: a.extent)
    }

    static func mul(_ a: CIImage, _ b: CIImage) -> CIImage {
        a.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: b]).cropped(to: a.extent)
    }

    /// r + g + b en los tres canales.
    static func sum(_ a: CIImage) -> CIImage {
        let ones = CIVector(x: 1, y: 1, z: 1, w: 0)
        return a.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": ones, "inputGVector": ones, "inputBVector": ones, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }

    static func add(_ a: CIImage, _ b: CIImage) -> CIImage {
        let opaqueB = b.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
        return opaqueB.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: a]).cropped(to: a.extent)
    }
}
