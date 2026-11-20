import QuartzCore
import SwiftUI

// MARK: - Guitarras y notas

/// Las guitarras de Fran y su afinación.
enum Guitar: String, CaseIterable, Identifiable {
    case yamaha, gretsch, dean, acustica

    var id: String { rawValue }

    var name: String {
        switch self {
        case .yamaha: "Yamaha"
        case .gretsch: "Gretsch"
        case .dean: "Dean"
        case .acustica: "Acústica"
        }
    }

    var detail: String {
        switch self {
        case .yamaha: "Tipo Strat HSS"
        case .gretsch: "Dos humbuckers"
        case .dean: "Tipo Explorer"
        case .acustica: "Sin amplificador"
        }
    }

    /// Semitonos respecto a Mi estándar: la Dean va medio tono abajo.
    var offset: Int { self == .dean ? -1 : 0 }
    var tuningName: String { self == .dean ? "Mi♭ estándar" : "Mi estándar" }

    /// Nota MIDI de cada cuerda al aire, de la 6ª (grave) a la 1ª.
    var openStrings: [Int] { [40, 45, 50, 55, 59, 64].map { $0 + offset } }

    /// MIDI de una cuerda (6 = grave … 1 = aguda) en un traste.
    func midi(string: Int, fret: Int) -> Int { openStrings[6 - string] + fret }
}

enum NoteName {
    static let sharps = ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
    static let flats = ["Do", "Re♭", "Re", "Mi♭", "Mi", "Fa", "Sol♭", "Sol", "La♭", "La", "Si♭", "Si"]

    static func of(_ midi: Int, flats useFlats: Bool = false) -> String {
        (useFlats ? flats : sharps)[((midi % 12) + 12) % 12]
    }

    static func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
    static func midi(_ freq: Double) -> Double { 69 + 12 * log2(freq / 440) }
}

// MARK: - Riffs

struct Fret: Hashable {
    let string: Int
    let fret: Int
}

/// Una nota suelta o un acorde en la tablatura.
struct TabEvent: Hashable {
    let beat: Double
    let frets: [Fret]
    /// Para acordes: «5» (power chord), «m» (menor) o «» (mayor).
    let suffix: String?

    var isChord: Bool { frets.count > 1 }
}

/// Un paso al escribir un riff: nota suelta o acorde.
enum Step {
    case note(Int, Int)
    case chord([Fret], String)

    static func n(_ string: Int, _ fret: Int) -> Step { .note(string, fret) }
    /// Power chord con la tónica en la 6ª cuerda.
    static func p6(_ f: Int) -> Step { .chord([Fret(string: 6, fret: f), Fret(string: 5, fret: f + 2), Fret(string: 4, fret: f + 2)], "5") }
    /// Power chord con la tónica en la 5ª cuerda.
    static func p5(_ f: Int) -> Step { .chord([Fret(string: 5, fret: f), Fret(string: 4, fret: f + 2), Fret(string: 3, fret: f + 2)], "5") }

    private static func open(_ shape: [(Int, Int)], _ suffix: String) -> Step {
        .chord(shape.map { Fret(string: $0.0, fret: $0.1) }, suffix)
    }
    static let mim = open([(6, 0), (5, 2), (4, 2), (3, 0), (2, 0), (1, 0)], "m")
    static let lam = open([(5, 0), (4, 2), (3, 2), (2, 1), (1, 0)], "m")
    static let re = open([(4, 0), (3, 2), (2, 3), (1, 2)], "")
    static let sol = open([(6, 3), (5, 2), (4, 0), (3, 0), (2, 0), (1, 3)], "")
    static let doM = open([(5, 3), (4, 2), (3, 0), (2, 1), (1, 0)], "")
}

enum Difficulty: Int {
    case facil, medio, dificil

    var title: String {
        switch self {
        case .facil: "Fácil"
        case .medio: "Medio"
        case .dificil: "Difícil"
        }
    }

    /// Margen para acertar a tiempo, en segundos (antes o después).
    var window: Double {
        switch self {
        case .facil: 0.25
        case .medio: 0.2
        case .dificil: 0.16
        }
    }
}

/// Riffs originales hechos para Rockola (no son de ninguna canción).
struct Riff: Identifiable {
    let id: String
    let title: String
    let mood: String
    let difficulty: Difficulty
    let bpm: Double
    /// Desenchufado: se toca siempre con la acústica.
    var acoustic = false
    let notes: [TabEvent]

    var key: String { "riff-\(id)" }
    var chords: Int { notes.filter(\.isChord).count }

    /// Construye una línea de pasos a intervalos iguales (nil = silencio), repitiéndola `times` veces.
    static func line(_ steps: [Step?], every: Double, times: Int = 1) -> [TabEvent] {
        var out: [TabEvent] = []
        let length = Double(steps.count) * every
        for r in 0..<times {
            for (i, step) in steps.enumerated() {
                let beat = Double(r) * length + Double(i) * every
                switch step {
                case .note(let s, let f): out.append(TabEvent(beat: beat, frets: [Fret(string: s, fret: f)], suffix: nil))
                case .chord(let frets, let suffix): out.append(TabEvent(beat: beat, frets: frets, suffix: suffix))
                case nil: break
                }
            }
        }
        return out
    }

    static let electric: [Riff] = {
        func n(_ s: Int, _ f: Int) -> Step? { .n(s, f) }
        func p6(_ f: Int) -> Step? { .p6(f) }
        func p5(_ f: Int) -> Step? { .p5(f) }
        return [
            Riff(id: "hierro", title: "Hierro frío", mood: "Negras en la 6ª cuerda, para calentar",
                 difficulty: .facil, bpm: 90,
                 notes: line([n(6, 0), n(6, 0), n(6, 3), n(6, 0), n(6, 5), n(6, 3), n(6, 0), nil,
                              n(6, 0), n(6, 0), n(6, 3), n(6, 5), n(6, 7), n(6, 5), n(6, 3), nil], every: 1, times: 2)),
            Riff(id: "muralla", title: "Muralla", mood: "Tu primer riff con power chords",
                 difficulty: .facil, bpm: 85,
                 notes: line([p6(0), nil, n(6, 0), n(6, 0), p6(3), nil, p6(5), nil,
                              p6(0), nil, n(6, 0), n(6, 0), p6(7), nil, p6(5), nil], every: 0.5, times: 2)),
            Riff(id: "pantano", title: "Pantano", mood: "Corcheas entre la 6ª y la 5ª, sabor frigio",
                 difficulty: .medio, bpm: 110,
                 notes: line([n(6, 0), n(6, 0), n(6, 1), n(6, 0), n(6, 0), n(6, 4), n(6, 3), n(6, 1),
                              n(5, 0), n(5, 0), n(5, 1), n(5, 0), n(5, 3), n(5, 1), n(6, 3), n(6, 1)], every: 0.5, times: 2)),
            Riff(id: "sal", title: "Tormenta de sal", mood: "Acordes que caen y notas sueltas",
                 difficulty: .medio, bpm: 100,
                 notes: line([p6(0), nil, n(6, 0), n(6, 0), p6(3), nil, n(6, 0), n(6, 0),
                              p6(5), nil, p6(3), nil, p6(1), nil, p6(0), nil], every: 0.5, times: 2)),
            Riff(id: "lento", title: "Fuego lento", mood: "Galope entre la 6ª y la 5ª con acordes",
                 difficulty: .medio, bpm: 105,
                 notes: line([n(6, 0), n(6, 0), p6(1), nil, n(6, 0), n(6, 0), p6(3), nil,
                              n(5, 0), n(5, 0), p5(1), nil, p5(3), nil, p6(6), nil], every: 0.5, times: 2)),
            Riff(id: "cuervo", title: "Cuervo de ceniza", mood: "Melodía oscura cruzando cuerdas",
                 difficulty: .dificil, bpm: 130,
                 notes: line([n(4, 2), n(4, 3), n(4, 5), n(3, 2), n(4, 5), n(4, 3), n(4, 2), n(5, 5),
                              n(4, 2), n(4, 3), n(4, 5), n(3, 4), n(3, 5), n(3, 4), n(4, 5), n(4, 3),
                              n(6, 0), n(6, 0), n(6, 1), n(6, 0), n(6, 3), n(6, 0), n(6, 5), n(6, 3),
                              n(5, 2), n(5, 3), n(5, 5), n(4, 2), n(4, 3), n(4, 5), n(3, 2), n(3, 4)], every: 0.5, times: 2)),
            Riff(id: "cuchillas", title: "Noche de cuchillas", mood: "Melodía rápida que remata en acordes",
                 difficulty: .dificil, bpm: 135,
                 notes: line([n(4, 2), n(4, 3), n(4, 5), n(4, 3), p6(0), nil, p6(1), nil,
                              n(3, 2), n(3, 4), n(3, 5), n(3, 4), p6(3), nil, p6(5), nil], every: 0.5, times: 2)),
        ]
    }()

    static let unplugged: [Riff] = {
        func n(_ s: Int, _ f: Int) -> Step? { .n(s, f) }
        let mim: Step? = Step.mim, lam: Step? = Step.lam, re: Step? = Step.re, sol: Step? = Step.sol, doM: Step? = Step.doM
        return [
            Riff(id: "lluvia", title: "Lluvia en el patio", mood: "Arpegios lentos, nota por nota",
                 difficulty: .facil, bpm: 70, acoustic: true,
                 notes: line([n(5, 0), n(4, 2), n(3, 2), n(2, 1), n(1, 0), n(2, 1), n(3, 2), n(4, 2),
                              n(5, 3), n(4, 2), n(3, 0), n(2, 1), n(1, 0), n(2, 1), n(3, 0), n(4, 2),
                              n(6, 3), n(5, 2), n(4, 0), n(3, 0), n(2, 0), n(3, 0), n(4, 0), n(5, 2),
                              n(6, 0), n(5, 2), n(4, 2), n(3, 0), n(2, 0), n(3, 0), n(4, 2), n(5, 2)], every: 0.5)),
            Riff(id: "tierra", title: "Camino de tierra", mood: "Rasgueos con acordes abiertos",
                 difficulty: .medio, bpm: 80, acoustic: true,
                 notes: line([mim, mim, doM, doM, sol, sol, re, re], every: 1, times: 2)),
            Riff(id: "viento", title: "Ceniza al viento", mood: "Bajos, punteos y acordes mezclados",
                 difficulty: .dificil, bpm: 92, acoustic: true,
                 notes: line([n(6, 0), nil, mim, nil, n(4, 2), n(3, 0), mim, nil,
                              n(5, 0), nil, lam, nil, n(3, 2), n(2, 1), lam, nil,
                              n(5, 3), nil, doM, nil, n(2, 1), n(1, 0), doM, nil,
                              n(4, 0), nil, re, nil, n(2, 3), n(1, 2), re, nil], every: 0.5)),
        ]
    }()

    static var all: [Riff] { electric + unplugged }
}

// MARK: - Partida de concierto

enum NoteState { case pending, hit, perfect, miss }

@MainActor
final class Concert: ObservableObject, Identifiable {
    let riff: Riff
    let guitar: Guitar
    let speed: Double
    let player: Player?

    /// Hora de cada nota en el reloj del sistema (segundos).
    private(set) var times: [Double] = []
    @Published private(set) var states: [NoteState]
    @Published private(set) var score = 0
    @Published private(set) var streak = 0
    @Published private(set) var bestStreak = 0
    @Published private(set) var feedback: (text: String, good: Bool)?
    @Published private(set) var lastHeard: String?
    @Published private(set) var finished = false
    @Published private(set) var startTime: Double = 0

    private var timer: Timer?
    private var feedbackID = 0

    init(riff: Riff, guitar: Guitar, speed: Double, player: Player?) {
        self.riff = riff
        self.guitar = riff.acoustic ? .acustica : guitar
        self.speed = speed
        self.player = player
        states = Array(repeating: .pending, count: riff.notes.count)
    }

    var secondsPerBeat: Double { 60 / (riff.bpm * speed) }
    /// Cuenta de 4 tiempos antes de la primera nota.
    var countIn: Double { 4 * secondsPerBeat }
    var hits: Int { states.filter { $0 == .hit || $0 == .perfect }.count }
    var multiplier: Int { min(4, 1 + streak / 8) }
    var accuracy: Int { riff.notes.isEmpty ? 0 : Int((Double(hits) / Double(riff.notes.count) * 100).rounded()) }
    var endTime: Double { (times.last ?? startTime) + 1.5 }

    private var flats: Bool { guitar.offset != 0 }
    /// Las notas desenchufadas se dejan sonar: un poco más de margen.
    var window: Double { riff.difficulty.window + (riff.acoustic ? 0.06 : 0) }

    /// MIDI de la nota (o de la más grave del acorde).
    func expected(_ i: Int) -> Int {
        riff.notes[i].frets.map { guitar.midi(string: $0.string, fret: $0.fret) }.min() ?? 0
    }

    /// Nombre del acorde según la guitarra (con la Dean, Mi5 suena como Mi♭5).
    func chordName(_ i: Int) -> String {
        NoteName.of(expected(i), flats: flats) + (riff.notes[i].suffix ?? "")
    }

    /// Notas MIDI exactas del acorde en esta guitarra.
    func chordNotes(_ i: Int) -> [Int] {
        riff.notes[i].frets.map { guitar.midi(string: $0.string, fret: $0.fret) }
    }

    /// Cómo debería repartirse el sonido de esas notas en las 12 notas, contando los armónicos de la cuerda.
    nonisolated static func template(_ notes: [Int]) -> [Float] {
        var t = [Float](repeating: 0, count: 12)
        for n in notes {
            for h in 1...8 {
                let f = NoteName.frequency(n) * Double(h)
                guard f >= 70, f <= 1600 else { continue }
                t[(Int(NoteName.midi(f).rounded()) % 12 + 12) % 12] += Float(1 / Double(h))
            }
        }
        return t
    }

    /// ¿Suena ese acorde? Se compara lo que oye el iPad con la plantilla (similitud de 0 a 1).
    /// En pruebas con guitarra sintética, el acorde correcto da 0,89 o más y los distintos menos de 0,85.
    nonisolated static func chordMatches(_ c: [Float], notes: [Int]) -> Bool {
        let t = template(notes)
        var dot: Float = 0, a: Float = 0, b: Float = 0
        for k in 0..<12 { dot += c[k] * t[k]; a += c[k] * c[k]; b += t[k] * t[k] }
        guard a > 0, b > 0 else { return false }
        return dot / (a.squareRoot() * b.squareRoot()) >= 0.86
    }

    func start() {
        startTime = CACurrentMediaTime() + countIn
        times = riff.notes.map { startTime + $0.beat * secondsPerBeat }
        states = Array(repeating: .pending, count: riff.notes.count)
        score = 0; streak = 0; bestStreak = 0
        feedback = nil; lastHeard = nil; finished = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() { timer?.invalidate() }

    private func tick() {
        let now = CACurrentMediaTime()
        // Margen extra porque el iPad tarda un poco en reconocer la nota.
        for i in states.indices where states[i] == .pending && now > times[i] + window + 0.35 {
            states[i] = .miss
            if streak > 0 { show("Se escapó", good: false) }
            streak = 0
        }
        if now > endTime, !finished {
            finished = true
            timer?.invalidate()
        }
    }

    func heard(_ note: HeardNote) {
        guard !finished else { return }
        lastHeard = NoteName.of(note.midi, flats: flats)
        let near = pendingNear(note.time, chords: false)
        guard !near.isEmpty else { return }

        // Vale la nota exacta o la misma una octava arriba o abajo (el micrófono a veces se confunde).
        if let i = near.first(where: { [0, 12, -12].contains(note.midi - expected($0)) }) {
            award(i, at: note.time)
        } else if let i = near.first {
            show("Era \(NoteName.of(expected(i), flats: flats))", good: false)
        }
    }

    func heard(_ chroma: HeardChroma) {
        guard !finished else { return }
        let near = pendingNear(chroma.time, chords: true)
        guard !near.isEmpty else { return }
        if let i = near.first(where: { Self.chordMatches(chroma.chroma, notes: chordNotes($0)) }) {
            lastHeard = chordName(i)
            award(i, at: chroma.time)
        } else if let i = near.first {
            show("Era \(chordName(i))", good: false)
        }
    }

    private func pendingNear(_ time: Double, chords: Bool) -> [Int] {
        states.indices.filter {
            states[$0] == .pending && riff.notes[$0].isChord == chords && abs(times[$0] - time) <= window
        }
    }

    private func award(_ i: Int, at time: Double) {
        let perfect = abs(times[i] - time) <= window / 2
        states[i] = perfect ? .perfect : .hit
        streak += 1
        bestStreak = max(bestStreak, streak)
        score += (perfect ? 150 : 100) * multiplier
        show(perfect ? "¡Perfecto!" : "¡Bien!", good: true)
    }

    private func show(_ text: String, good: Bool) {
        feedbackID += 1
        let id = feedbackID
        feedback = (text, good)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            if self?.feedbackID == id { self?.feedback = nil }
        }
    }
}

extension Store {
    /// Guarda un concierto en el panel del jugador y el récord del riff.
    func saveConcert(_ c: Concert) {
        if let p = c.player {
            update(p.id) { pl in
                pl.points += c.score
                pl.games += 1
                pl.bestScore = max(pl.bestScore, c.score)
                pl.bestStreak = max(pl.bestStreak, c.bestStreak)
                pl.history.append(GameRecord(date: .now, score: c.score, correct: c.hits, total: c.riff.notes.count,
                                             label: "Concierto · \(c.riff.title)", mode: .solo, rivals: [], won: nil))
                if pl.history.count > 200 { pl.history.removeFirst(pl.history.count - 200) }
            }
        }
        if c.score > best[c.riff.key, default: 0] { best[c.riff.key] = c.score }
    }
}
