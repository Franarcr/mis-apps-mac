import CoreImage
import CoreML
import Foundation

/// «Borrar objetos» con LaMa (Apache 2.0; conversión a Core ML de MLBoy, ~217 MB): rellena la zona pintada
/// con lo que debería haber detrás.
enum EraseModel {
    static let remote = RemoteModel(repo: "mlboydaisuke/LaMa-CoreML", name: "LaMa")
    static var isInstalled: Bool { remote.isInstalled }
    static func install(progress: @escaping (Double) -> Void) throws { try remote.install(progress: progress) }
}

/// Un trazo del pincel de borrar: puntos de 0 a 1 (origen abajo a la izquierda) y grosor relativo al ancho de la foto.
struct EraseStroke: Codable, Equatable {
    var points: [SelectionPoint]
    var radius: Double
}

extension EraseModel {
    static let side = 800

    /// Rellena lo pintado con LaMa. Cada grupo de trazos que se tocan se procesa en su propio recorte,
    /// así el resto de la foto conserva su resolución completa.
    static func inpaint(_ image: CIImage, strokes: [EraseStroke], context: CIContext) -> CIImage? {
        guard let model = try? remote.load(), !strokes.isEmpty else { return nil }
        let extent = image.extent
        var result = image
        for group in groups(strokes, in: extent) {
            let mask = maskImage(group.strokes, extent: extent)
            // Alrededor de lo pintado se deja contexto para que LaMa sepa qué hay detrás.
            let margin = max(max(group.box.width, group.box.height) * 0.6, min(extent.width, extent.height) * 0.08)
            var crop = group.box.insetBy(dx: -margin, dy: -margin)
            let edge = max(crop.width, crop.height)   // cuadrado, como lo que espera el modelo
            crop = CGRect(x: crop.midX - edge / 2, y: crop.midY - edge / 2, width: edge, height: edge)
            crop = crop.intersection(extent).integral
            guard crop.width > 8, crop.height > 8,
                  let imageBuffer = buffer(from: result, crop: crop, format: kCVPixelFormatType_32BGRA, context: context),
                  let maskBuffer = buffer(from: mask, crop: crop, format: kCVPixelFormatType_OneComponent8, context: context),
                  let output = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": imageBuffer, "mask": maskBuffer])),
                  let filled = output.featureValue(for: "output")?.imageBufferValue else { continue }
            let patch = CIImage(cvPixelBuffer: filled)
                .transformed(by: CGAffineTransform(scaleX: crop.width / CGFloat(side), y: crop.height / CGFloat(side)))
                .transformed(by: CGAffineTransform(translationX: crop.minX, y: crop.minY))
            // Solo se cambia lo pintado (un poco ampliado y con el borde suave).
            let soft = mask.clampedToExtent()
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(2, extent.width / 600)])
                .applyingGaussianBlur(sigma: max(1, extent.width / 1500))
                .cropped(to: crop)
            result = Develop.blend(patch, over: result, mask: soft).cropped(to: extent)
        }
        return result
    }

    private static func buffer(from image: CIImage, crop: CGRect, format: OSType, context: CIContext) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, side, side, format, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard let buffer else { return nil }
        let scaled = image.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(side) / crop.width, y: CGFloat(side) / crop.height))
        context.render(scaled, to: buffer)
        return buffer
    }

    /// Máscara de los trazos: blanco = lo que se borra.
    static func maskImage(_ strokes: [EraseStroke], extent: CGRect) -> CIImage {
        let width = Int(extent.width), height = Int(extent.height)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return CIImage(color: .black).cropped(to: extent)
        }
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes {
            let r = stroke.radius * extent.width
            let points = stroke.points.map { CGPoint(x: $0.x * extent.width, y: $0.y * extent.height) }
            if points.count == 1, let p = points.first {
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            } else {
                ctx.setLineWidth(r * 2)
                ctx.addLines(between: points)
                ctx.strokePath()
            }
        }
        guard let cg = ctx.makeImage() else { return CIImage(color: .black).cropped(to: extent) }
        return CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// Junta los trazos cuyas cajas se tocan (se borran en un mismo recorte).
    private static func groups(_ strokes: [EraseStroke], in extent: CGRect) -> [(strokes: [EraseStroke], box: CGRect)] {
        var groups: [(strokes: [EraseStroke], box: CGRect)] = []
        for stroke in strokes {
            let r = stroke.radius * extent.width
            let xs = stroke.points.map { extent.minX + $0.x * extent.width }, ys = stroke.points.map { extent.minY + $0.y * extent.height }
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { continue }
            var box = CGRect(x: minX - r, y: minY - r, width: maxX - minX + 2 * r, height: maxY - minY + 2 * r)
            var members = [stroke]
            // Absorbe los grupos que toca (y repite por si al crecer toca otros).
            var merged = true
            while merged {
                merged = false
                if let i = groups.firstIndex(where: { $0.box.insetBy(dx: -r, dy: -r).intersects(box) }) {
                    box = box.union(groups[i].box)
                    members = groups[i].strokes + members
                    groups.remove(at: i)
                    merged = true
                }
            }
            groups.append((members, box))
        }
        return groups
    }
}
