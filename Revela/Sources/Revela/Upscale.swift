import CoreImage
import CoreML
import Foundation

/// «Ampliar» con Real-ESRGAN ×4 (BSD-3; conversión a Core ML de MLBoy, ~67 MB): recupera detalle al
/// agrandar. La foto se procesa en mosaicos de 512 px que se solapan, para no notar las uniones.
enum UpscaleModel {
    static let remote = RemoteModel(repo: "mlboydaisuke/Real-ESRGAN-x4-CoreML", name: "RealESRGAN_x4", hasWeightsFile: false)
    static var isInstalled: Bool { remote.isInstalled }
    static func install(progress: @escaping (Double) -> Void) throws { try remote.install(progress: progress) }
}

extension UpscaleModel {
    static let tile = 512
    static let overlap = 32
    /// Más allá de esto (en megapíxeles) la foto ampliada no cabe con holgura en memoria.
    static let maxOutputMegapixels = 120.0

    enum Failure: LocalizedError {
        case tooLarge(Double)
        var errorDescription: String? {
            switch self {
            case .tooLarge(let mp):
                return String(format: "La foto ampliada tendría %.0f megapíxeles, demasiado grande. Usa ×2 o recorta la foto antes.", mp)
            }
        }
    }

    /// Amplía `image` ×2 o ×4. `progress` recibe 0…1.
    static func upscale(_ image: CIImage, factor: Int, context: CIContext, progress: (Double) -> Void = { _ in }) throws -> CIImage {
        let model = try remote.load()
        let extent = image.extent.integral
        let outWidth = Int(extent.width) * factor, outHeight = Int(extent.height) * factor
        let megapixels = Double(outWidth * outHeight) / 1_000_000
        guard megapixels <= maxOutputMegapixels else { throw Failure.tooLarge(megapixels) }
        guard let canvas = CGContext(data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.tooLarge(megapixels) }

        let source = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)).clampedToExtent()
        let width = Int(extent.width), height = Int(extent.height)
        let step = tile - overlap * 2
        let xs = Array(stride(from: 0, to: max(width - overlap * 2, 1), by: step))
        let ys = Array(stride(from: 0, to: max(height - overlap * 2, 1), by: step))
        let total = xs.count * ys.count
        var done = 0
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, tile, tile, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard let buffer else { throw Failure.tooLarge(megapixels) }

        for y0 in ys {
            for x0 in xs {
                // Mosaico de 512 que empieza `overlap` antes de la zona útil (fuera de la foto se repite el borde).
                let tx = x0 - overlap, ty = y0 - overlap
                context.render(source.transformed(by: CGAffineTransform(translationX: CGFloat(-tx), y: CGFloat(-ty)))
                                   .cropped(to: CGRect(x: 0, y: 0, width: tile, height: tile)), to: buffer)
                let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input": buffer]))
                guard let pixels = output.featureValue(for: "activation_out")?.imageBufferValue else { continue }
                // Zona útil: sin el solapamiento, y sin pasarse del borde de la foto.
                let useW = min(step, width - x0), useH = min(step, height - y0)
                guard useW > 0, useH > 0 else { continue }
                var result = CIImage(cvPixelBuffer: pixels)
                    .cropped(to: CGRect(x: overlap * 4, y: overlap * 4, width: useW * 4, height: useH * 4))
                    .transformed(by: CGAffineTransform(translationX: CGFloat(-overlap * 4), y: CGFloat(-overlap * 4)))
                if factor == 2 {
                    let f = CIFilter(name: "CILanczosScaleTransform")!
                    f.setValue(result, forKey: kCIInputImageKey)
                    f.setValue(0.5, forKey: kCIInputScaleKey)
                    f.setValue(1, forKey: kCIInputAspectRatioKey)
                    result = (f.outputImage ?? result).cropped(to: CGRect(x: 0, y: 0, width: useW * 2, height: useH * 2))
                }
                if let cg = context.createCGImage(result, from: result.extent) {
                    canvas.draw(cg, in: CGRect(x: x0 * factor, y: y0 * factor, width: cg.width, height: cg.height))
                }
                done += 1
                progress(Double(done) / Double(total))
            }
        }
        guard let cg = canvas.makeImage() else { throw Failure.tooLarge(megapixels) }
        return CIImage(cgImage: cg)
    }
}
