import AppKit
import Carbon.HIToolbox

/// Atajo de teclado: código de tecla y modificadores de Carbon.
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int

    /// "⌃⌥←", "⌃⌥⌘→"…
    var display: String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// "Opción + Mayúsculas + L": el mismo atajo con el nombre de las teclas.
    var words: String {
        var parts: [String] = []
        if modifiers & controlKey != 0 { parts.append("Control") }
        if modifiers & optionKey != 0 { parts.append("Opción") }
        if modifiers & shiftKey != 0 { parts.append("Mayúsculas") }
        if modifiers & cmdKey != 0 { parts.append("Comando") }
        return (parts + [Self.keyName(keyCode)]).joined(separator: " + ")
    }

    static func keyName(_ code: Int) -> String {
        let special: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Return: "↩", kVK_Space: "Espacio", kVK_Delete: "⌫", kVK_Tab: "⇥", kVK_Escape: "⎋",
            kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        if let name = special[code] { return name }
        // Letra o número según la distribución de teclado actual.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let layout = unsafeBitCast(data, to: CFData.self)
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length).uppercased() : "#\(code)"
    }

    /// Convierte los modificadores de un evento de teclado a los de Carbon.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var mods = 0
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.command) { mods |= cmdKey }
        return mods
    }
}

/// Una distribución: zona de una cuadrícula (columnas × filas, filas contadas desde arriba).
struct SavedLayout: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var columns: Int
    var rows: Int
    var col0: Int, row0: Int, col1: Int, row1: Int
    var shortcut: Shortcut?

    /// Zona en una pantalla (coordenadas de AppKit), sin separación.
    func rect(in area: CGRect) -> CGRect {
        let w = area.width / CGFloat(columns), h = area.height / CGFloat(rows)
        let height = CGFloat(row1 - row0 + 1) * h
        return CGRect(x: area.minX + CGFloat(col0) * w, y: area.maxY - CGFloat(row0) * h - height,
                      width: CGFloat(col1 - col0 + 1) * w, height: height)
    }

    /// Fracciones (0…1, origen arriba a la izquierda) para dibujar miniaturas.
    var unitRect: CGRect {
        CGRect(x: CGFloat(col0) / CGFloat(columns), y: CGFloat(row0) / CGFloat(rows),
               width: CGFloat(col1 - col0 + 1) / CGFloat(columns), height: CGFloat(row1 - row0 + 1) / CGFloat(rows))
    }

    static let defaults: [SavedLayout] = {
        let ctrlOpt = controlKey | optionKey
        func layout(_ name: String, _ c: Int, _ r: Int, _ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int, _ key: Int) -> SavedLayout {
            SavedLayout(name: name, columns: c, rows: r, col0: c0, row0: r0, col1: c1, row1: r1,
                        shortcut: Shortcut(keyCode: key, modifiers: ctrlOpt))
        }
        return [
            layout("Mitad izquierda", 2, 1, 0, 0, 0, 0, kVK_LeftArrow),
            layout("Mitad derecha", 2, 1, 1, 0, 1, 0, kVK_RightArrow),
            layout("Mitad superior", 1, 2, 0, 0, 0, 0, kVK_UpArrow),
            layout("Mitad inferior", 1, 2, 0, 1, 0, 1, kVK_DownArrow),
            layout("Maximizar", 1, 1, 0, 0, 0, 0, kVK_Return),
            layout("Tercio izquierdo", 3, 1, 0, 0, 0, 0, kVK_ANSI_1),
            layout("Tercio central", 3, 1, 1, 0, 1, 0, kVK_ANSI_2),
            layout("Tercio derecho", 3, 1, 2, 0, 2, 0, kVK_ANSI_3),
            layout("Dos tercios izquierda", 3, 1, 0, 0, 1, 0, kVK_ANSI_4),
        ]
    }()
}

/// Distribuciones guardadas en ~/Library/Application Support/Lazo/distribuciones.json.
@MainActor
final class LayoutStore: ObservableObject {
    @Published var layouts: [SavedLayout] { didSet { save(); onChange?() } }
    var onChange: (() -> Void)?

    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lazo")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("distribuciones.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([SavedLayout].self, from: data) {
            layouts = saved
        } else {
            layouts = SavedLayout.defaults
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(layouts).write(to: Self.file, options: .atomic)
    }

    /// Exporta e importa en un archivo .json (para pasarlas a otro Mac).
    func export(to url: URL) throws {
        try JSONEncoder().encode(layouts).write(to: url, options: .atomic)
    }

    func importLayouts(from url: URL) throws {
        layouts = try JSONDecoder().decode([SavedLayout].self, from: Data(contentsOf: url))
    }
}
