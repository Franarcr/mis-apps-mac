import Foundation
import ImageIO
import CArchive

/// Una página del cómic: los bytes de la imagen tal como vienen en el archivo y su tamaño en píxeles.
struct ComicPage {
    let name: String
    let data: Data
    let pixelSize: CGSize

    /// Las páginas apaisadas suelen ser dobles páginas ya unidas: se muestran solas.
    var isWide: Bool { pixelSize.width > pixelSize.height }
}

enum ComicError: LocalizedError {
    case cannotOpen(String)
    case encrypted
    case damaged(String)
    case noPages

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let detail): return "No es un archivo de cómic que se pueda leer. \(detail)"
        case .encrypted: return "El archivo está protegido con contraseña."
        case .damaged(let detail): return "El archivo está dañado o incompleto. \(detail)"
        case .noPages: return "El archivo no contiene imágenes."
        }
    }
}

/// Lee CBZ (ZIP), CBR (RAR 4 y 5), CB7 (7z) y CBT (TAR) con libarchive.
/// libarchive reconoce el formato por el contenido, así que da igual que un .cbr sea en realidad un ZIP.
enum ComicArchive {
    static let fileExtensions = ["cbz", "cbr", "cb7", "cbt", "zip", "rar", "7z"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff",
                                                       "heic", "avif", "jxl"]

    /// Lee todas las imágenes del archivo, ordenadas como en el Finder (page2 antes que page10).
    /// `progress` recibe la fracción leída (0…1) desde el hilo de la lectura.
    static func load(_ url: URL, progress: (Double) -> Void) throws -> [ComicPage] {
        guard let archive = archive_read_new() else { throw ComicError.cannotOpen("") }
        defer { archive_read_free(archive) }
        archive_read_support_filter_all(archive)
        archive_read_support_format_all(archive)
        guard archive_read_open_filename(archive, url.path, 1 << 16) == ARCHIVE_OK else {
            throw ComicError.cannotOpen(errorMessage(archive))
        }

        let fileSize = Double((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var pages: [ComicPage] = []
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            if status < ARCHIVE_WARN { throw ComicError.damaged(errorMessage(archive)) }
            // Lo que no es una página (carpetas, ComicInfo.xml, Thumbs.db…) se salta sin leerlo.
            guard let entry, ca_entry_is_file(entry) != 0, let name = entryName(entry), isPage(name) else { continue }
            if archive_entry_is_encrypted(entry) != 0 { throw ComicError.encrypted }

            var data = Data()
            while true {
                let count = buffer.withUnsafeMutableBytes { archive_read_data(archive, $0.baseAddress, $0.count) }
                if count == 0 { break }
                if count < 0 { throw ComicError.damaged(errorMessage(archive)) }
                data.append(contentsOf: buffer[0 ..< count])
            }
            if let size = pixelSize(of: data) {
                pages.append(ComicPage(name: name, data: data, pixelSize: size))
            }
            if fileSize > 0 { progress(min(1, Double(archive_filter_bytes(archive, -1)) / fileSize)) }
        }
        guard !pages.isEmpty else { throw ComicError.noPages }
        return pages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Descomprime la imagen de una página. Se puede llamar desde cualquier hilo.
    static func decode(_ page: ComicPage) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(page.data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private static func entryName(_ entry: OpaquePointer) -> String? {
        guard let raw = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) else { return nil }
        return String(cString: raw).replacingOccurrences(of: "\\", with: "/")
    }

    /// Una imagen que no está en una carpeta oculta ni en la basura que deja el Finder (__MACOSX, ._foto.jpg).
    private static func isPage(_ name: String) -> Bool {
        let components = name.split(separator: "/")
        guard let last = components.last,
              !components.contains(where: { $0.hasPrefix(".") || $0 == "__MACOSX" }) else { return false }
        return imageExtensions.contains((String(last) as NSString).pathExtension.lowercased())
    }

    /// Lee solo la cabecera de la imagen; si ImageIO no la reconoce, la página se descarta.
    private static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func errorMessage(_ archive: OpaquePointer) -> String {
        archive_error_string(archive).map { String(cString: $0) } ?? ""
    }
}
