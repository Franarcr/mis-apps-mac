import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// La atmósfera de la foto: quitar la neblina de lo lejano y reiluminar la escena según el cielo.
enum Atmosphere {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// «Quitar neblina» (dark channel prior): la neblina es un velo del color del aire que crece con la
    /// distancia. Se estima cuánto velo tiene cada zona (lo que le falta para tener algún canal oscuro) y se
    /// quita: J = A + (I − A) / t. Con el mapa de profundidad actúa en lo lejano y apenas en lo cercano;
    /// el cielo no se toca.
    static func dehaze(_ image: CIImage, depth: DepthInfo?, sky: CIImage?, amount: Double) -> CIImage {
        let extent = image.extent
        // Lo lejano: 1 en el fondo, 0 delante (sin profundidad, toda la foto por igual).
        var far = depth.map { $0.map.applyingFilter("CIColorInvert").cropped(to: extent) }
            ?? CIImage(color: .white).cropped(to: extent)
        if let sky { far = Arith.mul(far, sky.applyingFilter("CIColorInvert")).cropped(to: extent) }

        // Color del aire: el de la neblina más lejana (sin profundidad, lo más claro de la foto).
        let airWeight = depth.map { d in
            d.map.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: -4, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: -4, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: -4, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
            ]).applyingFilter("CIColorClamp").cropped(to: extent)
        } ?? CIImage(color: .white).cropped(to: extent)
        guard let air = average(image, weight: airWeight), air.allSatisfy({ $0 > 0.02 }) else { return image }

        // Canal oscuro de I / A: el mínimo de los tres canales, también en un entorno pequeño. Se calcula a 1/4
        // (es suave) y vuelve a tamaño completo.
        let normalized = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(1 / air[0]), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(1 / air[1]), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(1 / air[2]), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        func channel(_ v: CIVector) -> CIImage {
            normalized.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": v, "inputGVector": v, "inputBVector": v, "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }
        let darkest = channel(CIVector(x: 1, y: 0, z: 0, w: 0))
            .applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: channel(CIVector(x: 0, y: 1, z: 0, w: 0))])
            .applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: channel(CIVector(x: 0, y: 0, z: 1, w: 0))])
        let small = CGAffineTransform(scaleX: 0.25, y: 0.25)
        let radius = max(1, extent.width / 500 * 0.25)   // 12 px en una foto de 6000 (3 a 1/4)
        let dark = darkest.transformed(by: small).clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius])
            .applyingGaussianBlur(sigma: Double(radius))
            .transformed(by: small.inverted()).cropped(to: extent)

        // Transmisión t = 1 − ω · velo · lejanía, nunca por debajo de 0,35 (si no, se dispara el ruido).
        let omega = CGFloat(amount / 100 * 0.9)
        let haze = Arith.mul(dark.applyingFilter("CIColorClamp"), far)
        let t = haze.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -omega, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: -omega, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: -omega, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ]).applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0.35, y: 0.35, z: 0.35, w: 1)])
            .cropped(to: extent)
        let airImage = CIImage(color: CIColor(red: CGFloat(air[0]), green: CGFloat(air[1]), blue: CGFloat(air[2])))
            .cropped(to: extent)
        let veil = Arith.sub(image, airImage)
        // (I − A) es negativo en lo oscuro: se multiplica por 1 / t en vez de dividir con un modo de fusión)
        let inverse = t.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: CIImage(color: .white).cropped(to: extent)])
        let lifted = Arith.mul(veil, inverse)
        return Arith.add(lifted, airImage).applyingFilter("CIColorClamp").cropped(to: extent)
    }

    /// «Reiluminar la escena»: el paisaje toma la luz del cielo que tiene encima. Con un cielo soleado
    /// (azul, saturado) se aclara, se limpia el tono gris de un día nublado, se calienta un poco y gana
    /// contraste y color; con uno de tormenta se apaga y se enfría. Lo cercano cambia más que lo lejano.
    static func relight(_ image: CIImage, sky: CIImage?, depth: DepthInfo?, amount: Double) -> CIImage {
        let extent = image.extent
        let k = amount / 100
        // El cielo y su borde (que ya tiene el cielo nuevo, también donde entra unos píxeles en los objetos)
        // no se reiluminan: si no, quedaría un halo claro alrededor de todo.
        let notSky = sky.map { mask in
            mask.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 4, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 4, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 4, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).applyingFilter("CIColorClamp").clampedToExtent()
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(1, extent.width / 700) * 1.5])
                .cropped(to: extent).applyingFilter("CIColorInvert").cropped(to: extent)
        } ?? CIImage(color: .white).cropped(to: extent)
        guard let ground = average(image, weight: notSky) else { return image }
        func luma(_ c: [Float]) -> Double { Double(max(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2], 0.001)) }

        // Cuánto sol hay: un cielo saturado y claro es soleado; uno gris oscuro, de tormenta.
        var sunny = 0.5
        if let sky, let s = average(image, weight: sky) {
            let high = Double(s.max() ?? 0), low = Double(s.min() ?? 0)
            let saturation = high > 0.001 ? (high - low) / high : 0
            sunny = min(max((saturation - 0.15) * 2.5 + (luma(s) - 0.25) * 1.5, 0), 1)
        }

        // Luz: el suelo se lleva hacia un gris medio de día de sol (o de tormenta), hasta +1 / −0,7 pasos.
        let target = 0.10 + 0.10 * sunny
        let ev = min(max(log2(target / luma(ground)), -0.7), 1.0) * k
        var lit = Develop.exposure(image, ev: ev)

        // Color: la luz del sol calienta un poco y la de tormenta enfría. (No se neutraliza el tono medio del
        // suelo: en un paisaje es el verde de la vegetación, no una dominante.)
        let warm = (sunny - 0.4) * 0.10 * k
        let gains = [1 + warm, 1, 1 - warm]
        let norm = 1 / (0.2126 * gains[0] + 0.7152 * gains[1] + 0.0722 * gains[2])
        lit = lit.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(gains[0] * norm), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(gains[1] * norm), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(gains[2] * norm), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])

        // Con sol, sombras más abiertas (la luz llega a todas partes) y más color; con tormenta, menos color.
        if sunny > 0.3 {
            let h = CIFilter.highlightShadowAdjust()
            h.inputImage = lit
            h.shadowAmount = Float((sunny - 0.3) * 0.5 * k)
            h.highlightAmount = 1
            h.radius = Float(max(1, extent.width / 600))
            lit = h.outputImage ?? lit
        }
        let c = CIFilter.colorControls()
        c.inputImage = lit
        c.contrast = 1
        c.saturation = Float(1 + (sunny - 0.4) * 0.15 * k)
        c.brightness = 0
        lit = c.outputImage ?? lit
        let v = CIFilter.vibrance()
        v.inputImage = lit
        v.amount = Float(sunny * 0.3 * k)
        lit = v.outputImage ?? lit

        // Solo el paisaje; lo cercano del todo, lo lejano a medias (allí manda la bruma).
        var weight = notSky
        if let depth {
            let near = depth.map.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.6, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0.6, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0.6, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.4, y: 0.4, z: 0.4, w: 0),
            ]).cropped(to: extent)
            weight = Arith.mul(weight, near)
        }
        return Develop.blend(lit, over: image, mask: weight.cropped(to: extent))
    }

    /// Media de `image` ponderada por `weight` (gris).
    private static func average(_ image: CIImage, weight: CIImage) -> [Float]? {
        let extent = image.extent
        // Sobre una copia de unos 512 px: la media es la misma y no obliga a calcular la foto completa.
        let k = min(1, 512 / max(extent.width, extent.height))
        let small = CGAffineTransform(scaleX: k, y: k)
        func mean(_ full: CIImage) -> [Float] {
            var pixel = [Float](repeating: 0, count: 4)
            let img = full.transformed(by: small)
            let avg = img.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: img.extent)])
            context.render(avg, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBAf, colorSpace: nil)
            return pixel
        }
        let w = mean(weight)[0]
        guard w > 0.01 else { return nil }
        let m = mean(Arith.mul(image, weight))
        return (0..<3).map { m[$0] / w }
    }
}
