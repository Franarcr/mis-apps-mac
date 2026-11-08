import Foundation

/// Lo que pasa en el cuerpo según las horas desde la última comida.
/// Son rangos aproximados: dependen de lo que comiste, de cuánto te moviste y de cada persona.
enum FastingPhase: Int, CaseIterable, Identifiable {
    case digestion, glycogen, fatSwitch, ketosis, prolonged
    var id: Int { rawValue }

    var startHour: Double {
        switch self {
        case .digestion: 0
        case .glycogen: 4
        case .fatSwitch: 12
        case .ketosis: 18
        case .prolonged: 24
        }
    }

    var title: String {
        switch self {
        case .digestion: "Digestión"
        case .glycogen: "Glucógeno bajando"
        case .fatSwitch: "Cambio a grasa"
        case .ketosis: "Cetosis leve"
        case .prolonged: "Ayuno prolongado"
        }
    }

    var icon: String {
        switch self {
        case .digestion: "fork.knife"
        case .glycogen: "arrow.down.circle"
        case .fatSwitch: "flame"
        case .ketosis: "bolt.heart"
        case .prolonged: "exclamationmark.triangle"
        }
    }

    var explanation: String {
        switch self {
        case .digestion: "Absorbes lo que comiste; la glucosa y la insulina están altas."
        case .glycogen: "La insulina baja y el hígado va soltando glucosa de sus reservas (glucógeno)."
        case .fatSwitch: "Con el glucógeno más bajo, usas más grasa y aparecen las primeras cetonas."
        case .ketosis: "Las cetonas suben más. El hambre suele venir en olas y pasar."
        case .prolonged: "Más de un día sin comer. Si lo haces seguido, coméntalo con tu médico."
        }
    }

    static func at(hours: Double) -> FastingPhase {
        allCases.last { hours >= $0.startHour } ?? .digestion
    }
}
