import CoreImage
import Foundation

/// «Automático» de la sección Luz: una base de revelado como la de cualquier editor. Revela la foto con los
/// ajustes actuales, mide su histograma y corrige exposición, contraste, luces, sombras, blancos y negros
/// en varias pasadas (cada control de Revela tiene su propia forma; midiendo el resultado no hace falta
/// adivinar su efecto exacto).
enum AutoLight {
    /// Lo que se mide de una foto revelada (luminancia en sRGB, de 0 a 1).
    struct Stats {
        var p1 = 0.0, p5 = 0.0, p10 = 0.0, p30 = 0.0, p50 = 0.0, p95 = 0.0, p99 = 0.0
        var clippedHighlights = 0.0   // fracción de píxeles casi blancos
        var clippedShadows = 0.0      // fracción de píxeles casi negros
    }

    /// `render`: revela la foto con unos ajustes (en la vista previa, con las máscaras que tenga).
    static func adjust(_ start: Adjustments, render: (Adjustments) -> CIImage, context: CIContext) -> Adjustments {
        var a = start
        a.exposure = 0; a.contrast = 0; a.highlights = 0; a.shadows = 0; a.whites = 0; a.blacks = 0

        // Por etapas, como se revela a mano: cada una mide el resultado de las anteriores.
        // 1. Exposición: medida en el 30 % más oscuro (el paisaje o las personas; un cielo grande o una
        //    pared blanca no cuentan) y a medias: si la foto es clara u oscura a propósito no se fuerza.
        for _ in 0..<2 {
            guard let s = measure(render(a), context: context) else { return start }
            var ev = log2(pow(0.33, 2.2) / pow(max(s.p30, 0.01), 2.2)) * 0.5
            // Si a lo más claro le sobra margen (una foto gris, sin blancos), se sube hasta acercarlo al blanco.
            let headroom = log2(pow(0.95, 2.2) / pow(max(s.p99, 0.01), 2.2))
            if headroom > 0.1, s.clippedHighlights < 0.002 { ev = max(ev, headroom * 0.7) }
            if ev < 0 {
                // Oscurecer solo si hay mucho quemado, y sin que los blancos se vuelvan grises (≥ 0,95).
                ev = s.clippedHighlights > 0.02 ? max(ev, log2(pow(0.95, 2.2) / pow(max(s.p99, 0.01), 2.2))) : 0
            }
            a.exposure = clamp(a.exposure + ev, -1.5, 1.5)
        }
        // 2. Luces y sombras: se recuperan las luces si se queman (con moderación: mucho aplana la foto) y se
        //    abren las sombras si se empastan.
        if let s = measure(render(a), context: context) {
            if s.clippedHighlights > 0.01 { a.highlights = clamp(-15 - s.clippedHighlights * 800, -45, 0) }
            if s.p10 < 0.12 { a.shadows = clamp(10 + (0.12 - s.p10) * 300, 0, 50) }
        }
        // 3. Blancos y negros: que el histograma llegue de punta a punta (negros de verdad, blancos limpios).
        if let s = measure(render(a), context: context) {
            if s.p99 < 0.94 { a.whites = clamp((0.96 - s.p99) * 300, 0, 40) }
            if s.p1 > 0.03 { a.blacks = clamp(-(s.p1 - 0.015) * 250, -25, 0) }
        }
        // 4. Contraste: siempre un toque (da cuerpo), más si la foto queda plana; nunca lo quita.
        if let s = measure(render(a), context: context) {
            a.contrast = clamp((0.68 - (s.p95 - s.p5)) * 80 + 12, 5, 35)
        }
        // Valores redondos, como los dejaría una persona.
        a.exposure = (a.exposure * 20).rounded() / 20
        for key in [\Adjustments.contrast, \.highlights, \.shadows, \.whites, \.blacks] { a[keyPath: key] = a[keyPath: key].rounded() }
        return a
    }

    static func measure(_ image: CIImage, context: CIContext) -> Stats? {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return nil }
        let k = 400 / max(extent.width, extent.height)
        let small = image.transformed(by: CGAffineTransform(scaleX: k, y: k))
        let w = Int(small.extent.width), h = Int(small.extent.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        context.render(small, toBitmap: &pixels, rowBytes: w * 4, bounds: CGRect(x: small.extent.minX, y: small.extent.minY, width: CGFloat(w), height: CGFloat(h)),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var histogram = [Int](repeating: 0, count: 256)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let y = 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
            histogram[min(255, Int(y.rounded()))] += 1
        }
        let total = Double(w * h)
        func percentile(_ p: Double) -> Double {
            var sum = 0
            for (value, count) in histogram.enumerated() {
                sum += count
                if Double(sum) >= p * total { return Double(value) / 255 }
            }
            return 1
        }
        var s = Stats()
        s.p1 = percentile(0.01); s.p5 = percentile(0.05); s.p10 = percentile(0.1); s.p30 = percentile(0.3); s.p50 = percentile(0.5); s.p95 = percentile(0.95); s.p99 = percentile(0.99)
        s.clippedHighlights = Double(histogram[250...].reduce(0, +)) / total
        s.clippedShadows = Double(histogram[...4].reduce(0, +)) / total
        return s
    }

    private static func clamp(_ x: Double, _ low: Double, _ high: Double) -> Double { min(max(x, low), high) }
}
