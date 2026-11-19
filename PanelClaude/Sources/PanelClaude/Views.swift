import SwiftUI
import Charts

enum Section: String, CaseIterable, Identifiable {
    case resumen = "Resumen", chats = "Chats", conectores = "Conectores y MCP",
         plugins = "Plugins", habilidades = "Habilidades", tareas = "Tareas programadas",
         uso = "Uso del plan", espacio = "Espacio en disco"
    // El id tiene que ser la propia sección para que coincida con la selección
    // de la barra lateral (Section?); con un String los clics no hacían nada.
    var id: Self { self }
    var icon: String {
        switch self {
        case .resumen: "square.grid.2x2"
        case .chats: "bubble.left.and.bubble.right"
        case .conectores: "point.3.connected.trianglepath.dotted"
        case .plugins: "puzzlepiece.extension"
        case .habilidades: "wand.and.stars"
        case .tareas: "clock.arrow.circlepath"
        case .uso: "chart.xyaxis.line"
        case .espacio: "internaldrive"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var store: Store
    @State private var section: Section? = .resumen

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon).badge(badge(s))
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            Group {
                if !store.loadedOnce {
                    ProgressView("Leyendo los datos de Claude…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch section ?? .resumen {
                    case .resumen: ResumenView(go: { section = $0 })
                    case .chats: ChatsView()
                    case .conectores: ConectoresView()
                    case .plugins: PluginsView()
                    case .habilidades: HabilidadesView()
                    case .tareas: TareasView()
                    case .uso: UsoView()
                    case .espacio: EspacioView()
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    HStack(spacing: 8) {
                        if store.loading { ProgressView().controlSize(.small) }
                        Text("Actualizado \(Fmt.relative(store.snap.generatedAt))")
                            .font(.caption).foregroundStyle(.secondary)
                        Button { store.refresh() } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
                            .disabled(store.loading)
                    }
                }
            }
        }
        .alert("No se pudo completar", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") {}
        } message: { Text(store.lastError ?? "") }
    }

    func badge(_ s: Section) -> Int {
        let x = store.snap
        switch s {
        case .chats: return x.chats.count
        case .conectores: return x.connectors.count + x.mcpServers.count
        case .plugins: return x.plugins.count
        case .habilidades: return x.skills.count
        case .tareas: return x.tasks.count
        default: return 0
        }
    }
}

// MARK: - Resumen

struct ResumenView: View {
    @EnvironmentObject var store: Store
    var go: (Section) -> Void

    var body: some View {
        let s = store.snap
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    Tile(title: "Chats", value: "\(s.chats.count)", sub: Fmt.bytes(s.totalChatBytes), icon: "bubble.left.and.bubble.right") { go(.chats) }
                    Tile(title: "Chats pesados", value: "\(s.chats.filter(\.isHeavy).count)", sub: "más de 100 MB o 150 mil tokens", icon: "scalemass", tint: .orange) { go(.chats) }
                    Tile(title: "Conectores", value: "\(s.connectors.count)", sub: "de claude.ai", icon: "point.3.connected.trianglepath.dotted") { go(.conectores) }
                    Tile(title: "Servidores MCP y extensiones", value: "\(s.mcpServers.count)", sub: "en este Mac", icon: "server.rack") { go(.conectores) }
                    Tile(title: "Plugins", value: "\(s.plugins.count)", sub: "\(s.plugins.filter(\.enabled).count) activos", icon: "puzzlepiece.extension") { go(.plugins) }
                    Tile(title: "Habilidades", value: "\(s.skills.count)", sub: skillSplit(s), icon: "wand.and.stars") { go(.habilidades) }
                    Tile(title: "Tareas programadas", value: "\(s.tasks.count)", sub: "\(s.tasks.reduce(0) { $0 + $1.runs }) ejecuciones", icon: "clock.arrow.circlepath") { go(.tareas) }
                    Tile(title: "Uso semanal", value: s.usage.last.map { "\($0.sevenDay) %" } ?? "—", sub: s.usage.last.map { "5 h: \($0.fiveHour) %" } ?? "sin datos", icon: "chart.xyaxis.line", tint: usageTint(s)) { go(.uso) }
                    Tile(title: "Espacio de Claude", value: Fmt.bytes(s.totalDiskBytes), sub: "en el disco", icon: "internaldrive") { go(.espacio) }
                }

                if !s.warnings.isEmpty {
                    GroupBox("Avisos") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(s.warnings) { WarningRow(w: $0) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }
                }

                GroupBox("Los 8 chats que más pesan") {
                    VStack(spacing: 0) {
                        ForEach(s.chats.prefix(8)) { c in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(c.title).lineLimit(1)
                                    Text(c.project).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(Fmt.tokens(c.contextTokens) + " tokens").font(.caption).foregroundStyle(.secondary)
                                Text(Fmt.bytes(c.bytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
                            Divider()
                        }
                    }.padding(4)
                }
            }
            .padding(20)
        }
        .navigationTitle("Resumen")
    }

    func skillSplit(_ s: Snapshot) -> String {
        let cuenta = s.skills.filter { $0.source == "Cuenta" }.count
        let personal = s.skills.filter { $0.source == "Personal" }.count
        return "\(cuenta) de la cuenta · \(personal) tuyas · \(s.skills.count - cuenta - personal) de plugins"
    }

    func usageTint(_ s: Snapshot) -> Color {
        guard let u = s.usage.last?.sevenDay else { return .accentColor }
        return u >= 80 ? .red : u >= 50 ? .orange : .green
    }
}

struct Tile: View {
    let title: String, value: String, sub: String, icon: String
    var tint: Color = .accentColor
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.system(size: 28, weight: .semibold)).foregroundStyle(tint).monospacedDigit()
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WarningRow: View {
    let w: Warning
    var body: some View {
        Label {
            Text(w.text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: w.level == .alert ? "exclamationmark.triangle.fill" : w.level == .warn ? "exclamationmark.circle.fill" : "info.circle")
                .foregroundStyle(w.level == .alert ? .red : w.level == .warn ? .orange : .secondary)
        }
    }
}

// MARK: - Chats

struct ChatsView: View {
    @EnvironmentObject var store: Store
    @State private var search = ""
    @State private var onlyHeavy = false
    @State private var hideArchived = false
    @State private var hideTasks = true
    @State private var selection = Set<Chat.ID>()
    @State private var sort = [KeyPathComparator(\ChatRow.bytes, order: .reverse)]
    @State private var toTrash: [Chat] = []

    var rows: [ChatRow] {
        store.snap.chats
            .filter { !onlyHeavy || $0.isHeavy }
            .filter { !hideArchived || !$0.archived }
            .filter { !hideTasks || $0.scheduledTask == nil }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.project.localizedCaseInsensitiveContains(search) }
            .map(ChatRow.init)
            .sorted(using: sort)
    }

    var body: some View {
        let list = rows
        VStack(spacing: 0) {
            HStack {
                Toggle("Solo pesados", isOn: $onlyHeavy)
                Toggle("Ocultar archivados", isOn: $hideArchived)
                Toggle("Ocultar tareas programadas", isOn: $hideTasks)
                Spacer()
                Text("\(list.count) chats · \(Fmt.bytes(list.reduce(0) { $0 + $1.bytes }))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Table(list, selection: $selection, sortOrder: $sort) {
                TableColumn("Título", value: \.title) { r in
                    HStack(spacing: 4) {
                        if r.chat.isHeavy { Image(systemName: "scalemass.fill").foregroundStyle(.orange) }
                        if r.chat.archived { Image(systemName: "archivebox").foregroundStyle(.secondary) }
                        if r.chat.scheduledTask != nil { Image(systemName: "clock").foregroundStyle(.secondary) }
                        Text(r.title).lineLimit(1).help(r.title)
                    }
                }.width(min: 220, ideal: 320)
                TableColumn("Proyecto", value: \.project) { r in
                    Text(r.project).lineLimit(1).foregroundStyle(.secondary).help(r.project)
                }.width(min: 100, ideal: 180)
                TableColumn("Tamaño", value: \.bytes) { r in
                    Text(Fmt.bytes(r.bytes)).monospacedDigit()
                }.width(80)
                TableColumn("Contexto", value: \.context) { r in
                    Text(Fmt.tokens(r.context)).monospacedDigit()
                        .foregroundStyle(r.context >= Thresholds.heavyContext ? .orange : .primary)
                }.width(80)
                TableColumn("Mensajes", value: \.prompts) { r in
                    Text("\(r.prompts) / \(r.chat.replies)").monospacedDigit().help("Tus mensajes / respuestas de Claude")
                }.width(80)
                TableColumn("Última actividad", value: \.last) { r in
                    Text(Fmt.relative(r.chat.lastActivity)).help(Fmt.date(r.chat.lastActivity))
                }.width(min: 110, ideal: 130)
            }
            .contextMenu(forSelectionType: Chat.ID.self) { ids in
                let chats = store.snap.chats.filter { ids.contains($0.id) }
                if let c = chats.first {
                    Button("Mostrar en Finder") { store.reveal(c.path) }
                    Button("Copiar ID de la sesión") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(c.id, forType: .string)
                    }
                    Divider()
                    Button("Mover a la Papelera…", role: .destructive) { toTrash = chats }
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar por título o proyecto")
        .navigationTitle("Chats")
        .confirmationDialog(trashTitle, isPresented: Binding(get: { !toTrash.isEmpty }, set: { if !$0 { toTrash = [] } })) {
            Button("Mover a la Papelera", role: .destructive) {
                toTrash.forEach { store.trash(chat: $0) }
                toTrash = []
            }
        } message: {
            Text("Claude ya no podrá retomar \(toTrash.count == 1 ? "esta conversación" : "estas conversaciones"). Puedes recuperarlas desde la Papelera mientras no la vacíes.")
        }
    }

    var trashTitle: String {
        let b = toTrash.reduce(0) { $0 + $1.bytes }
        return toTrash.count == 1 ? "¿Mover «\(toTrash[0].title)» a la Papelera? (\(Fmt.bytes(b)))"
                                  : "¿Mover \(toTrash.count) chats a la Papelera? (\(Fmt.bytes(b)))"
    }
}

// Fila de la tabla con valores ordenables.
struct ChatRow: Identifiable {
    let chat: Chat
    var id: String { chat.id }
    var title: String { chat.title }
    var project: String { chat.project }
    var bytes: Int64 { chat.bytes }
    var context: Int { chat.contextTokens }
    var prompts: Int { chat.prompts }
    var last: Date { chat.lastActivity ?? .distantPast }
}

// MARK: - Conectores y MCP

struct ConectoresView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let s = store.snap
        List {
            SwiftUI.Section("Conectores de claude.ai (\(s.connectors.count))") {
                ForEach(s.connectors) { c in
                    HStack {
                        Image(systemName: "link").foregroundStyle(.secondary)
                        Text(c.name)
                        Spacer()
                        Text(c.url).font(.caption).foregroundStyle(.secondary)
                        Text("\(c.tools) herramientas").font(.caption).monospacedDigit().frame(width: 110, alignment: .trailing)
                    }
                }
                Text("Se activan en claude.ai › Ajustes › Conectores. Esta lista sale de tu sesión más reciente de Claude Code.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("Servidores MCP y extensiones en este Mac (\(s.mcpServers.count))") {
                ForEach(s.mcpServers) { m in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: m.source == "Extensión" ? "puzzlepiece" : "server.rack").foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(m.name)
                            Text(m.detail).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                        }
                        Spacer()
                        Text(m.source).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        .navigationTitle("Conectores y MCP")
    }
}

// MARK: - Plugins

struct PluginsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        List(store.snap.plugins) { p in
            HStack(alignment: .top) {
                Image(systemName: p.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(p.enabled ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(p.name).bold()
                        Text(p.source).font(.caption).padding(.horizontal, 6).padding(.vertical, 1).background(.quaternary, in: Capsule())
                    }
                    Text(p.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Text("\(p.skills) habilidades").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
        .navigationTitle("Plugins")
    }
}

// MARK: - Habilidades

struct HabilidadesView: View {
    @EnvironmentObject var store: Store
    @State private var search = ""
    var body: some View {
        let skills = store.snap.skills.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }
        let groups = Dictionary(grouping: skills, by: \.source)
        let order = groups.keys.sorted { a, b in rank(a) == rank(b) ? a < b : rank(a) < rank(b) }
        List {
            ForEach(order, id: \.self) { src in
                SwiftUI.Section("\(title(src)) (\(groups[src]!.count))") {
                    ForEach(groups[src]!) { sk in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(sk.name).bold()
                                Spacer()
                                if let u = sk.uses { Text("\(u) usos").font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(sk.description).font(.callout).foregroundStyle(.secondary).lineLimit(2).help(sk.description)
                        }.padding(.vertical, 2)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar habilidad")
        .navigationTitle("Habilidades")
    }
    func rank(_ s: String) -> Int { s == "Personal" ? 0 : s == "Cuenta" ? 1 : 2 }
    func title(_ s: String) -> String {
        switch s {
        case "Personal": "Tuyas, en este Mac"
        case "Cuenta": "De tu cuenta de claude.ai"
        default: "Del plugin \(s)"
        }
    }
}

// MARK: - Tareas

struct TareasView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        List(store.snap.tasks) { t in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(t.name).bold()
                    Spacer()
                    Text("\(t.runs) ejecuciones · última \(Fmt.relative(t.lastRun))").font(.caption).foregroundStyle(.secondary)
                }
                Text(t.description).font(.callout).foregroundStyle(.secondary)
            }.padding(.vertical, 3)
        }
        .overlay { if store.snap.tasks.isEmpty { Text("No hay tareas programadas").foregroundStyle(.secondary) } }
        .navigationTitle("Tareas programadas")
    }
}

// MARK: - Uso

struct UsoView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let u = store.snap.usage
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let last = u.last {
                    HStack(spacing: 24) {
                        UsageBar(title: "Límite de 5 horas", value: last.fiveHour)
                        UsageBar(title: "Límite semanal", value: last.sevenDay)
                    }
                    Text("Último dato: \(Fmt.date(last.date)). La app de Claude lo anota cuando la usas, así que puede estar algo atrasado.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                GroupBox("Historial") {
                    Chart {
                        ForEach(u, id: \.date) { s in
                            LineMark(x: .value("Fecha", s.date), y: .value("%", s.sevenDay))
                                .foregroundStyle(by: .value("Límite", "Semanal"))
                            PointMark(x: .value("Fecha", s.date), y: .value("%", s.sevenDay))
                                .foregroundStyle(by: .value("Límite", "Semanal"))
                            LineMark(x: .value("Fecha", s.date), y: .value("%", s.fiveHour))
                                .foregroundStyle(by: .value("Límite", "5 horas"))
                        }
                        RuleMark(y: .value("Alerta", Thresholds.usageAlert))
                            .lineStyle(StrokeStyle(dash: [4, 4])).foregroundStyle(.red.opacity(0.5))
                    }
                    .chartYScale(domain: 0...100)
                    .chartForegroundStyleScale(["Semanal": Color.orange, "5 horas": Color.blue])
                    .frame(height: 280)
                    .padding(6)
                }
                GroupBox("Chats que más gastaron (tokens escritos por Claude)") {
                    let top = store.snap.chats.sorted { $0.outputTokens > $1.outputTokens }.prefix(8)
                    VStack(spacing: 6) {
                        ForEach(Array(top)) { c in
                            HStack {
                                Text(c.title).lineLimit(1)
                                Spacer()
                                Text(Fmt.tokens(c.outputTokens)).monospacedDigit()
                            }
                        }
                    }.padding(6)
                }
            }
            .padding(20)
        }
        .navigationTitle("Uso del plan")
    }
}

// MARK: - Espacio

struct EspacioView: View {
    @EnvironmentObject var store: Store
    @State private var toTrash: DiskItem?

    var body: some View {
        let items = store.snap.disk
        let maxB = max(items.map(\.bytes).max() ?? 1, 1)
        List {
            SwiftUI.Section("Total: \(Fmt.bytes(store.snap.totalDiskBytes))") {
                ForEach(items) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(d.name).bold()
                            Spacer()
                            Text(Fmt.bytes(d.bytes)).monospacedDigit()
                        }
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.7))
                                .frame(width: max(2, g.size.width * CGFloat(d.bytes) / CGFloat(maxB)))
                        }.frame(height: 6)
                        HStack {
                            Text(d.note).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Mostrar") { store.reveal(d.path) }.controlSize(.small)
                            if d.cleanable {
                                Button("Vaciar…") { toTrash = d }.controlSize(.small)
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Espacio en disco")
        .confirmationDialog("¿Mover «\(toTrash?.name ?? "")» a la Papelera?", isPresented: Binding(get: { toTrash != nil }, set: { if !$0 { toTrash = nil } })) {
            Button("Mover a la Papelera", role: .destructive) {
                if let d = toTrash { store.trash(disk: d) }
                toTrash = nil
            }
        } message: {
            Text(store.claudeIsRunning
                 ? "Claude está abierto: ciérralo antes para que no vuelva a escribir ahí. Se regenera solo al abrirlo."
                 : "Claude lo vuelve a crear solo la próxima vez que lo abras.")
        }
    }
}
