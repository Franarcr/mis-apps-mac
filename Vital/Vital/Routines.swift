import Foundation
import HealthKit
import SwiftData
import SwiftUI

// MARK: - Datos guardados (SwiftData, solo en el iPhone)

@Model
final class Routine {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine) var items: [RoutineItem] = []

    init(name: String) {
        self.name = name
        createdAt = .now
    }

    var sortedItems: [RoutineItem] { items.sorted { $0.order < $1.order } }
}

@Model
final class RoutineItem {
    var exerciseID: String
    var order: Int
    var sets: Int
    var repMin: Int
    var repMax: Int
    var restSeconds: Int
    /// Piramidal: cada serie con menos repeticiones y más peso (p. ej. 12-10-8-6).
    var pyramid: Bool = false
    var pyramidReps: String = "12,10,8,6"
    var routine: Routine?

    init(exerciseID: String, order: Int, sets: Int = 3, repMin: Int = 8, repMax: Int = 12, restSeconds: Int = 90) {
        self.exerciseID = exerciseID
        self.order = order
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.restSeconds = restSeconds
    }

    @MainActor var exercise: Exercise? { ExerciseCatalog.exercise(exerciseID) }

    /// Repeticiones objetivo de cada serie.
    var targetReps: [Int] {
        if pyramid {
            let reps = pyramidReps.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 0 }
            if !reps.isEmpty { return reps }
        }
        return Array(repeating: repMin, count: sets)
    }
}

/// Un ejercicio que no está en la base y creaste tú.
@Model
final class CustomExercise {
    var id: String
    var name: String
    var muscles: String          // separados por comas (claves de `Muscle`)
    var equipment: String        // clave de `Equipment`
    var compound: Bool
    var unilateral: Bool

    init(name: String, muscles: [Muscle], equipment: Equipment, compound: Bool, unilateral: Bool) {
        id = "propio-\(UUID().uuidString)"
        self.name = name
        self.muscles = muscles.map(\.rawValue).joined(separator: ",")
        self.equipment = equipment.rawValue
        self.compound = compound
        self.unilateral = unilateral
    }

    var asExercise: Exercise {
        Exercise(id: id, n: name, en: name, m: muscles.split(separator: ",").map(String.init), s: [], e: equipment,
                 c: "strength", l: "intermediate", k: compound ? "compound" : "isolation", f: nil, i: [], img: [], u: unilateral)
    }
}

/// Una serie hecha. El peso se guarda siempre en kg (0 si es sin peso).
@Model
final class SetLog {
    var exerciseID: String
    var date: Date
    var session: UUID
    var weight: Double
    var reps: Int
    /// Número de serie dentro de la sesión (0, 1, 2…), para comparar cada una con su objetivo.
    var index: Int = 0

    init(exerciseID: String, date: Date, session: UUID, weight: Double, reps: Int, index: Int) {
        self.exerciseID = exerciseID
        self.date = date
        self.session = session
        self.weight = weight
        self.reps = reps
        self.index = index
    }
}

// MARK: - Perfil

enum TrainingLevel: String, CaseIterable, Identifiable {
    case novice, intermediate, advanced
    var id: String { rawValue }
    var name: String {
        switch self {
        case .novice: "Principiante (menos de 1 año)"
        case .intermediate: "Intermedio (1 a 3 años)"
        case .advanced: "Avanzado (más de 3 años)"
        }
    }
    var factor: Double {
        switch self {
        case .novice: 0.6
        case .intermediate: 1.0
        case .advanced: 1.35
        }
    }
}

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }

    func show(_ kg: Double) -> Double { self == .kg ? kg : kg * 2.20462 }
    func store(_ value: Double) -> Double { self == .kg ? value : value / 2.20462 }
    func format(_ kg: Double) -> String {
        let v = show(kg)
        return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v)) \(rawValue)" : String(format: "%.1f %@", v, rawValue)
    }
}

/// Peso corporal y sexo desde Salud, para la primera estimación de cargas.
enum BodyProfile {
    private static let store = HKHealthStore()

    static func read() async -> (weight: Double?, female: Bool?) {
        let massType = HKQuantityType(.bodyMass)
        try? await store.requestAuthorization(toShare: [], read: [massType, HKCharacteristicType(.biologicalSex)])
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: massType)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        let weight = (try? await descriptor.result(for: store))?.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
        let sex = try? store.biologicalSex().biologicalSex
        return (weight, sex == .female ? true : sex == .male ? false : nil)
    }
}

// MARK: - Cargas

/// Propone el peso de cada ejercicio.
/// - Primera vez: estima tu 1RM con tu peso corporal, sexo y nivel (proporciones típicas por tipo de ejercicio)
///   y propone un peso que te deje 2 repeticiones en reserva.
/// - Después: doble progresión con lo que anotaste. Si completaste todas las series en el máximo de repeticiones,
///   sube el peso; si alguna quedó por debajo del mínimo, lo baja un 5 %; si no, mismo peso y busca más repeticiones.
/// - Con recuperación en rojo, propone un 10 % menos (día de descarga).
enum LoadAdvisor {
    struct Suggestion {
        /// Peso (kg; nil = sin peso) y repeticiones de cada serie.
        let plan: [(weight: Double?, reps: Int)]
        let reason: String
        let isEstimate: Bool
    }

    @MainActor static func suggest(for item: RoutineItem, history: [SetLog], bodyWeight: Double, female: Bool,
                        level: TrainingLevel, recovery: Recovery?) -> Suggestion {
        let targets = item.targetReps
        guard let exercise = item.exercise else {
            return Suggestion(plan: targets.map { (nil, $0) }, reason: "", isEstimate: true)
        }
        let increment = self.increment(exercise.equipment)

        // Última sesión de este ejercicio, en el orden en que se hicieron las series.
        let last = history.filter { $0.exerciseID == item.exerciseID }.sorted { $0.date > $1.date }
        let lastSession = (last.first.map { first in last.filter { $0.session == first.session } } ?? [])
            .sorted { $0.index < $1.index }

        var plan: [(weight: Double?, reps: Int)]
        var reason: String
        var estimate = false

        if !exercise.equipment.isWeighted || (!lastSession.isEmpty && lastSession.allSatisfy { $0.weight == 0 }) {
            // Sin peso: se progresa en repeticiones.
            if let best = lastSession.map(\.reps).max() {
                plan = targets.map { (nil, max($0, best + 1)) }
                reason = "La última vez tu mejor serie fue de \(best): intenta una más."
            } else {
                plan = targets.map { (nil, $0) }
                reason = "Sin peso: cuenta repeticiones."
                estimate = true
            }
        } else if item.pyramid {
            // Pirámide: todo sale de tu 1RM estimado, con 2 repeticiones en reserva en cada serie.
            var oneRM: Double
            if !lastSession.isEmpty {
                oneRM = lastSession.map { epley($0.weight, $0.reps) }.max() ?? 0
                let missed = zip(lastSession, targets).contains { $0.reps <= $1 - 2 }
                let completed = lastSession.count >= targets.count && !zip(lastSession, targets).contains { $0.reps < $1 }
                if completed {
                    oneRM *= 1.025
                    reason = "Completaste toda la pirámide: sube un poco en cada serie."
                } else if missed {
                    oneRM *= 0.95
                    reason = "Alguna serie se quedó 2 o más repeticiones corta: baja un poco."
                } else {
                    reason = "Casi completa: mismo peso, busca todas las repeticiones."
                }
            } else if let estimated = estimatedOneRM(exercise, bodyWeight: bodyWeight, female: female, level: level) {
                oneRM = estimated
                reason = "Estimado por tu peso y nivel. Anota lo que hagas: la próxima vez se ajusta solo."
                estimate = true
            } else {
                return Suggestion(plan: targets.map { (nil, $0) }, reason: "Elige el peso de cada serie; la próxima vez se calcula solo.", isEstimate: true)
            }
            var previous = 0.0
            plan = targets.map { reps in
                // Cada serie al menos tan pesada como la anterior.
                let w = max(previous, max(increment, round(oneRM / (1 + Double(reps + 2) / 30), to: increment)))
                previous = w
                return (w, reps)
            }
        } else {
            // Series fijas: doble progresión.
            let target = item.repMin
            var weight: Double?
            var reps = target
            if !lastSession.isEmpty {
                let used = lastSession.map(\.weight).max() ?? 0
                let atUsed = lastSession.filter { $0.weight >= used - 0.01 }
                if atUsed.count >= item.sets && atUsed.allSatisfy({ $0.reps >= item.repMax }) {
                    weight = used + increment
                    reason = "Completaste todas las series en \(item.repMax): sube el peso."
                } else if atUsed.contains(where: { $0.reps < item.repMin }) {
                    weight = round(used * 0.95, to: increment)
                    reason = "Alguna serie quedó bajo \(item.repMin) repeticiones: baja un poco."
                } else {
                    weight = used
                    reps = min(item.repMax, (atUsed.map(\.reps).min() ?? target) + 1)
                    reason = "Mismo peso; busca una repetición más por serie."
                }
            } else if let oneRM = estimatedOneRM(exercise, bodyWeight: bodyWeight, female: female, level: level) {
                weight = max(increment, round(oneRM / (1 + Double(target + 2) / 30), to: increment))
                reason = "Estimado por tu peso y nivel. Anota lo que hagas: la próxima vez se ajusta solo."
                estimate = true
            } else {
                reason = "Elige un peso con el que llegues a \(target) repeticiones con margen."
                estimate = true
            }
            plan = Array(repeating: (weight, reps), count: item.sets)
        }

        if recovery?.signal == .poor, plan.contains(where: { $0.weight != nil }) {
            plan = plan.map { ($0.weight.map { round($0 * 0.9, to: increment) }, $0.reps) }
            reason += " Recuperación baja: 10 % menos hoy."
        }
        return Suggestion(plan: plan, reason: reason, isEstimate: estimate)
    }

    /// 1RM estimado (Epley): el peso que podrías levantar una vez.
    static func epley(_ weight: Double, _ reps: Int) -> Double { weight * (1 + Double(reps) / 30) }

    private static func estimatedOneRM(_ exercise: Exercise, bodyWeight: Double, female: Bool, level: TrainingLevel) -> Double? {
        guard let ratio = ratio(for: exercise) else { return nil }
        let lower = exercise.primaryMuscles.contains { $0.isLower }
        let sex = female ? (lower ? 0.8 : 0.65) : 1
        // Las mancuernas y kettlebells ya van por unidad; barra, máquina o polea a un lado mueven más o menos la mitad.
        let side = exercise.isUnilateral && ![.dumbbell, .kettlebells].contains(exercise.equipment) ? 0.5 : 1
        return bodyWeight * ratio * level.factor * sex * side
    }

    /// 1RM aproximado como proporción del peso corporal (hombre intermedio). Mancuernas y kettlebells: por unidad.
    private static func ratio(for exercise: Exercise) -> Double? {
        let muscles = Set(exercise.m)
        let legs = !muscles.isDisjoint(with: ["quadriceps", "glutes", "hamstrings", "lower back"])
        let chest = muscles.contains("chest")
        let shoulders = muscles.contains("shoulders")
        let back = !muscles.isDisjoint(with: ["lats", "middle back", "traps"])
        let compound = exercise.isCompound
        let name = exercise.en.lowercased()

        switch exercise.equipment {
        case .barbell:
            if name.contains("deadlift") { return 1.5 }
            if compound && legs { return 1.25 }
            if compound && chest { return 0.9 }
            if compound && shoulders { return 0.6 }
            if compound && back { return 0.8 }
            if muscles.contains("calves") { return 1.0 }
            return 0.35
        case .ezBar:
            return compound ? 0.5 : 0.35
        case .dumbbell:
            if compound && chest { return 0.32 }
            if compound && legs { return 0.25 }
            if compound && back { return 0.3 }
            if compound && shoulders { return 0.22 }
            if shoulders { return 0.07 }
            return 0.13
        case .kettlebells:
            return compound ? 0.25 : 0.12
        case .machine:
            if name.contains("leg press") { return 2.0 }
            if compound && legs { return 1.3 }
            if compound { return 0.8 }
            return legs ? 0.5 : 0.35
        case .cable:
            return compound ? 0.6 : 0.2
        case .medicineBall:
            return 0.05
        default:
            return nil
        }
    }

    static func increment(_ equipment: Equipment) -> Double {
        switch equipment {
        case .dumbbell, .kettlebells: 2
        case .medicineBall: 1
        default: 2.5
        }
    }

    static func round(_ value: Double, to step: Double) -> Double { (value / step).rounded() * step }
}
