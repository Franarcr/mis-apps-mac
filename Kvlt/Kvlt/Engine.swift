import SwiftUI

/// Rangos según los puntos acumulados de cada jugador.
struct Rank {
    let name: String
    let from: Int

    static let all = [
        Rank(name: "Novato", from: 0),
        Rank(name: "Fan", from: 2_000),
        Rank(name: "Melómano", from: 6_000),
        Rank(name: "Coleccionista", from: 12_000),
        Rank(name: "Leyenda", from: 25_000),
    ]

    static func of(_ points: Int) -> Rank { all.last { points >= $0.from } ?? all[0] }
    static func next(_ points: Int) -> Rank? { all.first { $0.from > points } }
}

struct GameRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var score: Int
    var correct: Int
    var total: Int
    var label: String
    var mode: GameMode
    var rivals: [String]
    /// nil en partidas de una sola persona.
    var won: Bool?
}

struct Player: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var color: Int
    var points = 0
    var games = 0
    var multiGames = 0
    var wins = 0
    var bestScore = 0
    var bestStreak = 0
    /// Preguntas contestadas y acertadas por género (clave: Genre.rawValue).
    var answered: [String: Int] = [:]
    var correct: [String: Int] = [:]
    var history: [GameRecord] = []

    var totalAnswered: Int { answered.values.reduce(0, +) }
    var totalCorrect: Int { correct.values.reduce(0, +) }
    var accuracy: Int { totalAnswered == 0 ? 0 : Int((Double(totalCorrect) / Double(totalAnswered) * 100).rounded()) }
}

/// Jugadores, récords y preguntas propias, guardados en el iPad.
@MainActor
final class Store: ObservableObject {
    @Published var players: [Player] = [] { didSet { save(players, "jugadores.json") } }
    @Published var best: [String: Int] { didSet { defaults.set(best, forKey: "mejores") } }
    @Published var custom: [Question] = [] { didSet { save(custom, "mis-preguntas.json") } }

    private let defaults = UserDefaults.standard

    private static func url(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: Self.url(name), options: .atomic) }
    }

    init() {
        best = defaults.dictionary(forKey: "mejores") as? [String: Int] ?? [:]
        if let data = try? Data(contentsOf: Self.url("mis-preguntas.json")),
           let list = try? JSONDecoder().decode([Question].self, from: data) {
            custom = list
        }
        if let data = try? Data(contentsOf: Self.url("jugadores.json")),
           let list = try? JSONDecoder().decode([Player].self, from: data) {
            players = list
        } else {
            // Los puntos de la primera versión (solo Kvlt) pasan a un primer jugador.
            let old = defaults.integer(forKey: "puntosTotales")
            if old > 0 { players = [Player(name: "Fran", color: 0, points: old)] }
        }
    }

    func player(_ id: UUID) -> Player? { players.first { $0.id == id } }

    @discardableResult
    func addPlayer(_ name: String) -> Player {
        let p = Player(name: name.trimmingCharacters(in: .whitespaces), color: players.count % PlayerColor.all.count)
        players.append(p)
        return p
    }

    func update(_ id: UUID, _ change: (inout Player) -> Void) {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return }
        change(&players[i])
    }

    func questions(_ pick: Pick) -> [Question] {
        let all = builtInQuestions + genreQuestions + custom
        if let topic = pick.topic { return all.filter { $0.scene == topic } }
        if let genre = pick.genre { return all.filter { $0.scene.genre == genre } }
        return all
    }

    /// Guarda el resultado de una partida en cada jugador.
    func apply(seats: [Seat], pick: Pick, mode: GameMode) {
        let multi = seats.count > 1
        let top = seats.map(\.score).max() ?? 0
        let leaders = seats.filter { $0.score == top && top > 0 }
        let winner = multi && leaders.count == 1 ? leaders[0].id : nil

        for seat in seats {
            update(seat.id) { p in
                p.points += seat.score
                p.games += 1
                if multi { p.multiGames += 1 }
                if seat.id == winner { p.wins += 1 }
                p.bestScore = max(p.bestScore, seat.score)
                p.bestStreak = max(p.bestStreak, seat.bestStreak)
                for (k, v) in seat.answeredBy { p.answered[k, default: 0] += v }
                for (k, v) in seat.correctBy { p.correct[k, default: 0] += v }
                p.history.append(GameRecord(date: .now, score: seat.score, correct: seat.correct, total: seat.answered,
                                            label: pick.title, mode: mode,
                                            rivals: seats.filter { $0.id != seat.id }.map(\.name),
                                            won: multi ? seat.id == winner : nil))
                if p.history.count > 200 { p.history.removeFirst(p.history.count - 200) }
            }
            if seat.score > best[pick.key, default: 0] { best[pick.key] = seat.score }
        }
    }
}

// MARK: - Partidas

enum GameMode: String, CaseIterable, Identifiable, Codable {
    case solo, turnos, duelo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .solo: "Solo"
        case .turnos: "Por turnos"
        case .duelo: "Duelo"
        }
    }
    var detail: String {
        switch self {
        case .solo: "10 preguntas para ti."
        case .turnos: "De 2 a 6 jugadores. Se pasan el iPad y cada uno contesta 5 preguntas."
        case .duelo: "Dos jugadores frente a frente, con el iPad en la mesa. La misma pregunta para los dos: gana el que acierte primero."
        }
    }
    var icon: String {
        switch self {
        case .solo: "person.fill"
        case .turnos: "person.3.fill"
        case .duelo: "bolt.horizontal.fill"
        }
    }
    var players: ClosedRange<Int> {
        switch self {
        case .solo: 1...1
        case .turnos: 2...6
        case .duelo: 2...2
        }
    }
}

struct Shown {
    let question: Question
    let options: [String]
    let correctIndex: Int

    init(_ q: Question) {
        let order = Array(q.options.indices).shuffled()
        question = q
        options = order.map { q.options[$0] }
        correctIndex = order.firstIndex(of: 0)!
    }

    var genre: Genre { question.scene.genre }
}

/// Lo que lleva cada jugador durante una partida.
struct Seat: Identifiable {
    let id: UUID
    let name: String
    let color: Int
    var score = 0
    var streak = 0
    var bestStreak = 0
    var correct = 0
    var answered = 0
    var answeredBy: [String: Int] = [:]
    var correctBy: [String: Int] = [:]

    init(_ p: Player) {
        id = p.id
        name = p.name
        color = p.color
    }

    mutating func mark(_ genre: Genre, right: Bool, gain: Int) {
        answered += 1
        answeredBy[genre.rawValue, default: 0] += 1
        if right {
            correct += 1
            correctBy[genre.rawValue, default: 0] += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            score += gain
        } else {
            streak = 0
        }
    }
}

enum Scoring {
    static let seconds = 15.0

    /// 100 por acertar, hasta 150 más por rapidez, y +10 % por cada acierto seguido.
    static func gain(timeLeft: Double, streak: Int) -> Int {
        let base = 100 + Int(timeLeft / seconds * 150)
        return Int(Double(base) * (1 + 0.1 * Double(max(0, streak - 1))))
    }
}

/// Partida solo o por turnos: cada pregunta le toca a un jugador.
@MainActor
final class Match: ObservableObject {
    let pick: Pick
    let mode: GameMode
    let items: [Shown]
    @Published private(set) var seats: [Seat]
    @Published private(set) var index = 0
    @Published private(set) var picked: Int?
    @Published private(set) var timeLeft = Scoring.seconds
    @Published private(set) var lastGain = 0
    @Published private(set) var finished = false
    /// Pantalla de «pásale el iPad a…» antes de cada pregunta.
    @Published private(set) var handoff: Bool

    private var timer: Timer?

    init(pick: Pick, mode: GameMode, players: [Player], pool: [Question]) {
        self.pick = pick
        self.mode = mode
        seats = players.map(Seat.init)
        let n = max(1, players.count)
        let perPlayer = min(n == 1 ? 10 : 5, pool.count / n)
        items = pool.shuffled().prefix(perPlayer * n).map(Shown.init)
        handoff = n > 1
    }

    var current: Shown? { index < items.count ? items[index] : nil }
    var seatIndex: Int { seats.isEmpty ? 0 : index % seats.count }
    var answered: Bool { picked != nil }
    var perPlayer: Int { items.count / max(1, seats.count) }
    var turn: Int { index / max(1, seats.count) + 1 }

    func start() { if !handoff { runTimer() } }

    func ready() {
        handoff = false
        runTimer()
    }

    private func runTimer() {
        timeLeft = Scoring.seconds
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard !answered, !finished, !handoff else { return }
        timeLeft = max(0, timeLeft - 0.1)
        if timeLeft <= 0 { choose(-1) }
    }

    /// -1 = se acabó el tiempo.
    func choose(_ option: Int) {
        guard !answered, let current else { return }
        picked = option
        timer?.invalidate()
        let right = option == current.correctIndex
        lastGain = right ? Scoring.gain(timeLeft: timeLeft, streak: seats[seatIndex].streak + 1) : 0
        seats[seatIndex].mark(current.genre, right: right, gain: lastGain)
    }

    func next() {
        guard answered else { return }
        if index + 1 >= items.count {
            finished = true
            timer?.invalidate()
        } else {
            index += 1
            picked = nil
            timeLeft = Scoring.seconds
            if seats.count > 1 { handoff = true } else { runTimer() }
        }
    }

    func stop() { timer?.invalidate() }
}

/// Duelo: dos jugadores, la misma pregunta, gana el primero que acierte.
@MainActor
final class Duel: ObservableObject {
    let pick: Pick
    let items: [Shown]
    @Published private(set) var seats: [Seat]
    @Published private(set) var index = 0
    @Published private(set) var picks: [Int?] = [nil, nil]
    @Published private(set) var winner: Int?
    @Published private(set) var resolved = false
    @Published private(set) var timeLeft = Scoring.seconds
    @Published private(set) var lastGain = 0
    @Published private(set) var finished = false

    private var timer: Timer?

    init(pick: Pick, players: [Player], pool: [Question]) {
        self.pick = pick
        seats = players.prefix(2).map(Seat.init)
        items = pool.shuffled().prefix(10).map(Shown.init)
    }

    var current: Shown? { index < items.count ? items[index] : nil }

    func start() {
        timeLeft = Scoring.seconds
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard !resolved, !finished else { return }
        timeLeft = max(0, timeLeft - 0.1)
        if timeLeft <= 0, let current {
            for i in seats.indices where picks[i] == nil { seats[i].mark(current.genre, right: false, gain: 0) }
            resolve()
        }
    }

    func choose(_ seat: Int, _ option: Int) {
        guard !resolved, picks[seat] == nil, let current else { return }
        picks[seat] = option
        if option == current.correctIndex {
            lastGain = Scoring.gain(timeLeft: timeLeft, streak: seats[seat].streak + 1)
            seats[seat].mark(current.genre, right: true, gain: lastGain)
            winner = seat
            resolve()
        } else {
            seats[seat].mark(current.genre, right: false, gain: 0)
            if picks.allSatisfy({ $0 != nil }) { resolve() }
        }
    }

    private func resolve() {
        resolved = true
        timer?.invalidate()
    }

    func next() {
        guard resolved else { return }
        if index + 1 >= items.count {
            finished = true
        } else {
            index += 1
            picks = [nil, nil]
            winner = nil
            resolved = false
            lastGain = 0
            start()
        }
    }

    func stop() { timer?.invalidate() }
}
