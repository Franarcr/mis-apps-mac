import Foundation

struct Problem: Identifiable, Hashable {
    enum Kind { case error, warning }
    let id = UUID()
    var kind: Kind
    var message: String
    var line: Int
    var column: Int
    /// "Revisión" (análisis del código) o "Vista previa" (error al ejecutar).
    var source: String = "Revisión"
}

/// Revisión sencilla del código: etiquetas sin cerrar, llaves descompensadas y avisos útiles.
enum Validator {
    static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link",
                                        "meta", "param", "source", "track", "wbr"]
    static let optionalClose: Set<String> = ["html", "head", "body", "p", "li", "dt", "dd", "option", "optgroup",
                                             "tr", "td", "th", "thead", "tbody", "tfoot", "colgroup", "caption",
                                             "rb", "rt", "rtc", "rp"]

    static func validate(_ text: String, lang: Lang) -> [Problem] {
        let lines = LineIndex(text)
        switch lang {
        case .html, .php: return html(text, lines)
        case .css: return brackets(mask(text, patterns: [#"/\*[\s\S]*?(?:\*/|$(?![\s\S]))"#, #""[^"\n]*"|'[^'\n]*'"#]), lines, pairs: ["{": "}"])
        case .js: return brackets(mask(text, patterns: [Highlighter.jsStrings, Highlighter.cStyleComments]), lines,
                                  pairs: ["{": "}", "(": ")", "[": "]"])
        }
    }

    /// Sustituye por espacios lo que coincide (conservando saltos de línea y posiciones).
    static func mask(_ text: String, patterns: [String], group: Int = 0) -> NSString {
        let out = NSMutableString(string: text)
        for p in patterns {
            Highlighter.re(p).enumerateMatches(in: text, range: NSRange(location: 0, length: out.length)) { m, _, _ in
                guard let r = m?.range(at: group), r.location != NSNotFound, r.length > 0 else { return }
                let sub = out.substring(with: r)
                let units = sub.utf16.map { $0 == 10 ? UInt16(10) : UInt16(32) }
                out.replaceCharacters(in: r, with: String(utf16CodeUnits: units, count: units.count))
            }
        }
        return out
    }

    static func html(_ text: String, _ lines: LineIndex) -> [Problem] {
        var problems: [Problem] = []
        func add(_ kind: Problem.Kind, _ msg: String, _ offset: Int) {
            let (l, c) = lines.position(of: offset)
            problems.append(Problem(kind: kind, message: msg, line: l, column: c))
        }
        let ns = text as NSString
        if let r = ns.range(of: "<!--", options: .backwards) as NSRange?, r.location != NSNotFound,
           ns.range(of: "-->", options: [], range: NSRange(location: r.location, length: ns.length - r.location)).location == NSNotFound {
            add(.error, "Comentario sin cerrar (falta -->)", r.location)
        }
        var masked = mask(text, patterns: [#"<!--[\s\S]*?(?:-->|$(?![\s\S]))"#, #"<\?[\s\S]*?(?:\?>|$(?![\s\S]))"#])
        masked = mask(masked as String, patterns: [#"<script[^>]*>([\s\S]*?)(?=</script>)"#, #"<style[^>]*>([\s\S]*?)(?=</style>)"#], group: 1)
        let m = masked as String

        if ns.range(of: "<html", options: .caseInsensitive).location != NSNotFound,
           ns.range(of: "<!doctype", options: .caseInsensitive).location == NSNotFound {
            add(.warning, "Falta <!DOCTYPE html> al principio", 0)
        }

        var stack: [(name: String, offset: Int)] = []
        var ids: [String: Int] = [:]
        let attrRe = Highlighter.re(#"([^\s"'>/=]+)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s>]+))?"#)
        Highlighter.re(#"<(/?)([A-Za-z][\w:.-]*)([^<>]*?)(/?)>"#).enumerateMatches(in: m, range: NSRange(location: 0, length: masked.length)) { match, _, _ in
            guard let match else { return }
            let closing = match.range(at: 1).length > 0
            let name = masked.substring(with: match.range(at: 2)).lowercased()
            let selfClosing = match.range(at: 4).length > 0
            let offset = match.range.location

            if closing {
                if voidTags.contains(name) {
                    add(.warning, "<\(name)> no necesita etiqueta de cierre", offset)
                    return
                }
                if let idx = stack.lastIndex(where: { $0.name == name }) {
                    for open in stack[(idx + 1)...].reversed() where !optionalClose.contains(open.name) {
                        add(.error, "Falta cerrar <\(open.name)> antes de </\(name)>", open.offset)
                    }
                    stack.removeSubrange(idx...)
                } else {
                    add(.error, "</\(name)> no tiene etiqueta de apertura", offset)
                }
                return
            }

            // Atributos: repetidos, id duplicados, imágenes sin alt.
            let attrsRange = match.range(at: 3)
            var seen: Set<String> = []
            var hasAlt = false
            attrRe.enumerateMatches(in: m, range: attrsRange) { a, _, _ in
                guard let a else { return }
                let attr = masked.substring(with: a.range(at: 1)).lowercased()
                if seen.contains(attr) { add(.warning, "Atributo «\(attr)» repetido en <\(name)>", a.range.location) }
                seen.insert(attr)
                if attr == "alt" { hasAlt = true }
                if attr == "id", a.range(at: 2).location != NSNotFound {
                    let v = masked.substring(with: a.range(at: 2)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if ids[v] != nil { add(.warning, "El id «\(v)» está repetido", a.range.location) }
                    ids[v] = a.range.location
                }
            }
            if name == "img" && !hasAlt { add(.warning, "A la imagen le falta el texto alternativo (alt)", offset) }

            if !voidTags.contains(name) && !selfClosing {
                stack.append((name, offset))
            }
        }
        for open in stack where !optionalClose.contains(open.name) {
            add(.error, "Falta cerrar <\(open.name)>", open.offset)
        }
        return problems.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
    }

    static func brackets(_ s: NSString, _ lines: LineIndex, pairs: [Character: Character]) -> [Problem] {
        var problems: [Problem] = []
        var stack: [(ch: Character, offset: Int)] = []
        let closers = Dictionary(uniqueKeysWithValues: pairs.map { ($0.value, $0.key) })
        for i in 0..<s.length {
            guard let scalar = Unicode.Scalar(s.character(at: i)) else { continue }
            let c = Character(scalar)
            if pairs[c] != nil {
                stack.append((c, i))
            } else if let opener = closers[c] {
                if let last = stack.last, last.ch == opener {
                    stack.removeLast()
                } else if let idx = stack.lastIndex(where: { $0.ch == opener }) {
                    for open in stack[(idx + 1)...] {
                        let (l, col) = lines.position(of: open.offset)
                        problems.append(Problem(kind: .error, message: "Falta cerrar «\(open.ch)» (\(pairs[open.ch]!))", line: l, column: col))
                    }
                    stack.removeSubrange(idx...)
                } else {
                    let (l, col) = lines.position(of: i)
                    problems.append(Problem(kind: .error, message: "«\(c)» sin su «\(opener)» de apertura", line: l, column: col))
                }
            }
        }
        for open in stack {
            let (l, col) = lines.position(of: open.offset)
            problems.append(Problem(kind: .error, message: "Falta cerrar «\(open.ch)» (\(pairs[open.ch]!))", line: l, column: col))
        }
        return problems.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
    }
}

/// Convierte posiciones del texto (UTF-16) en línea y columna.
struct LineIndex {
    private(set) var starts: [Int] = [0]
    init(_ text: String) {
        var i = 0
        for u in text.utf16 {
            i += 1
            if u == 10 { starts.append(i) }
        }
    }
    var count: Int { starts.count }
    func position(of offset: Int) -> (line: Int, column: Int) {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return (lo + 1, offset - starts[lo] + 1)
    }
    func offset(ofLine line: Int) -> Int {
        starts[max(0, min(line - 1, starts.count - 1))]
    }
}
