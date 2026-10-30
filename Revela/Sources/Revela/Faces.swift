import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Zonas de las caras de una foto (con la detección de caras de macOS), como máscaras en escala de grises.
struct FaceMasks {
    /// Piel de la cara: el óvalo de la cara sin ojos, cejas ni boca.
    let skin: CIImage
    let eyes: CIImage
    let teeth: CIImage
    /// Ancho medio de las caras, en píxeles (para que el suavizado dependa del tamaño de la cara).
    let faceWidth: CGFloat
    let count: Int

    static func detect(in image: CIImage, context: CIContext) -> FaceMasks? {
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        let request = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        let faces = (request.results ?? []).filter { $0.landmarks != nil && $0.confidence > 0.5 }
        guard !faces.isEmpty else { return nil }

        let size = image.extent.size
        let skin = MaskCanvas(size: size), eyes = MaskCanvas(size: size), teeth = MaskCanvas(size: size)
        var widths: CGFloat = 0
        for face in faces {
            guard let landmarks = face.landmarks else { continue }
            let box = VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height))
            widths += box.width
            func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                region?.pointsInImage(imageSize: size) ?? []
            }

            // Óvalo de la cara: la caja de Vision llega de cejas a barbilla; se amplía para incluir la frente.
            let oval = CGRect(x: box.minX - box.width * 0.05, y: box.minY - box.height * 0.05,
                              width: box.width * 1.1, height: box.height * 1.35)
            skin.fill(ellipse: oval, value: 1, blur: box.width * 0.08)
            for region in [landmarks.leftEye, landmarks.rightEye, landmarks.leftEyebrow, landmarks.rightEyebrow] {
                skin.fill(polygon: points(region), value: 0, grow: box.width * 0.04, blur: box.width * 0.03)
            }
            skin.fill(polygon: points(landmarks.outerLips), value: 0, grow: box.width * 0.03, blur: box.width * 0.03)

            for region in [landmarks.leftEye, landmarks.rightEye] {
                eyes.fill(polygon: points(region), value: 1, grow: 0, blur: box.width * 0.012)
            }
            teeth.fill(polygon: points(landmarks.innerLips), value: 1, grow: 0, blur: box.width * 0.01)
        }
        return FaceMasks(skin: skin.image(), eyes: eyes.image(), teeth: teeth.image(),
                         faceWidth: widths / CGFloat(faces.count), count: faces.count)
    }
}

/// Lienzo en escala de grises para dibujar máscaras (0 = fuera, 1 = dentro).
private final class MaskCanvas {
    private let size: CGSize
    private var current: CIImage

    init(size: CGSize) {
        self.size = size
        current = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
    }

    func fill(ellipse rect: CGRect, value: CGFloat, blur: CGFloat) {
        draw(CGPath(ellipseIn: rect, transform: nil), value: value, blur: blur)
    }

    func fill(polygon points: [CGPoint], value: CGFloat, grow: CGFloat, blur: CGFloat) {
        guard points.count >= 3 else { return }
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        // "grow" ensancha la forma con un trazo grueso alrededor.
        let shape = grow > 0 ? path.copy(strokingWithWidth: grow * 2, lineCap: .round, lineJoin: .round, miterLimit: 1) : path
        let combined = CGMutablePath()
        combined.addPath(path)
        combined.addPath(shape)
        draw(combined, value: value, blur: blur)
    }

    /// Dibuja la forma en una capa propia, la difumina y la funde con lo anterior.
    private func draw(_ path: CGPath, value: CGFloat, blur: CGFloat) {
        let width = Int(size.width), height = Int(size.height)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(path)
        ctx.fillPath(using: .winding)
        guard let cg = ctx.makeImage() else { return }
        let extent = CGRect(origin: .zero, size: size)
        let shape = CIImage(cgImage: cg).clampedToExtent().applyingGaussianBlur(sigma: max(blur, 0.5)).cropped(to: extent)
        // Dentro de la forma, el valor nuevo; fuera, lo que había.
        let fill = CIImage(color: CIColor(red: value, green: value, blue: value)).cropped(to: extent)
        current = fill.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: current, kCIInputMaskImageKey: shape])
    }

    func image() -> CIImage { current }
}

enum Retouch {
    /// Suaviza la piel conservando algo de textura: se mezcla una versión desenfocada solo en la piel.
    static func smoothSkin(_ image: CIImage, masks: FaceMasks, amount: Double, scale: Double) -> CIImage {
        let sigma = Double(masks.faceWidth) / 70
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: image.extent)
        // Al 100 % aún queda un 30 % de la textura original, para que la piel no parezca plástico.
        let mixed = Develop.mix(image, blurred, amount: amount / 100 * 0.7)
        return Develop.blend(mixed, over: image, mask: masks.skin)
    }

    static func brightenEyes(_ image: CIImage, masks: FaceMasks, amount: Double) -> CIImage {
        var eyes = Develop.exposure(image, ev: amount / 100 * 0.6)
        let f = CIFilter.sharpenLuminance()
        f.inputImage = eyes
        f.sharpness = Float(amount / 100)
        f.radius = 1.5
        eyes = f.outputImage ?? eyes
        return Develop.blend(eyes, over: image, mask: masks.eyes)
    }

    /// Dientes más blancos: menos amarillo y un poco más de luz, solo dentro de la boca.
    static func whitenTeeth(_ image: CIImage, masks: FaceMasks, amount: Double) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = image
        f.saturation = Float(1 - amount / 100 * 0.6)
        f.brightness = 0
        f.contrast = 1
        let white = Develop.exposure(f.outputImage ?? image, ev: amount / 100 * 0.4)
        return Develop.blend(white, over: image, mask: masks.teeth)
    }
}
