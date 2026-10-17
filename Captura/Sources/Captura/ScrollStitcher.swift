import CoreGraphics
import Foundation

/// Une fotogramas consecutivos de una zona que se desplaza hacia abajo en una sola imagen larga.
///
/// Cada fila de píxeles se resume en unos pocos valores de gris. Comparándolas con las del fotograma
/// anterior (con tolerancia, porque macOS aplica un ligero tramado de color que cambia en cada captura)
/// se detectan las cabeceras y pies fijos y cuánto se desplazó el contenido; solo se añaden las filas nuevas.
final class ScrollStitcher {
    enum Result: Equatable {
        case added(Int)   // filas nuevas añadidas
        case unchanged    // no hubo desplazamiento
        case lost         // se desplazó demasiado rápido: no hay solapamiento
    }

    static let maxHeight = 40_000

    /// Filas nuevas de un fotograma junto con su posible pie, para recortarlas al final.
    private struct Piece {
        let block: CGImage   // las `shift` filas nuevas seguidas de las `foot` filas "fijas" de abajo
        let shift: Int
        let foot: Int
    }

    private var first: CGImage?
    private var last: CGImage?
    private var lastRows: RowFeatures?
    private var pieces: [Piece] = []
    /// El pie fijo real es lo que coincide en todos los pares de fotogramas: el mínimo observado.
    /// (En un solo par, unas líneas en blanco del contenido pueden parecer parte del pie.)
    private var footer = Int.max
    private(set) var height = 0

    var isEmpty: Bool { first == nil }

    /// Registro opcional de cada comparación (para diagnosticar capturas que no se unen).
    var log: ((String) -> Void)?

    func add(_ frame: CGImage) -> Result {
        guard let current = RowFeatures(frame) else { return .unchanged }
        guard let previous = lastRows else {
            first = Self.copy(frame, rows: 0 ..< frame.height)
            last = first
            lastRows = current
            height = frame.height
            return .added(frame.height)
        }
        guard current.rows == previous.rows else { return .unchanged }

        let rows = current.rows
        let same = (0 ..< rows).map { current.diff($0, previous, $0) < RowFeatures.sameRow }
        // Quitando un posible cursor de texto o un efecto al pasar el ratón, todo sigue igual.
        guard same.filter({ !$0 }).count > max(2, rows / 100) else {
            log?("sin cambios")
            return .unchanged
        }

        var header = 0
        while header < rows, same[header] { header += 1 }
        var foot = 0
        while foot < rows - header, same[rows - 1 - foot] { foot += 1 }
        let length = rows - header - foot
        guard length > 20 else { return .unchanged }

        let match = Self.bestShift(previous: previous, next: current, from: header, length: length)
        // Con el ruido de color, un desplazamiento de 1–2 filas puede "encajar" sin haberse movido nada:
        // solo cuenta si encaja claramente mejor que quedarse quieto.
        let still = Self.score(previous: previous, next: current, from: header, length: length, shift: 0)
        if let m = match, m.score > still * 0.6 {
            log?("sin desplazamiento real (diferencia \(String(format: "%.1f", m.score)) frente a \(String(format: "%.1f", still)) sin moverse)")
            return .unchanged
        }
        log?("cabecera \(header) · pie \(foot) · zona \(length) · desplazamiento \(match.map { "\($0.shift) (diferencia \(String(format: "%.1f", $0.score)))" } ?? "—")")
        guard let shift = match?.shift, let block = Self.copy(frame, rows: (rows - foot - shift) ..< rows) else {
            return .lost
        }

        pieces.append(Piece(block: block, shift: shift, foot: foot))
        footer = min(footer, foot)
        last = Self.copy(frame, rows: 0 ..< rows)
        lastRows = current
        height += shift
        return .added(shift)
    }

    /// Imagen final: primer fotograma (sin el pie), las filas nuevas y el pie del último fotograma.
    func compose() -> CGImage? {
        guard let first, let last else { return nil }
        let width = first.width
        let foot = pieces.isEmpty ? 0 : footer
        var parts: [CGImage] = []
        if let top = first.cropping(to: CGRect(x: 0, y: 0, width: width, height: first.height - foot)) { parts.append(top) }
        for piece in pieces {
            // Con el pie ya conocido, las filas nuevas terminan justo encima de él.
            let y = piece.foot - foot
            if let rows = piece.block.cropping(to: CGRect(x: 0, y: y, width: width, height: piece.shift)) {
                parts.append(rows)
            }
        }
        if foot > 0, let bottom = last.cropping(to: CGRect(x: 0, y: last.height - foot, width: width, height: foot)) {
            parts.append(bottom)
        }
        let total = parts.reduce(0) { $0 + $1.height }

        guard let ctx = Self.context(width: width, height: total, like: first) else { return nil }
        var y = total
        for part in parts {
            y -= part.height
            ctx.draw(part, in: CGRect(x: 0, y: y, width: width, height: part.height))
        }
        return ctx.makeImage()
    }

    /// Copia unas filas a una imagen propia, para no retener en memoria el fotograma entero.
    private static func copy(_ image: CGImage, rows: Range<Int>) -> CGImage? {
        guard !rows.isEmpty, rows.lowerBound >= 0, rows.upperBound <= image.height,
              let cropped = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width, height: rows.count)),
              let ctx = context(width: image.width, height: rows.count, like: image) else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: image.width, height: rows.count))
        return ctx.makeImage()
    }

    private static func context(width: Int, height: Int, like image: CGImage) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    // MARK: Comparación

    /// Diferencia media de la zona con un desplazamiento concreto (sin contar las filas lisas).
    static func score(previous: RowFeatures, next: RowFeatures, from: Int, length: Int, shift: Int) -> Float {
        var total: Float = 0
        var compared = 0
        for k in 0 ..< (length - shift) {
            let a = from + shift + k, b = from + k
            if previous.flat[a], next.flat[b] { continue }
            total += previous.diff(a, next, b)
            compared += 1
        }
        return compared > 0 ? total / Float(compared) : 0
    }

    /// Desplazamiento (en filas) que mejor alinea la zona `[from, from + length)` de `next` con la de
    /// `previous`, junto con su diferencia media; `nil` si ninguno encaja.
    static func bestShift(previous: RowFeatures, next: RowFeatures, from: Int, length: Int) -> (shift: Int, score: Float)? {
        let minOverlap = max(20, length / 8)
        guard length - minOverlap >= 1 else { return nil }

        var best: (shift: Int, score: Float)?
        for shift in 1 ... (length - minOverlap) {
            let overlap = length - shift
            // Solo vale la pena seguir sumando mientras pueda mejorar al mejor encontrado.
            let limit = (best?.score ?? RowFeatures.maxMatch) * Float(overlap)
            var total: Float = 0
            var compared = 0
            for k in 0 ..< overlap {
                let a = from + shift + k, b = from + k
                if previous.flat[a], next.flat[b] { continue } // filas lisas: no aportan información
                total += previous.diff(a, next, b)
                compared += 1
                if total > limit { break }
            }
            guard compared >= 10 else { continue }
            let score = total / Float(compared)
            if score < (best?.score ?? RowFeatures.maxMatch) { best = (shift, score) }
        }
        return best
    }
}

/// Cada fila de un fotograma reducida a `columns` valores de gris (0–255), para comparar filas
/// rápido y con tolerancia al tramado de color. Se ignora el borde derecho, donde macOS superpone
/// la barra de desplazamiento mientras te desplazas.
struct RowFeatures {
    /// Diferencia media por debajo de la cual dos filas se consideran la misma.
    static let sameRow: Float = 4
    /// Diferencia media máxima para aceptar un desplazamiento.
    static let maxMatch: Float = 4

    static let columns = 96
    let rows: Int
    let values: [Float]
    /// Filas casi lisas (fondo sin contenido).
    let flat: [Bool]

    init?(_ image: CGImage) {
        let margin = max(32, image.width * 4 / 100)
        guard image.width > margin * 2,
              let image = image.cropping(to: CGRect(x: 0, y: 0, width: image.width - margin, height: image.height))
        else { return nil }
        let columns = Self.columns, height = image.height
        var pixels = [UInt8](repeating: 0, count: columns * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: columns, height: height, bitsPerComponent: 8,
                                      bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: height))
            return true
        }
        guard drawn else { return nil }

        rows = height
        values = pixels.map(Float.init) // el búfer empieza por la fila de arriba de la imagen
        flat = (0 ..< height).map { row in
            let slice = pixels[(row * columns) ..< ((row + 1) * columns)]
            return Int(slice.max()!) - Int(slice.min()!) < 10
        }
    }

    /// Diferencia media entre la fila `i` de este fotograma y la fila `j` de `other`.
    func diff(_ i: Int, _ other: RowFeatures, _ j: Int) -> Float {
        let c = Self.columns
        var total: Float = 0
        values.withUnsafeBufferPointer { a in
            other.values.withUnsafeBufferPointer { b in
                for x in 0 ..< c { total += abs(a[i * c + x] - b[j * c + x]) }
            }
        }
        return total / Float(c)
    }
}
