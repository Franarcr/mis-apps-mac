import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let phpScript = UTType("public.php-script") ?? UTType(filenameExtension: "php") ?? .sourceCode
    static let cssSource = UTType("public.css") ?? UTType(filenameExtension: "css") ?? .sourceCode
}

/// Un archivo de texto (HTML, CSS, JS, PHP…) abierto en Batido.
struct BatidoDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.html, .cssSource, .javaScript, .phpScript, .xml, .plainText, .sourceCode, .text]
    }
    static var writableContentTypes: [UTType] {
        [.html, .cssSource, .javaScript, .phpScript, .xml, .plainText]
    }

    var text: String

    init(text: String = Snippets.welcomePage) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
