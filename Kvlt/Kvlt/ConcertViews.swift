import QuartzCore
import SwiftUI

private let stage = Genre.metal.palette

// MARK: - Menú de Conciertos

/// Elegir jugador, guitarra y riff; desde aquí se abre el afinador o se empieza a tocar.
struct ConcertsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var listener = Listener()
    @AppStorage("guitarraElegida") private var guitarRaw = Guitar.yamaha.rawValue
    @AppStorage("jugadorConcierto") private var playerRaw = ""
    @AppStorage("velocidadConcierto") private var speed = 1.0
    @State private var showTuner = false
    @State private var concert: Concert?

    private var guitar: Guitar { Guitar(rawValue: guitarRaw) ?? .yamaha }
    private var player: Player? { store.players.first { $0.id.uuidString == playerRaw } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if listener.denied { deniedBanner }
                    section("Quién toca") { playerRow }
                    section("Tu guitarra") { guitarRow }
                    Button { showTuner = true } label: {
                        Label("Afinar \(guitar.name) · \(guitar.tuningName)", systemImage: "tuningfork")
                            .font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(stage.panel, in: Capsule())
                            .foregroundStyle(stage.text)
                    }
                    .buttonStyle(.plain)
                    section("Velocidad: \(Int((speed * 100).rounded())) %") {
                        Slider(value: $speed, in: 0.6...1.2, step: 0.05).tint(stage.accent)
                    }
                    section("Riffs") {
                        VStack(spacing: 12) { ForEach(Riff.all) { riffCard($0) } }
                    }
                    Text("Pon el iPad cerca del amplificador (o de la boca de la acústica). Toca nota por nota: los acordes todavía no se reconocen.")
                        .font(.footnote).foregroundStyle(stage.dim)
                }
                .padding(32)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(stage.bg.ignoresSafeArea())
            .navigationTitle("Conciertos")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .toolbarBackground(stage.bg, for: .navigationBar)
        }
        .tint(stage.accent)
        .onAppear {
            listener.start()
            if player == nil, let first = store.players.first { playerRaw = first.id.uuidString }
        }
        .onDisappear { listener.stop() }
        .sheet(isPresented: $showTuner) { TunerView(guitar: guitar).environmentObject(listener) }
        .fullScreenCover(item: $concert) { c in
            ConcertPlayView(concert: c).environmentObject(listener).environmentObject(store)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(stage.title(22)).foregroundStyle(stage.text)
            content()
        }
    }

    private var deniedBanner: some View {
        Label("Rockola no tiene permiso para usar el micrófono. Actívalo en Ajustes › Rockola › Micrófono.",
              systemImage: "mic.slash.fill")
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.bad.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(stage.text)
    }

    private var playerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.players) { pl in
                    let on = pl.id.uuidString == playerRaw
                    Button { playerRaw = pl.id.uuidString } label: {
                        HStack(spacing: 10) {
                            Avatar(name: pl.name, color: pl.color, size: 34)
                            Text(pl.name).font(.headline).foregroundStyle(stage.text)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(stage.panel, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? stage.accent : .clear, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
                let none = player == nil
                Button { playerRaw = "" } label: {
                    Text("Sin guardar")
                        .font(.headline).foregroundStyle(stage.dim)
                        .padding(.horizontal, 16).padding(.vertical, 16)
                        .background(stage.panel, in: Capsule())
                        .overlay(Capsule().strokeBorder(none ? stage.accent : .clear, lineWidth: 3))
                }
                .buttonStyle(.plain)
            }
            .padding(3)
        }
    }

    private var guitarRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            ForEach(Guitar.allCases) { g in
                let on = g == guitar
                Button { guitarRaw = g.rawValue } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: g == .acustica ? "guitars" : "guitars.fill")
                            .font(.title2).foregroundStyle(stage.accent)
                        Text(g.name).font(.headline).foregroundStyle(stage.text)
                        Text("\(g.detail) · \(g.tuningName)").font(.caption).foregroundStyle(stage.dim)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(stage.panel, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? stage.accent : stage.text.opacity(0.08),
                                                                           lineWidth: on ? 3 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func riffCard(_ r: Riff) -> some View {
        Button {
            concert = Concert(riff: r, guitar: guitar, speed: speed, player: player)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "play.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(stage.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(stage.text)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.title).font(stage.title(20)).foregroundStyle(stage.text)
                    Text(r.mood).font(.subheadline).foregroundStyle(stage.dim)
                    Text("\(r.difficulty.title) · \(Int(r.bpm)) ppm · \(r.notes.count) notas · récord \(store.best[r.key, default: 0])")
                        .font(.caption.monospacedDigit()).foregroundStyle(stage.dim)
                }
                Spacer()
            }
            .padding(14)
            .background(stage.panel, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(listener.denied)
    }
}

// MARK: - Afinador

struct TunerView: View {
    let guitar: Guitar
    @EnvironmentObject var listener: Listener
    @Environment(\.dismiss) private var dismiss

    private var flats: Bool { guitar.offset != 0 }

    /// Cuerda más cercana a lo que suena y cuántos cents se aleja.
    private var reading: (string: Int, cents: Double, midi: Int)? {
        guard let f = listener.frequency else { return nil }
        let m = NoteName.midi(f)
        let open = guitar.openStrings
        let i = open.indices.min { abs(Double(open[$0]) - m) < abs(Double(open[$1]) - m) }!
        // Si está lejos de toda cuerda al aire, muestra la nota más cercana.
        if abs(Double(open[i]) - m) > 2.5 {
            let near = Int(m.rounded())
            return (0, (m - Double(near)) * 100, near)
        }
        return (6 - i, (m - Double(open[i])) * 100, open[i])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 34) {
                Text("\(guitar.name) · \(guitar.tuningName)").font(.headline).foregroundStyle(stage.dim)
                if let r = reading {
                    let inTune = abs(r.cents) < 5
                    VStack(spacing: 6) {
                        Text(NoteName.of(r.midi, flats: flats))
                            .font(.system(size: 110, weight: .black, design: .serif))
                            .foregroundStyle(inTune ? Palette.good : stage.text)
                        Text(r.string > 0 ? "\(r.string)ª cuerda" : "Fuera de las cuerdas al aire")
                            .font(.title3).foregroundStyle(stage.dim)
                    }
                    needle(r.cents)
                    Text(inTune ? "Afinada" : (r.cents < 0 ? "Muy grave: aprieta la clavija" : "Muy aguda: afloja la clavija"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(inTune ? Palette.good : stage.text)
                } else {
                    Image(systemName: "waveform").font(.system(size: 80)).foregroundStyle(stage.dim)
                    Text("Toca una cuerda al aire").font(.title2).foregroundStyle(stage.text)
                    needle(nil)
                }
                strings
                LevelMeter(level: listener.level).frame(width: 240)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(stage.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .tint(stage.accent)
    }

    private func needle(_ cents: Double?) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let c = max(-50, min(50, cents ?? 0))
            ZStack {
                Capsule().fill(stage.panel).frame(height: 10)
                Rectangle().fill(Palette.good).frame(width: w * 0.1, height: 28).opacity(0.5)
                Rectangle().fill(stage.dim).frame(width: 2, height: 36)
                if cents != nil {
                    Capsule()
                        .fill(abs(c) < 5 ? Palette.good : stage.accent)
                        .frame(width: 8, height: 54)
                        .offset(x: w / 2 * c / 50)
                        .animation(.easeOut(duration: 0.12), value: c)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 560, maxHeight: 60)
    }

    private var strings: some View {
        HStack(spacing: 12) {
            ForEach(Array(guitar.openStrings.enumerated()), id: \.offset) { i, m in
                let n = 6 - i
                let on = reading?.string == n
                VStack(spacing: 2) {
                    Text("\(n)ª").font(.caption).foregroundStyle(stage.dim)
                    Text(NoteName.of(m, flats: flats)).font(.headline)
                        .foregroundStyle(on ? stage.bg : stage.text)
                }
                .frame(width: 64, height: 58)
                .background(on ? stage.accent : stage.panel, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill").foregroundStyle(stage.dim)
            GeometryReader { geo in
                // Escala en decibelios: de -60 dB (nada) a 0 dB (máximo).
                let db = 20 * log10(max(Double(level), 1e-6))
                let f = max(0, min(1, (db + 60) / 60))
                ZStack(alignment: .leading) {
                    Capsule().fill(stage.panel)
                    Capsule().fill(stage.accent).frame(width: geo.size.width * f)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Tocando

struct ConcertPlayView: View {
    @ObservedObject var concert: Concert
    @EnvironmentObject var listener: Listener
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    var body: some View {
        ZStack {
            stage.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                topBar
                highway
                bottomBar
            }
            .padding(24)
            if concert.finished { results }
        }
        .onAppear {
            let c = concert
            listener.onNote = { [weak c] n in c?.heard(n) }
            listener.start()
            concert.start()
        }
        .onDisappear {
            listener.onNote = nil
            listener.stop()
            concert.stop()
        }
        .onChange(of: concert.finished) { _, done in
            if done, !saved { saved = true; store.saveConcert(concert) }
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Label("Salir", systemImage: "xmark")
                    .font(.headline)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(stage.panel, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(stage.text)
            Label("\(concert.guitar.name) · \(concert.guitar.tuningName)", systemImage: "guitars.fill")
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(stage.panel, in: Capsule())
                .foregroundStyle(stage.text)
            Text("\(concert.riff.title) · \(concert.riff.difficulty.title.lowercased())").foregroundStyle(stage.dim)
            Spacer()
            Text("Racha x\(concert.multiplier)").font(.headline).foregroundStyle(Color(hex: 0xF5A524))
            Text("\(concert.score)")
                .font(.system(size: 30, weight: .black, design: .serif).monospacedDigit())
                .foregroundStyle(stage.text)
                .contentTransition(.numericText())
                .animation(.snappy, value: concert.score)
        }
        .font(.subheadline)
    }

    private var highway: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in draw(ctx, size: size, now: CACurrentMediaTime()) }
        }
        .background(stage.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topLeading) {
            if let f = concert.feedback {
                Text(f.text)
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundStyle(f.good ? Palette.good : Palette.bad)
                    .padding(.leading, 150).padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .overlay { countdown }
    }

    @ViewBuilder private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let left = concert.startTime - CACurrentMediaTime()
            if left > 0 {
                Text("\(Int(ceil(left / concert.secondsPerBeat)))")
                    .font(.system(size: 140, weight: .black, design: .serif))
                    .foregroundStyle(stage.text.opacity(0.85))
            }
        }
    }

    /// Dibuja las 6 cuerdas, la línea roja y las notas que vienen.
    private func draw(_ ctx: GraphicsContext, size: CGSize, now: Double) {
        let hitX: CGFloat = 120
        let top: CGFloat = 40, bottom = size.height - 40
        let gap = (bottom - top) / 5
        let pxPerSecond: CGFloat = 300
        func y(_ string: Int) -> CGFloat { top + CGFloat(string - 1) * gap }

        let labels = ["e", "B", "G", "D", "A", "E"]
        for s in 1...6 {
            var line = Path()
            line.move(to: CGPoint(x: 40, y: y(s)))
            line.addLine(to: CGPoint(x: size.width - 16, y: y(s)))
            ctx.stroke(line, with: .color(stage.dim.opacity(0.6)), lineWidth: s >= 4 ? 2 : 1)
            ctx.draw(Text(labels[s - 1]).font(.caption).foregroundStyle(stage.dim), at: CGPoint(x: 22, y: y(s)))
        }

        // Pulso del tiempo en la línea de golpe.
        let beatPhase = (now - concert.startTime) / concert.secondsPerBeat
        let pulse = beatPhase > -4 ? 1 - (beatPhase - floor(beatPhase)) : 0
        let bar = CGRect(x: hitX - 4, y: top - 22, width: 8, height: bottom - top + 44)
        ctx.fill(Path(roundedRect: bar, cornerRadius: 4), with: .color(stage.accent.opacity(0.55 + 0.45 * pulse)))

        let r: CGFloat = 22
        for i in concert.riff.notes.indices {
            guard i < concert.times.count else { break }
            let dt = concert.times[i] - now
            let x = hitX + CGFloat(dt) * pxPerSecond
            if x > size.width + r || x < -r { continue }
            let n = concert.riff.notes[i]
            let state = concert.states[i]
            let color: Color = switch state {
            case .pending: stage.accent
            case .hit, .perfect: Palette.good
            case .miss: stage.dim.opacity(0.4)
            }
            let fade = x < hitX - 10 && state == .pending ? 0.6 : 1
            let rect = CGRect(x: x - r, y: y(n.string) - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(fade)))
            if state == .perfect { ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(Palette.good), lineWidth: 2) }
            ctx.draw(Text("\(n.fret)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(stage.text),
                     at: CGPoint(x: x, y: y(n.string)))
        }
    }

    private var bottomBar: some View {
        HStack {
            Text("El iPad oye: ").foregroundStyle(stage.dim)
                + Text(concert.lastHeard ?? "—").bold().foregroundStyle(stage.text)
            Spacer()
            Text("\(concert.hits) de \(concert.riff.notes.count) notas").foregroundStyle(stage.dim).monospacedDigit()
            LevelMeter(level: listener.level).frame(width: 180)
        }
        .font(.headline)
    }

    private var results: some View {
        let record = store.best[concert.riff.key, default: 0]
        return VStack(spacing: 18) {
            Text(concert.accuracy >= 90 ? "¡Brutal!" : concert.accuracy >= 60 ? "Buen concierto" : "A seguir ensayando")
                .font(stage.title(44)).foregroundStyle(stage.text)
            HStack(spacing: 30) {
                stat("Puntos", "\(concert.score)")
                stat("Notas", "\(concert.hits)/\(concert.riff.notes.count)")
                stat("Aciertos", "\(concert.accuracy) %")
                stat("Mejor racha", "\(concert.bestStreak)")
            }
            if concert.score > 0, concert.score >= record { Text("¡Nuevo récord de este riff!").foregroundStyle(Color(hex: 0xF5A524)) }
            if concert.player == nil { Text("Sin jugador: no se guardó en ningún panel.").font(.footnote).foregroundStyle(stage.dim) }
            HStack(spacing: 14) {
                Button("Otra vez") { saved = false; concert.start() }
                    .font(.title3.bold())
                    .padding(.horizontal, 26).padding(.vertical, 14)
                    .background(stage.accent, in: Capsule())
                    .foregroundStyle(stage.text)
                Button("Salir") { dismiss() }
                    .font(.title3.bold())
                    .padding(.horizontal, 26).padding(.vertical, 14)
                    .background(stage.panel, in: Capsule())
                    .foregroundStyle(stage.text)
            }
            .buttonStyle(.plain)
        }
        .padding(36)
        .background(stage.bg.opacity(0.96), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(stage.accent, lineWidth: 2))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 34, weight: .black, design: .serif).monospacedDigit()).foregroundStyle(stage.text)
            Text(title).font(.caption).foregroundStyle(stage.dim)
        }
    }
}
