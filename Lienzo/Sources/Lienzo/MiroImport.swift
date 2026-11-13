import AppKit
import Security
import SwiftUI

/// Importa un tablero de Miro con su API pública (solo lectura) y lo convierte en un tablero de Lienzo.
enum MiroImportError: LocalizedError {
    case badLink, badToken, noAccess(String), http(Int), network(String)

    var errorDescription: String? {
        switch self {
        case .badLink: "No encuentro el tablero en ese enlace. Pega el enlace de Miro (miro.com/app/board/…) o elige el HTML descargado."
        case .badToken: "Miro no aceptó el código de acceso. Revisa que lo copiaste completo."
        case .noAccess(let detail): "Miro no deja leer ese tablero con este código. La app debe estar instalada en el equipo donde está el tablero. \(detail)"
        case .http(let code): "Miro respondió con un error (\(code)). Prueba de nuevo en un momento."
        case .network(let msg): "No se pudo conectar con Miro: \(msg)"
        }
    }
}

// MARK: - Enlaces y código guardado

enum MiroLink {
    /// Saca el id del tablero de un enlace, de un id suelto o de un HTML guardado desde Miro.
    static func boardID(from text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).removingPercentEncoding ?? text
        if let r = s.range(of: #"board/([A-Za-z0-9_\-]+=?)"#, options: .regularExpression) {
            return String(s[r].dropFirst("board/".count))
        }
        if s.range(of: #"^[A-Za-z0-9_\-]{8,}=?$"#, options: .regularExpression) != nil { return s }
        return nil
    }

    static func boardID(fromFile url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        return boardID(from: text)
    }
}

enum MiroKeychain {
    private static let service = "com.fran.lienzo.miro"

    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func save(_ token: String) {
        delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "token", kSecValueData as String: Data(token.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

// MARK: - API

struct MiroAPI {
    let token: String
    let boardID: String
    /// Para pruebas se puede apuntar a otro servidor con LIENZO_MIRO_API.
    static let base = ProcessInfo.processInfo.environment["LIENZO_MIRO_API"] ?? "https://api.miro.com"

    private func request(_ url: URL, auth: Bool = true) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        if auth {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        for attempt in 0..<4 {
            let data: Data, resp: URLResponse
            do { (data, resp) = try await URLSession.shared.data(for: req) } catch { throw MiroImportError.network(error.localizedDescription) }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200..<300: return data
            case 401: throw MiroImportError.badToken
            case 403, 404:
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
                throw MiroImportError.noAccess(msg)
            case 429 where attempt < 3, 500..<600 where attempt < 3:
                try await Task.sleep(nanoseconds: UInt64(2_000_000_000 * (attempt + 1)))
            default: throw MiroImportError.http(code)
            }
        }
        throw MiroImportError.http(429)
    }

    private var boardPath: String {
        let id = boardID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? boardID
        return "\(Self.base)/v2/boards/\(id)"
    }

    func boardName() async throws -> String? {
        let data = try await request(URL(string: boardPath)!)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["name"] as? String
    }

    /// Lee todas las páginas de una lista (items o connectors).
    func list(_ what: String, progress: (Int) -> Void) async throws -> [[String: Any]] {
        var all: [[String: Any]] = []
        var cursor: String?
        repeat {
            var comps = URLComponents(string: "\(boardPath)/\(what)")!
            comps.queryItems = [URLQueryItem(name: "limit", value: "50")] + (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
            let data = try await request(comps.url!)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            all += json["data"] as? [[String: Any]] ?? []
            cursor = json["cursor"] as? String
            if cursor?.isEmpty == true { cursor = nil }
            progress(all.count)
        } while cursor != nil
        return all
    }

    /// Baja una imagen del tablero en su tamaño original.
    func image(_ urlString: String) async throws -> Data {
        do { return try await image(urlString, format: "original") } catch { return try await image(urlString, format: "preview") }
    }

    private func image(_ urlString: String, format: String) async throws -> Data {
        guard var comps = URLComponents(string: urlString) else { throw MiroImportError.http(0) }
        var q = (comps.queryItems ?? []).filter { $0.name != "format" && $0.name != "redirect" }
        q += [URLQueryItem(name: "format", value: format), URLQueryItem(name: "redirect", value: "false")]
        comps.queryItems = q
        let data = try await request(comps.url!)
        var result = data
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let s = json["url"] as? String, let real = URL(string: s) {
            result = try await request(real, auth: false)
        }
        guard NSImage(data: result) != nil else { throw MiroImportError.http(0) }
        return result
    }
}

// MARK: - Conversión

enum MiroConverter {
    static let stickyColors: [String: String] = [
        "gray": "E6E6E6", "light_yellow": "FFF9B1", "yellow": "F5D128", "orange": "FF9D48",
        "light_green": "D5F692", "green": "C9DF56", "dark_green": "93D275", "cyan": "67C6C0",
        "light_pink": "FFCEE0", "pink": "EA94BB", "violet": "BE88C7", "red": "F24726",
        "light_blue": "A6CCF5", "blue": "6CD8FA", "dark_blue": "9EA9FF", "black": "1A1A1A", "white": "FFFFFF",
    ]

    struct Raw {
        let id: String
        let type: String
        let data: [String: Any]
        let style: [String: Any]
        let x: CGFloat, y: CGFloat
        let relativeToParent: Bool
        let w: CGFloat?, h: CGFloat?
        let parent: String?
    }

    static func num(_ v: Any?) -> CGFloat? {
        if let d = v as? Double { return CGFloat(d) }
        if let i = v as? Int { return CGFloat(i) }
        if let s = v as? String, let d = Double(s) { return CGFloat(d) }
        return nil
    }

    static func hex(_ v: Any?) -> String? {
        guard var s = (v as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty, s != "transparent" else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6, UInt32(s.prefix(6), radix: 16) != nil else { return nil }
        return String(s.prefix(6)).uppercased()
    }

    /// Texto plano a partir del HTML que guarda Miro.
    static func plain(_ html: String?) -> String {
        guard var s = html, !s.isEmpty else { return "" }
        for tag in ["</p>", "<br>", "<br/>", "<br />", "</li>", "</div>"] {
            s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (k, v) in ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&amp;": "&"] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        while s.contains("\n\n\n") { s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func raw(_ j: [String: Any]) -> Raw? {
        guard let id = (j["id"] as? String) ?? (j["id"] as? Int).map(String.init), let type = j["type"] as? String else { return nil }
        let pos = j["position"] as? [String: Any] ?? [:]
        let geo = j["geometry"] as? [String: Any] ?? [:]
        let parent = j["parent"] as? [String: Any]
        return Raw(id: id, type: type, data: j["data"] as? [String: Any] ?? [:], style: j["style"] as? [String: Any] ?? [:],
                   x: num(pos["x"]) ?? 0, y: num(pos["y"]) ?? 0,
                   relativeToParent: (pos["relativeTo"] as? String) == "parent_top_left",
                   w: num(geo["width"]), h: num(geo["height"]),
                   parent: (parent?["id"] as? String) ?? (parent?["id"] as? Int).map(String.init))
    }

    /// Convierte los elementos. `images` recibe el id de Miro y devuelve la clave de la imagen ya bajada.
    static func convert(_ json: [[String: Any]], connectors: [[String: Any]], images: [String: String]) -> (items: [Item], skipped: [String: Int]) {
        let raws = json.compactMap(raw)
        let byID = Dictionary(raws.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rects: [String: CGRect] = [:]

        func size(_ r: Raw) -> CGSize {
            let w = r.w ?? r.h ?? 200
            var h = r.h ?? w
            if r.h == nil, r.type == "sticky_note", (r.data["shape"] as? String) == "rectangle" { h = w * 0.65 }
            if r.h == nil, r.type == "text" { h = max(30, w * 0.25) }
            return CGSize(width: w, height: h)
        }

        func rect(_ id: String, depth: Int = 0) -> CGRect? {
            if let r = rects[id] { return r }
            guard let r = byID[id], depth < 20 else { return nil }
            let s = size(r)
            var cx = r.x, cy = r.y
            if r.relativeToParent, let p = r.parent, let pr = rect(p, depth: depth + 1) {
                cx += pr.minX
                cy += pr.minY
            }
            let result = CGRect(x: cx - s.width / 2, y: cy - s.height / 2, width: s.width, height: s.height)
            rects[id] = result
            return result
        }

        var ids: [String: UUID] = [:]
        var frames: [Item] = [], shapes: [Item] = [], pictures: [Item] = [], notes: [Item] = [], texts: [Item] = []
        var skipped: [String: Int] = [:]
        for r in raws {
            guard let box = rect(r.id) else { skipped[r.type, default: 0] += 1; continue }
            var it: Item
            switch r.type {
            case "frame":
                it = Item(kind: .frame)
                it.text = plain(r.data["title"] as? String)
                it.color = hex(r.style["fillColor"]) ?? "FFFFFF"
                it.rect = box
                frames.append(it)
            case "sticky_note":
                it = Item(kind: .note)
                it.text = plain(r.data["content"] as? String)
                let named = (r.style["fillColor"] as? String) ?? "light_yellow"
                it.color = stickyColors[named] ?? hex(named) ?? "FFF9B1"
                // Miro no dice el tamaño de letra de las notas: lo ajusta a la nota. Aquí, proporcional
                // a su tamaño; al dibujar se reduce si el texto no cabe.
                it.fontSize = num(r.style["fontSize"]) ?? max(6, min(box.width, box.height) * 0.16)
                it.rect = box
                notes.append(it)
            case "shape":
                it = Item(kind: .shape)
                let kinds: [String: ShapeKind] = ["rectangle": .rectangle, "round_rectangle": .rounded, "circle": .ellipse,
                                                  "triangle": .triangle, "rhombus": .diamond]
                it.shape = kinds[(r.data["shape"] as? String) ?? ""] ?? .rectangle
                it.text = plain(r.data["content"] as? String)
                let opacity = num(r.style["fillOpacity"]) ?? 1
                it.color = opacity < 0.05 ? "none" : (hex(r.style["fillColor"]) ?? "none")
                it.fontSize = num(r.style["fontSize"]) ?? 14
                it.lineWidth = max(1, num(r.style["borderWidth"]) ?? 2)
                it.rect = box
                shapes.append(it)
            case "text":
                it = Item(kind: .text)
                it.text = plain(r.data["content"] as? String)
                it.color = hex(r.style["color"]) ?? "1F2329"
                it.fontSize = num(r.style["fontSize"]) ?? 14
                it.rect = box
                // La altura de los textos sale de su contenido, para que no se corten.
                it.rect.size.height = Renderer.textHeight(it.text, size: it.fontSize, width: box.width - 8) + 8
                texts.append(it)
            case "image":
                guard let key = images[r.id] else { skipped["imagen sin bajar", default: 0] += 1; continue }
                it = Item(kind: .image)
                it.imageID = key
                it.rect = box
                pictures.append(it)
            case "card", "app_card":
                it = Item(kind: .note)
                let title = plain(r.data["title"] as? String)
                let desc = plain(r.data["description"] as? String)
                it.text = desc.isEmpty ? title : "\(title)\n\(desc)"
                it.color = "FFFFFF"
                it.fontSize = 16
                it.rect = box
                notes.append(it)
            case "document", "embed":
                it = Item(kind: .note)
                it.text = "Documento: " + plain((r.data["title"] as? String) ?? (r.data["url"] as? String) ?? "")
                it.color = "E6E6E6"
                it.fontSize = 14
                it.rect = box
                notes.append(it)
            default:
                skipped[r.type, default: 0] += 1
                continue
            }
            ids[r.id] = it.id
        }
        // Los marcos grandes primero, para que los marcos de dentro queden encima.
        frames.sort { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }

        var arrows: [Item] = []
        for c in connectors {
            let start = (c["startItem"] as? [String: Any])?["id"]
            let end = (c["endItem"] as? [String: Any])?["id"]
            let s = (start as? String) ?? (start as? Int).map(String.init)
            let e = (end as? String) ?? (end as? Int).map(String.init)
            guard let from = s.flatMap({ ids[$0] }), let to = e.flatMap({ ids[$0] }) else { skipped["flecha sin sus dos extremos", default: 0] += 1; continue }
            var it = Item(kind: .connector)
            it.from = from
            it.to = to
            let style = c["style"] as? [String: Any] ?? [:]
            it.color = hex(style["strokeColor"]) ?? "1F2329"
            it.lineWidth = max(1, num(style["strokeWidth"]) ?? 2)
            it.arrowEnd = ((style["endStrokeCap"] as? String) ?? "none") != "none"
            it.arrowStart = ((style["startStrokeCap"] as? String) ?? "none") != "none"
            arrows.append(it)
        }
        return (frames + shapes + pictures + notes + texts + arrows, skipped)
    }
}

// MARK: - Ventana

@MainActor
final class MiroImportModel: ObservableObject {
    @Published var link = ""
    // LIENZO_MIRO_TOKEN solo sirve para probar con un servidor simulado.
    @Published var token = ProcessInfo.processInfo.environment["LIENZO_MIRO_TOKEN"] ?? MiroKeychain.load() ?? ""
    @Published var remember = MiroKeychain.load() != nil
    @Published var running = false
    @Published var status = ""
    @Published var fraction: Double?
    @Published var error: String?
    private var task: Task<Void, Never>?
    var onFinish: (() -> Void)?

    func chooseHTML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.message = "Elige el HTML que bajaste de Miro"
        if panel.runModal() == .OK, let url = panel.url {
            if let id = MiroLink.boardID(fromFile: url) {
                link = "https://miro.com/app/board/\(id)/"
                error = nil
            } else {
                error = "Ese HTML no tiene el enlace de un tablero de Miro."
            }
        }
    }

    func cancel() {
        task?.cancel()
        running = false
    }

    func start() {
        error = nil
        guard let id = MiroLink.boardID(from: link) else { error = MiroImportError.badLink.localizedDescription; return }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { error = "Falta el código de acceso de Miro."; return }
        if remember { MiroKeychain.save(token) } else { MiroKeychain.delete() }
        running = true
        fraction = nil
        status = "Conectando con Miro…"
        task = Task { await run(MiroAPI(token: token, boardID: id)) }
    }

    private func run(_ api: MiroAPI) async {
        do {
            let name = try? await api.boardName()
            let items = try await api.list("items") { n in Task { @MainActor in self.status = "Leyendo elementos… \(n)" } }
            let connectors = (try? await api.list("connectors") { _ in }) ?? []
            let imageRefs: [(String, String)] = items.compactMap { j in
                guard (j["type"] as? String) == "image",
                      let id = (j["id"] as? String) ?? (j["id"] as? Int).map(String.init),
                      let url = (j["data"] as? [String: Any])?["imageUrl"] as? String else { return nil }
                return (id, url)
            }
            var images: [String: Data] = [:]
            var keys: [String: String] = [:]
            var failed = 0
            var done = 0
            // Varias imágenes a la vez, sin saturar a Miro.
            for chunk in stride(from: 0, to: imageRefs.count, by: 6).map({ Array(imageRefs[$0..<min($0 + 6, imageRefs.count)]) }) {
                try Task.checkCancellation()
                status = "Bajando imágenes \(done) de \(imageRefs.count)…"
                fraction = imageRefs.isEmpty ? nil : Double(done) / Double(imageRefs.count)
                let results = await withTaskGroup(of: (String, Data?).self) { group in
                    for (id, url) in chunk { group.addTask { (id, try? await api.image(url)) } }
                    var out: [(String, Data?)] = []
                    for await r in group { out.append(r) }
                    return out
                }
                for (id, data) in results {
                    done += 1
                    if let data, NSImage(data: data) != nil {
                        let key = UUID().uuidString
                        images[key] = data
                        keys[id] = key
                    } else {
                        failed += 1
                    }
                }
            }
            try Task.checkCancellation()
            Self.saveCopy(items: items, connectors: connectors)
            status = "Armando el tablero…"
            let result = MiroConverter.convert(items, connectors: connectors, images: keys)
            try openBoard(result.items, images: images, name: name)
            running = false
            onFinish?()
            if failed > 0 || !result.skipped.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Tablero importado"
                var lines: [String] = []
                if failed > 0 { lines.append(failed == 1 ? "1 imagen no se pudo bajar." : "\(failed) imágenes no se pudieron bajar.") }
                if !result.skipped.isEmpty {
                    lines.append("Se dejaron fuera, porque Lienzo aún no los tiene:")
                    for (type, n) in result.skipped.sorted(by: { $0.value > $1.value }) { lines.append("• \(type): \(n)") }
                }
                alert.informativeText = lines.joined(separator: "\n")
                alert.runModal()
            }
        } catch is CancellationError {
            running = false
        } catch {
            running = false
            self.error = error.localizedDescription
        }
    }

    /// Guarda lo que respondió Miro (sin el código ni las imágenes) para revisar importaciones raras.
    static let copyURL = Thumbnails.folder.deletingLastPathComponent().appendingPathComponent("ultima-importacion-miro.json")

    private static func saveCopy(items: [[String: Any]], connectors: [[String: Any]]) {
        let all: [String: Any] = ["items": items, "connectors": connectors]
        guard let data = try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: copyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: copyURL)
    }

    private func openBoard(_ items: [Item], images: [String: Data], name: String?) throws {
        let dc = NSDocumentController.shared
        guard let doc = try dc.makeUntitledDocument(ofType: BoardDocument.typeName) as? BoardDocument else { return }
        doc.board.items = items
        doc.board.images = images
        if let name, !name.isEmpty { doc.displayName = name }
        dc.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        doc.updateChangeCount(.changeDone)
    }
}

final class MiroImportWindow {
    static let shared = MiroImportWindow()
    private var window: NSWindow?
    private var model: MiroImportModel?

    @MainActor
    func show(link: String? = nil) {
        if window == nil {
            let m = MiroImportModel()
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Importar de Miro"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: MiroImportView(model: m))
            w.center()
            m.onFinish = { [weak w] in w?.orderOut(nil) }
            window = w
            model = m
        }
        if let link { model?.link = link }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MiroImportView: View {
    @ObservedObject var model: MiroImportModel
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Importar un tablero de Miro").font(.title2.bold())
            Text("Lienzo lee el tablero desde Miro y lo copia en un tablero nuevo, con notas, marcos, figuras, flechas e imágenes editables. Miro no se modifica.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Enlace del tablero").font(.headline)
                HStack {
                    TextField("https://miro.com/app/board/…", text: $model.link)
                        .textFieldStyle(.roundedBorder)
                    Button("Usar HTML descargado…") { model.chooseHTML() }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Código de acceso de Miro").font(.headline)
                SecureField("Pega aquí el código (token)", text: $model.token)
                    .textFieldStyle(.roundedBorder)
                Toggle("Recordarlo en este Mac (en el llavero)", isOn: $model.remember)
                DisclosureGroup("¿Cómo consigo el código?", isExpanded: $showHelp) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. En Miro abre tu perfil › Configuración › «Tus apps».")
                        Text("2. Acepta las condiciones de desarrollador y pulsa «Crear nueva app» (ponle Lienzo).")
                        Text("3. En permisos marca solo «boards:read».")
                        Text("4. Pulsa «Instalar app y obtener token», elige el equipo donde está el tablero y copia el código.")
                        Text("El código solo permite leer tus tableros. Puedes borrarlo en Miro cuando quieras.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.top, 4)
                    .textSelection(.enabled)
                }
            }

            if let e = model.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.running {
                VStack(alignment: .leading, spacing: 4) {
                    if let f = model.fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                    Text(model.status).font(.callout).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                if model.running {
                    Button("Cancelar") { model.cancel() }
                } else {
                    Button("Importar") { model.start() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 420)
    }
}
