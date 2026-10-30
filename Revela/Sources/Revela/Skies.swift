import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Cielos para «Cambiar cielo»: unos generados y cualquier foto de cielo que elijas.
enum Skies {
    struct Sky: Identifiable, Hashable {
        let id: String
        let name: String
    }

    static let builtIn: [Sky] = [
        Sky(id: "despejado", name: "Despejado"),
        Sky(id: "nubes", name: "Con nubes"),
        Sky(id: "atardecer", name: "Atardecer"),
        Sky(id: "dorado", name: "Hora dorada"),
        Sky(id: "tormenta", name: "Tormenta"),
    ]

    /// «Mis cielos»: fotos de cielo copiadas a ~/Library/Application Support/Revela/Cielos.
    static var folder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Revela/Cielos")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func mine() -> [Sky] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { Sky(id: $0.path, name: $0.deletingPathExtension().lastPathComponent) }
    }

    /// Copia una foto de cielo a «Mis cielos» (si ya estaba, la reutiliza).
    static func add(_ url: URL) throws -> Sky {
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        if url.standardizedFileURL != destination.standardizedFileURL, !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: url, to: destination)
        }
        return Sky(id: destination.path, name: destination.deletingPathExtension().lastPathComponent)
    }

    static func name(of id: String) -> String {
        builtIn.first { $0.id == id }?.name ?? URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent
    }

    /// Cambia o realza el cielo dentro de `mask`.
    static func apply(_ a: Adjustments, to image: CIImage, mask: CIImage) -> CIImage {
        var sky = image
        if let id = a.skyReplacement, let replacement = make(id, extent: image.extent, horizon: horizon(of: mask, in: image.extent)) {
            sky = a.skyAmount >= 100 ? replacement : Develop.mix(image, replacement, amount: a.skyAmount / 100)
        }
        if a.skyEnhance > 0 {
            let f = CIFilter.colorControls()
            f.inputImage = sky
            f.contrast = Float(1 + a.skyEnhance / 300)
            f.saturation = Float(1 + a.skyEnhance / 100 * 0.6)
            f.brightness = 0
            sky = f.outputImage ?? sky
            let v = CIFilter.vibrance()
            v.inputImage = sky
            v.amount = Float(a.skyEnhance / 100 * 0.5)
            sky = v.outputImage ?? sky
        }
        if a.skyLight != 0 { sky = Develop.exposure(sky, ev: a.skyLight / 100 * 1.2) }
        let ground = a.skyHarmonize > 0 ? harmonize(image, newSky: sky, mask: mask, amount: a.skyHarmonize / 100) : image
        // La máscara ya llega ajustada a los bordes de la foto (EdgeRefiner): no se difumina más.
        return Develop.blend(sky, over: ground, mask: mask)
    }

    /// «Armonizar con el cielo»: el resto de la foto toma algo del color y de la luz del cielo nuevo,
    /// como si la escena estuviera iluminada por él (un atardecer calienta el paisaje, una tormenta lo apaga).
    static func harmonize(_ image: CIImage, newSky: CIImage, mask: CIImage, amount: Double) -> CIImage {
        let extent = image.extent
        guard let old = average(image, mask: mask, extent: extent),
              let new = average(newSky, mask: mask, extent: extent) else { return image }
        func luma(_ c: [Float]) -> Float { max(0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2], 0.001) }
        // Color: el tinte del cielo nuevo (su color dividido por su brillo), aplicado con suavidad.
        let k = Float(amount) * 0.8
        let tint = (0..<3).map { 1 + k * (new[$0] / luma(new) - 1) }
        let normalize = 1 / max(0.299 * tint[0] + 0.587 * tint[1] + 0.114 * tint[2], 0.001)   // sin cambiar el brillo
        var result = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(tint[0] * normalize), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(tint[1] * normalize), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(tint[2] * normalize), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        // Luz: parte de la diferencia de brillo entre el cielo nuevo y el original (como mucho ±1,2 pasos).
        let ev = Double(log2(luma(new) / luma(old))) * 0.8 * amount
        if abs(ev) > 0.01 { result = Develop.exposure(result, ev: min(max(ev, -1.2), 1.2)) }
        return result.cropped(to: extent)
    }

    /// Color medio de `image` dentro de la máscara (media(foto × máscara) / media(máscara)).
    private static func average(_ image: CIImage, mask: CIImage, extent: CGRect) -> [Float]? {
        func mean(_ x: CIImage) -> [Float] {
            let avg = x.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
            var pixel = [Float](repeating: 0, count: 4)
            context.render(avg, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBAf, colorSpace: nil)
            return pixel
        }
        let area = mean(mask)[0]
        guard area > 0.02 else { return nil }
        let weighted = mean(image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask]))
        return (0..<3).map { weighted[$0] / area }
    }

    private static var fileCache: [String: CIImage] = [:]

    /// `horizon`: altura (en coordenadas de la foto) donde termina el cielo; el cielo nuevo se coloca con su
    /// horizonte ahí. Sin ella, se supone a un 30 % desde abajo.
    static func make(_ id: String, extent: CGRect, horizon: CGFloat? = nil) -> CIImage? {
        let horizon = horizon ?? extent.minY + extent.height * 0.3
        switch id {
        case "despejado": return gradient([(0, rgb(0.16, 0.38, 0.78)), (0.6, rgb(0.42, 0.65, 0.92)), (1, rgb(0.78, 0.88, 0.97))], extent, horizon)
        case "nubes":
            let base = gradient([(0, rgb(0.2, 0.42, 0.8)), (0.6, rgb(0.5, 0.7, 0.93)), (1, rgb(0.82, 0.9, 0.97))], extent, horizon)
            return clouds(over: base, color: rgb(1, 1, 1), density: 0.55, extent: extent)
        case "atardecer":
            let base = gradient([(0, rgb(0.18, 0.2, 0.45)), (0.45, rgb(0.75, 0.38, 0.45)), (0.8, rgb(0.98, 0.6, 0.3)),
                                 (1, rgb(1, 0.82, 0.5))], extent, horizon)
            return clouds(over: base, color: rgb(0.98, 0.7, 0.55), density: 0.35, extent: extent)
        case "dorado":
            let base = gradient([(0, rgb(0.45, 0.55, 0.75)), (0.6, rgb(0.95, 0.8, 0.55)), (1, rgb(1, 0.9, 0.65))], extent, horizon)
            return clouds(over: base, color: rgb(1, 0.93, 0.8), density: 0.4, extent: extent)
        case "tormenta":
            let base = gradient([(0, rgb(0.15, 0.17, 0.22)), (0.7, rgb(0.35, 0.38, 0.45)), (1, rgb(0.55, 0.57, 0.62))], extent, horizon)
            return clouds(over: base, color: rgb(0.62, 0.64, 0.7), density: 0.75, extent: extent)
        default:
            if fileCache[id] == nil { fileCache[id] = CIImage(contentsOf: URL(fileURLWithPath: id), options: [.applyOrientationProperty: true]) }
            guard let photo = fileCache[id] else { return nil }
            // El horizonte del cielo (su borde de abajo) va un poco por debajo del horizonte de la foto, y el
            // cielo cubre desde ahí hasta arriba; lo que sobre a los lados o arriba se recorta.
            let bottom = horizon - extent.height * 0.03
            let needed = max(extent.maxY - bottom, 1)
            let s = max(extent.width / photo.extent.width, needed / photo.extent.height)
            let scaled = photo.transformed(by: CGAffineTransform(scaleX: s, y: s))
            return scaled
                .transformed(by: CGAffineTransform(translationX: extent.midX - scaled.extent.midX, y: bottom - scaled.extent.minY))
                .clampedToExtent()
                .cropped(to: extent)
        }
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Altura del horizonte: la fila más baja (en una versión de 64 filas) que aún es cielo en su mayoría.
    static func horizon(of mask: CIImage, in extent: CGRect) -> CGFloat {
        let rows = 64, cols = 32
        let small = mask.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(cols) / extent.width, y: CGFloat(rows) / extent.height))
        var pixels = [Float](repeating: 0, count: rows * cols * 4)
        context.render(small, toBitmap: &pixels, rowBytes: cols * 16, bounds: CGRect(x: 0, y: 0, width: cols, height: rows),
                       format: .RGBAf, colorSpace: nil)
        // Fila 0 del mapa de bits = arriba. Se baja mientras más de un tercio de la fila sea cielo.
        var lowest = 0
        for row in 0..<rows {
            let sky = (0..<cols).reduce(Float(0)) { $0 + pixels[(row * cols + $1) * 4] } / Float(cols)
            if sky > 0.33 { lowest = row } else if row > lowest + 2 { break }
        }
        return extent.maxY - extent.height * CGFloat(lowest + 1) / CGFloat(rows)
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> CIColor { CIColor(red: r, green: g, blue: b) }

    /// Degradado vertical: posición 0 = arriba, 1 = a la altura del horizonte (a un tercio desde abajo);
    /// por debajo del horizonte sigue el último color.
    private static func gradient(_ stops: [(Double, CIColor)], _ extent: CGRect, _ horizon: CGFloat) -> CIImage {
        let rows = 256
        var pixels = [Float]()
        for row in 0..<rows {   // fila 0 = arriba
            let t = Double(row) / Double(rows - 1)
            let upper = stops.lastIndex { $0.0 <= t } ?? 0
            let lower = min(upper + 1, stops.count - 1)
            let (t0, c0) = stops[upper], (t1, c1) = stops[lower]
            let k = t1 > t0 ? (t - t0) / (t1 - t0) : 0
            pixels += [Float(c0.red + (c1.red - c0.red) * k), Float(c0.green + (c1.green - c0.green) * k),
                       Float(c0.blue + (c1.blue - c0.blue) * k), 1]
        }
        let column = CIImage(bitmapData: Data(bytes: pixels, count: pixels.count * 4), bytesPerRow: 16,
                             size: CGSize(width: 1, height: rows), format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let skyHeight = max(extent.maxY - horizon, extent.height * 0.2)
        return column
            .transformed(by: CGAffineTransform(scaleX: extent.width, y: skyHeight / CGFloat(rows)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.maxY - skyHeight))
            .clampedToExtent()
            .cropped(to: extent)
    }

    /// Nubes de ruido suave (dos escalas) pintadas de `color` sobre el degradado, más densas arriba.
    private static func clouds(over base: CIImage, color: CIColor, density: Double, extent: CGRect) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return base }
        let unit = extent.width / 100
        func octave(_ cell: CGFloat) -> CIImage {
            // Cada punto de ruido se convierte en una mancha de `cell` píxeles, más ancha que alta (nubes tendidas).
            noise.cropped(to: CGRect(x: 0, y: 0, width: 512, height: 512))
                .transformed(by: CGAffineTransform(scaleX: cell * 2, y: cell))
                .clampedToExtent()
                .applyingGaussianBlur(sigma: Double(cell) * 0.5)
                .cropped(to: extent)
        }
        let large = octave(unit * 3), small = octave(unit * 0.8)
        let mixed = Develop.mix(large, small, amount: 0.3)
        // Del ruido solo las zonas claras son nube; `density` sube o baja el umbral.
        // Son nube las zonas donde el ruido queda por debajo del umbral: salen islas redondeadas sobre el cielo.
        // Más `density`, umbral más alto y más nubes.
        let threshold = CGFloat(0.5 + density * 0.3), gain: CGFloat = 5
        let cloudMask = mixed.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -gain, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: -gain, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: -gain, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: threshold * gain, y: threshold * gain, z: threshold * gain, w: 0),
        ]).applyingFilter("CIColorClamp")
        // Hacia el horizonte las nubes se desvanecen.
        let fade = CIFilter.linearGradient()
        fade.point0 = CGPoint(x: 0, y: extent.maxY)
        fade.point1 = CGPoint(x: 0, y: extent.minY + extent.height * 0.35)
        fade.color0 = CIColor(red: 1, green: 1, blue: 1)
        fade.color1 = CIColor(red: 0.15, green: 0.15, blue: 0.15)
        let mask = cloudMask.applyingFilter("CIMultiplyCompositing",
                                            parameters: [kCIInputBackgroundImageKey: fade.outputImage!.cropped(to: extent)])
        let white = CIImage(color: color).cropped(to: extent)
        return Develop.blend(white, over: base, mask: mask.cropped(to: extent))
    }
}
