import AppKit

/// Da estilo al Markdown mientras se escribe, sin cambiar el texto: las marcas (#, **, `…) se quedan
/// visibles pero atenuadas, como en Tot.
enum MarkdownStyler {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let heading = regex(#"^(#{1,3})[ \t]+(.+)$"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    // Un solo * o _ a cada lado; el contenido no puede empezar ni acabar en otro marcador (eso es **negrita**).
    private static let italic = regex(#"(?<![\*_\w])([\*_])(?=[^\s\*_])(.+?)(?<=[^\s\*_])\1(?![\*_\w])"#)
    private static let code = regex(#"`([^`\n]+)`"#)
    private static let strike = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let quote = regex(#"^>[ \t]?.*$"#)
    private static let bullet = regex(#"^[ \t]*([-*+]|\d+\.)[ \t]"#)
    private static let checkbox = regex(#"^[ \t]*[-*+][ \t]\[( |x|X)\][ \t]?(.*)$"#)
    private static let links = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func baseAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 4
        return [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph]
    }

    static func apply(to storage: NSTextStorage, fontSize: CGFloat, accent: NSColor) {
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        let marker = NSColor.tertiaryLabelColor
        storage.setAttributes(baseAttributes(fontSize: fontSize), range: all)

        func each(_ expression: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            expression.enumerateMatches(in: storage.string, range: all) { match, _, _ in
                if let match { body(match) }
            }
        }
        func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, _ range: NSRange) {
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: fontSize)
                let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
                storage.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: sub)
            }
        }

        each(heading) { m in
            let level = m.range(at: 1).length
            let size = fontSize + CGFloat(4 - level) * 3 + 1
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: m.range)
            storage.addAttribute(.foregroundColor, value: marker, range: m.range(at: 1))
        }
        each(quote) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range)
            addTrait(.italic, m.range)
        }
        each(bullet) { m in
            storage.addAttribute(.foregroundColor, value: accent, range: m.range(at: 1))
        }
        each(checkbox) { m in
            let box = NSRange(location: m.range(at: 1).location - 1, length: 3)
            storage.addAttribute(.foregroundColor, value: accent, range: box)
            if m.range(at: 1).length > 0, text.substring(with: m.range(at: 1)).lowercased() == "x" {
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .foregroundColor: NSColor.secondaryLabelColor], range: m.range(at: 2))
            }
        }
        each(bold) { m in
            addTrait(.bold, m.range)
            let width = m.range(at: 1).length
            storage.addAttribute(.foregroundColor, value: marker, range: NSRange(location: m.range.location, length: width))
            storage.addAttribute(.foregroundColor, value: marker,
                                 range: NSRange(location: NSMaxRange(m.range) - width, length: width))
        }
        each(italic) { m in
            addTrait(.italic, m.range)
            storage.addAttribute(.foregroundColor, value: marker, range: NSRange(location: m.range.location, length: 1))
            storage.addAttribute(.foregroundColor, value: marker, range: NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
        each(strike) { m in
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .foregroundColor: NSColor.secondaryLabelColor], range: m.range)
        }
        each(code) { m in
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular),
                                   .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.25),
                                   .foregroundColor: accent], range: m.range)
        }
        links.enumerateMatches(in: storage.string, range: all) { match, _, _ in
            guard let match, let url = match.url else { return }
            storage.addAttributes([.link: url, .foregroundColor: accent,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue], range: match.range)
        }
    }
}
