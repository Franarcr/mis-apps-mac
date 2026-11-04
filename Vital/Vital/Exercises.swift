import Foundation

/// Un ejercicio de free-exercise-db (dominio público), con el nombre traducido al español.
struct Exercise: Decodable, Identifiable, Hashable {
    let id: String
    let n: String            // nombre en español
    let en: String           // nombre original, para buscar también en inglés
    let m: [String]          // músculos principales
    let s: [String]          // músculos secundarios
    let e: String            // equipo
    let c: String            // categoría (strength, stretching…)
    let l: String            // nivel
    let k: String?           // compound / isolation
    let f: String?           // push / pull / static
    let i: [String]          // instrucciones (en inglés)
    let img: [String]
    var u: Bool? = nil       // unilateral (solo en los ejercicios propios)

    var name: String { n }
    var isCustom: Bool { id.hasPrefix("propio-") }
    /// A una pierna o un brazo: la carga de barra, máquina o polea es más o menos la mitad.
    var isUnilateral: Bool {
        if let u { return u }
        let name = en.lowercased()
        return ["one-arm", "one arm", "single-arm", "single arm", "one-leg", "one leg", "single-leg", "single leg", "one-legged"]
            .contains { name.contains($0) }
    }
    var isCompound: Bool { k == "compound" }
    var equipment: Equipment { Equipment(rawValue: e) ?? .other }
    var primaryMuscles: [Muscle] { m.compactMap(Muscle.init(rawValue:)) }
    var secondaryMuscles: [Muscle] { s.compactMap(Muscle.init(rawValue:)) }
    var imageURLs: [URL] {
        img.compactMap { URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\($0)") }
    }
    var categoryName: String {
        ["strength": "Fuerza", "stretching": "Estiramiento", "plyometrics": "Pliometría", "powerlifting": "Powerlifting",
         "olympic weightlifting": "Halterofilia", "strongman": "Strongman", "cardio": "Cardio"][c] ?? c
    }
    var levelName: String { ["beginner": "Principiante", "intermediate": "Intermedio", "expert": "Avanzado"][l] ?? l }
}

enum Muscle: String, CaseIterable, Identifiable {
    case chest, shoulders, triceps, biceps, forearms, lats, middleBack = "middle back", lowerBack = "lower back", traps
    case abdominals, quadriceps, hamstrings, glutes, calves, adductors, abductors, neck

    var id: String { rawValue }
    var name: String {
        switch self {
        case .chest: "Pecho"
        case .shoulders: "Hombros"
        case .triceps: "Tríceps"
        case .biceps: "Bíceps"
        case .forearms: "Antebrazos"
        case .lats: "Dorsales"
        case .middleBack: "Espalda media"
        case .lowerBack: "Lumbares"
        case .traps: "Trapecios"
        case .abdominals: "Abdominales"
        case .quadriceps: "Cuádriceps"
        case .hamstrings: "Isquiotibiales"
        case .glutes: "Glúteos"
        case .calves: "Pantorrillas"
        case .adductors: "Aductores"
        case .abductors: "Abductores"
        case .neck: "Cuello"
        }
    }
    var isLower: Bool { [.quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors, .lowerBack].contains(self) }
}

enum Equipment: String, CaseIterable, Identifiable {
    case bodyOnly = "body only", dumbbell, barbell, machine, cable, ezBar = "e-z curl bar", kettlebells, bands
    case medicineBall = "medicine ball", exerciseBall = "exercise ball", foamRoll = "foam roll", other

    var id: String { rawValue }
    var name: String {
        switch self {
        case .bodyOnly: "Peso corporal"
        case .dumbbell: "Mancuernas"
        case .barbell: "Barra"
        case .machine: "Máquina"
        case .cable: "Polea"
        case .ezBar: "Barra Z"
        case .kettlebells: "Kettlebell"
        case .bands: "Bandas"
        case .medicineBall: "Balón medicinal"
        case .exerciseBall: "Fitball"
        case .foamRoll: "Rodillo"
        case .other: "Otro"
        }
    }
    var icon: String {
        switch self {
        case .bodyOnly: "figure.strengthtraining.functional"
        case .dumbbell, .kettlebells: "dumbbell.fill"
        case .barbell, .ezBar: "figure.strengthtraining.traditional"
        case .machine: "gearshape.2.fill"
        case .cable: "cable.connector"
        case .bands: "point.topleft.down.to.point.bottomright.curvepath"
        case .medicineBall, .exerciseBall: "circle.fill"
        case .foamRoll: "cylinder.fill"
        case .other: "ellipsis.circle"
        }
    }
    /// Si se le pone peso (el resto se cuenta solo en repeticiones).
    var isWeighted: Bool { ![.bodyOnly, .bands, .exerciseBall, .foamRoll, .other].contains(self) }
}

/// Los 876 ejercicios, cargados una sola vez desde la app.
enum ExerciseCatalog {
    static let all: [Exercise] = {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Exercise].self, from: data) else { return [] }
        return list.sorted { $0.n.localizedCompare($1.n) == .orderedAscending }
    }()

    static let byID: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Los ejercicios que creaste tú (se guardan con SwiftData; las pantallas los copian aquí).
    @MainActor static var custom: [Exercise] = []

    @MainActor static func exercise(_ id: String) -> Exercise? {
        byID[id] ?? custom.first { $0.id == id }
    }

    @MainActor static func search(_ text: String, muscle: Muscle?, equipment: Equipment?, includeStretching: Bool) -> [Exercise] {
        filter(custom, text, muscle, equipment, includeStretching) + filter(all, text, muscle, equipment, includeStretching)
    }

    private static func filter(_ list: [Exercise], _ text: String, _ muscle: Muscle?, _ equipment: Equipment?, _ includeStretching: Bool) -> [Exercise] {
        let words = tokens(text).filter { !stopWords.contains($0) }
        func matches(_ haystack: [String]) -> Bool {
            words.allSatisfy { word in
                (synonyms[word] ?? [word]).contains { option in haystack.contains { $0.hasPrefix(option) } }
            }
        }
        var byName: [Exercise] = [], byOther: [Exercise] = []
        for ex in list {
            if !includeStretching && ex.c == "stretching" { continue }
            if let muscle, !ex.m.contains(muscle.rawValue) { continue }
            if let equipment, ex.e != equipment.rawValue { continue }
            guard !words.isEmpty else { byName.append(ex); continue }
            // Primero los que lo dicen en el nombre; después los que coinciden por músculo o equipo.
            if matches(tokens(ex.n + " " + ex.en)) {
                byName.append(ex)
            } else if matches(tokens(([ex.n, ex.en, ex.equipment.name] + (ex.primaryMuscles + ex.secondaryMuscles).map(\.name))
                .joined(separator: " "))) {
                byOther.append(ex)
            }
        }
        return byName + byOther
    }

    /// Palabras sin tildes, en minúscula y en singular («Elevaciones» → «elevacion»), para que el plural
    /// o una tilde olvidada no dejen fuera un ejercicio.
    private static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { word in
                var w = String(word)
                if w.count > 4 && w.hasSuffix("ones") { w.removeLast(2) }
                else if w.count > 3 && w.hasSuffix("s") { w.removeLast() }
                return w
            }
    }

    private static let stopWords: Set<String> = ["de", "con", "a", "en", "la", "el", "al", "y", "para", "del", "lo"]

    /// Nombres de gimnasio que no coinciden con los de la base (ya en singular y sin tildes).
    private static let synonyms: [String: [String]] = [
        "pantorrilla": ["pantorrilla", "talon", "gemelo", "calf"],
        "gemelo": ["gemelo", "talon", "pantorrilla"],
        "femoral": ["femoral", "isquio", "hamstring"],
        "isquio": ["isquio", "femoral"],
        "cuadricep": ["cuadricep", "quad"],
        "jalon": ["jalon", "pulldown"],
        "polea": ["polea", "cable"],
        "dominada": ["dominada", "pull", "chin"],
        "fondo": ["fondo", "dip"],
        "abdominal": ["abdominal", "crunch"],
        "abdomen": ["abdominal", "crunch"],
        "espalda": ["espalda", "dorsal", "remo"],
        "hombro": ["hombro", "deltoide"],
        "deltoide": ["deltoide", "hombro"],
        "gluteo": ["gluteo", "hip", "cadera"],
        "pecho": ["pecho", "banca", "pectoral"],
        "pectoral": ["pecho", "pectoral"],
        "sentadilla": ["sentadilla", "squat"],
        "zancada": ["zancada", "lunge", "desplante"],
        "desplante": ["zancada", "desplante", "lunge"],
        "maquina": ["maquina", "machine", "smith"],
        "mancuerna": ["mancuerna", "dumbbell"],
        "barra": ["barra", "barbell"],
        "elevacion": ["elevacion", "raise"],
    ]
}
