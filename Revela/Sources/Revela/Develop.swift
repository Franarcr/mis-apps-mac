import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Todos los ajustes de una foto. Se guardan aparte (la foto original nunca se modifica).
struct Adjustments: Codable, Equatable {
    // Luz
    var exposure: Double = 0        // -3…3 pasos
    var contrast: Double = 0        // -100…100
    var highlights: Double = 0      // -100…100
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    // Color
    var temperature: Double = 0     // -100 (frío)…100 (cálido)
    var tint: Double = 0            // -100 (verde)…100 (magenta)
    var vibrance: Double = 0
    var saturation: Double = 0
    // Detalle
    var clarity: Double = 0         // 0…100
    var sharpness: Double = 0       // 0…100
    // Efectos
    var vignette: Double = 0        // 0…100
    var look: String?               // nombre de un look o ruta de un .cube
    var lookAmount: Double = 100
    // IA
    var autoEnhance = false
    var straighten: Double = 0      // grados
    var backgroundBlur: Double = 0  // 0…100
    var subjectLight: Double = 0    // -100…100
    var backgroundLight: Double = 0 // -100…100

    var usesSubjectMask: Bool { backgroundBlur > 0 || subjectLight != 0 || backgroundLight != 0 }
    static let neutral = Adjustments()
}

/// Aplica los ajustes a una imagen. Todo es Core Image (en la GPU) y no destructivo.
enum Develop {
    /// `mask`: máscara del sujeto (blanco = sujeto) del mismo tamaño que `image`, si hace falta.
    /// `scale`: tamaño relativo a la foto completa (para que radios y texturas se vean igual en la vista previa).
    static func apply(_ a: Adjustments, to image: CIImage, mask: CIImage?, scale: Double) -> CIImage {
        var img = image
        let extent = image.extent

        if a.autoEnhance {
            for filter in image.autoAdjustmentFilters(options: [.redEye: false]) {
                filter.setValue(img, forKey: kCIInputImageKey)
                img = filter.outputImage ?? img
            }
        }

        // Luz del sujeto y del fondo (con la máscara de la IA), antes del resto para que el color se aplique igual.
        if let mask, a.subjectLight != 0 || a.backgroundLight != 0 {
            let subject = exposure(img, ev: a.subjectLight / 100 * 1.2)
            let background = exposure(img, ev: a.backgroundLight / 100 * 1.5)
            img = blend(subject, over: background, mask: mask)
        }

        if a.exposure != 0 { img = exposure(img, ev: a.exposure) }

        if a.temperature != 0 || a.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 + a.temperature * 30, y: a.tint * 0.8)
            img = f.outputImage ?? img
        }

        // Recuperar luces y abrir sombras de forma "inteligente"; lo demás, con una curva.
        if a.highlights < 0 || a.shadows > 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = img
            f.highlightAmount = Float(1 + min(a.highlights, 0) / 100)
            f.shadowAmount = Float(max(a.shadows, 0) / 100)
            f.radius = Float(max(1, 10 * scale))
            img = f.outputImage ?? img
        }
        if a.highlights > 0 || a.shadows < 0 || a.whites != 0 || a.blacks != 0 {
            let f = CIFilter.toneCurve()
            f.inputImage = img
            f.point0 = CGPoint(x: 0, y: max(0, a.blacks / 100 * 0.12))
            f.point1 = CGPoint(x: 0.25, y: 0.25 + min(a.shadows, 0) / 100 * 0.1 + min(a.blacks, 0) / 100 * 0.05)
            f.point2 = CGPoint(x: 0.5, y: 0.5)
            f.point3 = CGPoint(x: 0.75, y: 0.75 + max(a.highlights, 0) / 100 * 0.1 + max(a.whites, 0) / 100 * 0.04)
            f.point4 = CGPoint(x: 1, y: 1 + min(a.whites, 0) / 100 * 0.12)
            img = f.outputImage ?? img
        }

        if a.contrast != 0 || a.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = img
            f.contrast = Float(1 + a.contrast / 250)
            f.saturation = Float(1 + a.saturation / 100)
            f.brightness = 0
            img = f.outputImage ?? img
        }
        if a.vibrance != 0 {
            let f = CIFilter.vibrance()
            f.inputImage = img
            f.amount = Float(a.vibrance / 100)
            img = f.outputImage ?? img
        }

        if a.clarity > 0 {
            // Contraste local: máscara de enfoque con radio grande.
            let f = CIFilter.unsharpMask()
            f.inputImage = img
            f.radius = Float(max(2, 40 * scale))
            f.intensity = Float(a.clarity / 100 * 0.7)
            img = f.outputImage ?? img
        }

        if let look = a.look, a.lookAmount > 0, let styled = Looks.apply(look, to: img) {
            img = a.lookAmount >= 100 ? styled : mix(img, styled, amount: a.lookAmount / 100)
        }

        if let mask, a.backgroundBlur > 0 {
            let blurred = img.clampedToExtent()
                .applyingGaussianBlur(sigma: a.backgroundBlur / 100 * 30 * scale)
                .cropped(to: img.extent)
            img = blend(img, over: blurred, mask: mask)
        }

        if a.sharpness > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = img
            f.sharpness = Float(a.sharpness / 100 * 1.2)
            f.radius = Float(max(0.5, 1.6 * scale))
            img = f.outputImage ?? img
        }

        if a.vignette > 0 {
            let f = CIFilter.vignette()
            f.inputImage = img
            f.intensity = Float(a.vignette / 100 * 1.6)
            f.radius = Float(a.vignette / 100 * 2 + 1)
            img = f.outputImage ?? img
        }

        if a.straighten != 0 {
            let f = CIFilter.straighten()
            f.inputImage = img
            f.angle = Float(a.straighten * .pi / 180)
            img = f.outputImage ?? img
        }

        return img.cropped(to: extent)
    }

    static func exposure(_ image: CIImage, ev: Double) -> CIImage {
        let f = CIFilter.exposureAdjust()
        f.inputImage = image
        f.ev = Float(ev)
        return f.outputImage ?? image
    }

    /// `top` donde la máscara es blanca, `bottom` donde es negra.
    static func blend(_ top: CIImage, over bottom: CIImage, mask: CIImage) -> CIImage {
        let f = CIFilter.blendWithMask()
        f.inputImage = top
        f.backgroundImage = bottom
        f.maskImage = mask
        return f.outputImage ?? top
    }

    static func mix(_ a: CIImage, _ b: CIImage, amount: Double) -> CIImage {
        let f = CIFilter.dissolveTransition()
        f.inputImage = a
        f.targetImage = b
        f.time = Float(amount)
        return f.outputImage ?? b
    }
}
