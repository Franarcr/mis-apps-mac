import Foundation

// Lee todo lo que Claude guarda en este Mac. Solo lee: nunca cambia nada.
struct Scanner {
    let fm = FileManager.default
    let home = FileManager.default.homeDirectoryForCurrentUser
    var claudeDir: URL { home.appendingPathComponent(".claude") }
    var appDir: URL { home.appendingPathComponent("Library/Application Support/Claude") }

    func scan() -> Snapshot {
        var s = Snapshot()
        let meta = desktopSessions()
        s.chats = chats(meta: meta)
        s.connectors = connectors(meta: meta)
        s.mcpServers = mcpServers()
        let (plugins, pluginSkills) = pluginsAndSkills()
        s.plugins = plugins
        s.skills = accountSkills() + personalSkills() + pluginSkills
        s.tasks = tasks(meta: meta)
        s.usage = usage()
        s.disk = disk()
        s.warnings = warnings(s)
        return s
    }

    // MARK: - Sesiones de la app de escritorio (títulos, archivado, tareas)

    struct SessionMeta {
        var cliId: String
        var title: String?
        var archived: Bool
        var scheduledTask: String?
        var lastActivity: Date?
        var remoteMcp: [[String: Any]]
    }

    func desktopSessions() -> [String: SessionMeta] {
        var out: [String: SessionMeta] = [:]
        for f in glob(appDir.appendingPathComponent("claude-code-sessions"), depth: 3, ext: "json") {
            guard let d = readJSON(f) as? [String: Any], let cli = d["cliSessionId"] as? String else { continue }
            let last = (d["lastActivityAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            let m = SessionMeta(cliId: cli,
                                title: d["title"] as? String,
                                archived: d["isArchived"] as? Bool ?? false,
                                scheduledTask: d["scheduledTaskId"] as? String,
                                lastActivity: last,
                                remoteMcp: d["remoteMcpServersConfig"] as? [[String: Any]] ?? [])
            // Si hay dos, se queda la más reciente.
            if let old = out[cli], (old.lastActivity ?? .distantPast) > (last ?? .distantPast) { continue }
            out[cli] = m
        }
        return out
    }

    // MARK: - Chats

    func chats(meta: [String: SessionMeta]) -> [Chat] {
        var cache = ChatCache.load()
        var result: [Chat] = []
        let projects = claudeDir.appendingPathComponent("projects")
        let dirs = (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
            for f in files where f.pathExtension == "jsonl" {
                let vals = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(vals?.fileSize ?? 0)
                let mtime = vals?.contentModificationDate?.timeIntervalSince1970 ?? 0
                var stats: ChatStats
                if let c = cache.entries[f.path], c.size == size, c.mtime == mtime {
                    stats = c.stats
                } else {
                    stats = parseTranscript(f)
                    cache.entries[f.path] = .init(size: size, mtime: mtime, stats: stats)
                }
                let id = f.deletingPathExtension().lastPathComponent
                // Carpeta hermana con resultados de herramientas y subagentes.
                let side = dir.appendingPathComponent(id)
                let extra = fm.fileExists(atPath: side.path) ? folderSize(side) : 0
                let m = meta[id]
                let title = m?.title ?? stats.customTitle ?? stats.firstPrompt ?? "Sin título"
                let project = stats.cwd.map { shortPath($0) } ?? dir.lastPathComponent
                result.append(Chat(id: id, title: title, project: project, path: f.path,
                                   bytes: size + extra, prompts: stats.prompts, replies: stats.replies,
                                   contextTokens: stats.contextTokens, outputTokens: stats.outputTokens,
                                   model: stats.model ?? "—", created: stats.firstDate,
                                   lastActivity: m?.lastActivity ?? stats.lastDate,
                                   archived: m?.archived ?? false, scheduledTask: m?.scheduledTask))
            }
        }
        // Quita del caché los chats que ya no existen.
        let live = Set(result.map(\.path))
        cache.entries = cache.entries.filter { live.contains($0.key) }
        cache.save()
        return result.sorted { $0.bytes > $1.bytes }
    }

    func parseTranscript(_ url: URL) -> ChatStats {
        var st = ChatStats()
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return st }
        var seen = Set<String>()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let n = raw.count
            var start = 0
            while start < n {
                let p = memchr(base + start, 0x0A, n - start)
                let end = p.map { base.distance(to: UnsafeRawPointer($0)) } ?? n
                let len = end - start
                // Las líneas enormes son resultados de herramientas (imágenes, archivos): no se analizan.
                if len > 0 && len < 400_000 {
                    let line = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base + start), count: len, deallocator: .none)
                    if let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        handle(o, &st, &seen, iso)
                    }
                }
                start = end + 1
            }
        }
        return st
    }

    private func handle(_ o: [String: Any], _ st: inout ChatStats, _ seen: inout Set<String>, _ iso: ISO8601DateFormatter) {
        let type = o["type"] as? String
        if type == "custom-title", let t = o["customTitle"] as? String { st.customTitle = t; return }
        guard type == "user" || type == "assistant" else { return }
        if o["isSidechain"] as? Bool == true { return }
        if let ts = o["timestamp"] as? String, let d = iso.date(from: ts) {
            if st.firstDate == nil { st.firstDate = d }
            st.lastDate = d
        }
        if st.cwd == nil, let c = o["cwd"] as? String { st.cwd = c }
        guard let msg = o["message"] as? [String: Any] else { return }
        if type == "assistant" {
            if let m = msg["model"] as? String, m != "<synthetic>" { st.model = m }
            if let u = msg["usage"] as? [String: Any] {
                let ctx = (u["input_tokens"] as? Int ?? 0) + (u["cache_creation_input_tokens"] as? Int ?? 0) + (u["cache_read_input_tokens"] as? Int ?? 0)
                if ctx > 0 { st.contextTokens = ctx }
                let id = msg["id"] as? String ?? UUID().uuidString
                if seen.insert(id).inserted {
                    st.replies += 1
                    st.outputTokens += u["output_tokens"] as? Int ?? 0
                }
            }
        } else {
            if o["isMeta"] as? Bool == true { return }
            var text: String?
            if let s = msg["content"] as? String { text = s }
            else if let arr = msg["content"] as? [[String: Any]] {
                if arr.contains(where: { $0["type"] as? String == "tool_result" }) { return }
                text = arr.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            }
            guard let t = text, !t.hasPrefix("<") else { return }   // comandos internos
            st.prompts += 1
            if st.firstPrompt == nil {
                let clean = t.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                st.firstPrompt = String(clean.prefix(80))
            }
        }
    }

    // MARK: - Conectores (los de claude.ai que usan tus sesiones)

    func connectors(meta: [String: SessionMeta]) -> [Connector] {
        let latest = meta.values
            .filter { !$0.remoteMcp.isEmpty }
            .max { ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast) }
        return (latest?.remoteMcp ?? []).compactMap { c in
            guard let name = c["name"] as? String else { return nil }
            let tools: Int
            if let a = c["tools"] as? [Any] { tools = a.count }
            else if let d = c["tools"] as? [String: Any] { tools = d.count }
            else { tools = 0 }
            let url = (c["url"] as? String).flatMap { URL(string: $0)?.host } ?? ""
            return Connector(name: name, url: url, tools: tools)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Servidores MCP locales y extensiones

    func mcpServers() -> [MCPServer] {
        var out: [MCPServer] = []
        func describe(_ v: Any?) -> String {
            guard let d = v as? [String: Any] else { return "" }
            if let u = d["url"] as? String { return u }
            let cmd = d["command"] as? String ?? ""
            let args = (d["args"] as? [String] ?? []).joined(separator: " ")
            return [cmd, args].filter { !$0.isEmpty }.joined(separator: " ")
        }
        if let d = readJSON(appDir.appendingPathComponent("claude_desktop_config.json")) as? [String: Any],
           let servers = d["mcpServers"] as? [String: Any] {
            for (k, v) in servers { out.append(MCPServer(name: k, source: "App de escritorio", detail: describe(v))) }
        }
        if let d = readJSON(home.appendingPathComponent(".claude.json")) as? [String: Any] {
            for (k, v) in d["mcpServers"] as? [String: Any] ?? [:] {
                out.append(MCPServer(name: k, source: "Claude Code", detail: describe(v)))
            }
            for (path, p) in d["projects"] as? [String: Any] ?? [:] {
                for (k, v) in (p as? [String: Any])?["mcpServers"] as? [String: Any] ?? [:] {
                    out.append(MCPServer(name: k, source: "Proyecto \(shortPath(path))", detail: describe(v)))
                }
            }
        }
        if let d = readJSON(appDir.appendingPathComponent("extensions-installations.json")) as? [String: Any],
           let exts = d["extensions"] as? [String: Any] {
            for (id, v) in exts {
                let e = v as? [String: Any]
                let man = e?["manifest"] as? [String: Any]
                let name = man?["display_name"] as? String ?? man?["name"] as? String ?? id
                let ver = e?["version"] as? String ?? ""
                out.append(MCPServer(name: name, source: "Extensión", detail: "versión \(ver)"))
            }
        }
        return out.sorted { ($0.source, $0.name) < ($1.source, $1.name) }
    }

    // MARK: - Plugins y habilidades

    func pluginsAndSkills() -> ([Plugin], [Skill]) {
        var plugins: [Plugin] = []
        var skills: [Skill] = []
        let usage = skillUsage()
        for f in glob(appDir.appendingPathComponent("plugin-list"), depth: 3, ext: "json") where f.lastPathComponent == "plugins.json" {
            guard let d = readJSON(f) as? [String: Any], let list = d["plugins"] as? [[String: Any]] else { continue }
            for p in list {
                let id = p["id"] as? String ?? "?"
                let dir = URL(fileURLWithPath: p["installPath"] as? String ?? "/nada")
                let man = readJSON(dir.appendingPathComponent(".claude-plugin/plugin.json")) as? [String: Any]
                let name = man?["name"] as? String ?? p["name"] as? String ?? id
                let source = id.split(separator: "@").last.map(String.init) ?? ""
                let pskills = readSkills(in: dir.appendingPathComponent("skills"), source: name, usage: usage, prefix: name)
                skills += pskills
                plugins.append(Plugin(id: id, name: name, description: man?["description"] as? String ?? "",
                                      enabled: p["enabled"] as? Bool ?? true, skills: pskills.count,
                                      source: pluginSourceName(source)))
            }
        }
        return (plugins.sorted { $0.name < $1.name }, skills)
    }

    func pluginSourceName(_ s: String) -> String {
        switch s {
        case "knowledge-work-plugins": return "Anthropic"
        case "anthropic-plugin-directory": return "Directorio"
        case "My Uploads": return "Subido por ti"
        default: return s
        }
    }

    func accountSkills() -> [Skill] {
        let usage = skillUsage()
        let root = appDir.appendingPathComponent("local-agent-mode-sessions/skills-plugin")
        var out: [Skill] = []
        for org in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for acct in (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? [] {
                out += readSkills(in: acct.appendingPathComponent("skills"), source: "Cuenta", usage: usage, prefix: "anthropic-skills")
            }
        }
        // Si hay varias copias de la misma cuenta, se deja una.
        var seen = Set<String>()
        return out.filter { seen.insert($0.name).inserted }.sorted { $0.name < $1.name }
    }

    func personalSkills() -> [Skill] {
        readSkills(in: claudeDir.appendingPathComponent("skills"), source: "Personal", usage: skillUsage(), prefix: nil)
    }

    func readSkills(in dir: URL, source: String, usage: [String: Int], prefix: String?) -> [Skill] {
        var out: [Skill] = []
        for s in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            let file = s.appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let fmatter = frontMatter(text)
            let name = fmatter["name"] ?? s.lastPathComponent
            let uses = usage[name] ?? prefix.flatMap { usage["\($0):\(name)"] }
            out.append(Skill(name: name, description: fmatter["description"] ?? "", source: source, uses: uses))
        }
        return out.sorted { $0.name < $1.name }
    }

    func skillUsage() -> [String: Int] {
        guard let d = readJSON(home.appendingPathComponent(".claude.json")) as? [String: Any],
              let u = d["skillUsage"] as? [String: Any] else { return [:] }
        return u.compactMapValues { ($0 as? [String: Any])?["usageCount"] as? Int }
    }

    // MARK: - Tareas programadas

    func tasks(meta: [String: SessionMeta]) -> [ScheduledTask] {
        let root = claudeDir.appendingPathComponent("scheduled-tasks")
        return ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).compactMap { dir in
            guard let text = try? String(contentsOf: dir.appendingPathComponent("SKILL.md"), encoding: .utf8) else { return nil }
            let f = frontMatter(text)
            let name = f["name"] ?? dir.lastPathComponent
            let runs = meta.values.filter { $0.scheduledTask == dir.lastPathComponent }
            return ScheduledTask(name: name, description: f["description"] ?? "", runs: runs.count,
                                 lastRun: runs.compactMap(\.lastActivity).max())
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Uso del plan

    func usage() -> [UsageSample] {
        guard let d = readJSON(appDir.appendingPathComponent("plan-usage-history.json")) as? [String: Any],
              let samples = d["samples"] as? [[String: Any]] else { return [] }
        return samples.compactMap { s in
            guard let t = s["t"] as? Double, let u = s["u"] as? [String: Any] else { return nil }
            return UsageSample(date: Date(timeIntervalSince1970: t / 1000),
                               fiveHour: u["fh"] as? Int ?? 0, sevenDay: u["sd"] as? Int ?? 0)
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Espacio en disco

    func disk() -> [DiskItem] {
        let items: [(String, URL, String, Bool)] = [
            ("Máquina virtual de Cowork", appDir.appendingPathComponent("vm_bundles"),
             "La usa Cowork para trabajar aislado. Si la borras, Claude la vuelve a descargar.", false),
            ("Chats de Claude Code", claudeDir.appendingPathComponent("projects"),
             "Las conversaciones completas. Bórralas desde la pestaña Chats.", false),
            ("Versiones de Claude Code", appDir.appendingPathComponent("claude-code"),
             "Programas de Claude Code que usa la app.", false),
            ("Disco de Claude Code", appDir.appendingPathComponent("claude-code-vm"),
             "Entorno aislado de Claude Code.", false),
            ("Sesiones de Cowork", appDir.appendingPathComponent("local-agent-mode-sessions"),
             "Plugins, habilidades y archivos de las sesiones de Cowork.", false),
            ("Caché de la app", appDir.appendingPathComponent("Cache"),
             "Copias temporales de páginas. Se regeneran solas.", true),
            ("Caché de código", appDir.appendingPathComponent("Code Cache"),
             "Código precompilado de la app. Se regenera solo.", true),
            ("Historial de archivos", claudeDir.appendingPathComponent("file-history"),
             "Copias que permiten deshacer cambios de Claude en tus archivos.", false),
        ]
        var out: [DiskItem] = []
        var counted: Int64 = 0
        for (name, url, note, clean) in items where fm.fileExists(atPath: url.path) {
            let b = folderSize(url)
            if url.path.hasPrefix(appDir.path) { counted += b }
            out.append(DiskItem(name: name, path: url.path, bytes: b, note: note, cleanable: clean))
        }
        let rest = folderSize(appDir) - counted
        if rest > 0 {
            out.append(DiskItem(name: "Otros datos de la app", path: appDir.path, bytes: rest,
                                note: "Ajustes, sesiones, cookies y archivos pequeños.", cleanable: false))
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Avisos

    func warnings(_ s: Snapshot) -> [Warning] {
        var w: [Warning] = []
        let bigFiles = s.chats.filter { $0.bytes >= Thresholds.heavyBytes }
        if !bigFiles.isEmpty {
            let total = bigFiles.reduce(0) { $0 + $1.bytes }
            w.append(.init(level: .alert, text: "\(bigFiles.count) chats pesan más de 100 MB (\(Fmt.bytes(total)) en total). Si ya no los usas, puedes borrarlos desde la pestaña Chats."))
        }
        let bigCtx = s.chats.filter { $0.contextTokens >= Thresholds.heavyContext && !$0.archived }
        if !bigCtx.isEmpty {
            w.append(.init(level: .warn, text: "\(bigCtx.count) chats sin archivar tienen más de \(Fmt.tokens(Thresholds.heavyContext)) tokens de contexto: cada mensaje nuevo gasta más de tu plan. Para un tema nuevo, empieza un chat nuevo."))
        }
        if let last = s.usage.last {
            if last.sevenDay >= Thresholds.usageAlert {
                w.append(.init(level: .alert, text: "Llevas el \(last.sevenDay) % del límite semanal (dato del \(Fmt.date(last.date)))."))
            } else if last.sevenDay >= 50 {
                w.append(.init(level: .warn, text: "Llevas el \(last.sevenDay) % del límite semanal (dato del \(Fmt.date(last.date)))."))
            }
        }
        if s.totalDiskBytes >= Thresholds.diskAlert {
            let vm = s.disk.first { $0.path.hasSuffix("vm_bundles") }?.bytes ?? 0
            w.append(.init(level: .warn, text: "Claude ocupa \(Fmt.bytes(s.totalDiskBytes)) en el disco; \(Fmt.bytes(vm)) son la máquina virtual de Cowork."))
        }
        for m in s.mcpServers where m.source != "Extensión" {
            let cmd = m.detail.split(separator: " ").first.map(String.init) ?? ""
            if cmd.hasPrefix("/") && !fm.fileExists(atPath: cmd) {
                w.append(.init(level: .alert, text: "El servidor MCP «\(m.name)» apunta a \(cmd), que ya no existe: fallará al arrancar."))
            }
        }
        for t in s.tasks {
            if t.runs == 0 {
                w.append(.init(level: .info, text: "La tarea programada «\(t.name)» no tiene ejecuciones guardadas."))
            } else if t.runs >= 30 {
                let b = s.chats.filter { $0.scheduledTask == t.name }.reduce(0) { $0 + $1.bytes }
                w.append(.init(level: .info, text: "La tarea «\(t.name)» ha dejado \(t.runs) chats guardados (\(Fmt.bytes(b))). Puedes ocultarlos en la pestaña Chats."))
            }
        }
        let disabled = s.plugins.filter { !$0.enabled }
        if !disabled.isEmpty {
            w.append(.init(level: .info, text: "Plugins desactivados: \(disabled.map(\.name).joined(separator: ", "))."))
        }
        let archived = s.chats.filter(\.archived)
        if !archived.isEmpty {
            let b = archived.reduce(0) { $0 + $1.bytes }
            w.append(.init(level: .info, text: "\(archived.count) chats archivados siguen ocupando \(Fmt.bytes(b))."))
        }
        return w
    }

    // MARK: - Utilidades

    func readJSON(_ url: URL) -> Any? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    func glob(_ root: URL, depth: Int, ext: String) -> [URL] {
        guard depth >= 0 else { return [] }
        var out: [URL] = []
        for u in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                out += glob(u, depth: depth - 1, ext: ext)
            } else if u.pathExtension == ext {
                out.append(u)
            }
        }
        return out
    }

    func folderSize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    func shortPath(_ p: String) -> String {
        if p.contains("local-agent-mode-sessions") { return "Cowork" }
        return p.replacingOccurrences(of: home.path, with: "~")
    }

    func frontMatter(_ text: String) -> [String: String] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var out: [String: String] = [:]
        var key: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if let r = line.range(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") {
                key = String(line[..<r.lowerBound])
                var v = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if v == ">" || v == "|" || v == ">-" || v == "|-" { v = "" }
                out[key!] = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if let k = key {
                let v = line.trimmingCharacters(in: .whitespaces)
                out[k] = [out[k] ?? "", v].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        return out
    }
}

// Resultados de leer un .jsonl, guardados para no releer los que no cambiaron.
struct ChatStats: Codable {
    var prompts = 0
    var replies = 0
    var contextTokens = 0
    var outputTokens = 0
    var model: String?
    var cwd: String?
    var customTitle: String?
    var firstPrompt: String?
    var firstDate: Date?
    var lastDate: Date?
}

struct ChatCache: Codable {
    struct Entry: Codable { var size: Int64; var mtime: Double; var stats: ChatStats }
    var version = 1
    var entries: [String: Entry] = [:]

    static var url: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PanelClaude")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chats-cache.json")
    }

    static func load() -> ChatCache {
        guard let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(ChatCache.self, from: d), c.version == 1 else { return ChatCache() }
        return c
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: Self.url, options: .atomic) }
    }
}
