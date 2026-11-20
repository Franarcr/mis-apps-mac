import SwiftUI
import Charts

/// Panel de un jugador: puntos, aciertos por género y cómo le ha ido.
struct DashboardView: View {
    let playerID: UUID

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let pl = store.player(playerID) {
                content(pl)
            } else {
                ContentUnavailableView("Jugador eliminado", systemImage: "person.slash")
            }
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
    }

    private func content(_ pl: Player) -> some View {
        let rank = Rank.of(pl.points)
        let next = Rank.next(pl.points)
        let color = PlayerColor.of(pl.color)
        return ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 20) {
                    Avatar(name: pl.name, color: pl.color, size: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pl.name).font(.system(size: 38, weight: .black, design: .rounded))
                        Text(rank.name.uppercased()).font(.headline).kerning(2).foregroundStyle(color)
                        if let next {
                            ProgressView(value: Double(pl.points - rank.from), total: Double(next.from - rank.from))
                                .tint(color)
                                .frame(maxWidth: 320)
                            Text("Faltan \(next.from - pl.points) puntos para \(next.name)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    tile("Puntos", "\(pl.points)", "star.fill")
                    tile("Partidas", "\(pl.games)", "gamecontroller.fill")
                    tile("Victorias", pl.multiGames == 0 ? "—" : "\(pl.wins) de \(pl.multiGames)", "trophy.fill")
                    tile("Aciertos", pl.totalAnswered == 0 ? "—" : "\(pl.accuracy) %", "checkmark.seal.fill")
                    tile("Mejor partida", "\(pl.bestScore)", "crown.fill")
                    tile("Mejor racha", "x\(pl.bestStreak)", "flame.fill")
                }

                section("Aciertos por género") { genreChart(pl) }

                if pl.history.count >= 2 {
                    section("Últimas partidas") { historyChart(pl) }
                }

                if !pl.history.isEmpty {
                    section("Historial") {
                        VStack(spacing: 8) {
                            ForEach(pl.history.suffix(12).reversed()) { r in recordRow(r) }
                        }
                    }
                }

                section("Perfil") { editor(pl) }
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(pl.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.bold))
            c()
        }
    }

    private func genreChart(_ pl: Player) -> some View {
        Chart(Genre.allCases) { g in
            let answered = pl.answered[g.rawValue, default: 0]
            let correct = pl.correct[g.rawValue, default: 0]
            let pct = answered == 0 ? 0 : Double(correct) / Double(answered) * 100
            BarMark(x: .value("Aciertos", pct), y: .value("Género", g.title))
                .foregroundStyle(g.palette.accent)
                .cornerRadius(6)
                .annotation(position: .trailing) {
                    Text(answered == 0 ? "sin jugar" : "\(Int(pct.rounded())) %  ·  \(correct) de \(answered)")
                        .font(.caption).foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine()
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0) %") }
            }
        }
        .frame(height: 280)
    }

    private func historyChart(_ pl: Player) -> some View {
        let recent = Array(pl.history.suffix(20).enumerated())
        let color = PlayerColor.of(pl.color)
        return Chart(recent, id: \.offset) { i, r in
            LineMark(x: .value("Partida", i + 1), y: .value("Puntos", r.score))
                .foregroundStyle(color)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Partida", i + 1), y: .value("Puntos", r.score))
                .foregroundStyle(r.won == true ? Palette.good : color)
                .symbolSize(r.won == true ? 120 : 50)
        }
        .chartXAxis(.hidden)
        .frame(height: 220)
    }

    private func recordRow(_ r: GameRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.mode.icon).frame(width: 26).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).font(.subheadline.weight(.semibold))
                Text(detail(r)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if r.won == true { Image(systemName: "trophy.fill").foregroundStyle(.yellow) }
            Text("\(r.score)").font(.headline.monospacedDigit())
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func detail(_ r: GameRecord) -> String {
        var parts = [r.date.formatted(date: .abbreviated, time: .shortened), "\(r.correct)/\(r.total) " + (r.label.hasPrefix("Concierto") ? "notas" : "correctas")]
        if !r.rivals.isEmpty { parts.append("vs. " + r.rivals.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func editor(_ pl: Player) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Nombre", text: Binding(
                get: { store.player(playerID)?.name ?? "" },
                set: { new in store.update(playerID) { $0.name = new } }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)
            HStack(spacing: 12) {
                ForEach(PlayerColor.all.indices, id: \.self) { i in
                    Button { store.update(playerID) { $0.color = i } } label: {
                        Circle().fill(PlayerColor.all[i])
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(.white, lineWidth: pl.color == i ? 3 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Todos los jugadores ordenados por puntos.
struct LeaderboardView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.players.isEmpty {
                    Text("Todavía no hay jugadores.").foregroundStyle(.secondary)
                }
                ForEach(Array(store.players.sorted { $0.points > $1.points }.enumerated()), id: \.element.id) { i, pl in
                    NavigationLink { DashboardView(playerID: pl.id) } label: {
                        HStack(spacing: 14) {
                            Text(i < 3 ? ["🥇", "🥈", "🥉"][i] : "\(i + 1)").font(.title2).frame(width: 40)
                            Avatar(name: pl.name, color: pl.color, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name).font(.headline)
                                Text("\(Rank.of(pl.points).name) · \(pl.games) partidas · \(pl.wins) victorias")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(pl.points)").font(.title3.weight(.bold).monospacedDigit())
                                Text("\(pl.accuracy) % aciertos").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Tabla general")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }
}

/// Crear y borrar jugadores.
struct PlayersView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var toDelete: Player?

    var body: some View {
        NavigationStack {
            List {
                Section("Nuevo jugador") {
                    HStack {
                        TextField("Nombre", text: $newName).onSubmit(add)
                        Button("Agregar", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Jugadores") {
                    ForEach(store.players) { pl in
                        NavigationLink { DashboardView(playerID: pl.id) } label: {
                            HStack(spacing: 12) {
                                Avatar(name: pl.name, color: pl.color, size: 36)
                                Text(pl.name)
                                Spacer()
                                Text("\(pl.points) pts").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .swipeActions {
                            Button("Borrar", role: .destructive) { toDelete = pl }
                        }
                    }
                }
            }
            .navigationTitle("Jugadores")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .confirmationDialog("¿Borrar a \(toDelete?.name ?? "")?", isPresented: Binding(
                get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Borrar jugador y sus puntos", role: .destructive) {
                    if let id = toDelete?.id { store.players.removeAll { $0.id == id } }
                    toDelete = nil
                }
            } message: {
                Text("Se pierden sus puntos y su historial. No se puede deshacer.")
            }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.addPlayer(name)
        newName = ""
    }
}
