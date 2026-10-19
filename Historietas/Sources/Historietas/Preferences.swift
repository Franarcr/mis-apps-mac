import Foundation

/// Cómo se ajustan las páginas a la ventana.
enum FitMode: Int {
    case page      // la página entera a la vista
    case width     // todo el ancho, con desplazamiento vertical
    case original  // un píxel de la imagen por píxel de pantalla
}

/// Ajustes guardados en UserDefaults. Cada ventana nueva empieza con los últimos que se usaron.
enum Preferences {
    private static var defaults: UserDefaults { .standard }
    private static let maxRecents = 15

    static var fit: FitMode {
        get { FitMode(rawValue: defaults.integer(forKey: "fit")) ?? .page }
        set { defaults.set(newValue.rawValue, forKey: "fit") }
    }

    static var doublePage: Bool {
        get { defaults.bool(forKey: "doublePage") }
        set { defaults.set(newValue, forKey: "doublePage") }
    }

    /// Lectura de derecha a izquierda, como el manga.
    static var rightToLeft: Bool {
        get { defaults.bool(forKey: "rightToLeft") }
        set { defaults.set(newValue, forKey: "rightToLeft") }
    }

    /// En doble página, la portada va sola para que las páginas enfrentadas queden bien emparejadas.
    static var coverAlone: Bool {
        get { defaults.object(forKey: "coverAlone") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "coverAlone") }
    }

    // MARK: Página por la que va cada cómic

    static func lastPage(for url: URL) -> Int {
        defaults.dictionary(forKey: "positions")?[url.path] as? Int ?? 0
    }

    static func setLastPage(_ page: Int, for url: URL) {
        var positions = defaults.dictionary(forKey: "positions") ?? [:]
        positions[url.path] = page
        defaults.set(positions, forKey: "positions")
    }

    // MARK: Abiertos recientemente

    static var recents: [URL] {
        (defaults.stringArray(forKey: "recents") ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func addRecent(_ url: URL) {
        var paths = defaults.stringArray(forKey: "recents") ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(maxRecents)), forKey: "recents")
    }

    static func clearRecents() { defaults.removeObject(forKey: "recents") }
}
