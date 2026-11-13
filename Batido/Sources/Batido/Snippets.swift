import SwiftUI

/// Un fragmento de código que se inserta delante y detrás de la selección.
/// `${caret}` marca dónde queda el cursor después de insertarlo.
struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var group: String
    var before: String
    var after: String = ""
    /// Si es verdadero, el fragmento sustituye la selección en vez de envolverla.
    var replacesSelection = false
    /// Atajo: tecla y modificadores ("cmd", "shift", "option", "control").
    var key: String? = nil
    var modifiers: [String] = []

    var shortcut: KeyboardShortcut? {
        guard let key, let ch = key.first else { return nil }
        var mods: EventModifiers = []
        if modifiers.contains("cmd") { mods.insert(.command) }
        if modifiers.contains("shift") { mods.insert(.shift) }
        if modifiers.contains("option") { mods.insert(.option) }
        if modifiers.contains("control") { mods.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(ch), modifiers: mods)
    }

    var shortcutLabel: String {
        guard let key else { return "" }
        var s = ""
        if modifiers.contains("control") { s += "⌃" }
        if modifiers.contains("option") { s += "⌥" }
        if modifiers.contains("shift") { s += "⇧" }
        if modifiers.contains("cmd") { s += "⌘" }
        return s + key.uppercased()
    }
}

enum Snippets {
    static let basePage = """
    <!DOCTYPE html>
    <html lang="es">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Página nueva</title>
        <style>

        </style>
      </head>
      <body>
        ${caret}
        <script>

        </script>
      </body>
    </html>

    """

    static let welcomePage = """
    <!DOCTYPE html>
    <html lang="es">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Hola desde Batido</title>
        <style>
          body { font-family: -apple-system, sans-serif; margin: 3rem; color: #333; }
          h1 { color: #e0457b; }
        </style>
      </head>
      <body>
        <h1>¡Hola!</h1>
        <p>Escribe a la izquierda y mira el resultado aquí al momento.</p>
      </body>
    </html>

    """

    static let builtIns: [Snippet] = [
        Snippet(name: "Página base", group: "Página", before: basePage, replacesSelection: true, key: "d", modifiers: ["cmd", "shift"]),
        Snippet(name: "Meta viewport", group: "Página", before: "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">", replacesSelection: true),
        Snippet(name: "Enlazar CSS", group: "Página", before: "<link rel=\"stylesheet\" href=\"${caret}\">", replacesSelection: true),
        Snippet(name: "Script externo", group: "Página", before: "<script src=\"${caret}\"></script>", replacesSelection: true),
        Snippet(name: "Bloque de estilo", group: "Página", before: "<style>\n  ", after: "${caret}\n</style>"),
        Snippet(name: "Bloque de script", group: "Página", before: "<script>\n  ", after: "${caret}\n</script>"),

        Snippet(name: "Negrita", group: "Texto", before: "<strong>", after: "</strong>", key: "b", modifiers: ["cmd"]),
        Snippet(name: "Cursiva", group: "Texto", before: "<em>", after: "</em>", key: "i", modifiers: ["cmd"]),
        Snippet(name: "Párrafo", group: "Texto", before: "<p>", after: "</p>", key: "p", modifiers: ["cmd", "option"]),
        Snippet(name: "Título 1", group: "Texto", before: "<h1>", after: "</h1>", key: "1", modifiers: ["cmd", "option"]),
        Snippet(name: "Título 2", group: "Texto", before: "<h2>", after: "</h2>", key: "2", modifiers: ["cmd", "option"]),
        Snippet(name: "Título 3", group: "Texto", before: "<h3>", after: "</h3>", key: "3", modifiers: ["cmd", "option"]),
        Snippet(name: "Salto de línea", group: "Texto", before: "<br>", replacesSelection: true),
        Snippet(name: "Span", group: "Texto", before: "<span class=\"${caret}\">", after: "</span>"),

        Snippet(name: "Enlace", group: "Contenido", before: "<a href=\"${caret}\">", after: "</a>", key: "k", modifiers: ["cmd", "shift"]),
        Snippet(name: "Imagen", group: "Contenido", before: "<img src=\"${caret}\" alt=\"\">", replacesSelection: true),
        Snippet(name: "Lista", group: "Contenido", before: "<ul>\n  <li>", after: "${caret}</li>\n</ul>"),
        Snippet(name: "Lista numerada", group: "Contenido", before: "<ol>\n  <li>", after: "${caret}</li>\n</ol>"),
        Snippet(name: "Tabla", group: "Contenido", before: "<table>\n  <tr>\n    <th>${caret}</th>\n    <th></th>\n  </tr>\n  <tr>\n    <td></td>\n    <td></td>\n  </tr>\n</table>", replacesSelection: true),
        Snippet(name: "Div", group: "Contenido", before: "<div class=\"${caret}\">", after: "</div>"),
        Snippet(name: "Sección", group: "Contenido", before: "<section>\n  ", after: "${caret}\n</section>"),
        Snippet(name: "Botón", group: "Contenido", before: "<button type=\"button\">", after: "${caret}</button>"),
        Snippet(name: "Formulario", group: "Contenido", before: "<form action=\"${caret}\" method=\"post\">\n  <label>Nombre <input type=\"text\" name=\"nombre\"></label>\n  <button type=\"submit\">Enviar</button>\n</form>", replacesSelection: true),
        Snippet(name: "Comentario HTML", group: "Contenido", before: "<!-- ", after: "${caret} -->"),

        Snippet(name: "Bloque PHP", group: "PHP", before: "<?php ", after: "${caret} ?>"),
        Snippet(name: "Echo", group: "PHP", before: "<?= ", after: "${caret} ?>"),
    ]
}

/// Fragmentos de fábrica más los que crea Fran (guardados en las preferencias).
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()
    private let key = "fragmentosPropios"

    @Published var custom: [Snippet] = [] {
        didSet { save() }
    }

    var builtIns: [Snippet] { Snippets.builtIns }

    var groups: [(name: String, items: [Snippet])] {
        var order: [String] = []
        var map: [String: [Snippet]] = [:]
        for s in builtIns + custom {
            if map[s.group] == nil { order.append(s.group) }
            map[s.group, default: []].append(s)
        }
        return order.map { ($0, map[$0]!) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Snippet].self, from: data) {
            custom = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
