import AppKit

/// Las 7 notas. Cada una es un archivo Markdown en ~/Library/Application Support/Puntos/
/// y se guarda sola medio segundo después del último cambio.
@MainActor
final class NotesStore {
    static let count = 7

    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.96, green: 0.33, blue: 0.33, alpha: 1), // rojo
        NSColor(srgbRed: 0.98, green: 0.58, blue: 0.22, alpha: 1), // naranja
        NSColor(srgbRed: 0.97, green: 0.80, blue: 0.20, alpha: 1), // amarillo
        NSColor(srgbRed: 0.35, green: 0.80, blue: 0.40, alpha: 1), // verde
        NSColor(srgbRed: 0.20, green: 0.75, blue: 0.80, alpha: 1), // turquesa
        NSColor(srgbRed: 0.30, green: 0.52, blue: 0.98, alpha: 1), // azul
        NSColor(srgbRed: 0.68, green: 0.42, blue: 0.95, alpha: 1), // morado
    ]

    static let colorNames = ["Rojo", "Naranja", "Amarillo", "Verde", "Turquesa", "Azul", "Morado"]

    private(set) var texts: [String]
    let folder: URL
    private var pendingSaves: [Int: DispatchWorkItem] = [:]

    /// Avisa de cambios (para actualizar los puntos rellenos y el menú).
    var onChange: (() -> Void)?

    var selected: Int {
        get { min(max(UserDefaults.standard.integer(forKey: "selected"), 0), Self.count - 1) }
        set { UserDefaults.standard.set(newValue, forKey: "selected") }
    }

    /// `folder` permite usar otra carpeta (la imagen de prueba usa una temporal).
    init(folder: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.folder = folder ?? support.appendingPathComponent("Puntos")
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        texts = (0 ..< Self.count).map { _ in "" }
        for i in 0 ..< Self.count {
            texts[i] = (try? String(contentsOf: url(i), encoding: .utf8)) ?? ""
        }
    }

    func url(_ index: Int) -> URL { folder.appendingPathComponent("Nota \(index + 1).md") }

    func update(_ index: Int, text: String) {
        guard texts[index] != text else { return }
        texts[index] = text
        pendingSaves[index]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save(index) }
        pendingSaves[index] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        onChange?()
    }

    /// Guarda ya lo que quede pendiente (al salir de la app).
    func saveAll() {
        for (index, work) in pendingSaves {
            work.cancel()
            save(index)
        }
    }

    private func save(_ index: Int) {
        pendingSaves[index] = nil
        try? texts[index].write(to: url(index), atomically: true, encoding: .utf8)
    }

    /// Primera línea con texto, sin marcas de Markdown (para el menú).
    func preview(_ index: Int) -> String? {
        let line = texts[index].split(separator: "\n").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "#>-*[] \t"))
        }.first { !$0.isEmpty }
        guard let line else { return nil }
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }
}
