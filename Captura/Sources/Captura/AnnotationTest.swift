import AppKit

/// Dibuja una anotación de cada tipo, en todos los colores y tamaños, sobre una imagen.
@MainActor
enum AnnotationTest {
    static func run(source: URL, output: URL) {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("No se pudo leer la imagen"); return }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let annotations = [
            Annotation(kind: .highlight(CGRect(x: w * 0.05, y: h * 0.08, width: w * 0.35, height: h * 0.12)), color: 2, size: 1),
            Annotation(kind: .rectangle(CGRect(x: w * 0.55, y: h * 0.1, width: w * 0.38, height: h * 0.3)), color: 0, size: 1),
            Annotation(kind: .arrow(from: CGPoint(x: w * 0.3, y: h * 0.75), to: CGPoint(x: w * 0.55, y: h * 0.45)), color: 0, size: 2),
            Annotation(kind: .arrow(from: CGPoint(x: w * 0.8, y: h * 0.85), to: CGPoint(x: w * 0.7, y: h * 0.5)), color: 4, size: 0),
            Annotation(kind: .text(origin: CGPoint(x: w * 0.05, y: h * 0.78), string: "Pulsa aquí para empezar"), color: 0, size: 1),
            Annotation(kind: .text(origin: CGPoint(x: w * 0.58, y: h * 0.62), string: "Ojo"), color: 2, size: 2),
            Annotation(kind: .text(origin: CGPoint(x: w * 0.05, y: h * 0.3), string: "Paso 1"), color: 3, size: 0),
        ]
        guard let result = AnnotationRenderer.render(image, annotations),
              let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: output)
        print("Imagen anotada: \(result.width)×\(result.height) → \(output.path)")
    }
}
