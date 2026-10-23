import Foundation

/// Operaciones de alto nivel (las usan la ventana y los Servicios del Finder).
enum ArchiveActions {
    /// Extrae junto al comprimido. Si dentro hay un único elemento de primer nivel, se deja tal cual;
    /// si hay varios, se agrupan en una carpeta con el nombre del comprimido. Devuelve lo creado.
    static func extractHere(_ archive: URL, password: String?, progress: Progress) throws -> URL {
        let folder = archive.deletingLastPathComponent()
        let listing = try ArchiveEngine.list(archive)
        let tops = Set(listing.items.compactMap { ArchiveEngine.safeRelativePath($0.path)?.split(separator: "/").first.map(String.init) })

        if tops.count == 1, let only = tops.first {
            // Se extrae en una carpeta temporal del mismo volumen y se mueve el elemento con un nombre libre.
            let staging = folder.appendingPathComponent(".compresor-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            try ArchiveEngine.extract(archive, to: staging, password: password, progress: progress)
            let source = staging.appendingPathComponent(only)
            let ext = source.pathExtension
            let name = ext.isEmpty ? only : (only as NSString).deletingPathExtension
            let target = ArchiveEngine.uniqueURL(in: folder, name: name, extension: ext.isEmpty ? nil : ext)
            try FileManager.default.moveItem(at: source, to: target)
            return target
        }
        let target = ArchiveEngine.uniqueURL(in: folder, name: ArchiveEngine.baseName(archive), extension: nil)
        try ArchiveEngine.extract(archive, to: target, password: password, progress: progress)
        return target
    }

    /// Comprime junto al primer elemento: "Nombre.zip" si es uno solo, "Archivo.zip" si son varios.
    static func compress(_ items: [URL], format: CreateFormat = .zip, password: String? = nil,
                         name: String? = nil, progress: Progress) throws -> URL {
        guard let first = items.first else { throw ArchiveError.failed("No hay nada que comprimir") }
        let folder = first.deletingLastPathComponent()
        let base = name ?? (items.count == 1 ? (first.lastPathComponent as NSString).deletingPathExtension : "Archivo")
        let target = ArchiveEngine.uniqueURL(in: folder, name: base.isEmpty ? first.lastPathComponent : base,
                                             extension: format.fileExtension)
        try ArchiveEngine.create(from: items, to: target, format: format, password: password, progress: progress)
        return target
    }
}
