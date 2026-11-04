import Charts
import HealthKit
import SwiftUI

struct TrainingView: View {
    @ObservedObject var model: TrainingModel
    @ObservedObject var health: VitalModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !model.loaded {
                        ProgressView("Leyendo entrenamientos…").padding(.top, 120)
                    } else if let error = model.error {
                        Text("No se pudo leer Salud: \(error)").padding(.top, 120)
                    } else {
                        if health.isDemo || ProcessInfo.processInfo.arguments.contains("-demo") {
                            Label("Datos de ejemplo (simulador)", systemImage: "flask")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        StrainCard(strain: model.todayStrain, target: TrainingModel.target(for: health.todayRecovery),
                                   recovery: health.todayRecovery)
                        LoadCard(model: model)
                        FitnessCard(model: model)
                        WorkoutsCard(model: model)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { await model.load(restingHR: health.baseline(\.restingHR)?.mean) }
            .navigationTitle("Entreno")
            .navigationDestination(for: UUID.self) { id in
                if let workout = model.workouts.first(where: { $0.id == id }) {
                    WorkoutDetailView(model: model, workout: workout)
                }
            }
        }
        .tint(.white)
    }
}

// MARK: - Tarjetas

private struct StrainCard: View {
    let strain: Int
    let target: ClosedRange<Int>
    let recovery: Recovery?

    private var signal: Signal {
        target.contains(strain) ? .good : strain > target.upperBound + 10 ? .poor : .fair
    }

    var body: some View {
        Card {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 16)
                    // Zona recomendada para hoy, en gris claro detrás.
                    Circle()
                        .trim(from: Double(target.lowerBound) / 100, to: Double(target.upperBound) / 100)
                        .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 16))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .trim(from: 0, to: Double(strain) / 100)
                        .stroke(Color.cyan.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(strain)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(strain == 0 ? .white : signal.color)
                        Text("ESFUERZO DE HOY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)
                .padding(.top, 4)

                Text("Objetivo para hoy: \(target.lowerBound)–\(target.upperBound)").font(.title3.bold())
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var message: String {
        let reason = recovery.map { "Con tu recuperación de \($0.score)" } ?? "Sin datos de recuperación"
        if strain < target.lowerBound { return "\(reason), puedes sumar \(target.lowerBound - strain) puntos o más." }
        if strain <= target.upperBound { return "\(reason), ya estás en la zona ideal. Buen trabajo." }
        return "\(reason), hoy ya te pasaste del objetivo. Toca descansar."
    }
}

private struct LoadCard: View {
    @ObservedObject var model: TrainingModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Carga de entrenamiento", systemImage: "chart.bar.fill").font(.headline).foregroundStyle(.cyan)
                if let ratio = model.loadRatio {
                    let signal = TrainingModel.ratioSignal(ratio.ratio)
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.2f", ratio.ratio))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(signal.color)
                        Text(ratioText(ratio.ratio)).foregroundStyle(.secondary)
                    }
                    Text("Últimos 7 días frente a tu media semanal del último mes. Entre 0,8 y 1,3 progresas sin riesgo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Chart(model.dailyLoad(days: 28), id: \.day) { item in
                    BarMark(x: .value("Día", item.day, unit: .day), y: .value("Esfuerzo", TrainingModel.strain(item.load)))
                        .foregroundStyle(Color.cyan.gradient)
                        .cornerRadius(3)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private func ratioText(_ ratio: Double) -> String {
        switch ratio {
        case ..<0.8: "Estás entrenando menos que de costumbre"
        case ...1.3: "Carga equilibrada"
        case ...1.5: "Subiendo rápido: vigila la recuperación"
        default: "Demasiado de golpe: riesgo de lesión"
        }
    }
}

private struct FitnessCard: View {
    @ObservedObject var model: TrainingModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Forma física", systemImage: "bolt.heart.fill").font(.headline).foregroundStyle(.green)
                HStack(alignment: .top) {
                    vo2
                    recovery
                }
                if model.vo2.count >= 2 {
                    Chart(model.vo2, id: \.0) { point in
                        LineMark(x: .value("Fecha", point.0), y: .value("VO₂ máx.", point.1))
                            .foregroundStyle(.green)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Fecha", point.0), y: .value("VO₂ máx.", point.1))
                            .foregroundStyle(.green).symbolSize(20)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .frame(height: 100)
                }
            }
        }
    }

    private var vo2: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VO₂ máx.").font(.caption).foregroundStyle(.secondary)
            if let last = model.vo2.last {
                // Comparado con la primera medida de hace 3 meses o más reciente.
                let first = model.vo2.first(where: { $0.0 >= Date.now.addingTimeInterval(-90 * 86_400) }) ?? last
                let change = last.1 - first.1
                Text(String(format: "%.1f", last.1))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle((change >= -0.5 ? Signal.good : change >= -2 ? .fair : .poor).color)
                Text(String(format: "%+.1f en 3 meses", change)).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("—").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Text("Sal a caminar o correr al aire libre con el reloj").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recuperación cardiaca").font(.caption).foregroundStyle(.secondary)
            if let last = model.heartRateRecovery.last {
                // Cuánto baja el pulso en el primer minuto tras parar: menos de 12 es una mala señal.
                Text("\(Int(last.1.rounded()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle((last.1 >= 20 ? Signal.good : last.1 >= 12 ? .fair : .poor).color)
                Text("lpm en 1 min · \(last.0.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("—").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Text("Aparece tras un entreno intenso").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkoutsCard: View {
    @ObservedObject var model: TrainingModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Entrenamientos").font(.headline).padding(.bottom, 6)
                if model.workouts.isEmpty {
                    Text("No hay entrenamientos en las últimas 6 semanas.").foregroundStyle(.secondary)
                }
                ForEach(model.workouts.prefix(15)) { workout in
                    NavigationLink(value: workout.id) {
                        HStack(spacing: 12) {
                            Image(systemName: workout.icon).font(.title3).foregroundStyle(.cyan).frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name).font(.callout.weight(.semibold))
                                Text("\(workout.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(minutes(workout.duration))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(TrainingModel.strain(workout.load))").font(.callout.weight(.bold)).foregroundStyle(.cyan)
                                Text("esfuerzo").font(.caption2).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

func minutes(_ t: TimeInterval) -> String {
    let m = Int((t / 60).rounded())
    return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min"
}

// MARK: - Detalle

struct WorkoutDetailView: View {
    @ObservedObject var model: TrainingModel
    let workout: Workout
    @State private var zones: [TimeInterval]?

    private static let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]
    private static let zoneNames = ["Muy suave", "Suave", "Moderada", "Intensa", "Máxima"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: workout.icon).font(.largeTitle).foregroundStyle(.cyan)
                            VStack(alignment: .leading) {
                                Text(workout.name).font(.title2.bold())
                                Text(workout.start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            fact("Duración", minutes(workout.duration))
                            fact("Esfuerzo", "\(TrainingModel.strain(workout.load))")
                            fact("Esfuerzo (reloj)", workout.effort.map { "\(Int($0.rounded())) / 10" } ?? "—")
                            fact("Pulso medio", workout.averageHR.map { "\(Int($0.rounded())) lpm" } ?? "—")
                            fact("Pulso máximo", workout.maximumHR.map { "\(Int($0.rounded())) lpm" } ?? "—")
                            fact("Calorías", workout.energy.map { "\(Int($0.rounded())) kcal" } ?? "—")
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Zonas de pulso").font(.headline)
                        if let zones {
                            let total = max(1, zones.reduce(0, +))
                            ForEach((0..<5).reversed(), id: \.self) { i in
                                HStack {
                                    Text("Z\(i + 1)").font(.caption.weight(.bold)).frame(width: 24, alignment: .leading)
                                    Text(Self.zoneNames[i]).font(.caption).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 3).fill(Self.zoneColors[i])
                                            .frame(width: max(2, geo.size.width * zones[i] / total))
                                    }
                                    .frame(height: 12)
                                    Text(minutes(zones[i])).font(.caption).monospacedDigit().frame(width: 52, alignment: .trailing)
                                }
                            }
                            Text("Zonas según tu pulso máximo estimado de \(Int(model.maximumHR)) lpm.")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                let m = workout.duration
                zones = [0.1, 0.25, 0.35, 0.22, 0.08].map { $0 * m }
            } else {
                zones = (try? await model.reader.zones(for: workout, maximum: model.maximumHR)) ?? [0, 0, 0, 0, 0]
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
    }
}
