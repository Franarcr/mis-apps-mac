import Foundation
import CGrabador

/// La imagen elegida: un archivo .img/.iso tal cual, uno comprimido (.gz, .xz, .bz2…) o un .zip que la contiene.
struct DiskImage: Equatable {
    enum Kind: Equatable {
        case plain
        case compressed      // un solo flujo comprimido: se descomprime al vuelo
        case zip(entry: String)
    }

    static let plainExtensions: Set<String> = ["img", "iso", "bin", "raw", "dd", "dsk", "hddimg", "sdcard", "wic", "image"]
    static let compressedExtensions: Set<String> = ["gz", "xz", "bz2", "zst", "lz4", "lzma", "z"]
    static let allExtensions = plainExtensions.union(compressedExtensions).union(["zip"])

    let url: URL
    let kind: Kind
    let fileSize: Int64
    /// Tamaño ya descomprimido, si se conoce (en .gz o .xz no se sabe hasta terminar).
    let imageSize: Int64?
    /// Aviso para mostrar junto al nombre (por ejemplo, una ISO de Windows).
    let warning: String?

    var name: String { url.lastPathComponent }
    var displaySize: String {
        if let imageSize { return ByteCountFormatter.string(fromByteCount: imageSize, countStyle: .file) }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file) + " comprimida"
    }

    enum Failure: LocalizedError {
        case unsupported(String), unreadable(String), emptyZip
        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): return "No sé grabar archivos .\(ext). Usa una imagen .img, .iso o comprimida (.zip, .gz, .xz)."
            case .unreadable(let detail): return "No se pudo leer la imagen: \(detail)"
            case .emptyZip: return "El .zip no contiene ninguna imagen (.img, .iso…)."
            }
        }
    }

    static func open(_ url: URL) throws -> DiskImage {
        let ext = url.pathExtension.lowercased()
        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else { throw Failure.unreadable("el archivo está vacío o no existe") }

        if plainExtensions.contains(ext) || ext.isEmpty {
            return DiskImage(url: url, kind: .plain, fileSize: fileSize, imageSize: fileSize, warning: bootWarning(url: url, ext: ext))
        }
        if compressedExtensions.contains(ext) {
            // Se comprueba que libarchive lo entiende leyendo un trozo.
            let reader = try ImageReader(DiskImage(url: url, kind: .compressed, fileSize: fileSize, imageSize: nil, warning: nil))
            defer { reader.close() }
            var probe = [UInt8](repeating: 0, count: 4096)
            _ = try probe.withUnsafeMutableBytes { try reader.read(into: $0.baseAddress!, count: 4096) }
            return DiskImage(url: url, kind: .compressed, fileSize: fileSize, imageSize: gzipSize(url, ext: ext, fileSize: fileSize), warning: nil)
        }
        if ext == "zip" {
            // La imagen es el archivo más grande con extensión de imagen (o, si no hay, el más grande).
            guard let a = archive_read_new() else { throw Failure.unreadable("sin memoria") }
            defer { archive_read_free(a) }
            archive_read_support_format_zip(a)
            guard archive_read_open_filename(a, url.path, 1 << 16) == ARCHIVE_OK else {
                throw Failure.unreadable(String(cString: archive_error_string(a)))
            }
            var best: (name: String, size: Int64, image: Bool)?
            var entry: OpaquePointer?
            while archive_read_next_header(a, &entry) == ARCHIVE_OK {
                guard let entry, cg_entry_is_file(entry) == 1, let path = archive_entry_pathname(entry) else { continue }
                let name = String(cString: path)
                if name.hasPrefix("__MACOSX/") { continue }
                let size = archive_entry_size(entry)
                let image = plainExtensions.contains((name as NSString).pathExtension.lowercased())
                if best == nil || (image && !best!.image) || (image == best!.image && size > best!.size) {
                    best = (name, size, image)
                }
                archive_read_data_skip(a)
            }
            guard let best else { throw Failure.emptyZip }
            return DiskImage(url: url, kind: .zip(entry: best.name), fileSize: fileSize, imageSize: best.size, warning: nil)
        }
        throw Failure.unsupported(ext)
    }

    /// En un .gz los últimos 4 bytes guardan el tamaño original (módulo 4 GB): solo se usa si encaja.
    private static func gzipSize(_ url: URL, ext: String, fileSize: Int64) -> Int64? {
        guard ext == "gz", let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(fileSize - 4))) != nil, let tail = try? handle.read(upToCount: 4), tail.count == 4 else { return nil }
        guard (try? handle.seek(toOffset: 0)) != nil, let magic = try? handle.read(upToCount: 2), magic == Data([0x1f, 0x8b]) else { return nil }
        let size = Int64(tail.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
        return size >= fileSize ? size : nil
    }

    /// Una ISO sin tabla de particiones (las de Windows, por ejemplo) no arranca grabada tal cual en un USB.
    private static func bootWarning(url: URL, ext: String) -> String? {
        guard ext == "iso", let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 1024) else { return nil }
        try? handle.close()
        let hasMBR = head.count >= 512 && head[510] == 0x55 && head[511] == 0xAA
        let hasGPT = head.count >= 520 && head[512 ..< 520] == Data("EFI PART".utf8)
        return hasMBR || hasGPT ? nil
            : "Esta ISO no parece preparada para USB (las de Windows, por ejemplo, no lo están). Puede que no arranque."
    }
}

/// Lee la imagen ya descomprimida, por trozos.
final class ImageReader {
    private var handle: FileHandle?
    private var archive: OpaquePointer?
    /// Bytes del archivo original consumidos (para el progreso cuando no se sabe el tamaño final).
    private(set) var consumed: Int64 = 0

    init(_ image: DiskImage) throws {
        switch image.kind {
        case .plain:
            handle = try FileHandle(forReadingFrom: image.url)
        case .compressed, .zip:
            guard let a = archive_read_new() else { throw DiskImage.Failure.unreadable("sin memoria") }
            archive = a
            archive_read_support_filter_all(a)
            if case .zip = image.kind { archive_read_support_format_zip(a) } else { archive_read_support_format_raw(a) }
            guard archive_read_open_filename(a, image.url.path, 1 << 20) == ARCHIVE_OK else {
                throw DiskImage.Failure.unreadable(String(cString: archive_error_string(a)))
            }
            var entry: OpaquePointer?
            while true {
                let status = archive_read_next_header(a, &entry)
                guard status == ARCHIVE_OK || status == ARCHIVE_WARN, let entry else {
                    throw DiskImage.Failure.unreadable("no se encontró la imagen dentro del archivo")
                }
                // Un .gz/.xz que en realidad no está comprimido se rechaza (solo tendría el filtro "none").
                if image.kind == .compressed, archive_filter_count(a) < 2 {
                    throw DiskImage.Failure.unreadable("no está comprimido en un formato conocido")
                }
                guard case .zip(let wanted) = image.kind else { break }
                if let path = archive_entry_pathname(entry), String(cString: path) == wanted { break }
                archive_read_data_skip(a)
            }
        }
    }

    /// Llena hasta `count` bytes; devuelve menos solo al final de la imagen.
    func read(into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        var filled = 0
        while filled < count {
            let n: Int
            if let handle {
                let r = Darwin.read(handle.fileDescriptor, buffer + filled, count - filled)
                if r < 0 {
                    if errno == EINTR { continue }
                    throw DiskImage.Failure.unreadable(String(cString: strerror(errno)))
                }
                n = r
                consumed += Int64(n)
            } else if let archive {
                let r = archive_read_data(archive, buffer + filled, count - filled)
                if r < 0 { throw DiskImage.Failure.unreadable(String(cString: archive_error_string(archive))) }
                n = r
                consumed = archive_filter_bytes(archive, -1)
            } else {
                n = 0
            }
            if n == 0 { break }
            filled += n
        }
        return filled
    }

    func close() {
        try? handle?.close()
        handle = nil
        if let archive { archive_read_free(archive) }
        archive = nil
    }

    deinit { close() }
}
