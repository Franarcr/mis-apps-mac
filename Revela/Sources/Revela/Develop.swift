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
    var lensBlur: Double = 0        // 0…100, según la profundidad
    // Retrato
    var skinSmoothing: Double = 0   // 0…100
    var eyes: Double = 0            // 0…100
    var teeth: Double = 0           // 0…100
    // Selección con un clic (SAM): dónde se hizo clic y los ajustes de esa zona
    var selection: [SelectionPoint] = []
    var selExposure: Double = 0     // -100…100
    var selContrast: Double = 0
    var selSaturation: Double = 0
    var selTemperature: Double = 0
    // Cielo
    var skyLight: Double = 0        // -100…100
    var skyEnhance: Double = 0      // 0…100
    var skyReplacement: String?     // cielo incluido o ruta de una foto de cielo
    var skyAmount: Double = 100
    var skyHarmonize: Double = 0    // 0…100: el resto de la foto toma color y luz del cielo
    var skyHaze: Double = 0         // 0…100: bruma del color del cielo nuevo junto al horizonte

    // Agua: dónde se hizo clic y sus ajustes
    var water: [SelectionPoint] = []
    var waterTint: Double = 0        // 0…100: color del cielo en el agua
    var waterReflection: Double = 0  // 0…100
    var waterLight: Double = 0       // -100…100
    // Borrar objetos (LaMa): trazos del pincel
    var erase: [EraseStroke] = []

    var usesSelection: Bool { !selection.isEmpty }
    var usesSky: Bool { skyLight != 0 || skyEnhance > 0 || skyReplacement != nil || skyHarmonize > 0 }
    var usesWater: Bool { !water.isEmpty }
    var usesSubjectMask: Bool { backgroundBlur > 0 || subjectLight != 0 || backgroundLight != 0 }
    var usesFaces: Bool { skinSmoothing > 0 || eyes > 0 || teeth > 0 }
    var usesDepth: Bool { lensBlur > 0 }

    init() {}

    // Los ajustes guardados antes de añadir un control nuevo se leen con ese control a cero.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read(_ key: CodingKeys, _ value: inout Double) { if let v = try? c.decode(Double.self, forKey: key) { value = v } }
        read(.exposure, &exposure); read(.contrast, &contrast); read(.highlights, &highlights); read(.shadows, &shadows)
        read(.whites, &whites); read(.blacks, &blacks); read(.temperature, &temperature); read(.tint, &tint)
        read(.vibrance, &vibrance); read(.saturation, &saturation); read(.clarity, &clarity); read(.sharpness, &sharpness)
        read(.vignette, &vignette); read(.lookAmount, &lookAmount); read(.straighten, &straighten)
        read(.backgroundBlur, &backgroundBlur); read(.subjectLight, &subjectLight); read(.backgroundLight, &backgroundLight)
        read(.lensBlur, &lensBlur); read(.skinSmoothing, &skinSmoothing); read(.eyes, &eyes); read(.teeth, &teeth)
        read(.selExposure, &selExposure); read(.selContrast, &selContrast); read(.selSaturation, &selSaturation)
        read(.selTemperature, &selTemperature); read(.skyLight, &skyLight); read(.skyEnhance, &skyEnhance); read(.skyAmount, &skyAmount); read(.skyHarmonize, &skyHarmonize); read(.skyHaze, &skyHaze)
        selection = (try? c.decode([SelectionPoint].self, forKey: .selection)) ?? []
        erase = (try? c.decode([EraseStroke].self, forKey: .erase)) ?? []
        water = (try? c.decode([SelectionPoint].self, forKey: .water)) ?? []
        read(.waterTint, &waterTint); read(.waterReflection, &waterReflection); read(.waterLight, &waterLight)
        skyReplacement = try? c.decode(String.self, forKey: .skyReplacement)
        look = try? c.decode(String.self, forKey: .look)
        autoEnhance = (try? c.decode(Bool.self, forKey: .autoEnhance)) ?? false
    }
    static let neutral = Adjustments()

    /// Los ajustes que tienen sentido en otra foto: sin los clics de selección y de agua, los trazos de
    /// borrar ni el enderezado, que dependen de dónde está cada cosa en esta foto.
    var transferable: Adjustments {
        var a = self
        a.keepPhotoSpecific(from: .neutral)
        return a
    }

    /// Copia de `other` lo que es propio de una foto (clics, trazos, enderezado y sus ajustes).
    mutating func keepPhotoSpecific(from other: Adjustments) {
        selection = other.selection
        selExposure = other.selExposure; selContrast = other.selContrast
        selSaturation = other.selSaturation; selTemperature = other.selTemperature
        water = other.water
        waterTint = other.waterTint; waterReflection = other.waterReflection; waterLight = other.waterLight
        erase = other.erase
        straighten = other.straighten
    }
}

/// Aplica los ajustes a una imagen. Todo es Core Image (en la GPU) y no destructivo.
enum Develop {
    /// `mask`: máscara del sujeto (blanco = sujeto) del mismo tamaño que `image`, si hace falta.
    /// `scale`: tamaño relativo a la foto completa (para que radios y texturas se vean igual en la vista previa).
    static func apply(_ a: Adjustments, to image: CIImage, mask: CIImage?, faces: FaceMasks? = nil,
                      depth: DepthInfo? = nil, selection: CIImage? = nil, sky: CIImage? = nil,
                      water: CIImage? = nil, scale: Double) -> CIImage {
        var img = image
        let extent = image.extent

        if a.autoEnhance {
            for filter in image.autoAdjustmentFilters(options: [.redEye: false]) {
                filter.setValue(img, forKey: kCIInputImageKey)
                img = filter.outputImage ?? img
            }
        }

        // Retrato: antes que el color, para que el retoque se funda con el resto.
        if let faces {
            if a.skinSmoothing > 0 { img = Retouch.smoothSkin(img, masks: faces, amount: a.skinSmoothing, scale: scale) }
            if a.eyes > 0 { img = Retouch.brightenEyes(img, masks: faces, amount: a.eyes) }
            if a.teeth > 0 { img = Retouch.whitenTeeth(img, masks: faces, amount: a.teeth) }
        }

        // Cielo: se cambia o se realza antes de los ajustes generales, para que todo quede con el mismo tono.
        if let sky, a.usesSky {
            img = Skies.apply(a, to: img, mask: sky)
        }

        // Agua: después del cielo, para tomar su color (el cambiado, si se cambió).
        if let water, a.waterTint > 0 || a.waterReflection > 0 || a.waterLight != 0 {
            img = Water.apply(a, to: img, water: water, sky: sky)
        }

        // Ajustes solo en la zona seleccionada con un clic.
        if let selection, a.selExposure != 0 || a.selContrast != 0 || a.selSaturation != 0 || a.selTemperature != 0 {
            var local = img
            if a.selExposure != 0 { local = exposure(local, ev: a.selExposure / 100 * 1.5) }
            if a.selTemperature != 0 {
                let f = CIFilter.temperatureAndTint()
                f.inputImage = local
                f.neutral = CIVector(x: 6500, y: 0)
                f.targetNeutral = CIVector(x: 6500 + a.selTemperature * 30, y: 0)
                local = f.outputImage ?? local
            }
            if a.selContrast != 0 || a.selSaturation != 0 {
                let f = CIFilter.colorControls()
                f.inputImage = local
                f.contrast = Float(1 + a.selContrast / 250)
                f.saturation = Float(1 + a.selSaturation / 100)
                f.brightness = 0
                local = f.outputImage ?? local
            }
            img = blend(local, over: img, mask: selection)
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
            let blurred = blurBehind(img, subject: mask, sigma: a.backgroundBlur / 100 * 30 * scale)
            img = blend(img, over: blurred, mask: mask)
        }

        if let depth, a.lensBlur > 0 {
            img = lensBlur(img, depth: depth, subject: mask, amount: a.lensBlur, scale: scale)
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

    /// Desenfoca el fondo sin que el color del sujeto se derrame alrededor (sin halo): se desenfoca
    /// solo lo que no es sujeto y se divide por la máscara desenfocada ("convolución normalizada").
    static func blurBehind(_ image: CIImage, subject: CIImage, sigma: Double) -> CIImage {
        let extent = image.extent
        let background = subject.applyingFilter("CIColorInvert")
        let onlyBackground = image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: background])
        let blurredImage = onlyBackground.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        let weight = background.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
            .applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0.02, y: 0.02, z: 0.02, w: 1)])
        return blurredImage.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: blurredImage,
                                                                            kCIInputImageKey: weight])
    }

    /// Desenfoque de lente: más desenfoque cuanto más lejos (o más cerca) está algo del plano enfocado.
    static func lensBlur(_ image: CIImage, depth: DepthInfo, subject: CIImage?, amount: Double, scale: Double) -> CIImage {
        let f = CGFloat(depth.focus)
        // Detrás del plano enfocado: (foco − profundidad) × 3. Delante, la mitad.
        func ramp(_ k: CGFloat, _ bias: CGFloat) -> CIImage {
            depth.map.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
            ]).applyingFilter("CIColorClamp")
        }
        let behind = ramp(-3, f * 3), front = ramp(1.5, -f * 1.5)
        var blurMask = behind.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: front])
            .applyingFilter("CIColorClamp")
        if let subject {
            // El sujeto siempre queda nítido.
            let black = CIImage(color: .black).cropped(to: image.extent)
            blurMask = blend(black, over: blurMask, mask: subject)
        }
        let source = subject.map { blend(image, over: blurBehind(image, subject: $0, sigma: 6 * scale), mask: $0) } ?? image
        let f2 = CIFilter.maskedVariableBlur()
        f2.inputImage = source.clampedToExtent()
        f2.mask = blurMask.clampedToExtent()
        f2.radius = Float(amount / 100 * 30 * scale)
        let blurred = (f2.outputImage ?? source).cropped(to: image.extent)
        return subject.map { blend(image, over: blurred, mask: $0) } ?? blurred
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
