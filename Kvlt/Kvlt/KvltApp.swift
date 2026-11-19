import SwiftUI

@main
struct KvltApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Kvlt.blood)
        }
    }
}

struct RoundChoice: Identifiable {
    let id = UUID()
    let scene: MetalScene?
}

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var playing: RoundChoice?
    @State private var editing = false

    var body: some View {
        ZStack {
            Kvlt.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    Button { playing = RoundChoice(scene: nil) } label: {
                        HStack {
                            Image(systemName: "flame.fill")
                            Text("Ronda de todas las escenas")
                            Spacer()
                            Text("10 preguntas · 15 s").font(.callout).foregroundStyle(Kvlt.bone.opacity(0.7))
                        }
                        .font(.title3.weight(.bold))
                        .padding(20)
                        .background(Kvlt.blood, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Kvlt.bone)
                    }
                    .buttonStyle(.plain)

                    Text("Escenas").font(Kvlt.title(26)).foregroundStyle(Kvlt.bone)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(MetalScene.allCases) { scene in sceneCard(scene) }
                    }
                }
                .padding(32)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .fullScreenCover(item: $playing) { choice in
            RoundView(round: Round(scene: choice.scene, pool: store.questions(for: choice.scene)))
                .environmentObject(store)
        }
        .sheet(isPresented: $editing) {
            CustomQuestionsView().environmentObject(store)
        }
    }

    private var header: some View {
        let rank = Rank.of(store.totalPoints)
        let next = Rank.next(store.totalPoints)
        return HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("KVLT").font(Kvlt.title(64)).foregroundStyle(Kvlt.bone).kerning(6)
                Text("Trivia de metal extremo y underground").foregroundStyle(Kvlt.ash)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(rank.name.uppercased()).font(Kvlt.title(24)).foregroundStyle(Kvlt.blood)
                Text("\(store.totalPoints) puntos").font(.headline.monospacedDigit()).foregroundStyle(Kvlt.bone)
                if let next {
                    ProgressView(value: Double(store.totalPoints - rank.from), total: Double(next.from - rank.from))
                        .frame(width: 220)
                    Text("Faltan \(next.from - store.totalPoints) para \(next.name)").font(.caption).foregroundStyle(Kvlt.ash)
                }
            }
        }
    }

    private func sceneCard(_ scene: MetalScene) -> some View {
        let count = store.questions(for: scene).count
        return Button {
            if scene == .tuyas && count == 0 { editing = true } else { playing = RoundChoice(scene: scene) }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: scene.icon)
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(Kvlt.blood.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Kvlt.blood)
                VStack(alignment: .leading, spacing: 3) {
                    Text(scene.title).font(.headline).foregroundStyle(Kvlt.bone)
                    Text(scene.subtitle).font(.caption).foregroundStyle(Kvlt.ash)
                    Text("\(count) preguntas · récord \(store.best[scene.rawValue, default: 0])")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Kvlt.ash)
                }
                Spacer()
                if scene == .tuyas {
                    Button { editing = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Kvlt.bone)
                }
            }
            .padding(16)
            .background(Kvlt.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Kvlt.bone.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && scene != .tuyas)
    }
}

struct RoundView: View {
    @EnvironmentObject var store: Store
    @StateObject var round: Round
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    var body: some View {
        ZStack {
            Kvlt.black.ignoresSafeArea()
            if round.finished {
                results
            } else if let item = round.current {
                question(item)
            } else {
                Text("No hay preguntas en esta escena todavía.").foregroundStyle(Kvlt.bone)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { round.stop(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(Kvlt.ash)
            }
            .padding(24)
        }
        .onAppear { round.start() }
        .onChange(of: round.finished) { _, done in
            if done && !saved {
                saved = true
                store.record(round.score, scene: round.scene)
            }
        }
    }

    private func question(_ item: Round.Shown) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text((round.scene?.title ?? "Todas las escenas").uppercased())
                    .font(.headline).kerning(2).foregroundStyle(Kvlt.blood)
                Text("· \(round.index + 1) de \(round.items.count)").foregroundStyle(Kvlt.ash)
                Spacer()
                if round.streak > 1 {
                    Label("Racha x\(round.streak)", systemImage: "flame.fill").foregroundStyle(Kvlt.blood).font(.headline)
                }
                Text("\(round.score)").font(Kvlt.title(30).monospacedDigit()).foregroundStyle(Kvlt.bone)
                    .padding(.trailing, 60)
            }

            ProgressView(value: round.timeLeft, total: Round.seconds)
                .tint(round.timeLeft < 5 ? Kvlt.blood : Kvlt.bone)
                .animation(.linear(duration: 0.1), value: round.timeLeft)

            Text(item.question.text)
                .font(Kvlt.title(36))
                .foregroundStyle(Kvlt.bone)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(item.options.indices, id: \.self) { i in
                    optionButton(item, i)
                }
            }

            if round.answered {
                feedback(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: 1100)
        .animation(.easeOut(duration: 0.25), value: round.answered)
    }

    private func optionButton(_ item: Round.Shown, _ i: Int) -> some View {
        let letters = ["A", "B", "C", "D"]
        let isRight = i == item.correctIndex
        let isPicked = round.picked == i
        let bg: Color = !round.answered ? Kvlt.panel : (isRight ? Kvlt.good.opacity(0.35) : (isPicked ? Kvlt.blood.opacity(0.45) : Kvlt.panel.opacity(0.5)))
        return Button { round.choose(i) } label: {
            HStack(spacing: 14) {
                Text(letters[i])
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(Kvlt.bone.opacity(0.4)))
                Text(item.options[i]).font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
                Spacer()
                if round.answered && isRight { Image(systemName: "checkmark.circle.fill").foregroundStyle(Kvlt.good) }
                if round.answered && isPicked && !isRight { Image(systemName: "xmark.circle.fill").foregroundStyle(Kvlt.blood) }
            }
            .foregroundStyle(Kvlt.bone)
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Kvlt.bone.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(round.answered)
    }

    private func feedback(_ item: Round.Shown) -> some View {
        let right = round.picked == item.correctIndex
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(right ? "¡Correcto! +\(round.lastGain)" : (round.picked == -1 ? "Se acabó el tiempo" : "No era esa"))
                    .font(Kvlt.title(24))
                    .foregroundStyle(right ? Kvlt.good : Kvlt.blood)
                Text(item.question.fact).foregroundStyle(Kvlt.bone.opacity(0.85))
            }
            Spacer()
            Button(round.index + 1 >= round.items.count ? "Ver resultado" : "Siguiente") { round.next() }
                .font(.title3.weight(.bold))
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(Kvlt.blood, in: Capsule())
                .foregroundStyle(Kvlt.bone)
                .buttonStyle(.plain)
        }
        .padding(22)
        .background(Kvlt.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private var results: some View {
        let rank = Rank.of(store.totalPoints)
        return VStack(spacing: 22) {
            Text(round.correct >= 9 ? "TRUE" : round.correct >= 6 ? "NADA MAL" : "A ESCUCHAR MÁS DEMOS")
                .font(Kvlt.title(44)).foregroundStyle(Kvlt.blood).kerning(3)
            Text("\(round.score)").font(Kvlt.title(96).monospacedDigit()).foregroundStyle(Kvlt.bone)
            Text("\(round.correct) de \(round.items.count) correctas · mejor racha x\(round.bestStreak)")
                .font(.title3).foregroundStyle(Kvlt.ash)
            Text("Rango: \(rank.name) · \(store.totalPoints) puntos en total")
                .font(.headline).foregroundStyle(Kvlt.bone)
            HStack(spacing: 16) {
                Button("Volver") { dismiss() }
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(Kvlt.panel, in: Capsule())
            }
            .font(.title3.weight(.bold))
            .foregroundStyle(Kvlt.bone)
            .buttonStyle(.plain)
        }
        .padding(40)
    }
}

/// Para agregar preguntas propias, por ejemplo de la escena tica.
struct CustomQuestionsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var right = ""
    @State private var wrong = ["", "", ""]
    @State private var fact = ""

    private var valid: Bool {
        ![text, right, wrong[0], wrong[1], wrong[2]].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

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
                        store.custom.append(Question(scene: .tuyas, text: text, options: [right] + wrong, fact: fact.isEmpty ? "Pregunta agregada por ti." : fact))
                        text = ""; right = ""; wrong = ["", "", ""]; fact = ""
                    }
                    .disabled(!valid)
                } header: {
                    Text("Nueva pregunta")
                } footer: {
                    Text("Ideal para bandas de Costa Rica y de la escena local. Las respuestas se barajan solas.")
                }

                if !store.custom.isEmpty {
                    Section("Tus preguntas (\(store.custom.count))") {
                        ForEach(store.custom) { q in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.text)
                                Text("Respuesta: \(q.options[0])").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { store.custom.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("Tus preguntas")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }
}
