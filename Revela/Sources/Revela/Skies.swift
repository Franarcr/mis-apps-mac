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
    /// `subject`: las personas y objetos principales (Vision); no son lejanos, así que no reciben bruma.
    static func apply(_ a: Adjustments, to image: CIImage, mask: CIImage, subject: CIImage? = nil) -> CIImage {
        let extent = image.extent
        let replacement = a.skyReplacement.flatMap { make($0, extent: extent, horizon: horizon(of: mask, in: extent)) }
        // El cielo entra unos píxeles en los objetos: el borde claro que deja la mezcla de hoja y cielo viejo
        // queda cubierto (y el cielo viejo de ese borde se resta al componer).
        let grow = max(1, extent.width / 700)
        let oldSky = localSky(image, mask: mask)
        var sky = image
        if let replacement {
            if a.skyAmount >= 100 {
                sky = replacement
            } else {
                // Con menos intensidad, en el cielo abierto se mezcla con la foto (se intuyen las nubes viejas);
                // junto a los objetos, con el color del cielo viejo de la zona, para que no se transparenten
                // rejillas, ramas ni bordes.
                let amount = a.skyAmount / 100
                let far = Develop.mix(image, replacement, amount: amount)
                let near = Develop.mix(oldSky, replacement, amount: amount)
                // Cielo abierto = zonas amplias (los huecos de un árbol o de una rejilla no lo son, aunque sean
                // grandes: si no, unos toman un color y otros otro y quedan parches). Se calcula a 1/8 y el paso
                // de una mezcla a la otra es gradual.
                let small = CGAffineTransform(scaleX: 1.0 / 8, y: 1.0 / 8)
                let open = threshold(mask.transformed(by: small).clampedToExtent()
                    .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: extent.width / 40 / 8])
                    .applyingGaussianBlur(sigma: Double(extent.width / 50 / 8))
                    .transformed(by: small.inverted()).cropped(to: extent))
                sky = Develop.blend(far, over: near, mask: open)
            }
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
        var ground = a.skyHarmonize > 0 ? harmonize(image, newSky: sky, mask: mask, amount: a.skyHarmonize / 100) : image
        // Sin cielo nuevo (solo luz o realce del cielo de la foto) basta con mezclar con la máscara.
        guard replacement != nil else { return Develop.blend(sky, over: ground, mask: mask) }
        // Bruma y niebla son cosa de lo lejano: las personas de delante (aunque estén a la altura del
        // horizonte o junto al cielo) no las reciben.
        let unhazed = ground
        if a.skyHaze > 0 {
            ground = horizonHaze(ground, newSky: sky, mask: mask, horizon: horizon(of: mask, in: extent), amount: a.skyHaze / 100)
        }
        ground = liftFog(ground, reference: image, newSky: localSky(sky, mask: mask), oldSky: oldSky, mask: mask,
                         horizon: horizon(of: mask, in: extent))
        if let subject { ground = Develop.blend(unhazed, over: ground, mask: subject) }
        // Las estructuras finas junto al cielo (la rejilla de unas aspas, cables) que tienen casi el color del
        // cielo viejo están veladas por la misma niebla o luz: toman la parte proporcional del cielo nuevo.
        // (cerrado de la máscara a como mucho 2048 px de ancho: a tamaño completo es muy lento)
        let k = min(1, 2048 / extent.width)
        let down = CGAffineTransform(scaleX: k, y: k)
        let closed = mask.transformed(by: down).clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: grow * 3 * k])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: grow * 3 * k])
            .transformed(by: down.inverted()).cropped(to: extent)
        let thinObjects = Arith.mul(mask.applyingFilter("CIColorInvert").cropped(to: extent), closed)
        let third = CGFloat(1) / 3
        // (comparados como se ven, de 0 a 1: en un RAW el cielo quemado vale más que el blanco)
        let veil = ground.applyingFilter("CIColorClamp")
            .applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: oldSky.applyingFilter("CIColorClamp")])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: -2.5 * third, y: -2.5 * third, z: -2.5 * third, w: 0),
                "inputGVector": CIVector(x: -2.5 * third, y: -2.5 * third, z: -2.5 * third, w: 0),
                "inputBVector": CIVector(x: -2.5 * third, y: -2.5 * third, z: -2.5 * third, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
            ]).applyingFilter("CIColorClamp").cropped(to: extent)
        // Proporcional (×cielo nuevo / cielo viejo): con una resta, lo oscuro se pasaría de negro.
        ground = Develop.blend(relit(ground, newSky: sky, oldSky: oldSky, chroma: 0.5), over: ground,
                               mask: Arith.mul(thinObjects, veil))
        // Solo se crece junto a objetos gruesos (árboles, edificios): las estructuras finas (listones de las
        // aspas, cables, ramas sueltas) desaparecerían. Un objeto es grueso si sobrevive a una apertura.
        let notSky = mask.applyingFilter("CIColorInvert")
        let thick = notSky.clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: grow * 2])
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: grow * 3])
            .cropped(to: extent)
        let dilated = mask.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: grow])
            .applyingGaussianBlur(sigma: Double(grow) * 0.25).cropped(to: extent)
        // En todos los bordes, también los finos, el cielo entra 1–2 px: tapa el ribete sin borrar listones.
        let thin = mask.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(0.6, extent.width / 3500)])
            .cropped(to: extent)
        // Sobre las personas el cielo no crece (dejaría un halo claro alrededor de la cabeza).
        var dilatedNearThick = Arith.mul(dilated, thick)
        if let subject { dilatedNearThick = Arith.mul(dilatedNearThick, subject.applyingFilter("CIColorInvert").cropped(to: extent)) }
        // Ni en el follaje: entre hojas y huecos dibujaría contornos del cielo nuevo alrededor de cada mata.
        dilatedNearThick = Arith.mul(dilatedNearThick, Texture.map(image).applyingFilter("CIColorInvert").cropped(to: extent))
        let grown = dilatedNearThick.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: thin])
            .cropped(to: extent)
        return composite(sky, over: ground, oldSky: oldSky, mask: grown)
    }

    /// Niebla junto al cielo: los árboles y edificios lejanos se ven a través de un velo del color del cielo
    /// viejo (y entre ellos asoma ese cielo). Cuanto más se parece un píxel al cielo viejo de su zona, más velo
    /// tiene, y ese velo se cambia por el color del cielo nuevo. Lo oscuro o de otro color (lo cercano) no cambia.
    private static let fogKernel = CIColorKernel(source: """
        kernel vec4 fogVeil(__sample g, __sample o) {
            float lg = max((g.r + g.g + g.b) / 3.0, 0.001);
            float lo = max((o.r + o.g + o.b) / 3.0, 0.001);
            vec3 d = abs(g.rgb / lg - o.rgb / lo);
            float hue = clamp(1.0 - (d.r + d.g + d.b) / 3.0 / 0.12, 0.0, 1.0);
            float bright = clamp((lg / lo - 0.15) / 0.25, 0.0, 1.0);
            float v = hue * bright;
            return vec4(v, v, v, 1.0);
        }
        """)!

    /// `reference`: la foto antes de armonizar (para reconocer la niebla por su tono, que armonizar ya cambió).
    private static func liftFog(_ ground: CIImage, reference: CIImage, newSky: CIImage, oldSky: CIImage, mask: CIImage,
                                horizon: CGFloat) -> CIImage {
        let extent = ground.extent
        // Velo: lo que tiene el mismo tono que el cielo viejo de su zona (gris con gris), aunque sea más oscuro
        // (la niebla queda por debajo de un cielo quemado). Lo muy oscuro o de otro color no es velo.
        let veil = fogKernel.apply(extent: extent, arguments: [reference, oldSky]) ?? ground
        // Solo cerca del cielo y por encima del horizonte (lo de abajo, la orilla y el agua, está cerca).
        // (a 1/16 del tamaño: con un radio tan grande, a resolución completa no cabe en memoria)
        let small = CGAffineTransform(scaleX: 1.0 / 16, y: 1.0 / 16)
        let near = mask.transformed(by: small).clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: extent.width / 30 / 16])
            .applyingGaussianBlur(sigma: Double(extent.width / 80 / 16))
            .transformed(by: small.inverted()).cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.6, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1.6, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.6, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).applyingFilter("CIColorClamp").cropped(to: extent)
        let f = CIFilter.linearGradient()
        f.point0 = CGPoint(x: 0, y: horizon + extent.height * 0.01)
        f.point1 = CGPoint(x: 0, y: horizon - extent.height * 0.10)
        f.color0 = CIColor(red: 1, green: 1, blue: 1)
        f.color1 = CIColor(red: 0, green: 0, blue: 0)
        let region = Arith.mul(near, f.outputImage!.cropped(to: extent))
        // Solo la niebla de verdad, que es lisa: en el follaje con mucho detalle (un árbol cercano con huecos)
        // el parecido al cielo viene de los huecos, no de un velo, y teñirlo lo dejaría gris azulado.
        let smooth = Texture.map(reference).applyingFilter("CIColorInvert").cropped(to: extent)
        let weight = Arith.mul(Arith.mul(veil, region), smooth)
        return Develop.blend(relit(ground, newSky: newSky, oldSky: oldSky, chroma: 0.6), over: ground, mask: weight)
    }

    /// `image` con la luz del cielo nuevo en vez de la del viejo: ×(cielo nuevo / cielo viejo). Con `chroma` < 1 el
    /// cambio de color se suaviza (en objetos oscuros, la proporción de cada canal por separado satura mucho).
    private static func relit(_ image: CIImage, newSky: CIImage, oldSky: CIImage, chroma: Double = 1) -> CIImage {
        var r = Arith.ratio(newSky.applyingFilter("CIColorClamp"), oldSky.applyingFilter("CIColorClamp"))
        if chroma < 1 {
            let l = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            let gray = r.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": l, "inputGVector": l, "inputBVector": l, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            r = Develop.mix(gray, r, amount: chroma)
        }
        return Arith.mul(image, r).applyingFilter("CIColorClamp").cropped(to: image.extent)
    }

    /// Valores ≥ 0,9 → 1, el resto baja rápido a 0 (la parte segura de una máscara).
    private static func threshold(_ mask: CIImage) -> CIImage {
        mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 10, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 10, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 10, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: -9, y: -9, z: -9, w: 0),
        ]).applyingFilter("CIColorClamp").cropped(to: mask.extent)
    }

    /// Color del cielo viejo en cada zona: media del cielo seguro de alrededor (unos 100 px en una foto de 6000:
    /// así los huecos de una rejilla toman el color del cielo de alrededor y no el suyo).
    private static func localSky(_ image: CIImage, mask: CIImage) -> CIImage {
        let extent = image.extent
        // Se calcula a 1/8 del tamaño (el resultado es muy suave): a resolución completa no cabe en memoria.
        let small = CGAffineTransform(scaleX: 1.0 / 8, y: 1.0 / 8)
        let smallExtent = extent.applying(small)
        let sigma = Double(extent.width / 60 / 8)
        let core = threshold(mask)
        let num = Arith.mul(image, core).transformed(by: small).clampedToExtent()
            .applyingGaussianBlur(sigma: sigma).cropped(to: smallExtent)
        let den = core.transformed(by: small).clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: smallExtent)
            .applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0.001, y: 0.001, z: 0.001, w: 1)])
        // Se calcula una sola vez (si no, Core Image lo repite para cada trozo de la foto).
        var result = den.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: num])
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!   // el espacio de trabajo: sin conversión
        if let cg = context.createCGImage(result, from: smallExtent, format: .RGBAh, colorSpace: linear) {
            result = CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: smallExtent.minX, y: smallExtent.minY))
        }
        return result.clampedToExtent().transformed(by: small.inverted()).cropped(to: extent)
    }

    /// Pone el cielo nuevo quitando el viejo de los bordes: un píxel de borde con una proporción `m` de cielo
    /// es m·cielo viejo + (1 − m)·hoja; se le resta el cielo viejo de su zona y se suma el nuevo:
    /// resultado = foto + m·(cielo nuevo − cielo viejo). Así no queda contorno gris. Donde la máscara es
    /// segura se pone el cielo nuevo tal cual.
    private static func composite(_ newSky: CIImage, over ground: CIImage, oldSky: CIImage, mask: CIImage) -> CIImage {
        let extent = ground.extent
        // Proporcional: donde es cielo del todo da el cielo nuevo exacto; en el borde (hoja o niebla con cielo
        // viejo) cambia la luz del cielo sin restar de más (una resta dejaba un contorno oscuro).
        let edge = Develop.blend(relit(ground, newSky: newSky, oldSky: oldSky), over: ground, mask: mask)
        // Lo que es cielo en su mayoría (≥ 65 %) recibe el cielo nuevo tal cual; la fórmula de borde, solo
        // la franja fina (en huecos pequeños, como los de una rejilla, el cielo viejo puede ser más claro).
        let mostlySky = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 5, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 5, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 5, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: -2.25, y: -2.25, z: -2.25, w: 0),
        ]).applyingFilter("CIColorClamp").cropped(to: extent)
        return Develop.blend(newSky, over: edge, mask: mostlySky)
    }

    /// «Bruma del horizonte»: lo lejano, junto al horizonte, toma el color del cielo nuevo cerca del horizonte
    /// (perspectiva atmosférica). Así los edificios y árboles lejanos no quedan con el gris del cielo viejo.
    static func horizonHaze(_ image: CIImage, newSky: CIImage, mask: CIImage, horizon: CGFloat, amount: Double) -> CIImage {
        let extent = image.extent
        // Color del cielo nuevo en la franja justo encima del horizonte.
        let band = CGRect(x: extent.minX, y: horizon, width: extent.width, height: extent.height * 0.08).intersection(extent)
        guard band.height > 1 else { return image }
        let color = newSky.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: band)])
            .clampedToExtent().cropped(to: extent)
        // Más bruma en el horizonte y nada a un 15 % de la altura por debajo.
        let f = CIFilter.linearGradient()
        f.point0 = CGPoint(x: 0, y: horizon)
        f.point1 = CGPoint(x: 0, y: horizon - extent.height * 0.15)
        let k = CGFloat(amount)
        f.color0 = CIColor(red: k, green: k, blue: k)
        f.color1 = CIColor(red: 0, green: 0, blue: 0)
        let fade = f.outputImage!.cropped(to: extent)
        // Como la bruma real: lo lejano se mezcla con el color del aire, sin perder del todo sus formas.
        let mixed = Develop.mix(image, color, amount: 0.75)
        return Develop.blend(mixed, over: image, mask: fade)
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
        // Sobre una copia de unos 512 px: la media es la misma y no obliga a calcular la foto completa.
        let k = min(1, 512 / max(extent.width, extent.height))
        func mean(_ full: CIImage) -> [Float] {
            let x = full.transformed(by: CGAffineTransform(scaleX: k, y: k))
            let avg = x.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: x.extent)])
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
            guard let original = fileCache[id] else { return nil }
            // Sin los bordes de la foto (a veces tienen un viñeteado o una línea oscura): por debajo del
            // horizonte, donde la foto de cielo no llega, se prolonga su última fila, y esa fila ha de ser cielo.
            let e = original.extent
            let photo = original.cropped(to: CGRect(x: e.minX + e.width * 0.01, y: e.minY + e.height * 0.03,
                                                    width: e.width * 0.98, height: e.height * 0.96))
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
