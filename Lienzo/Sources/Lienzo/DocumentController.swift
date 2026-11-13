import AppKit

/// Igual que el controlador de documentos normal, pero «Abrir…» también acepta el HTML
/// guardado desde Miro y lo lleva al importador con el tablero ya puesto.
final class LienzoDocumentController: NSDocumentController {
    private static let htmlTypes = ["public.html"]

    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?,
                                 completionHandler: @escaping (Int) -> Void) {
        super.beginOpenPanel(openPanel, forTypes: (inTypes ?? []) + Self.htmlTypes, completionHandler: completionHandler)
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        super.runModalOpenPanel(openPanel, forTypes: (types ?? []) + Self.htmlTypes)
    }

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        guard ["html", "htm"].contains(url.pathExtension.lowercased()) else {
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
            return
        }
        if let id = MiroLink.boardID(fromFile: url) {
            MainActor.assumeIsolated { MiroImportWindow.shared.show(link: "https://miro.com/app/board/\(id)/") }
            completionHandler(nil, false, nil)
        } else {
            let alert = NSAlert()
            alert.messageText = "Este HTML no es de un tablero de Miro"
            alert.informativeText = "Lienzo solo abre HTML guardados desde un tablero de Miro, para importarlo."
            alert.runModal()
            completionHandler(nil, false, nil)
        }
    }
}
