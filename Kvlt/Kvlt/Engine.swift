import SwiftUI

enum Kvlt {
    static let black = Color(red: 0.04, green: 0.03, blue: 0.03)
    static let panel = Color(red: 0.10, green: 0.08, blue: 0.08)
    static let blood = Color(red: 0.70, green: 0.07, blue: 0.12)
    static let bone = Color(red: 0.91, green: 0.88, blue: 0.83)
    static let ash = Color(red: 0.55, green: 0.52, blue: 0.50)
    static let good = Color(red: 0.30, green: 0.62, blue: 0.36)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .serif) }
}

/// Rangos según los puntos acumulados de todas las rondas.
struct Rank {
    let name: String
    let from: Int

    static let all = [
        Rank(name: "Poser", from: 0),
        Rank(name: "Headbanger", from: 2_000),
        Rank(name: "Tape trader", from: 6_000),
        Rank(name: "Underground", from: 12_000),
        Rank(name: "True kvlt", from: 25_000),
    ]

    static func of(_ points: Int) -> Rank { all.last { points >= $0.from } ?? all[0] }
    static func next(_ points: Int) -> Rank? { all.first { $0.from > points } }
}

/// Puntos guardados y preguntas propias.
@MainActor
final class Store: ObservableObject {
    @Published var totalPoints: Int { didSet { defaults.set(totalPoints, forKey: "puntosTotales") } }
    @Published var best: [String: Int] { didSet { defaults.set(best, forKey: "mejores") } }
    @Published var custom: [Question] = [] { didSet { saveCustom() } }

    private let defaults = UserDefaults.standard
    private var customURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mis-preguntas.json")
    }

    init() {
        totalPoints = defaults.integer(forKey: "puntosTotales")
        best = defaults.dictionary(forKey: "mejores") as? [String: Int] ?? [:]
        if let data = try? Data(contentsOf: customURL), let list = try? JSONDecoder().decode([Question].self, from: data) {
            custom = list
        }
    }

    private func saveCustom() {
        if let data = try? JSONEncoder().encode(custom) { try? data.write(to: customURL, options: .atomic) }
    }

    func questions(for scene: MetalScene?) -> [Question] {
        let all = builtInQuestions + custom
        guard let scene else { return all }
        return all.filter { $0.scene == scene }
    }

    func record(_ score: Int, scene: MetalScene?) {
        totalPoints += score
        let key = scene?.rawValue ?? "todas"
        if score > best[key, default: 0] { best[key] = score }
    }
}

/// Una ronda de hasta 10 preguntas con 15 segundos cada una.
@MainActor
final class Round: ObservableObject {
    struct Shown {
        let question: Question
        let options: [String]
        let correctIndex: Int
    }

    static let seconds = 15.0

    let scene: MetalScene?
    @Published private(set) var items: [Shown] = []
    @Published private(set) var index = 0
    @Published private(set) var picked: Int?
    @Published private(set) var timeLeft = seconds
    @Published private(set) var score = 0
    @Published private(set) var streak = 0
    @Published private(set) var bestStreak = 0
    @Published private(set) var correct = 0
    @Published private(set) var lastGain = 0
    @Published private(set) var finished = false

    private var timer: Timer?

    init(scene: MetalScene?, pool: [Question]) {
        self.scene = scene
        items = pool.shuffled().prefix(10).map { q in
            let order = Array(q.options.indices).shuffled()
            return Shown(question: q, options: order.map { q.options[$0] }, correctIndex: order.firstIndex(of: 0)!)
        }
    }

    var current: Shown? { index < items.count ? items[index] : nil }
    var answered: Bool { picked != nil }

    func start() {
        timeLeft = Self.seconds
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard !answered, !finished else { return }
        timeLeft = max(0, timeLeft - 0.1)
        if timeLeft <= 0 { choose(-1) }
    }

    /// -1 = se acabó el tiempo.
    func choose(_ option: Int) {
        guard !answered, let current else { return }
        picked = option
        timer?.invalidate()
        if option == current.correctIndex {
            streak += 1
            bestStreak = max(bestStreak, streak)
            correct += 1
            // 100 por acertar, hasta 150 más por rapidez, y +10 % por cada acierto seguido.
            let base = 100 + Int(timeLeft / Self.seconds * 150)
            lastGain = Int(Double(base) * (1 + 0.1 * Double(streak - 1)))
            score += lastGain
        } else {
            streak = 0
            lastGain = 0
        }
    }

    func next() {
        guard answered else { return }
        if index + 1 >= items.count {
            finished = true
            timer?.invalidate()
        } else {
            index += 1
            picked = nil
            start()
        }
    }

    func stop() { timer?.invalidate() }
}
