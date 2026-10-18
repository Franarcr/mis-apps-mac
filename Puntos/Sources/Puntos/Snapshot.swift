import AppKit

/// Imagen del editor con notas de ejemplo, en una carpeta temporal (no toca las notas reales).
@MainActor
enum Snapshot {
    static func render(to url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Puntos-prueba-\(UUID().uuidString)")
        let store = NotesStore(folder: folder)
        store.update(0, text: """
        # Lista de la compra
        Para el **sábado**, sin falta:

        - [x] Pan y *café*
        - [ ] Fruta para la semana
        - [ ] Pilas para el `Magic Mouse`

        > Ojo: la tienda cierra a las 20:00

        ## Ideas
        1. Probar la receta de https://example.com/receta
        2. ~~Comprar velas~~ ya hay
        """)
        store.update(2, text: "Notas de la reunión")
        store.update(5, text: "Contraseña del wifi de casa en el cajón")

        let controller = NoteWindowController(store: store)
        let frame = controller.window.contentView!.superview!
        controller.window.setContentSize(NSSize(width: 460, height: 540))
        frame.layoutSubtreeIfNeeded()
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        try? FileManager.default.removeItem(at: folder)
        print("Imagen guardada en \(url.path)")
    }
}
