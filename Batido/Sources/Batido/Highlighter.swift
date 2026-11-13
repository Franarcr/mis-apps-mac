import AppKit

/// Lenguaje con el que se colorea, revisa y muestra el documento.
enum Lang: String, CaseIterable, Identifiable {
    case html, css, js, php
    var id: String { rawValue }
    var title: String {
        switch self {
        case .html: return "HTML"
        case .css: return "CSS"
        case .js: return "JavaScript"
        case .php: return "PHP"
        }
    }

    static func from(url: URL?) -> Lang {
        switch url?.pathExtension.lowercased() ?? "" {
        case "css", "scss": return .css
        case "js", "mjs", "jsx", "ts", "json": return .js
        case "php", "php3", "php4", "phtml", "inc": return .php
        default: return .html
        }
    }
}

/// Colorea el código con expresiones regulares (sin dependencias externas).
enum Highlighter {
    static let tag = NSColor.systemBlue
    static let attr = NSColor.systemTeal
    static let string = NSColor.systemRed
    static let comment = NSColor.secondaryLabelColor
    static let keyword = NSColor.systemPink
    static let number = NSColor.systemPurple
    static let selector = NSColor.systemGreen
    static let function = NSColor.systemIndigo
    static let variable = NSColor.systemOrange
    static let doctype = NSColor.systemGray

    private static var cache: [String: NSRegularExpression] = [:]
    static func re(_ p: String) -> NSRegularExpression {
        if let r = cache[p] { return r }
        let r = try! NSRegularExpression(pattern: p, options: [])
        cache[p] = r
        return r
    }

    static func highlight(_ storage: NSTextStorage, lang: Lang, font: NSFont, enabled: Bool) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: NSColor.textColor], range: full)
        if enabled && storage.length < 400_000 {
            let s = storage.string as NSString
            switch lang {
            case .html: html(storage, s, full)
            case .css: css(storage, s, full)
            case .js: js(storage, s, full)
            case .php: html(storage, s, full)
            }
        }
        storage.endEditing()
    }

    private static func color(_ st: NSTextStorage, _ s: NSString, _ pattern: String, _ c: NSColor,
                              in range: NSRange, group: Int = 0) {
        re(pattern).enumerateMatches(in: s as String, range: range) { m, _, _ in
            guard let m else { return }
            let r = m.range(at: group)
            if r.location != NSNotFound { st.addAttribute(.foregroundColor, value: c, range: r) }
        }
    }

    /// Cadenas y comentarios en una sola pasada, para que "http://" dentro de una cadena no parezca comentario.
    private static func stringsAndComments(_ st: NSTextStorage, _ s: NSString, in range: NSRange,
                                           strings: String, comments: String) {
        re("(\(strings))|(\(comments))").enumerateMatches(in: s as String, range: range) { m, _, _ in
            guard let m else { return }
            if m.range(at: 1).location != NSNotFound {
                st.addAttribute(.foregroundColor, value: string, range: m.range(at: 1))
            } else if m.range(at: 2).location != NSNotFound {
                st.addAttribute(.foregroundColor, value: comment, range: m.range(at: 2))
            }
        }
    }

    static let jsStrings = #""(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`"#
    static let cStyleComments = #"//[^\n]*|/\*[\s\S]*?(?:\*/|$(?![\s\S]))"#

    static func html(_ st: NSTextStorage, _ s: NSString, _ range: NSRange) {
        // Etiquetas con sus atributos y valores.
        re(#"<(/?)([A-Za-z][\w:.-]*)([^<>]*?)(/?)>"#).enumerateMatches(in: s as String, range: range) { m, _, _ in
            guard let m else { return }
            st.addAttribute(.foregroundColor, value: tag, range: m.range)
            let inner = m.range(at: 3)
            if inner.length > 0 {
                st.addAttribute(.foregroundColor, value: NSColor.textColor, range: inner)
                color(st, s, #"[A-Za-z_:@][\w:.@-]*(?=\s*=|\s|$)"#, attr, in: inner)
                color(st, s, #""[^"]*"|'[^']*'"#, string, in: inner)
            }
        }
        color(st, s, #"<![Dd][Oo][Cc][Tt][Yy][Pp][Ee][^>]*>"#, doctype, in: range)
        color(st, s, #"&#?\w+;"#, number, in: range)

        // CSS dentro de <style> y JavaScript dentro de <script>.
        re(#"<style[^>]*>([\s\S]*?)(?=</style>|$(?![\s\S]))"#).enumerateMatches(in: s as String, range: range) { m, _, _ in
            guard let r = m?.range(at: 1), r.length > 0 else { return }
            st.addAttribute(.foregroundColor, value: NSColor.textColor, range: r)
            css(st, s, r)
        }
        re(#"<script[^>]*>([\s\S]*?)(?=</script>|$(?![\s\S]))"#).enumerateMatches(in: s as String, range: range) { m, _, _ in
            guard let r = m?.range(at: 1), r.length > 0 else { return }
            st.addAttribute(.foregroundColor, value: NSColor.textColor, range: r)
            js(st, s, r)
        }
        color(st, s, #"<!--[\s\S]*?(?:-->|$(?![\s\S]))"#, comment, in: range)

        // Bloques PHP.
        re(#"<\?(?:php|=)?([\s\S]*?)(?:\?>|$(?![\s\S]))"#).enumerateMatches(in: s as String, range: range) { m, _, _ in
            guard let m else { return }
            st.addAttribute(.foregroundColor, value: tag, range: m.range)
            let r = m.range(at: 1)
            if r.length > 0 {
                st.addAttribute(.foregroundColor, value: NSColor.textColor, range: r)
                php(st, s, r)
            }
        }
    }

    static func css(_ st: NSTextStorage, _ s: NSString, _ range: NSRange) {
        color(st, s, #"(?<=[{;\s])[\w-]+(?=\s*:)"#, attr, in: range)
        color(st, s, #"[^{};/]+(?=\{)"#, selector, in: range)
        color(st, s, #"#[0-9a-fA-F]{3,8}\b|\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|vmin|vmax|s|ms|deg|fr|pt|ch)?\b"#, number, in: range)
        color(st, s, #"@[\w-]+|!important"#, keyword, in: range)
        stringsAndComments(st, s, in: range, strings: #""[^"\n]*"|'[^'\n]*'"#, comments: #"/\*[\s\S]*?(?:\*/|$(?![\s\S]))"#)
    }

    static func js(_ st: NSTextStorage, _ s: NSString, _ range: NSRange) {
        color(st, s, #"\b[A-Za-z_$][\w$]*(?=\s*\()"#, function, in: range)
        color(st, s, #"\b(?:break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|function|if|import|in|instanceof|let|new|return|super|switch|this|throw|try|typeof|var|void|while|with|yield|async|await|of|static|from)\b"#, keyword, in: range)
        color(st, s, #"\b(?:true|false|null|undefined|NaN|Infinity)\b|\b\d+(?:\.\d+)?\b"#, number, in: range)
        stringsAndComments(st, s, in: range, strings: jsStrings, comments: cStyleComments)
    }

    static func php(_ st: NSTextStorage, _ s: NSString, _ range: NSRange) {
        color(st, s, #"\b[A-Za-z_][\w]*(?=\s*\()"#, function, in: range)
        color(st, s, #"\b(?:echo|print|if|else|elseif|endif|foreach|endforeach|for|endfor|while|endwhile|do|as|function|fn|return|class|interface|trait|extends|implements|new|public|private|protected|static|const|array|isset|unset|empty|require|include|require_once|include_once|switch|case|default|break|continue|namespace|use|match|try|catch|finally|throw|global)\b"#, keyword, in: range)
        color(st, s, #"\b(?:true|false|null|TRUE|FALSE|NULL)\b|\b\d+(?:\.\d+)?\b"#, number, in: range)
        color(st, s, #"\$[A-Za-z_]\w*"#, variable, in: range)
        stringsAndComments(st, s, in: range, strings: #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#,
                           comments: #"//[^\n]*|#[^\n]*|/\*[\s\S]*?(?:\*/|$(?![\s\S]))"#)
    }
}
