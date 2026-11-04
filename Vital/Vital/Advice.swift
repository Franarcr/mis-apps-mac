import Foundation

/// El consejo del día: frases hechas a partir de tus medidas de hoy, en el iPhone y sin internet.
/// Va de lo más importante (posible enfermedad) a lo menos; como mucho tres frases.
enum Advice {
    struct Tip: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let signal: Signal
    }

    @MainActor
    static func tips(for model: VitalModel) -> [Tip] {
        guard let today = model.today else { return [] }
        func signal(_ metric: Metric) -> Signal? {
            today[keyPath: metric.keyPath].map { metric.signal($0, base: model.baseline(metric.keyPath)?.mean) }
        }
        var tips: [Tip] = []

        let temperatureHigh = (today.wristTemperature ?? 0) - (model.baseline(\.wristTemperature)?.mean ?? .infinity) >= 0.5
        let bodyStressed = [Metric.hrv, .restingHR, .respiratory].contains { signal($0).map { $0 != .good } ?? false }
        if temperatureHigh && bodyStressed {
            tips.append(Tip(icon: "thermometer.sun.fill",
                            text: "La temperatura de tu muñeca subió y tu cuerpo muestra estrés: puede que estés incubando algo. Hoy prioriza descanso, agua y dormir temprano.",
                            signal: .poor))
        } else if signal(.hrv) == .poor || (signal(.hrv) == .fair && signal(.restingHR) != .good) {
            tips.append(Tip(icon: "waveform.path.ecg",
                            text: "Tu VFC está por debajo de lo normal: el cuerpo aún se está recuperando. Mejor un entrenamiento suave o movilidad.",
                            signal: signal(.hrv) ?? .fair))
        }
        if let oxygen = signal(.oxygen), oxygen != .good {
            tips.append(Tip(icon: "drop.fill",
                            text: "Tu SpO₂ al dormir fue más baja de lo habitual. Si se repite varias noches, coméntalo con tu médico.",
                            signal: oxygen))
        }
        if let breathing = signal(.breathing), breathing != .good {
            tips.append(Tip(icon: "zzz",
                            text: "Más alteraciones respiratorias de lo normal. El alcohol, cenar tarde, dormir boca arriba o la congestión las suben.",
                            signal: breathing))
        }
        if model.sleepDebt >= 5 * 3600 {
            tips.append(Tip(icon: "bed.double.fill",
                            text: "Llevas \(hours(model.sleepDebt)) de deuda de sueño esta semana. Acostarte 30 minutos antes unos días la va bajando.",
                            signal: model.sleepDebt >= 6 * 3600 ? .poor : .fair))
        } else if let bedtime = model.bedtime, bedtime.spread >= 60 {
            tips.append(Tip(icon: "clock.fill",
                            text: "Te acuestas a horas muy distintas (± \(Int(bedtime.spread)) min). Un horario regular mejora la calidad del sueño tanto como dormir más.",
                            signal: .fair))
        }
        if tips.isEmpty, let recovery = model.todayRecovery {
            tips.append(recovery.signal == .good
                ? Tip(icon: "figure.run", text: "Todo está en tu rango. Buen día para un entrenamiento exigente.", signal: .good)
                : Tip(icon: "checkmark.circle.fill", text: "Tus medidas están en tu rango. Entrena con normalidad, sin forzar.", signal: .good))
        }
        return Array(tips.prefix(3))
    }
}
