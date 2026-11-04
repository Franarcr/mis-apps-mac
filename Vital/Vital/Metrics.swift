import SwiftUI

/// Semáforo: verde, naranja o rojo.
enum Signal {
    case good, fair, poor

    var color: Color {
        switch self {
        case .good: .green
        case .fair: .orange
        case .poor: .red
        }
    }
}

/// Las medidas del reloj que se muestran en tarjetas, con su semáforo respecto a tu base.
enum Metric: String, CaseIterable, Identifiable {
    case hrv, restingHR, respiratory, oxygen, temperature, breathing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: "VFC"
        case .restingHR: "FC en reposo"
        case .respiratory: "Respiración"
        case .oxygen: "SpO₂"
        case .temperature: "Temp. muñeca"
        case .breathing: "Alt. respiratorias"
        }
    }

    var icon: String {
        switch self {
        case .hrv: "waveform.path.ecg"
        case .restingHR: "heart.fill"
        case .respiratory: "lungs.fill"
        case .oxygen: "drop.fill"
        case .temperature: "thermometer.medium"
        case .breathing: "zzz"
        }
    }

    var unit: String {
        switch self {
        case .hrv: "ms"
        case .restingHR: "lpm"
        case .respiratory: "rpm"
        case .oxygen: "%"
        case .temperature: "°C"
        case .breathing: "/h"
        }
    }

    var keyPath: KeyPath<DayData, Double?> {
        switch self {
        case .hrv: \.hrv
        case .restingHR: \.restingHR
        case .respiratory: \.respiratoryRate
        case .oxygen: \.oxygen
        case .temperature: \.wristTemperature
        case .breathing: \.breathingDisturbances
        }
    }

    var explanation: String {
        switch self {
        case .hrv: "Variabilidad de la frecuencia cardiaca durante el sueño. Más alta que tu normal suele indicar buena recuperación."
        case .restingHR: "Pulso en reposo del día. Si sube varios latidos sobre tu normal puede ser cansancio, estrés, alcohol o el inicio de una enfermedad."
        case .respiratory: "Respiraciones por minuto mientras duermes. Es muy estable: subir más de 1 sobre tu normal es una señal a vigilar."
        case .oxygen: "Saturación de oxígeno durante el sueño. Lo normal es 95 % o más."
        case .temperature: "Diferencia de la temperatura de tu muñeca al dormir con tu normal. Más de medio grado arriba puede anunciar un resfriado."
        case .breathing: "Pausas o interrupciones breves de la respiración por hora de sueño. El reloj avisa de posible apnea si se mantienen altas durante un mes. El alcohol, dormir boca arriba o la congestión las suben."
        }
    }

    /// Lo que se muestra en grande: la temperatura, como diferencia con la base; el resto, el valor.
    func display(_ value: Double, base: Double?) -> String {
        switch self {
        case .hrv, .restingHR, .oxygen: "\(Int(value.rounded()))"
        case .respiratory, .breathing: String(format: "%.1f", value)
        case .temperature: base.map { String(format: "%+.1f", value - $0) } ?? String(format: "%.1f", value)
        }
    }

    /// Texto bajo el número.
    func detail(_ value: Double, base: Double?) -> String? {
        switch self {
        case .oxygen:
            return value >= 95 ? "Normal" : "Más baja de lo habitual"
        case .temperature:
            guard let base else { return "Calibrando tu base" }
            return abs(value - base) < 0.5 ? "Dentro de tu rango" : "Fuera de tu rango"
        case .hrv:
            return base.map { String(format: "%+.0f %% vs. tu base", (value - $0) / $0 * 100) }
        case .restingHR:
            return base.map { String(format: "%+.0f vs. tu base", value - $0) }
        case .respiratory, .breathing:
            return base.map { String(format: "%+.1f vs. tu base", value - $0) }
        }
    }

    /// Verde si está en tu rango, naranja si se aleja un poco, rojo si se aleja mucho.
    func signal(_ value: Double, base: Double?) -> Signal {
        if self == .oxygen {
            return value >= 95 ? .good : value >= 92 ? .fair : .poor
        }
        guard let base else { return .good }
        let change = value - base
        switch self {
        case .hrv:
            let percent = change / base * 100
            return percent >= -5 ? .good : percent >= -15 ? .fair : .poor
        case .restingHR:
            return change <= 1 ? .good : change <= 4 ? .fair : .poor
        case .respiratory:
            return change <= 0.5 ? .good : change <= 1.5 ? .fair : .poor
        case .temperature:
            return abs(change) < 0.5 ? .good : abs(change) < 1 ? .fair : .poor
        case .breathing:
            return change <= 1.5 ? .good : change <= 4 ? .fair : .poor
        case .oxygen:
            return .good
        }
    }
}

extension SleepNight {
    var signal: Signal { asleep >= 7 * 3600 ? .good : asleep >= 6 * 3600 ? .fair : .poor }
}
