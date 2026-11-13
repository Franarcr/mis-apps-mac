import AppKit
import CryptoKit

/// Un tablero guardado como archivo .lienzo (JSON con las imágenes dentro).
@objc(BoardDocument)
final class BoardDocument: NSDocument {
    static let typeName = "com.fran.lienzo.tablero"

    var board = Board()
    weak var canvas: CanvasView?
    /// Estado antes de un cambio en curso (arrastre, edición de texto).
    private var pending: [Item]?

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(BoardWindowController(board: self))
        WelcomeWindow.shared.close()
    }

    // MARK: - Lectura y escritura

    override func data(ofType typeName: String) throws -> Data {
        var b = board
        // Solo se guardan las imágenes que se usan (en memoria se conservan para poder deshacer).
        let used = Set(b.items.compactMap(\.imageID))
        b.images = b.images.filter { used.contains($0.key) }
        if let c = canvas {
            b.viewCenter = c.viewCenter
            b.viewScale = c.scale
        }
        return try JSONEncoder().encode(b)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        do {
            board = try JSONDecoder().decode(Board.self, from: data)
        } catch {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    override func save(to url: URL, ofType typeName: String, for op: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        if op != .autosaveInPlaceOperation && op != .autosaveElsewhereOperation {
            canvas?.endEditing()
        }
        super.save(to: url, ofType: typeName, for: op) { [weak self] error in
            if error == nil, op != .autosaveElsewhereOperation, let self {
                Thumbnails.write(for: url, board: self.board)
            }
            completionHandler(error)
        }
    }

    override func canClose(withDelegate delegate: Any, shouldClose: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        canvas?.endEditing()
        super.canClose(withDelegate: delegate, shouldClose: shouldClose, contextInfo: contextInfo)
    }

    // MARK: - Cambios con deshacer

    /// Empieza un cambio que se confirma más tarde con `commit`.
    func begin() {
        if pending == nil { pending = board.items }
    }

    func commit(_ name: String) {
        guard let old = pending else { return }
        pending = nil
        if old != board.items { registerUndo(old, name) }
        changed()
    }

    /// Hace un cambio de una vez, con su paso de deshacer.
    func apply(_ name: String, _ change: (inout [Item]) -> Void) {
        let old = board.items
        change(&board.items)
        if old != board.items { registerUndo(old, name) }
        changed()
    }

    private func registerUndo(_ old: [Item], _ name: String) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { doc in
            let current = doc.board.items
            doc.board.items = old
            doc.registerUndo(current, name)
            doc.canvas?.pruneSelection()
            doc.changed()
        }
        um.setActionName(name)
    }

    func changed() {
        canvas?.needsDisplay = true
        DispatchQueue.main.async { [weak self] in self?.canvas?.refreshUndoState() }
    }
}

/// Miniaturas de los tableros para la ventana de recientes.
enum Thumbnails {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Lienzo/Miniaturas", isDirectory: true)
    }

    static func url(for file: URL) -> URL {
        let digest = SHA256.hash(data: Data(file.standardizedFileURL.path.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(name + ".png")
    }

    static func write(for file: URL, board: Board) {
        let items = board.items
        let lookup = Renderer.lookup(items)
        guard let area = Renderer.bounds(of: items, lookup: lookup)?.insetBy(dx: -30, dy: -30) else {
            try? FileManager.default.removeItem(at: url(for: file))
            return
        }
        let scale = min(520 / area.width, 330 / area.height, 1)
        guard let png = Exporter.png(items, lookup: lookup, images: board.images, area: area, scale: scale,
                                     background: NSColor(hex: "F4F4F1")) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? png.write(to: url(for: file))
    }
}
