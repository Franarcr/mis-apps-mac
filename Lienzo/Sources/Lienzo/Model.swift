import AppKit

/// Tipos de elemento que puede haber en un tablero.
enum ItemKind: String, Codable {
    case note, text, shape, connector, pen, frame, image, comment
}

enum ShapeKind: String, Codable, CaseIterable, Identifiable {
    case rectangle, rounded, ellipse, diamond, triangle
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .rounded: "app"
        case .ellipse: "circle"
        case .diamond: "diamond"
        case .triangle: "triangle"
        }
    }
    var title: String {
        switch self {
        case .rectangle: "Rectángulo"
        case .rounded: "Rectángulo redondeado"
        case .ellipse: "Círculo"
        case .diamond: "Rombo"
        case .triangle: "Triángulo"
        }
    }
}

/// Herramientas de la barra lateral.
enum Tool: String, CaseIterable, Identifiable {
    case select, hand, note, text, shape, connector, pen, frame, image, comment
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .hand: "hand.raised"
        case .note: "note.text"
        case .text: "textformat"
        case .shape: "square.on.circle"
        case .connector: "arrow.up.right"
        case .pen: "pencil.tip"
        case .frame: "rectangle.dashed"
        case .image: "photo"
        case .comment: "text.bubble"
        }
    }
    var title: String {
        switch self {
        case .select: "Seleccionar"
        case .hand: "Mover el tablero"
        case .note: "Nota adhesiva"
        case .text: "Texto"
        case .shape: "Figuras"
        case .connector: "Flecha"
        case .pen: "Lápiz"
        case .frame: "Marco"
        case .image: "Imagen"
        case .comment: "Comentario"
        }
    }
    /// Tecla para elegirla desde el tablero.
    var key: String {
        switch self {
        case .select: "v"
        case .hand: "h"
        case .note: "n"
        case .text: "t"
        case .shape: "s"
        case .connector: "l"
        case .pen: "p"
        case .frame: "f"
        case .image: "i"
        case .comment: "c"
        }
    }
}

/// Un elemento del tablero. Las coordenadas van en puntos del tablero, con el eje Y hacia abajo.
struct Item: Identifiable, Equatable {
    var id = UUID()
    var kind: ItemKind
    var rect = CGRect.zero
    var text = ""
    /// Color de fondo (notas, figuras, marcos, comentarios) o de trazo (texto, flechas, lápiz).
    var color = "FFE98A"
    var fontSize: CGFloat = 16
    var shape: ShapeKind?
    /// Trazo del lápiz, en proporciones 0…1 dentro de `rect`.
    var points: [CGPoint]?
    var lineWidth: CGFloat = 2
    /// Extremos de una flecha: unidos a un elemento (`from`/`to`) o sueltos (`start`/`end`).
    var from: UUID?
    var to: UUID?
    var start: CGPoint?
    var end: CGPoint?
    var imageID: String?
    /// Puntas de flecha (nil = como siempre: sin punta al inicio, con punta al final).
    var arrowStart: Bool?
    var arrowEnd: Bool?
}

extension Item: Codable {
    enum CodingKeys: String, CodingKey {
        case id, kind, rect, text, color, fontSize, shape, points, lineWidth, from, to, start, end, imageID, arrowStart, arrowEnd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ItemKind.self, forKey: .kind)
        rect = try c.decodeIfPresent(CGRect.self, forKey: .rect) ?? .zero
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "FFE98A"
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 16
        shape = try c.decodeIfPresent(ShapeKind.self, forKey: .shape)
        points = try c.decodeIfPresent([CGPoint].self, forKey: .points)
        lineWidth = try c.decodeIfPresent(CGFloat.self, forKey: .lineWidth) ?? 2
        from = try c.decodeIfPresent(UUID.self, forKey: .from)
        to = try c.decodeIfPresent(UUID.self, forKey: .to)
        start = try c.decodeIfPresent(CGPoint.self, forKey: .start)
        end = try c.decodeIfPresent(CGPoint.self, forKey: .end)
        imageID = try c.decodeIfPresent(String.self, forKey: .imageID)
        arrowStart = try c.decodeIfPresent(Bool.self, forKey: .arrowStart)
        arrowEnd = try c.decodeIfPresent(Bool.self, forKey: .arrowEnd)
    }
}

/// Contenido completo de un archivo .lienzo.
struct Board: Codable {
    var format = 1
    var items: [Item] = []
    /// Imágenes pegadas, por identificador.
    var images: [String: Data] = [:]
    var viewCenter: CGPoint?
    var viewScale: CGFloat?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format) ?? 1
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        images = try c.decodeIfPresent([String: Data].self, forKey: .images) ?? [:]
        viewCenter = try c.decodeIfPresent(CGPoint.self, forKey: .viewCenter)
        viewScale = try c.decodeIfPresent(CGFloat.self, forKey: .viewScale)
    }
}

/// Elementos copiados al portapapeles.
struct Clip: Codable {
    var items: [Item]
    var images: [String: Data]
    static let pasteboardType = NSPasteboard.PasteboardType("com.fran.lienzo.elementos")
}

enum Palette {
    struct Swatch: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }
    static let colors: [Swatch] = [
        .init(name: "Amarillo", hex: "FFE98A"), .init(name: "Naranja", hex: "FFC98B"),
        .init(name: "Rosa", hex: "FFB8CF"), .init(name: "Morado", hex: "D7C4FF"),
        .init(name: "Azul", hex: "AFD6FF"), .init(name: "Verde", hex: "C6EDA0"),
        .init(name: "Gris", hex: "E4E4E0"), .init(name: "Blanco", hex: "FFFFFF"),
        .init(name: "Rojo", hex: "E5484D"), .init(name: "Azul fuerte", hex: "2F6FEB"),
        .init(name: "Verde fuerte", hex: "2E9E5B"), .init(name: "Negro", hex: "1F2329"),
    ]
    static let ink: [Swatch] = [
        .init(name: "Negro", hex: "1F2329"), .init(name: "Rojo", hex: "E5484D"),
        .init(name: "Azul", hex: "2F6FEB"), .init(name: "Verde", hex: "2E9E5B"),
        .init(name: "Naranja", hex: "F08C2E"), .init(name: "Morado", hex: "8B5CF6"),
    ]
}

extension NSColor {
    convenience init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Texto legible sobre este color de fondo.
    static func ink(on hex: String) -> NSColor {
        if hex == "none" { return NSColor(hex: "1F2329") }
        let c = NSColor(hex: hex)
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return lum < 0.55 ? .white : NSColor(hex: "1F2329")
    }
}

enum Geo {
    static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        var t: CGFloat = 0
        if len2 > 0 { t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) }
        let x = a.x + t * dx - p.x, y = a.y + t * dy - p.y
        return (x * x + y * y).squareRoot()
    }

    /// Punto del borde de `r` en la dirección de `target`.
    static func boundaryPoint(_ r: CGRect, toward target: CGPoint) -> CGPoint {
        let c = CGPoint(x: r.midX, y: r.midY)
        let dx = target.x - c.x, dy = target.y - c.y
        if dx == 0 && dy == 0 { return c }
        let tx = dx == 0 ? CGFloat.infinity : (r.width / 2) / abs(dx)
        let ty = dy == 0 ? CGFloat.infinity : (r.height / 2) / abs(dy)
        let t = min(tx, ty, 1)
        return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
    }
}
