import Foundation
import HealthKit

/// Lo que se mide de un día: la noche que termina esa mañana y los valores del Apple Watch.
struct DayData: Identifiable {
    var id: Date { day }
    let day: Date
    var sleep: SleepNight?
    /// VFC (SDNN) en milisegundos: la media durante el sueño, o la del día si no hay sueño registrado.
    var hrv: Double?
    var restingHR: Double?
    var respiratoryRate: Double?
    /// Saturación de oxígeno en %, media durante el sueño.
    var oxygen: Double?
    /// Temperatura de la muñeca al dormir, en °C (Salud muestra la diferencia con tu base).
    var wristTemperature: Double?
    /// Alteraciones respiratorias por hora durante el sueño (lo que usa el aviso de apnea del reloj).
    var breathingDisturbances: Double?
}

/// Pulso de hoy: el último registrado y el rango del día.
struct HeartRateToday {
    let latest: Double
    let latestDate: Date
    let minimum: Double
    let maximum: Double
    let average: Double
}

/// Un aviso del reloj (pulso alto o bajo, ritmo irregular, hipertensión, apnea).
struct WatchAlert: Identifiable {
    enum Kind {
        case highHeartRate, lowHeartRate, irregularRhythm, hypertension, sleepApnea
        var title: String {
            switch self {
            case .highHeartRate: "Pulso alto en reposo"
            case .lowHeartRate: "Pulso bajo"
            case .irregularRhythm: "Ritmo cardiaco irregular"
            case .hypertension: "Posible hipertensión"
            case .sleepApnea: "Posible apnea del sueño"
            }
        }
        var icon: String {
            switch self {
            case .highHeartRate: "arrow.up.heart.fill"
            case .lowHeartRate: "arrow.down.heart.fill"
            case .irregularRhythm: "waveform.path.ecg.rectangle.fill"
            case .hypertension: "heart.text.square.fill"
            case .sleepApnea: "lungs.fill"
            }
        }
    }
    let id = UUID()
    let kind: Kind
    let date: Date
}

struct SleepNight {
    var start: Date
    var end: Date
    var core: TimeInterval = 0
    var deep: TimeInterval = 0
    var rem: TimeInterval = 0
    var unspecified: TimeInterval = 0
    var awake: TimeInterval = 0

    var asleep: TimeInterval { core + deep + rem + unspecified }
    var hasStages: Bool { core + deep + rem > 0 }
}

/// Lectura de Salud (HealthKit). Solo lee: Vital nunca escribe en Salud.
final class HealthReader {
    private let store = HKHealthStore()
    private let calendar = Calendar.current

    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let restingType = HKQuantityType(.restingHeartRate)
    private let respiratoryType = HKQuantityType(.respiratoryRate)
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let oxygenType = HKQuantityType(.oxygenSaturation)
    private let temperatureType = HKQuantityType(.appleSleepingWristTemperature)
    private let disturbancesType = HKQuantityType(.appleSleepingBreathingDisturbances)
    private let heartRateType = HKQuantityType(.heartRate)
    private let alertTypes: [(HKCategoryType, WatchAlert.Kind)] = {
        var types: [(HKCategoryType, WatchAlert.Kind)] = [
            (HKCategoryType(.highHeartRateEvent), .highHeartRate),
            (HKCategoryType(.lowHeartRateEvent), .lowHeartRate),
            (HKCategoryType(.irregularHeartRhythmEvent), .irregularRhythm),
            (HKCategoryType(.sleepApneaEvent), .sleepApnea),
        ]
        // El aviso de hipertensión llegó con iOS 26.2.
        if #available(iOS 26.2, *) { types.append((HKCategoryType(.hypertensionEvent), .hypertension)) }
        return types
    }()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async throws {
        var types: Set<HKObjectType> = [hrvType, restingType, respiratoryType, sleepType, oxygenType, temperatureType,
                                        disturbancesType, heartRateType]
        types.formUnion(alertTypes.map(\.0))
        try await store.requestAuthorization(toShare: [], read: types)
    }

    /// Los últimos `days` días, del más antiguo al de hoy.
    func load(days: Int) async throws -> [DayData] {
        let today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: today)!
        // La noche del primer día empieza la tarde anterior.
        let from = calendar.date(byAdding: .hour, value: -12, to: first)!
        let range = HKQuery.predicateForSamples(withStart: from, end: .now)

        async let sleepSamples = categorySamples(sleepType, range)
        async let hrvSamples = quantitySamples(hrvType, range)
        async let restingSamples = quantitySamples(restingType, range)
        async let respiratorySamples = quantitySamples(respiratoryType, range)
        async let oxygenSamples = quantitySamples(oxygenType, range)
        async let temperatureSamples = quantitySamples(temperatureType, range)
        async let disturbanceSamples = quantitySamples(disturbancesType, range)

        let nights = groupSleep(try await sleepSamples)
        let hrv = try await hrvSamples
        let resting = try await restingSamples
        let respiratory = try await respiratorySamples
        let oxygen = try await oxygenSamples
        let temperature = try await temperatureSamples
        let disturbances = try await disturbanceSamples
        let ms = HKUnit.secondUnit(with: .milli)
        let perMinute = HKUnit.count().unitDivided(by: .minute())

        return (0..<days).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: first)!
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            var data = DayData(day: day, sleep: nights[day])
            if let night = data.sleep {
                data.hrv = mean(hrv.filter { $0.startDate >= night.start && $0.startDate <= night.end }, ms)
                data.respiratoryRate = mean(respiratory.filter { $0.startDate >= night.start && $0.startDate <= night.end }, perMinute)
                data.oxygen = mean(oxygen.filter { $0.startDate >= night.start && $0.startDate <= night.end }, .percent())
                    .map { $0 * 100 }
            }
            // La temperatura de la muñeca es una sola medida por noche: va con la mañana en que termina.
            data.wristTemperature = mean(temperature.filter { nightDay($0.endDate) == day }, .degreeCelsius())
            data.breathingDisturbances = mean(disturbances.filter { nightDay($0.endDate) == day }, Self.perHour)
            if data.hrv == nil {
                data.hrv = mean(hrv.filter { $0.startDate >= day && $0.startDate < next }, ms)
            }
            data.restingHR = mean(resting.filter { $0.startDate >= day && $0.startDate < next }, perMinute)
            return data
        }
    }

    /// Las alteraciones respiratorias se guardan como «veces por hora».
    private static let perHour = HKUnit.count().unitDivided(by: .hour())

    /// Pulso desde las 0 h de hoy, o `nil` si el reloj aún no registró nada.
    func heartRateToday() async throws -> HeartRateToday? {
        let range = HKQuery.predicateForSamples(withStart: calendar.startOfDay(for: .now), end: .now)
        let samples = try await quantitySamples(heartRateType, range)
        guard let last = samples.last else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        return HeartRateToday(latest: last.quantity.doubleValue(for: unit), latestDate: last.endDate,
                              minimum: values.min()!, maximum: values.max()!,
                              average: values.reduce(0, +) / Double(values.count))
    }

    /// Avisos del reloj de los últimos `days` días, del más reciente al más antiguo.
    func alerts(days: Int) async throws -> [WatchAlert] {
        let from = calendar.date(byAdding: .day, value: -days, to: .now)!
        let range = HKQuery.predicateForSamples(withStart: from, end: .now)
        var result: [WatchAlert] = []
        for (type, kind) in alertTypes {
            result += try await categorySamples(type, range).map { WatchAlert(kind: kind, date: $0.startDate) }
        }
        return result.sorted { $0.date > $1.date }
    }

    /// Agrupa el sueño por la mañana en que termina: lo que acaba antes de las 18 h es la noche de ese día.
    private func groupSleep(_ samples: [HKCategorySample]) -> [Date: SleepNight] {
        var nights: [Date: SleepNight] = [:]
        for sample in samples {
            let day = nightDay(sample.endDate)
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            var night = nights[day] ?? SleepNight(start: sample.startDate, end: sample.endDate)
            night.start = min(night.start, sample.startDate)
            night.end = max(night.end, sample.endDate)
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .asleepCore: night.core += duration
            case .asleepDeep: night.deep += duration
            case .asleepREM: night.rem += duration
            case .asleepUnspecified: night.unspecified += duration
            case .awake: night.awake += duration
            default: break // En cama: no cuenta como sueño.
            }
            nights[day] = night
        }
        // Si varias fuentes (reloj e iPhone) registran lo mismo, el sueño se contaría dos veces:
        // se recorta a lo que cabe entre el inicio y el final de la noche.
        for (day, var night) in nights {
            let span = night.end.timeIntervalSince(night.start)
            if night.asleep + night.awake > span, night.asleep > 0 {
                let factor = span / (night.asleep + night.awake)
                night.core *= factor; night.deep *= factor; night.rem *= factor
                night.unspecified *= factor; night.awake *= factor
                nights[day] = night
            }
        }
        return nights.filter { $0.value.asleep > 0 }
    }

    /// Lo que termina antes de las 18 h cuenta para ese día; lo que termina después, para el siguiente.
    private func nightDay(_ end: Date) -> Date {
        calendar.startOfDay(for: end.addingTimeInterval(6 * 3600))
    }

    private func mean(_ samples: [HKQuantitySample], _ unit: HKUnit) -> Double? {
        // Si Apple cambiara la unidad de algún dato, mejor quedarse sin él que cerrar la app.
        let samples = samples.filter { $0.quantity.is(compatibleWith: unit) }
        guard !samples.isEmpty else { return nil }
        return samples.map { $0.quantity.doubleValue(for: unit) }.reduce(0, +) / Double(samples.count)
    }

    private func quantitySamples(_ type: HKQuantityType, _ predicate: NSPredicate) async throws -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }

    private func categorySamples(_ type: HKCategoryType, _ predicate: NSPredicate) async throws -> [HKCategorySample] {
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: type, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }
}
