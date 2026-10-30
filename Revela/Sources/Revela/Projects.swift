import AppKit
import CoreImage
import ImageIO

/// Un proyecto: una lista de fotos (de una o varias carpetas) con nombre, para editar por lotes. Las fotos no se
/// mueven ni se copian: el proyecto solo guarda dónde están. Los ajustes de cada foto siguen en `EditStore`.
struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var photos: [String] = []           // rutas
    /// Revelado inicial que reciben las fotos que se añaden sin ajustes propios.
    var base: Adjustments?
}

/// Proyectos en ~/Library/Application Support/Revela/proyectos.json.
enum ProjectStore {
    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Revela")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("proyectos.json")
    }

    static func load() -> [Project] {
        (try? JSONDecoder().decode([Project].self, from: Data(contentsOf: file))) ?? []
    }

    static func save(_ projects: [Project]) {
        guard !EditStore.readOnly else { return }
        try? JSONEncoder().encode(projects).write(to: file, options: .atomic)
    }
}

/// Grupos de ajustes que se pueden sincronizar entre fotos (los mismos que las secciones de la barra lateral).
/// Lo propio de cada foto (clics de selección y de agua, trazos de borrar, enderezado) nunca se sincroniza.
enum SyncGroup: String, CaseIterable, Identifiable {
    case light = "Luz", color = "Color", detail = "Detalle", looks = "Looks"
    case ai = "Inteligencia artificial", portrait = "Retrato", sky = "Cielo"
    var id: String { rawValue }

    private var numbers: [WritableKeyPath<Adjustments, Double>] {
        switch self {
        case .light: return [\.exposure, \.contrast, \.highlights, \.shadows, \.whites, \.blacks]
        case .color: return [\.temperature, \.tint, \.vibrance, \.saturation]
        case .detail: return [\.texture, \.clarity, \.sharpness, \.vignette]
        case .looks: return [\.lookAmount]
        case .ai: return [\.backgroundBlur, \.lensBlur, \.dehaze, \.subjectLight, \.backgroundLight]
        case .portrait: return [\.skinSmoothing, \.eyes, \.teeth]
        case .sky: return [\.skyLight, \.skyEnhance, \.skyAmount, \.skyHarmonize, \.skyHaze, \.relight]
        }
    }

    /// Copia este grupo de `source` a `target`.
    func copy(from source: Adjustments, to target: inout Adjustments) {
        for key in numbers { target[keyPath: key] = source[keyPath: key] }
        switch self {
        case .looks: target.look = source.look
        case .ai: target.autoEnhance = source.autoEnhance
        case .sky: target.skyReplacement = source.skyReplacement
        default: break
        }
    }
}

/// Miniaturas de las fotos (la que trae el archivo, o una reducida), en memoria.
final class Thumbnails: @unchecked Sendable {
    static let shared = Thumbnails()
    private var cache: [String: CGImage] = [:]
    private let lock = NSLock()
    /// Tres a la vez y en orden: con cientos de fotos (y más en un disco externo) no se satura el disco.
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 3
        q.qualityOfService = .utility
        return q
    }()

    func cached(_ url: URL) -> CGImage? { lock.lock(); defer { lock.unlock() }; return cache[url.path] }

    func load(_ url: URL, done: @escaping @Sendable (CGImage?) -> Void) {
        if let image = cached(url) { done(image); return }
        queue.addOperation {
            var image: CGImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 240,
                ] as CFDictionary)
            }
            if let image { self.lock.lock(); self.cache[url.path] = image; self.lock.unlock() }
            DispatchQueue.main.async { done(image) }
        }
    }
}
