import SwiftUI

private let letters = ["A", "B", "C", "D"]

/// Partida solo o por turnos.
struct MatchView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var match: Match
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    private var p: Palette { match.pick.palette }
    private var multi: Bool { match.seats.count > 1 }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            if match.finished {
                results
            } else if match.handoff {
                handoffView
            } else if let item = match.current {
                question(item)
            } else {
                Text("No hay suficientes preguntas aquí todavía.").foregroundStyle(p.text)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { match.stop(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(p.dim)
            }
            .padding(24)
        }
        .onAppear { match.start() }
        .onChange(of: match.finished) { _, done in
            if done && !saved {
                saved = true
                store.apply(seats: match.seats, pick: match.pick, mode: match.mode)
            }
        }
    }

    private var handoffView: some View {
        let seat = match.seats[match.seatIndex]
        return VStack(spacing: 26) {
            Text(match.pick.title.uppercased()).font(.headline).kerning(2).foregroundStyle(p.accent)
            Avatar(name: seat.name, color: seat.color, size: 120)
            Text("Turno de \(seat.name)").font(p.title(52)).foregroundStyle(p.text)
            Text("Pregunta \(match.turn) de \(match.perPlayer)").font(.title3).foregroundStyle(p.dim)
            Button { match.ready() } label: {
                Text("Estoy listo")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 44).padding(.vertical, 18)
                    .background(PlayerColor.of(seat.color), in: Capsule())
                    .foregroundStyle(.black.opacity(0.8))
            }
            .buttonStyle(.plain)
            scoreboard.padding(.top, 20)
        }
        .padding(40)
    }

    private var scoreboard: some View {
        HStack(spacing: 14) {
            ForEach(Array(match.seats.enumerated()), id: \.element.id) { i, seat in
                VStack(spacing: 6) {
                    Avatar(name: seat.name, color: seat.color, size: 36)
                    Text(seat.name).font(.caption).foregroundStyle(p.text).lineLimit(1)
                    Text("\(seat.score)").font(.headline.monospacedDigit()).foregroundStyle(p.text)
                }
                .frame(width: 110)
                .padding(.vertical, 12)
                .background(p.panel.opacity(i == match.seatIndex ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func question(_ item: Shown) -> some View {
        let seat = match.seats[match.seatIndex]
        return VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 12) {
                if multi { Avatar(name: seat.name, color: seat.color, size: 36) }
                Text((multi ? seat.name : match.pick.title).uppercased())
                    .font(.headline).kerning(2).foregroundStyle(multi ? PlayerColor.of(seat.color) : p.accent)
                Text(multi ? "· pregunta \(match.turn) de \(match.perPlayer)" : "· \(match.index + 1) de \(match.items.count)")
                    .foregroundStyle(p.dim)
                Spacer()
                if seat.streak > 1 {
                    Label("Racha x\(seat.streak)", systemImage: "flame.fill").foregroundStyle(p.accent).font(.headline)
                }
                Text("\(seat.score)").font(p.title(30).monospacedDigit()).foregroundStyle(p.text)
                    .padding(.trailing, 60)
            }

            ProgressView(value: match.timeLeft, total: Scoring.seconds)
                .tint(match.timeLeft < 5 ? Palette.bad : p.accent)
                .animation(.linear(duration: 0.1), value: match.timeLeft)

            Text(item.question.text)
                .font(p.title(36))
                .foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(item.options.indices, id: \.self) { i in
                    OptionButton(text: item.options[i], letter: letters[i],
                                 state: optionState(item, i), palette: p) { match.choose(i) }
                        .disabled(match.answered)
                }
            }

            if match.answered {
                feedback(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: 1100)
        .animation(.easeOut(duration: 0.25), value: match.answered)
    }

    private func optionState(_ item: Shown, _ i: Int) -> OptionButton.Look {
        guard match.answered else { return .normal }
        if i == item.correctIndex { return .right }
        return match.picked == i ? .wrong : .faded
    }

    private func feedback(_ item: Shown) -> some View {
        let right = match.picked == item.correctIndex
        let last = match.index + 1 >= match.items.count
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(right ? "¡Correcto! +\(match.lastGain)" : (match.picked == -1 ? "Se acabó el tiempo" : "No era esa"))
                    .font(p.title(24))
                    .foregroundStyle(right ? Palette.good : Palette.bad)
                Text(item.question.fact).foregroundStyle(p.text.opacity(0.85))
            }
            Spacer()
            Button(last ? "Ver resultado" : (multi ? "Pasar el iPad" : "Siguiente")) { match.next() }
                .font(.title3.weight(.bold))
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(p.accent, in: Capsule())
                .foregroundStyle(p.bg)
                .buttonStyle(.plain)
        }
        .padding(22)
        .background(p.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private var results: some View {
        let ranking = match.seats.sorted { $0.score > $1.score }
        let tie = ranking.count > 1 && ranking[0].score == ranking[1].score
        return VStack(spacing: 22) {
            if multi {
                Text(tie ? "¡EMPATE!" : "¡GANÓ \(ranking[0].name.uppercased())!")
                    .font(p.title(48)).foregroundStyle(p.accent)
                VStack(spacing: 10) {
                    ForEach(Array(ranking.enumerated()), id: \.element.id) { i, seat in
                        HStack(spacing: 14) {
                            Text("\(i + 1)").font(p.title(26)).foregroundStyle(p.dim).frame(width: 34)
                            Avatar(name: seat.name, color: seat.color, size: 44)
                            Text(seat.name).font(.title3.weight(.semibold)).foregroundStyle(p.text)
                            Spacer()
                            Text("\(seat.correct)/\(seat.answered) · racha x\(seat.bestStreak)").foregroundStyle(p.dim)
                            Text("\(seat.score)").font(p.title(28).monospacedDigit()).foregroundStyle(p.text).frame(minWidth: 90, alignment: .trailing)
                        }
                        .padding(14)
                        .background(p.panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .frame(maxWidth: 700)
            } else if let seat = match.seats.first {
                Text(seat.correct >= 9 ? "¡MAESTRO!" : seat.correct >= 6 ? "NADA MAL" : "A ESCUCHAR MÁS DISCOS")
                    .font(p.title(44)).foregroundStyle(p.accent).kerning(2)
                Text("\(seat.score)").font(p.title(96).monospacedDigit()).foregroundStyle(p.text)
                Text("\(seat.correct) de \(seat.answered) correctas · mejor racha x\(seat.bestStreak)")
                    .font(.title3).foregroundStyle(p.dim)
                if let pl = store.player(seat.id) {
                    Text("Rango: \(Rank.of(pl.points).name) · \(pl.points) puntos en total")
                        .font(.headline).foregroundStyle(p.text)
                }
            }
            Button("Volver") { dismiss() }
                .font(.title3.weight(.bold))
                .padding(.horizontal, 32).padding(.vertical, 14)
                .background(p.panel, in: Capsule())
                .foregroundStyle(p.text)
                .buttonStyle(.plain)
                .padding(.top, 10)
        }
        .padding(40)
    }
}

struct OptionButton: View {
    enum Look { case normal, right, wrong, faded }

    let text: String
    let letter: String
    let state: Look
    let palette: Palette
    var compact = false
    let action: () -> Void

    var body: some View {
        let bg: Color = switch state {
        case .normal: palette.panel
        case .right: Palette.good.opacity(0.4)
        case .wrong: Palette.bad.opacity(0.45)
        case .faded: palette.panel.opacity(0.45)
        }
        Button(action: action) {
            HStack(spacing: 12) {
                Text(letter)
                    .font(.headline)
                    .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                    .overlay(Circle().strokeBorder(palette.text.opacity(0.4)))
                Text(text).font((compact ? Font.body : .title3).weight(.semibold)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if state == .right { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good) }
                if state == .wrong { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.bad) }
            }
            .foregroundStyle(palette.text)
            .padding(compact ? 12 : 18)
            .frame(maxWidth: .infinity, minHeight: compact ? 56 : 76, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.text.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// Duelo con el iPad en la mesa: la mitad de arriba está girada para el jugador de enfrente.
struct DuelView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var duel: Duel
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    private var p: Palette { duel.pick.palette }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            if duel.finished {
                results
            } else if let item = duel.current {
                VStack(spacing: 0) {
                    half(0, item).rotationEffect(.degrees(180))
                    middle(item)
                    half(1, item)
                }
            }
        }
        .onAppear { duel.start() }
        .onChange(of: duel.finished) { _, done in
            if done && !saved {
                saved = true
                store.apply(seats: duel.seats, pick: duel.pick, mode: .duelo)
            }
        }
    }

    private func half(_ s: Int, _ item: Shown) -> some View {
        let seat = duel.seats[s]
        let color = PlayerColor.of(seat.color)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Avatar(name: seat.name, color: seat.color, size: 34)
                Text(seat.name).font(.headline).foregroundStyle(color)
                Spacer()
                if duel.resolved && duel.winner == s {
                    Text("+\(duel.lastGain)").font(.headline).foregroundStyle(Palette.good)
                }
                Text("\(seat.score)").font(p.title(28).monospacedDigit()).foregroundStyle(p.text)
            }
            Text(item.question.text)
                .font(p.title(26))
                .foregroundStyle(p.text)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(item.options.indices, id: \.self) { i in
                    OptionButton(text: item.options[i], letter: letters[i], state: state(s, item, i),
                                 palette: p, compact: true) { duel.choose(s, i) }
                        .disabled(duel.resolved || duel.picks[s] != nil)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.opacity(0.07))
    }

    private func state(_ s: Int, _ item: Shown, _ i: Int) -> OptionButton.Look {
        if duel.resolved {
            if i == item.correctIndex { return .right }
            return duel.picks[s] == i ? .wrong : .faded
        }
        if let pick = duel.picks[s] { return pick == i ? .wrong : .faded }
        return .normal
    }

    private func middle(_ item: Shown) -> some View {
        HStack(spacing: 16) {
            Button { duel.stop(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(p.dim)
            }
            .buttonStyle(.plain)
            if duel.resolved {
                VStack(alignment: .leading, spacing: 2) {
                    Text(duel.winner.map { "¡Punto para \(duel.seats[$0].name)!" } ?? "Nadie acertó")
                        .font(.headline).foregroundStyle(duel.winner == nil ? Palette.bad : Palette.good)
                    Text(item.question.fact).font(.caption).foregroundStyle(p.text.opacity(0.8)).lineLimit(2)
                }
                Spacer()
                Button(duel.index + 1 >= duel.items.count ? "Ver resultado" : "Siguiente") { duel.next() }
                    .font(.headline)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(p.accent, in: Capsule())
                    .foregroundStyle(p.bg)
                    .buttonStyle(.plain)
            } else {
                Text("\(duel.index + 1)/\(duel.items.count)").font(.headline.monospacedDigit()).foregroundStyle(p.dim)
                ProgressView(value: duel.timeLeft, total: Scoring.seconds)
                    .tint(duel.timeLeft < 5 ? Palette.bad : p.accent)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
        .background(p.panel)
    }

    private var results: some View {
        let a = duel.seats[0], b = duel.seats[1]
        let winner = a.score == b.score ? nil : (a.score > b.score ? a : b)
        return VStack(spacing: 26) {
            Text(winner.map { "¡GANÓ \($0.name.uppercased())!" } ?? "¡EMPATE!")
                .font(p.title(52)).foregroundStyle(p.accent)
            HStack(spacing: 40) {
                ForEach([a, b]) { seat in
                    VStack(spacing: 10) {
                        Avatar(name: seat.name, color: seat.color, size: 90)
                        Text(seat.name).font(.title2.weight(.bold)).foregroundStyle(p.text)
                        Text("\(seat.score)").font(p.title(56).monospacedDigit()).foregroundStyle(p.text)
                        Text("\(seat.correct) aciertos").foregroundStyle(p.dim)
                    }
                }
            }
            Button("Volver") { dismiss() }
                .font(.title3.weight(.bold))
                .padding(.horizontal, 32).padding(.vertical, 14)
                .background(p.panel, in: Capsule())
                .foregroundStyle(p.text)
                .buttonStyle(.plain)
        }
        .padding(40)
    }
}
