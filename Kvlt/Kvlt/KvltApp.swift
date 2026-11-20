import SwiftUI

@main
struct KvltApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

enum Playing: Identifiable {
    case match(Match)
    case duel(Duel)

    var id: ObjectIdentifier {
        switch self {
        case .match(let m): ObjectIdentifier(m)
        case .duel(let d): ObjectIdentifier(d)
        }
    }
}

struct PlayerRef: Identifiable { let id: UUID }

struct HomeView: View {
    @EnvironmentObject var store: Store
    @AppStorage("generoElegido") private var selectedRaw = Genre.metal.rawValue
    @State private var setup: Pick?
    @State private var pending: Playing?
    @State private var playing: Playing?
    @State private var dashboard: PlayerRef?
    @State private var showBoard = false
    @State private var showPlayers = false
    @State private var customFor: Genre?
    @State private var showConcerts = false

    private var selected: Genre? { Genre(rawValue: selectedRaw) }
    private var p: Palette { selected?.palette ?? .mix }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    concertsCard
                    genreStrip
                    genreSection
                    playersSection
                }
                .padding(32)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .tint(p.accent)
        .animation(.easeInOut(duration: 0.3), value: selectedRaw)
        .sheet(item: $setup, onDismiss: {
            if let pending { playing = pending; self.pending = nil }
        }) { pick in
            SetupView(pick: pick) { mode, players in
                let pool = store.questions(pick)
                pending = mode == .duelo
                    ? .duel(Duel(pick: pick, players: players, pool: pool))
                    : .match(Match(pick: pick, mode: mode, players: players, pool: pool))
            }
            .environmentObject(store)
        }
        .fullScreenCover(item: $playing) { game in
            switch game {
            case .match(let m): MatchView(match: m).environmentObject(store)
            case .duel(let d): DuelView(duel: d).environmentObject(store)
            }
        }
        .sheet(item: $dashboard) { ref in
            NavigationStack { DashboardView(playerID: ref.id) }.environmentObject(store)
        }
        .sheet(isPresented: $showBoard) { LeaderboardView().environmentObject(store) }
        .sheet(isPresented: $showPlayers) { PlayersView().environmentObject(store) }
        .sheet(item: $customFor) { genre in CustomQuestionsView(genre: genre).environmentObject(store) }
        .fullScreenCover(isPresented: $showConcerts) { ConcertsView().environmentObject(store) }
    }

    private var concertsCard: some View {
        let m = Genre.metal.palette
        return Button { showConcerts = true } label: {
            HStack(spacing: 18) {
                Image(systemName: "guitars.fill")
                    .font(.system(size: 30))
                    .frame(width: 64, height: 64)
                    .background(m.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(m.text)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conciertos").font(m.title(26)).foregroundStyle(m.text)
                    Text("Toca riffs con tu guitarra de verdad: el iPad te escucha").foregroundStyle(m.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(m.dim)
            }
            .padding(18)
            .background(m.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(m.accent.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Partes

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ROCKOLA").font(p.title(60)).foregroundStyle(p.text).kerning(5)
                Text("Trivia musical para jugar solo o con amigos").foregroundStyle(p.dim)
            }
            Spacer()
            Button { showBoard = true } label: {
                Label("Tabla general", systemImage: "trophy.fill")
                    .font(.headline)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(p.panel, in: Capsule())
                    .foregroundStyle(p.text)
            }
            .buttonStyle(.plain)
        }
    }

    private var genreStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                genreCard(nil)
                ForEach(Genre.allCases) { genreCard($0) }
            }
            .padding(.vertical, 4)
        }
    }

    private func genreCard(_ g: Genre?) -> some View {
        let gp = g?.palette ?? .mix
        let isSelected = (g?.rawValue ?? "todas") == selectedRaw
        return Button { selectedRaw = g?.rawValue ?? "todas" } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: g?.icon ?? "shuffle").font(.title2).foregroundStyle(gp.accent)
                Spacer()
                Text(g?.title ?? "Todos").font(gp.title(19)).foregroundStyle(gp.text).lineLimit(2)
                Text("\(store.questions(Pick(genre: g)).count) preguntas").font(.caption).foregroundStyle(gp.dim)
            }
            .padding(16)
            .frame(width: 160, height: 136, alignment: .topLeading)
            .background(gp.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isSelected ? gp.accent : gp.text.opacity(0.08), lineWidth: isSelected ? 3 : 1))
        }
        .buttonStyle(.plain)
    }

    private var genreSection: some View {
        let pick = Pick(genre: selected)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selected?.title ?? "Todos los géneros").font(p.title(34)).foregroundStyle(p.text)
                Text(selected?.subtitle ?? "Preguntas mezcladas de toda la música").foregroundStyle(p.dim)
            }

            Button { setup = pick } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Jugar")
                    Spacer()
                    Text("Récord \(store.best[pick.key, default: 0])").font(.callout.monospacedDigit()).opacity(0.8)
                }
                .font(.title3.weight(.bold))
                .padding(20)
                .background(p.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(p.bg)
            }
            .buttonStyle(.plain)
            .disabled(store.questions(pick).isEmpty)

            if selected == .metal {
                Text("Escenas").font(p.title(24)).foregroundStyle(p.text).padding(.top, 6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(Genre.metal.topics) { topicCard($0) }
                }
            } else if let selected {
                Button { customFor = selected } label: {
                    Label("Tus preguntas de \(selected.title.lowercased())", systemImage: "square.and.pencil")
                        .font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(p.panel, in: Capsule())
                        .foregroundStyle(p.text)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func topicCard(_ topic: Topic) -> some View {
        let pick = Pick(genre: .metal, topic: topic)
        let count = store.questions(pick).count
        return Button {
            if topic == .tuyas && count == 0 { customFor = .metal } else { setup = pick }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: topic.icon)
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(p.accent.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(p.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title).font(.headline).foregroundStyle(p.text)
                    Text(topic.subtitle).font(.caption).foregroundStyle(p.dim)
                    Text("\(count) preguntas · récord \(store.best[pick.key, default: 0])")
                        .font(.caption2.monospacedDigit()).foregroundStyle(p.dim)
                }
                Spacer()
                if topic == .tuyas {
                    Button { customFor = .metal } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .buttonStyle(.plain)
                        .foregroundStyle(p.text)
                }
            }
            .padding(16)
            .background(p.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(p.text.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && topic != .tuyas)
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Jugadores").font(p.title(24)).foregroundStyle(p.text)
                Spacer()
                Button("Administrar") { showPlayers = true }.font(.headline)
            }
            if store.players.isEmpty {
                Button { showPlayers = true } label: {
                    Label("Crea tu jugador para empezar a guardar puntos", systemImage: "person.badge.plus")
                        .font(.headline)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.panel, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(p.text)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                ForEach(store.players.sorted { $0.points > $1.points }) { pl in
                    Button { dashboard = PlayerRef(id: pl.id) } label: {
                        HStack(spacing: 14) {
                            Avatar(name: pl.name, color: pl.color, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name).font(.headline).foregroundStyle(p.text)
                                Text("\(Rank.of(pl.points).name) · \(pl.points) pts").font(.caption.monospacedDigit()).foregroundStyle(p.dim)
                                Text("\(pl.games) partidas · \(pl.accuracy) % aciertos").font(.caption2).foregroundStyle(p.dim)
                            }
                            Spacer()
                            Image(systemName: "chart.bar.fill").foregroundStyle(p.dim)
                        }
                        .padding(14)
                        .background(p.panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Elegir modo y jugadores antes de empezar.
struct SetupView: View {
    let pick: Pick
    let onStart: (GameMode, [Player]) -> Void

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ultimoModo") private var modeRaw = GameMode.solo.rawValue
    @State private var chosen: [UUID] = []
    @State private var newName = ""

    private var mode: GameMode { GameMode(rawValue: modeRaw) ?? .solo }
    private var poolCount: Int { store.questions(pick).count }
    private var canStart: Bool { mode.players.contains(chosen.count) && poolCount >= chosen.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Modo", selection: $modeRaw) {
                        ForEach(GameMode.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text(mode.detail).foregroundStyle(.secondary)
                } header: {
                    Text(pick.title)
                }

                Section {
                    ForEach(store.players) { pl in
                        Button { toggle(pl.id) } label: {
                            HStack(spacing: 12) {
                                Avatar(name: pl.name, color: pl.color, size: 34)
                                Text(pl.name).foregroundStyle(.primary)
                                Spacer()
                                if let i = chosen.firstIndex(of: pl.id) {
                                    if mode == .turnos { Text("\(i + 1)º").foregroundStyle(.secondary) }
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(PlayerColor.of(pl.color))
                                }
                            }
                        }
                    }
                    HStack {
                        TextField("Nuevo jugador", text: $newName)
                            .onSubmit(add)
                        Button("Agregar", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text(playersHeader)
                } footer: {
                    if mode == .turnos { Text("Juegan en el orden en que los marcas.") }
                }
            }
            .navigationTitle("Nueva partida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Empezar") {
                        onStart(mode, chosen.compactMap { store.player($0) })
                        dismiss()
                    }
                    .bold()
                    .disabled(!canStart)
                }
            }
            .onAppear { if chosen.isEmpty, let first = store.players.first { chosen = [first.id] } }
            .onChange(of: modeRaw) { _, _ in
                if chosen.count > mode.players.upperBound { chosen = Array(chosen.prefix(mode.players.upperBound)) }
            }
        }
    }

    private var playersHeader: String {
        let r = mode.players
        if r.lowerBound == r.upperBound { return r.lowerBound == 1 ? "Elige 1 jugador" : "Elige \(r.lowerBound) jugadores" }
        return "Elige de \(r.lowerBound) a \(r.upperBound) jugadores"
    }

    private func toggle(_ id: UUID) {
        if let i = chosen.firstIndex(of: id) {
            chosen.remove(at: i)
        } else if mode == .solo {
            chosen = [id]
        } else if chosen.count < mode.players.upperBound {
            chosen.append(id)
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let p = store.addPlayer(name)
        newName = ""
        toggle(p.id)
    }
}

/// Para agregar preguntas propias a cualquier género.
struct CustomQuestionsView: View {
    let genre: Genre

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var right = ""
    @State private var wrong = ["", "", ""]
    @State private var fact = ""

    private var valid: Bool {
        ![text, right, wrong[0], wrong[1], wrong[2]].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var mine: [Question] { store.custom.filter { $0.scene.genre == genre } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pregunta", text: $text, axis: .vertical)
                    TextField("Respuesta correcta", text: $right)
                    ForEach(0..<3, id: \.self) { i in
                        TextField("Respuesta incorrecta \(i + 1)", text: $wrong[i])
                    }
                    TextField("Dato curioso (opcional)", text: $fact, axis: .vertical)
                    Button("Agregar pregunta") {
                        store.custom.append(Question(scene: genre.customTopic, text: text, options: [right] + wrong,
                                                     fact: fact.isEmpty ? "Pregunta agregada por ti." : fact))
                        text = ""; right = ""; wrong = ["", "", ""]; fact = ""
                    }
                    .disabled(!valid)
                } header: {
                    Text("Nueva pregunta de \(genre.title.lowercased())")
                } footer: {
                    Text("Ideal para bandas y artistas de Costa Rica. Las respuestas se barajan solas.")
                }

                if !mine.isEmpty {
                    Section("Tus preguntas (\(mine.count))") {
                        ForEach(mine) { q in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.text)
                                Text("Respuesta: \(q.options[0])").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { mine[$0].id }
                            store.custom.removeAll { ids.contains($0.id) }
                        }
                    }
                }
            }
            .navigationTitle("Tus preguntas")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }
}
