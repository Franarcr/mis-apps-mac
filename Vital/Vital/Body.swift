import Charts
import HealthKit
import SwiftData
import SwiftUI

/// Medidas del cuerpo que la báscula (Fitdays) guarda en Salud.
enum BodyMetric: String, CaseIterable, Identifiable {
    case weight, fat, lean, bmi, waist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "Peso"
        case .fat: "Grasa corporal"
        case .lean: "Masa magra"
        case .bmi: "IMC"
        case .waist: "Cintura"
        }
    }

    var unit: String {
        switch self {
        case .weight, .lean: "kg"
        case .fat: "%"
        case .bmi: ""
        case .waist: "cm"
        }
    }

    var type: HKQuantityType {
        switch self {
        case .weight: HKQuantityType(.bodyMass)
        case .fat: HKQuantityType(.bodyFatPercentage)
        case .lean: HKQuantityType(.leanBodyMass)
        case .bmi: HKQuantityType(.bodyMassIndex)
        case .waist: HKQuantityType(.waistCircumference)
        }
    }

    var hkUnit: HKUnit {
        switch self {
        case .weight, .lean: .gramUnit(with: .kilo)
        case .fat: .percent()
        case .bmi: .count()
        case .waist: .meterUnit(with: .centi)
        }
    }

    /// Salud guarda el porcentaje como 0–1.
    func value(_ q: HKQuantity) -> Double { self == .fat ? q.doubleValue(for: hkUnit) * 100 : q.doubleValue(for: hkUnit) }

    func format(_ v: Double) -> String { String(format: "%.1f", v) }

    /// Semáforo por rangos de salud habituales. El peso y la masa magra no tienen uno propio:
    /// se colorean por su tendencia.
    func signal(_ v: Double, female: Bool) -> Signal? {
        switch self {
        case .bmi: v < 25 ? .good : v < 30 ? .fair : .poor
        case .fat: female ? (v < 30 ? .good : v < 35 ? .fair : .poor) : (v < 20 ? .good : v < 25 ? .fair : .poor)
        case .waist: female ? (v < 80 ? .good : v < 88 ? .fair : .poor) : (v < 94 ? .good : v < 102 ? .fair : .poor)
        case .weight, .lean: nil
        }
    }

    /// Si subir es bueno (masa magra), malo (grasa, cintura) o depende de tu objetivo (peso).
    var higherIsBetter: Bool? {
        switch self {
        case .lean: true
        case .fat, .waist, .bmi: false
        case .weight: nil
        }
    }
}

@MainActor
final class BodyModel: ObservableObject {
    @Published var series: [BodyMetric: [(date: Date, value: Double)]] = [:]
    @Published var loaded = false
    /// Edad (de la fecha de nacimiento en Salud), para comparar con la edad corporal de la báscula.
    @Published var age: Int?
    /// Estatura en cm (la última de Salud), para el metabolismo basal.
    @Published var height: Double?
    private let store = HKHealthStore()

    var latestWeight: Double? { series[.weight]?.last?.value }

    func load() async {
        if ProcessInfo.processInfo.arguments.contains("-demo") { showDemo(); return }
        guard HKHealthStore.isHealthDataAvailable() else { loaded = true; return }
        var types: Set<HKObjectType> = Set(BodyMetric.allCases.map(\.type))
        types.insert(HKCharacteristicType(.dateOfBirth))
        types.insert(HKQuantityType(.height))
        try? await store.requestAuthorization(toShare: [], read: types)
        if let year = (try? store.dateOfBirthComponents())?.year {
            age = Calendar.current.component(.year, from: .now) - year
        }
        let heightQuery = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.height))],
                                                  sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        if let cm = (try? await heightQuery.result(for: store))?.first?.quantity.doubleValue(for: .meterUnit(with: .centi)),
           (120...230).contains(cm) {
            height = cm
        }
        let from = Calendar.current.date(byAdding: .day, value: -365, to: .now)!
        var result: [BodyMetric: [(Date, Double)]] = [:]
        for metric in BodyMetric.allCases {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: metric.type, predicate: HKQuery.predicateForSamples(withStart: from, end: .now))],
                sortDescriptors: [SortDescriptor(\.startDate)])
            let samples = (try? await descriptor.result(for: store)) ?? []
            let values = samples.filter { $0.quantity.is(compatibleWith: metric.hkUnit) }.map { ($0.startDate, metric.value($0.quantity)) }
            if !values.isEmpty { result[metric] = values }
        }
        series = result
        loaded = true
    }

    /// Último valor menos el de hace unos `days` días (el pesaje más cercano antes de esa fecha).
    func change(_ metric: BodyMetric, days: Int) -> Double? {
        guard let points = series[metric], let last = points.last else { return nil }
        let cutoff = last.date.addingTimeInterval(-Double(days) * 86_400)
        guard let before = points.last(where: { $0.date <= cutoff }) else { return nil }
        return last.value - before.value
    }

    private func showDemo() {
        let now = Date.now
        var weight: [(Date, Double)] = [], fat: [(Date, Double)] = [], lean: [(Date, Double)] = [], bmi: [(Date, Double)] = []
        for week in stride(from: 26, through: 0, by: -1) {
            let date = now.addingTimeInterval(-Double(week) * 7 * 86_400)
            let w = 84.5 - Double(26 - week) * 0.12 + sin(Double(week)) * 0.3
            let f = 24.8 - Double(26 - week) * 0.08
            weight.append((date, w)); fat.append((date, f)); lean.append((date, w * (1 - f / 100))); bmi.append((date, w / (1.76 * 1.76)))
        }
        series = [.weight: weight, .fat: fat, .lean: lean, .bmi: bmi]
        loaded = true
    }
}

// MARK: - Tarjeta y detalle

struct BodyCard: View {
    @ObservedObject var model: BodyModel
    @AppStorage("mujer") private var female = false
    @Query(sort: \ScaleReading.date) private var readings: [ScaleReading]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Cuerpo", systemImage: "scalemass.fill").font(.headline).foregroundStyle(.mint)
                    Spacer()
                    if let date = model.series[.weight]?.last?.date {
                        Text("Pesaje: \(date.formatted(.dateTime.day().month(.abbreviated)))").font(.caption).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                if model.series.isEmpty {
                    Text("Aún no hay pesajes en Salud. En Fitdays activa la conexión con Apple Salud y pésate.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        ForEach(BodyMetric.allCases.filter { model.series[$0] != nil }) { metric in
                            cell(metric)
                        }
                    }
                }
                if let last = readings.last {
                    Divider().overlay(.white.opacity(0.15))
                    Text("De la báscula · \(last.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(ScaleMetric.allCases.filter { last.values[$0] != nil }) { metric in
                            scaleCell(metric, last.values[metric]!)
                        }
                    }
                }
            }
        }
    }

    private func scaleCell(_ metric: ScaleMetric, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(metric.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric.format(value)).font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(metric.signal(value, female: female, age: model.age)?.color ?? .white)
                Text(metric.unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func cell(_ metric: BodyMetric) -> some View {
        let value = model.series[metric]!.last!.value
        let change = model.change(metric, days: 30)
        return VStack(alignment: .leading, spacing: 2) {
            Text(metric.title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.format(value))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(metric.signal(value, female: female)?.color ?? .white)
                Text(metric.unit).font(.caption).foregroundStyle(.secondary)
            }
            if let change {
                Text(String(format: "%+.1f en 30 días", change))
                    .font(.caption).foregroundStyle(trendColor(metric, change))
            }
        }
    }
}

/// Verde si va en la buena dirección, naranja si va en la mala; gris si no está claro (peso) o casi no cambió.
func trendColor(_ metric: BodyMetric, _ change: Double) -> Color {
    guard let higherIsBetter = metric.higherIsBetter, abs(change) >= 0.2 else { return .secondary }
    return (change > 0) == higherIsBetter ? .green : .orange
}

struct BodyDetailView: View {
    @ObservedObject var model: BodyModel
    @AppStorage("mujer") private var female = false
    @State private var days = 90
    @State private var importing = false
    @Query(sort: \ScaleReading.date) private var readings: [ScaleReading]
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Periodo", selection: $days) {
                    Text("30 días").tag(30)
                    Text("90 días").tag(90)
                    Text("6 meses").tag(180)
                    Text("1 año").tag(365)
                }
                .pickerStyle(.segmented)

                ForEach(BodyMetric.allCases.filter { model.series[$0] != nil }) { metric in
                    chart(metric)
                }
                ForEach(ScaleMetric.allCases.filter { m in readings.contains { $0.values[m] != nil } }) { metric in
                    scaleChart(metric)
                }
                if !readings.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Lecturas de capturas").font(.headline)
                            ForEach(readings.reversed()) { reading in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reading.date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))
                                        // Los valores, para reconocer una lectura mala y borrarla.
                                        Text(ScaleMetric.allCases.compactMap { m in
                                            reading.values[m].map { "\(m.title) \(m.format($0))" }
                                        }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) { context.delete(reading) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
                Card {
                    Text("Peso, grasa, masa magra, IMC y cintura llegan solos desde Fitdays a través de Salud. La grasa visceral, el agua, el músculo, el hueso, la proteína, el metabolismo basal, la edad corporal, la puntuación y la relación cintura-cadera no pasan a Salud: añádelos con una captura del informe de Fitdays.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Cuerpo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { importing = true } label: { Label("Añadir captura", systemImage: "camera.viewfinder") }
        }
        .sheet(isPresented: $importing) { ScaleImportView() }
    }

    private func scaleChart(_ metric: ScaleMetric) -> some View {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        let points = readings.compactMap { r in r.values[metric].map { (date: r.date, value: $0) } }.filter { $0.date >= cutoff }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title).font(.headline)
                    Spacer()
                    if let last = points.last {
                        Text("\(metric.format(last.value)) \(metric.unit)").font(.headline)
                            .foregroundStyle(metric.signal(last.value, female: female, age: model.age)?.color ?? .white)
                    }
                    if points.count >= 2, let first = points.first, let last = points.last, let up = metric.higherIsBetter {
                        let change = last.value - first.value
                        Text(change >= 0 ? "+\(metric.format(change))" : metric.format(change)).font(.callout)
                            .foregroundStyle(abs(change) < 0.05 ? .secondary : ((change > 0) == up ? Color.green : .orange))
                    }
                }
                if points.count >= 2 {
                    Chart(points, id: \.date) { point in
                        LineMark(x: .value("Fecha", point.date), y: .value(metric.title, point.value))
                            .foregroundStyle(.teal).interpolationMethod(.monotone)
                        PointMark(x: .value("Fecha", point.date), y: .value(metric.title, point.value))
                            .foregroundStyle(.teal).symbolSize(18)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 120)
                } else {
                    Text("Con dos o más capturas verás la evolución.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chart(_ metric: BodyMetric) -> some View {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        let points = (model.series[metric] ?? []).filter { $0.date >= cutoff }
        let change = model.change(metric, days: days)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title).font(.headline)
                    Spacer()
                    if let last = points.last {
                        Text("\(metric.format(last.value)) \(metric.unit)").font(.headline)
                            .foregroundStyle(metric.signal(last.value, female: female)?.color ?? .white)
                    }
                    if let change {
                        Text(String(format: "%+.1f", change)).font(.callout).foregroundStyle(trendColor(metric, change))
                    }
                }
                if points.count >= 2 {
                    Chart(points, id: \.date) { point in
                        LineMark(x: .value("Fecha", point.date), y: .value(metric.title, point.value))
                            .foregroundStyle(.mint).interpolationMethod(.monotone)
                        PointMark(x: .value("Fecha", point.date), y: .value(metric.title, point.value))
                            .foregroundStyle(.mint).symbolSize(18)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 150)
                } else {
                    Text("Pocos pesajes en este periodo.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
