import Charts
import HealthKit
import SwiftUI

/// Estrés y energía del día, al estilo de Bevel (su fórmula no es pública; esta es la nuestra).
///
/// - **Estrés (5–100), cada 15 minutos, solo estando quieto:** en calma ronda 15; sube con el pulso sobre el de
///   reposo y, un poco, si la VFC cae bajo lo normal de día. No cuentan como estrés: entrenar, moverse (pasos)
///   ni la hora y media siguiente a un entrenamiento, en la que el pulso sigue alto mientras te recuperas.
/// - **Energía (0–100):** al despertar parte de tu recuperación; se gasta un poco por estar despierto, más con
///   el entrenamiento (según su esfuerzo), el movimiento y el estrés, y se recarga en los ratos de calma.
enum StressEnergy {
    enum Kind { case rest, moving, recovering, workout }

    struct Bucket: Identifiable {
        var id: Date { start }
        let start: Date
        let kind: Kind
        let stress: Double?      // solo en reposo y con pulso medido
    }

    struct Result {
        let buckets: [Bucket]
        let energy: [(date: Date, value: Double)]

        private var restValues: [Double] { buckets.filter { $0.kind == .rest }.compactMap(\.stress) }
        var dayStress: Int? { restValues.isEmpty ? nil : Int((restValues.reduce(0, +) / Double(restValues.count)).rounded()) }
        var currentStress: Int? { buckets.last(where: { $0.kind == .rest && $0.stress != nil })?.stress.map { Int($0.rounded()) } }
        var currentEnergy: Int? { energy.last.map { Int($0.value.rounded()) } }
        /// Minutos del día en cada nivel de estrés (bajo, medio, alto).
        var minutesByLevel: (low: Int, medium: Int, high: Int) {
            (restValues.filter { $0 < 30 }.count * 15, restValues.filter { (30..<60).contains($0) }.count * 15,
             restValues.filter { $0 >= 60 }.count * 15)
        }
    }

    static let bucket: TimeInterval = 15 * 60
    /// Pasos en 15 minutos a partir de los que se cuenta como movimiento, no como estrés.
    static let movingSteps = 120.0

    static func stressSignal(_ v: Double) -> Signal { v < 30 ? .good : v < 60 ? .fair : .poor }
    static func energySignal(_ v: Double) -> Signal { v >= 60 ? .good : v >= 30 ? .fair : .poor }

    static func compute(heartRate: [(date: Date, bpm: Double, sedentary: Bool)], hrv: [(date: Date, ms: Double)],
                        steps: [(date: Date, count: Double)],
                        restingHR: Double, maximumHR: Double, baselineHRV: Double?,
                        wake: Date?, recovery: Int?, workouts: [Workout], now: Date = .now) -> Result {
        let calendar = Calendar.current
        let start = wake ?? calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now)!
        let reserve = max(20, maximumHR - restingHR)
        // La VFC de día es más baja que la de la noche (tu base): se compara con ~70 % de ella.
        let dayHRV = baselineHRV.map { $0 * 0.7 }
        var buckets: [Bucket] = []
        var time = start
        while time < now {
            let end = time.addingTimeInterval(bucket)
            let samples = heartRate.filter { $0.date >= time && $0.date < end }
            let stepCount = steps.filter { $0.date >= time && $0.date < end }.map(\.count).reduce(0, +)
            let kind: Kind
            if workouts.contains(where: { $0.start < end && $0.end > time }) {
                kind = .workout
            } else if workouts.contains(where: { $0.end <= time && time.timeIntervalSince($0.end) < 90 * 60 }) {
                kind = .recovering
            } else if stepCount >= movingSteps || samples.filter({ !$0.sedentary }).count * 2 > samples.count {
                kind = .moving
            } else {
                kind = .rest
            }
            var stress: Double?
            if kind == .rest, !samples.isEmpty {
                let hr = samples.map(\.bpm).reduce(0, +) / Double(samples.count)
                // Pulso: en tu reposo, 15 (calma); con reposo + 40 % de tu reserva cardiaca, 100.
                var s = 0.15 + 0.85 * (hr - restingHR) / (0.4 * reserve)
                // VFC cercana (±90 min): por debajo de lo normal de día suma estrés; por encima, resta.
                if let reference = dayHRV,
                   let near = hrv.min(by: { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }),
                   abs(near.date.timeIntervalSince(time)) < 90 * 60 {
                    s += 0.15 * max(-1, min(1, 1 - near.ms / reference))
                }
                stress = min(100, max(5, s * 100))
            }
            buckets.append(Bucket(start: time, kind: kind, stress: stress))
            time = end
        }

        // Energía: parte de la recuperación de la noche.
        var energy = 35 + 0.65 * Double(recovery ?? 50)
        var curve: [(Date, Double)] = [(start, energy)]
        for b in buckets {
            let end = b.start.addingTimeInterval(bucket)
            var delta = -0.35                                  // estar despierto gasta ~1,4 por hora
            switch b.kind {
            case .workout:
                // Un entrenamiento gasta hasta ~20 puntos según su esfuerzo (0–100), repartidos en su duración.
                for w in workouts where w.start < end && w.end > b.start {
                    let overlap = min(end, w.end).timeIntervalSince(max(b.start, w.start))
                    delta -= Double(TrainingModel.strain(w.load)) * 0.2 * overlap / max(60, w.duration)
                }
            case .moving:
                delta -= 0.3
            case .recovering:
                break
            case .rest:
                if let s = b.stress {
                    delta -= max(0, s - 30) / 100 * 1.2        // el estrés (desde 30) gasta
                    if s < 30 { delta += 0.8 }                 // la calma recarga un poco
                }
            }
            energy = min(100, max(0, energy + delta))
            curve.append((min(end, now), energy))
        }
        return Result(buckets: buckets, energy: curve)
    }
}

/// Pulso de hoy (con su contexto de movimiento) y VFC del día, de Salud.
enum StressReader {
    private static let store = HKHealthStore()

    static func read() async -> (heartRate: [(date: Date, bpm: Double, sedentary: Bool)], hrv: [(date: Date, ms: Double)],
                                 steps: [(date: Date, count: Double)]) {
        let from = Calendar.current.startOfDay(for: .now)
        let range = HKQuery.predicateForSamples(withStart: from, end: .now)
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let hrDescriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: range)],
                                                   sortDescriptors: [SortDescriptor(\.startDate)])
        let hrvDescriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.heartRateVariabilitySDNN), predicate: range)],
                                                    sortDescriptors: [SortDescriptor(\.startDate)])
        let hr = ((try? await hrDescriptor.result(for: store)) ?? []).map { sample in
            // El reloj marca si estabas quieto (1) o en movimiento (2) al medir.
            let context = (sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber)?.intValue ?? 0
            return (sample.startDate, sample.quantity.doubleValue(for: perMinute), context != 2)
        }
        let hrv = ((try? await hrvDescriptor.result(for: store)) ?? []).map {
            ($0.startDate, $0.quantity.doubleValue(for: .secondUnit(with: .milli)))
        }
        let stepType = HKQuantityType(.stepCount)
        try? await store.requestAuthorization(toShare: [], read: [stepType])
        let stepDescriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: stepType, predicate: range)],
                                                     sortDescriptors: [SortDescriptor(\.startDate)])
        // Solo los pasos del reloj: el iPhone en el bolsillo los duplicaría.
        let steps = ((try? await stepDescriptor.result(for: store)) ?? [])
            .filter { $0.sourceRevision.productType?.hasPrefix("Watch") ?? false }
            .map { ($0.startDate, $0.quantity.doubleValue(for: .count())) }
        return (hr, hrv, steps)
    }

    /// Un día inventado para el simulador: mañana tranquila, pico de estrés a mediodía, entreno a las 7.
    static func demo() -> (heartRate: [(date: Date, bpm: Double, sedentary: Bool)], hrv: [(date: Date, ms: Double)],
                           steps: [(date: Date, count: Double)]) {
        let day = Calendar.current.startOfDay(for: .now)
        var hr: [(Date, Double, Bool)] = []
        var t = day.addingTimeInterval(6.5 * 3600)
        while t < .now {
            let hour = t.timeIntervalSince(day) / 3600
            let bpm = 62 + 14 * exp(-pow(hour - 12.5, 2) / 2) + 8 * exp(-pow(hour - 17, 2) / 1) + Double.random(in: -3...3)
            hr.append((t, bpm, true))
            t = t.addingTimeInterval(5 * 60)
        }
        let hrv = [(day.addingTimeInterval(9 * 3600), 32.0), (day.addingTimeInterval(13 * 3600), 22.0), (day.addingTimeInterval(16 * 3600), 28.0)]
        let steps = [(day.addingTimeInterval(8.2 * 3600), 600.0), (day.addingTimeInterval(8.4 * 3600), 450.0)]
        return (hr, hrv, steps)
    }
}

@MainActor
final class StressModel: ObservableObject {
    @Published var result: StressEnergy.Result?

    func load(health: VitalModel, training: TrainingModel) async {
        let demo = ProcessInfo.processInfo.arguments.contains("-demo")
        let data = demo ? StressReader.demo() : await StressReader.read()
        let today = Calendar.current.startOfDay(for: .now)
        result = StressEnergy.compute(
            heartRate: data.heartRate, hrv: data.hrv, steps: data.steps,
            restingHR: health.baseline(\.restingHR)?.mean ?? 60, maximumHR: training.maximumHR,
            baselineHRV: health.baseline(\.hrv)?.mean,
            wake: health.today?.sleep?.end, recovery: health.todayRecovery?.score,
            workouts: training.workouts.filter { $0.end > today })
        // `-depurar`: imprime lo que entra en el cálculo, para revisarlo desde el Mac.
        if ProcessInfo.processInfo.arguments.contains("-depurar"), let r = result {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            print("DEP reposo", health.baseline(\.restingHR)?.mean as Any, "max", training.maximumHR,
                  "baseVFC", health.baseline(\.hrv)?.mean as Any, "despertar", health.today?.sleep?.end as Any,
                  "recuperacion", health.todayRecovery?.score as Any)
            print("DEP pulso", data.heartRate.count, "quieto", data.heartRate.filter(\.sedentary).count, "VFC", data.hrv.map { "\(f.string(from: $0.date)) \(Int($0.ms))" })
            for w in training.workouts.filter({ $0.end > today }) {
                print("DEP entreno", w.name, f.string(from: w.start), f.string(from: w.end), "carga", Int(w.load), "esfuerzo", TrainingModel.strain(w.load))
            }
            for (b, e) in zip(r.buckets, r.energy.dropFirst()) {
                let hr = data.heartRate.filter { $0.date >= b.start && $0.date < b.start.addingTimeInterval(StressEnergy.bucket) }
                print("DEP", f.string(from: b.start), "\(b.kind)", "estres", b.stress.map { Int($0) } as Any,
                      "pulso", hr.isEmpty ? "-" : "\(Int(hr.map(\.bpm).reduce(0, +) / Double(hr.count)))", "energia", Int(e.value))
            }
        }
    }
}

// MARK: - Tarjeta

struct StressEnergyCard: View {
    let result: StressEnergy.Result

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    gauge("Estrés", value: result.currentStress, detail: result.dayStress.map { "media hoy \($0)" },
                          signal: result.currentStress.map { StressEnergy.stressSignal(Double($0)) }, icon: "brain.head.profile")
                    gauge("Energía", value: result.currentEnergy, detail: energyText,
                          signal: result.currentEnergy.map { StressEnergy.energySignal(Double($0)) }, icon: "bolt.fill")
                }
                Chart {
                    ForEach(result.buckets) { b in
                        let end = b.start.addingTimeInterval(StressEnergy.bucket - 60)
                        if b.kind == .workout {
                            RectangleMark(xStart: .value("Desde", b.start), xEnd: .value("Hasta", end),
                                          yStart: .value("Estrés", 0), yEnd: .value("Estrés", 100))
                                .foregroundStyle(.cyan.opacity(0.18))
                        } else if b.kind != .rest {
                            RectangleMark(xStart: .value("Desde", b.start), xEnd: .value("Hasta", end),
                                          yStart: .value("Estrés", 0), yEnd: .value("Estrés", 100))
                                .foregroundStyle(.white.opacity(0.06))
                        } else if let s = b.stress {
                            RectangleMark(xStart: .value("Desde", b.start), xEnd: .value("Hasta", end),
                                          yStart: .value("Estrés", 0), yEnd: .value("Estrés", max(2, s)))
                                .foregroundStyle(StressEnergy.stressSignal(s).color.opacity(0.75))
                        }
                    }
                    ForEach(result.energy, id: \.date) { point in
                        LineMark(x: .value("Hora", point.date), y: .value("Energía", point.value))
                            .foregroundStyle(.yellow)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
                .frame(height: 130)
                HStack(spacing: 14) {
                    legend(.yellow, "Energía")
                    legend(.green, "Calma")
                    legend(.orange, "Estrés medio")
                    legend(.red, "Alto")
                    legend(.cyan.opacity(0.5), "Entreno")
                    legend(.white.opacity(0.3), "En movimiento")
                }
                .font(.caption2)
                let m = result.minutesByLevel
                Text("Hoy: \(minutes(TimeInterval(m.low * 60))) en calma · \(minutes(TimeInterval(m.medium * 60))) estrés medio · \(minutes(TimeInterval(m.high * 60))) alto")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var energyText: String? {
        guard let first = result.energy.first?.value else { return nil }
        return "empezó en \(Int(first.rounded()))"
    }

    private func gauge(_ title: String, value: Int?, detail: String?, signal: Signal?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(signal?.color ?? .secondary)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) { Circle().fill(color).frame(width: 7, height: 7); Text(text).foregroundStyle(.secondary) }
    }
}
