import CoreImage
import CoreImage.CIFilterBuiltins

/// Agua congruente con el cielo: tono, reflejo y luz, solo dentro de la máscara del agua.
enum Water {
    static func apply(_ a: Adjustments, to image: CIImage, water mask: CIImage, sky: CIImage?) -> CIImage {
        let extent = image.extent
        var result = image
        let skyMask = sky ?? horizonGuess(extent)

        if a.waterTint > 0 {
            // Color medio del cielo = media(foto × cielo) / media(cielo). Se calcula en la GPU, sin leer píxeles.
            let average = { (x: CIImage) in
                x.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)]).clampedToExtent()
            }
            let weighted = image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: skyMask])
            let skyColor = average(skyMask).applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: average(weighted)])
                .cropped(to: extent)
            // Modo «color»: tono y saturación del cielo con la luz (olas, brillos) del agua.
            let tinted = skyColor.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: result])
            result = Develop.mix(result, tinted, amount: a.waterTint / 100 * 0.8)
        }

        if a.waterReflection > 0 {
            // El cielo reflejado: la foto volteada sobre la línea de horizonte (lo más bajo del cielo),
            // algo desenfocada y estirada en vertical, como en un agua con ondas.
            let horizon = lowestSkyY(skyMask, extent: extent)
            let flipped = image
                .transformed(by: CGAffineTransform(translationX: 0, y: -horizon))
                .transformed(by: CGAffineTransform(scaleX: 1, y: -1.15))
                .transformed(by: CGAffineTransform(translationX: 0, y: horizon))
            let reflection = flipped.clampedToExtent().applyingGaussianBlur(sigma: Double(extent.width / 600)).cropped(to: extent)
            let reflected = reflection.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: result])
            result = Develop.mix(result, reflected, amount: a.waterReflection / 100)
        }

        if a.waterLight != 0 { result = Develop.exposure(result, ev: a.waterLight / 100 * 1.2) }

        return Develop.blend(result, over: image, mask: mask)
    }

    /// Sin máscara de cielo: se toma como cielo el tercio superior de la foto.
    private static func horizonGuess(_ extent: CGRect) -> CIImage {
        let f = CIFilter.linearGradient()
        f.point0 = CGPoint(x: 0, y: extent.maxY - extent.height * 0.25)
        f.point1 = CGPoint(x: 0, y: extent.maxY - extent.height * 0.4)
        f.color0 = CIColor(red: 1, green: 1, blue: 1)
        f.color1 = CIColor(red: 0, green: 0, blue: 0)
        return f.outputImage!.cropped(to: extent)
    }

    /// Altura aproximada del horizonte: el borde inferior medio del cielo (con su media vertical).
    private static func lowestSkyY(_ skyMask: CIImage, extent: CGRect) -> CGFloat {
        // Media del cielo por filas no es posible sin leer píxeles; se usa la fracción de cielo de la foto:
        // si el cielo ocupa el 60 % de arriba, el horizonte está al 40 % de la altura.
        let context = CIContext(options: [.cacheIntermediates: false])
        let avg = skyMask.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(avg, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return extent.minY + extent.height * CGFloat(1 - pixel[0])
    }
}
