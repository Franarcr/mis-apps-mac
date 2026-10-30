import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Una foto abierta: la original y una copia reducida para editar con fluidez.
final class Photo {
    let url: URL
    let isRAW: Bool
    /// Copia reducida (lado mayor ≤ `previewSize`) para la vista previa.
    let preview: CIImage
    /// Tamaño de la vista previa respecto a la original (1 = mismo tamaño).
    let previewScale: Double
    let fullSize: CGSize

    static let previewSize: CGFloat = 2048
    static let rawExtensions: Set<String> = ["dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf",
                                              "rw2", "pef", "srw", "3fr", "erf", "iiq", "mos", "mrw", "kdc", "dcr", "raw", "rwl"]
    static let openableTypes: [UTType] = [.jpeg, .png, .heic, .heif, .tiff, .rawImage, .image]

    enum Failure: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self { case .unreadable(let name): return "No se pudo abrir «\(name)». ¿Es una foto?" }
        }
    }

    init(url: URL) throws {
        self.url = url
        isRAW = Self.rawExtensions.contains(url.pathExtension.lowercased())
        guard let full = Self.load(url, raw: isRAW, scale: 1) else { throw Failure.unreadable(url.lastPathComponent) }
        fullSize = full.extent.size
        let factor = min(1, Self.previewSize / max(fullSize.width, fullSize.height))
        previewScale = Double(factor)
        if factor < 1, let small = Self.load(url, raw: isRAW, scale: factor) {
            preview = small.transformed(by: CGAffineTransform(translationX: -small.extent.minX, y: -small.extent.minY))
        } else {
            preview = full
        }
    }

    /// La foto completa (para exportar).
    func fullImage() -> CIImage? { Self.load(url, raw: isRAW, scale: 1) }

    private static let detailContext = CIContext(options: [.cacheIntermediates: false])

    /// Copia al doble de la vista previa (o la original, si es menor), ya calculada: las máscaras del cielo y
    /// del agua de la vista previa se hacen con ella, porque a 2048 px los huecos de una rejilla o los bordes
    /// de las cañas son de 1–2 px y la máscara saldría muy distinta de la de la exportación.
    lazy var detail: CIImage = {
        let factor = min(1, CGFloat(previewScale) * 2)
        guard factor > CGFloat(previewScale), let image = Self.load(url, raw: isRAW, scale: factor) else { return preview }
        let moved = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        guard let cg = Self.detailContext.createCGImage(moved, from: moved.extent, format: .RGBAh,
                                                        colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)) else { return preview }
        return CIImage(cgImage: cg)
    }()

    /// Una máscara hecha sobre `detail`, llevada al tamaño de la vista previa y ya calculada (así mover un control
    /// no la vuelve a calcular).
    func previewMask(_ mask: CIImage) -> CIImage {
        var m = mask
        if detail.extent.width != preview.extent.width {
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = mask
            f.scale = Float(preview.extent.height / detail.extent.height)
            f.aspectRatio = Float((preview.extent.width / detail.extent.width) / (preview.extent.height / detail.extent.height))
            m = (f.outputImage ?? mask).applyingFilter("CIColorClamp")
        }
        m = m.cropped(to: preview.extent)
        guard let cg = Self.detailContext.createCGImage(m, from: preview.extent, format: .RGBAh,
                                                        colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)) else { return m }
        return CIImage(cgImage: cg)
    }

    private static func load(_ url: URL, raw: Bool, scale: CGFloat) -> CIImage? {
        if raw, let filter = CIRAWFilter(imageURL: url) {
            filter.scaleFactor = Float(scale)
            return filter.outputImage
        }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
        guard scale < 1 else { return image }
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = image
        f.scale = Float(scale)
        f.aspectRatio = 1
        return f.outputImage
    }
}

/// IA que viene con macOS (Vision): sujeto principal y horizonte. Funciona sin internet.
enum Intelligence {
    /// Máscara del sujeto principal (personas, animales u objetos): blanco = sujeto.
    static func subjectMask(for image: CIImage, context: CIContext) -> CIImage? {
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        let handler = VNImageRequestHandler(cgImage: cg)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }
            let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            var mask = CIImage(cvPixelBuffer: buffer)
            // El borde se suaviza un poco para que el desenfoque no deje un recorte duro.
            let sx = image.extent.width / mask.extent.width, sy = image.extent.height / mask.extent.height
            mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            return mask.clampedToExtent()
                .applyingGaussianBlur(sigma: max(1, image.extent.width / 800))
                .cropped(to: image.extent)
        } catch {
            return nil
        }
    }

    /// Ángulo (en grados) para dejar el horizonte recto, o nil si no hay horizonte claro.
    static func horizonCorrection(for image: CIImage, context: CIContext) -> Double? {
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        let request = VNDetectHorizonRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        guard let angle = request.results?.first?.angle else { return nil }
        let degrees = -Double(angle) * 180 / .pi
        return abs(degrees) < 0.2 || abs(degrees) > 20 ? nil : degrees
    }
}

/// Guardar la foto revelada.
enum Exporter {
    enum Format: String, CaseIterable, Identifiable {
        case jpeg = "JPEG", heic = "HEIC", png = "PNG", tiff = "TIFF"
        var id: String { rawValue }
        var fileExtension: String { ["JPEG": "jpg", "HEIC": "heic", "PNG": "png", "TIFF": "tif"][rawValue]! }
    }

    static func materialize(_ mask: CIImage, context: CIContext) -> CIImage {
        guard let cg = context.createCGImage(mask, from: mask.extent, format: .RGBAh,
                                             colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)) else { return mask }
        return CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: mask.extent.minX, y: mask.extent.minY))
    }

    /// `upscale`: 1 (tamaño original), 2 o 4 (con Real-ESRGAN). `progress` informa de la ampliación (0…1).
    static func export(_ photo: Photo, adjustments: Adjustments, to url: URL, format: Format, quality: Double,
                       upscale: Int = 1, usePreview: Bool = false, context: CIContext,
                       progress: (Double) -> Void = { _ in }) throws {
        // `usePreview`: revela la copia reducida, como la vista previa del editor (para pruebas).
        guard var full = usePreview ? photo.preview : photo.fullImage() else { throw Photo.Failure.unreadable(photo.url.lastPathComponent) }
        let scale = usePreview ? photo.previewScale : 1
        if !adjustments.erase.isEmpty, let erased = EraseModel.inpaint(full, strokes: adjustments.erase, context: context) {
            full = erased
        }
        let mask = adjustments.usesSubjectMask || adjustments.usesDepth ? Intelligence.subjectMask(for: full, context: context) : nil
        let faces = adjustments.usesFaces ? FaceMasks.detect(in: full, context: context) : nil
        let depth = adjustments.usesDepth ? DepthInfo.compute(for: full, subject: mask, context: context) : nil
        var selection: CIImage?, sky: CIImage?, water: CIImage?
        if adjustments.usesSelection || adjustments.usesSky || adjustments.usesWater,
           let embedding = SegmentModel.encode(full, context: context) {
            // En la vista previa, como en el editor: cielo y agua con la copia de detalle, llevados a su tamaño.
            let guide = usePreview ? photo.detail : full
            let fit: (CIImage) -> CIImage = usePreview ? photo.previewMask : { $0 }
            if adjustments.usesSky || adjustments.usesWater {
                sky = SegmentModel.mask(embedding, points: SegmentModel.skyPoints, extent: guide.extent, connectedToTop: true,
                                        guide: guide).map(fit)
            }
            if adjustments.usesWater {
                water = SegmentModel.objectMask(embedding, points: adjustments.water, extent: guide.extent, guide: guide,
                                                excluding: sky).map(fit)
            }
            if adjustments.usesSelection {
                selection = SegmentModel.objectMask(embedding, points: adjustments.selection, extent: full.extent)
            }
            if !adjustments.usesSky { sky = nil }
            // Cada máscara se calcula una sola vez: si no, Core Image repite toda su cadena (desenfoques grandes,
            // comparaciones de color) en cada trozo de la foto y una exportación tarda minutos.
            if !usePreview {
                sky = sky.map { Self.materialize($0, context: context) }
                water = water.map { Self.materialize($0, context: context) }
                selection = selection.map { Self.materialize($0, context: context) }
            }
        }
        var output = Develop.apply(adjustments, to: full, mask: mask, faces: faces, depth: depth,
                                   selection: selection, sky: sky, water: water, scale: scale)
        if upscale > 1 {
            output = try UpscaleModel.upscale(output, factor: upscale, context: context, progress: progress)
        }
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality,
        ]
        switch format {
        case .jpeg: try context.writeJPEGRepresentation(of: output, to: url, colorSpace: space, options: options)
        case .heic: try context.writeHEIFRepresentation(of: output, to: url, format: .RGBA8, colorSpace: space, options: options)
        case .png: try context.writePNGRepresentation(of: output, to: url, format: .RGBA8, colorSpace: space)
        case .tiff: try context.writeTIFFRepresentation(of: output, to: url, format: .RGBA16, colorSpace: space)
        }
    }
}
