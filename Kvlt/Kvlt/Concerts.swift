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

struct TabNote: Hashable {
    let beat: Double
    let string: Int
    let fret: Int
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
    let notes: [TabNote]

    var key: String { "riff-\(id)" }

    /// Construye una línea de notas a intervalos iguales, repitiéndola `times` veces.
    static func line(_ steps: [(Int, Int)?], every: Double, times: Int = 1) -> [TabNote] {
        var out: [TabNote] = []
        let length = Double(steps.count) * every
        for r in 0..<times {
            for (i, s) in steps.enumerated() {
                if let s { out.append(TabNote(beat: Double(r) * length + Double(i) * every, string: s.0, fret: s.1)) }
            }
        }
        return out
    }

    static let all: [Riff] = [
        Riff(id: "hierro", title: "Hierro frío", mood: "Negras en la 6ª cuerda, para calentar",
             difficulty: .facil, bpm: 90,
             notes: line([(6, 0), (6, 0), (6, 3), (6, 0), (6, 5), (6, 3), (6, 0), nil,
                          (6, 0), (6, 0), (6, 3), (6, 5), (6, 7), (6, 5), (6, 3), nil], every: 1, times: 2)),
        Riff(id: "pantano", title: "Pantano", mood: "Corcheas entre la 6ª y la 5ª, sabor frigio",
             difficulty: .medio, bpm: 110,
             notes: line([(6, 0), (6, 0), (6, 1), (6, 0), (6, 0), (6, 4), (6, 3), (6, 1),
                          (5, 0), (5, 0), (5, 1), (5, 0), (5, 3), (5, 1), (6, 3), (6, 1)], every: 0.5, times: 2)),
        Riff(id: "cuervo", title: "Cuervo de ceniza", mood: "Melodía oscura cruzando cuerdas",
             difficulty: .dificil, bpm: 130,
             notes: line([(4, 2), (4, 3), (4, 5), (3, 2), (4, 5), (4, 3), (4, 2), (5, 5),
                          (4, 2), (4, 3), (4, 5), (3, 4), (3, 5), (3, 4), (4, 5), (4, 3),
                          (6, 0), (6, 0), (6, 1), (6, 0), (6, 3), (6, 0), (6, 5), (6, 3),
                          (5, 2), (5, 3), (5, 5), (4, 2), (4, 3), (4, 5), (3, 2), (3, 4)], every: 0.5, times: 2)),
    ]
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
        self.guitar = guitar
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

    func expected(_ i: Int) -> Int { guitar.midi(string: riff.notes[i].string, fret: riff.notes[i].fret) }

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
        for i in states.indices where states[i] == .pending && now > times[i] + riff.difficulty.window + 0.3 {
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
        lastHeard = NoteName.of(note.midi, flats: guitar.offset != 0)
        let win = riff.difficulty.window
        let near = states.indices.filter { states[$0] == .pending && abs(times[$0] - note.time) <= win }
        guard !near.isEmpty else { return }

        // Vale la nota exacta o la misma una octava arriba o abajo (el micrófono a veces se confunde).
        if let i = near.first(where: { [0, 12, -12].contains(note.midi - expected($0)) }) {
            let perfect = abs(times[i] - note.time) <= win / 2
            states[i] = perfect ? .perfect : .hit
            streak += 1
            bestStreak = max(bestStreak, streak)
            score += (perfect ? 150 : 100) * multiplier
            show(perfect ? "¡Perfecto!" : "¡Bien!", good: true)
        } else if let i = near.first {
            let want = NoteName.of(expected(i), flats: guitar.offset != 0)
            show("Era \(want)", good: false)
        }
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
