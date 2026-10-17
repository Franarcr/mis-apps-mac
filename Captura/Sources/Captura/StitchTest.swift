import AppKit

/// Prueba de la unión de capturas con desplazamiento, sin pantalla:
/// trocea una imagen alta en "fotogramas" solapados (con cabecera fija) y comprueba que
/// al unirlos se obtiene exactamente la imagen esperada.
///   Captura --stitch-test /ruta/imagen.png [salida.png]
enum StitchTest {
    /// Con `footer`, cada fotograma lleva además un pie fijo (barra gris con margen blanco encima).
    /// Con `scrollbar`, cada fotograma lleva la barra de desplazamiento superpuesta de macOS en el borde derecho.
    /// Con `noise`, cada fotograma lleva un ligero ruido de color distinto (como el tramado de macOS).
    static func run(source: URL, output: URL?, footer: Bool = false, scrollbar: Bool = false, noise: Bool = false) -> Bool {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            print("No se pudo leer la imagen")
            return false
        }
        let header = 60, footerHeight = footer ? 50 : 0, window = min(500, image.height / 2)
        guard let headerImage = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: header)) else { return false }
        let content = image.height - header
        let viewport = window - header - footerHeight

        // Fotogramas: cabecera fija + ventana de contenido en distintas posiciones.
        var offsets: [Int] = []
        var offset = 0
        var generator = SystemRandomNumberGenerator()
        while offset + viewport < content {
            offsets.append(offset)
            offsets.append(offset) // fotograma repetido (sin desplazamiento)
            offset += Int.random(in: 15 ... viewport / 2, using: &generator)
        }
        offsets.append(content - viewport)

        let stitcher = ScrollStitcher()
        var lost = 0
        for top in offsets {
            var frame = makeFrame(header: headerImage, image: image, contentTop: header + top, viewport: viewport,
                                  footer: footerHeight)
            if scrollbar { frame = drawScrollbar(on: frame, progress: Double(top) / Double(content - viewport)) }
            if noise { frame = addNoise(to: frame) }
            if stitcher.add(frame) == .lost { lost += 1 }
        }
        guard let result = stitcher.compose() else { return false }
        if let output, let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) {
            try? png.write(to: output)
        }

        // Lo esperado: la imagen original más el pie al final.
        let expected = footer ? appendFooter(to: image, height: footerHeight) : image
        var differing: [Int] = []
        if let got = RowFeatures(result), let want = RowFeatures(expected), got.rows == want.rows {
            differing = (0 ..< got.rows).filter { got.diff($0, want, $0) >= RowFeatures.sameRow }
        }
        if !differing.isEmpty {
            print("Filas distintas: \(differing.count) · primera: \(differing[0]) · última: \(differing.last!)")
        }
        let same = result.width == expected.width && result.height == expected.height && differing.isEmpty
        print("Fotogramas: \(offsets.count) · perdidos: \(lost) · resultado: \(result.width)×\(result.height) · esperado: \(expected.width)×\(expected.height)")
        print("Escenario: \(footer ? "con pie fijo" : "sin pie")\(scrollbar ? ", barra de desplazamiento" : "")\(noise ? ", ruido de color" : "")")
        print(same ? "OK: la imagen unida coincide con la original" : "FALLO: la imagen unida no coincide")
        return same
    }

    private static func makeFrame(header: CGImage, image: CGImage, contentTop: Int, viewport: Int, footer: Int) -> CGImage {
        let width = image.width, height = header.height + viewport + footer
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let slice = image.cropping(to: CGRect(x: 0, y: contentTop, width: width, height: viewport))!
        drawFooter(in: ctx, width: width, height: footer)
        ctx.draw(slice, in: CGRect(x: 0, y: footer, width: width, height: viewport))
        ctx.draw(header, in: CGRect(x: 0, y: footer + viewport, width: width, height: header.height))
        return ctx.makeImage()!
    }

    /// Barra de desplazamiento gris semitransparente cuya posición sigue al contenido.
    private static func drawScrollbar(on frame: CGImage, progress: Double) -> CGImage {
        let ctx = CGContext(data: nil, width: frame.width, height: frame.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        let thumb = Double(frame.height) * 0.15
        let y = (1 - progress) * (Double(frame.height) - thumb)
        ctx.setFillColor(CGColor(gray: 0.3, alpha: 0.55))
        ctx.addPath(CGPath(roundedRect: CGRect(x: Double(frame.width) - 16, y: y, width: 10, height: thumb),
                           cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()
        return ctx.makeImage()!
    }

    /// Suma a cada canal un ruido aleatorio de ±3 niveles.
    private static func addNoise(to frame: CGImage) -> CGImage {
        let width = frame.width, height = frame.height
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var generator = SystemRandomNumberGenerator()
        for i in 0 ..< width * height * 4 where i % 4 != 3 {
            data[i] = UInt8(clamping: Int(data[i]) + Int.random(in: -3 ... 3, using: &generator))
        }
        return ctx.makeImage()!
    }

    /// Pie de prueba: 10 filas blancas y una barra gris con una "caja de texto" más clara.
    private static func drawFooter(in ctx: CGContext, width: Int, height: Int) {
        guard height > 0 else { return }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height - 10))
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 20, y: 8, width: width / 2, height: height - 26))
    }

    private static func appendFooter(to image: CGImage, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: image.width, height: image.height + height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        drawFooter(in: ctx, width: image.width, height: height)
        ctx.draw(image, in: CGRect(x: 0, y: height, width: image.width, height: image.height))
        return ctx.makeImage()!
    }
}
