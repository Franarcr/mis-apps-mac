import Foundation

/// Prueba completa sin interfaz: crea una carpeta con archivos, la comprime en cada formato
/// (ZIP también con contraseña), lista, extrae y compara byte a byte.
///   Compresor --self-test
enum SelfTest {
    static func run() -> Bool {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("compresor-prueba-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("Proyecto ñandú")
        try? fm.createDirectory(at: source.appendingPathComponent("docs/sub"), withIntermediateDirectories: true)
        var originals: [String: Data] = [:]
        func write(_ path: String, _ data: Data) {
            try? data.write(to: source.appendingPathComponent(path))
            originals["Proyecto ñandú/" + path] = data
        }
        write("leeme.txt", Data("Hola, mundo. Con tildes: árbol, canción.\n".utf8))
        write("docs/notas.md", Data(String(repeating: "Línea de prueba comprimible.\n", count: 5000).utf8))
        write("docs/sub/aleatorio.bin", Data((0 ..< 300_000).map { _ in UInt8.random(in: 0 ... 255) }))
        write("vacío.txt", Data())

        var ok = true
        func check(_ label: String, _ condition: Bool, _ detail: String = "") {
            print("\(condition ? "OK   " : "FALLO") \(label)\(detail.isEmpty ? "" : " · \(detail)")")
            if !condition { ok = false }
        }

        for (format, password) in [(CreateFormat.zip, nil), (.zip, "secreta123"), (.sevenZip, nil), (.tarGz, nil), (.tarXz, nil)] as [(CreateFormat, String?)] {
            let label = format.title + (password == nil ? "" : " con contraseña")
            do {
                let archive = try ArchiveActions.compress([source], format: format, password: password, progress: Progress())
                let size = (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let listing = try ArchiveEngine.list(archive)
                check("\(label): crear y listar", listing.items.filter { !$0.isDirectory }.count == originals.count,
                      "\(listing.items.count) entradas · \(size) bytes · formato \(listing.format)")
                if password != nil {
                    check("\(label): marcado como cifrado", listing.hasEncryptedItems)
                    var rejected = false
                    do { try ArchiveEngine.extract(archive, to: root.appendingPathComponent("mal"), password: "otra", progress: Progress()) }
                    catch { rejected = true }
                    check("\(label): rechaza contraseña incorrecta", rejected)
                }
                let out = root.appendingPathComponent("salida-\(format.rawValue)-\(password == nil ? "a" : "b")")
                try ArchiveEngine.extract(archive, to: out, password: password, progress: Progress())
                let differing = originals.filter { path, data in (try? Data(contentsOf: out.appendingPathComponent(path))) != data }
                for (path, data) in differing {
                    let got = try? Data(contentsOf: out.appendingPathComponent(path))
                    print("      distinto: \(path) · esperado \(data.count) bytes · obtenido \(got.map { "\($0.count) bytes" } ?? "no existe")")
                }
                let same = differing.isEmpty
                check("\(label): extraer idéntico", same)
                try? fm.removeItem(at: archive)
            } catch {
                check(label, false, error.localizedDescription)
            }
        }

        // Extraer aquí: un único elemento de primer nivel → sin carpeta extra.
        do {
            let archive = try ArchiveActions.compress([source], progress: Progress())
            let result = try ArchiveActions.extractHere(archive, password: nil, progress: Progress())
            check("Extraer aquí (una carpeta)", result.lastPathComponent == "Proyecto ñandú 2", result.lastPathComponent)
        } catch { check("Extraer aquí", false, error.localizedDescription) }

        // Rutas peligrosas.
        check("Ruta con ..", ArchiveEngine.safeRelativePath("../../etc/passwd") == nil)
        check("Ruta absoluta", ArchiveEngine.safeRelativePath("/tmp/x") == "tmp/x")
        return ok
    }
}
