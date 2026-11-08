import Charts
import SwiftUI

struct TodayView: View {
    @ObservedObject var model: VitalModel
    @ObservedObject var bodyData: BodyModel
    @ObservedObject var stress: StressModel
    @State private var showingInfo = false
    @State private var importingScale = false
    @AppStorage("ayunoActivo") private var fastingEnabled = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AppExpiryBanner()
                    switch model.state {
                    case .loading:
                        ProgressView("Leyendo Salud…").padding(.top, 120)
                    case .unavailable:
                        message("Salud no está disponible en este dispositivo.", icon: "heart.slash")
                    case .failed(let error):
                        message("No se pudo leer Salud: \(error)", icon: "exclamationmark.triangle")
                    case .ready:
                        content
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { await model.load(); await bodyData.load() }
            .navigationTitle(Self.title)
            .navigationDestination(for: Metric.self) { MetricDetailView(model: model, metric: $0) }
            .navigationDestination(for: BodyMetric.self) { _ in BodyDetailView(model: bodyData) }
            .toolbar {
                Button { showingInfo = true } label: { Image(systemName: "info.circle") }
            }
            .sheet(isPresented: $showingInfo) { InfoSheet() }
            .sheet(isPresented: $importingScale) { ScaleImportView() }
        }
        .tint(.white)
    }

    @ViewBuilder private var content: some View {
        if model.isDemo {
            Label("Datos de ejemplo (simulador)", systemImage: "flask")
                .font(.caption).foregroundStyle(.secondary)
        }
        RecoveryCard(recovery: model.todayRecovery, live: model.liveRecovery, daysWithHRV: model.daysWithHRV)
        if let result = stress.result { StressEnergyCard(result: result) }
        if fastingEnabled { FastingSummaryCard() }
        let tips = Advice.tips(for: model)
        if !tips.isEmpty { TipsCard(tips: tips) }
        if !model.alerts.isEmpty { AlertsCard(alerts: model.alerts) }
        if let heartRate = model.heartRate { HeartRateCard(heartRate: heartRate) }
        if let today = model.today {
            SleepCard(sleep: today.sleep, debt: model.sleepDebt, bedtime: model.bedtime)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Metric.allCases) { metric in
                    NavigationLink(value: metric) {
                        MetricCard(metric: metric, value: today[keyPath: metric.keyPath],
                                   base: model.baseline(metric.keyPath)?.mean)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if bodyData.loaded {
            NavigationLink(value: BodyMetric.weight) { BodyCard(model: bodyData) }.buttonStyle(.plain)
            Button { importingScale = true } label: {
                Label("Leer captura de Fitdays (grasa visceral y más)", systemImage: "camera.viewfinder")
                    .font(.callout.weight(.semibold)).frame(maxWidth: .infinity)
                    .padding(12).background(.mint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            }
            .foregroundStyle(.mint)
        }
        TrendCard(model: model)
    }

    /// «Miércoles 4 nov.»: solo la primera letra en mayúscula, y corto para que quepa en el título.
    private static var title: String {
        let text = Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).multilineTextAlignment(.center)
        }
        .padding(.top, 120)
    }
}

// MARK: - Tarjetas

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct RecoveryCard: View {
    let recovery: Recovery?
    var live: Recovery? = nil
    let daysWithHRV: Int

    /// La lectura del momento, solo si ya no coincide con la fijada al despertar.
    private var changed: Recovery? { live.flatMap { $0.score != recovery?.score ? $0 : nil } }

    var body: some View {
        Card {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 16)
                    if let recovery {
                        Circle()
                            .trim(from: 0, to: Double(recovery.score) / 100)
                            .stroke(recovery.signal.color.gradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        if let changed {
                            // Anillo interno: la lectura de este momento.
                            Circle().stroke(.white.opacity(0.08), lineWidth: 6).padding(20)
                            Circle()
                                .trim(from: 0, to: Double(changed.score) / 100)
                                .stroke(changed.signal.color.opacity(0.75), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .padding(20)
                        }
                        VStack(spacing: 0) {
                            Text("\(recovery.score)")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundStyle(recovery.signal.color)
                            Text("RECUPERACIÓN").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            if let changed {
                                Text("ahora \(changed.score)").font(.caption.weight(.semibold)).foregroundStyle(changed.signal.color.opacity(0.85))
                                    .padding(.top, 2)
                            }
                        }
                    } else {
                        Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)
                .padding(.top, 4)

                if let recovery {
                    Text(recovery.title).font(.title3.bold())
                    Text(recovery.advice).foregroundStyle(.secondary)
                    if let changed {
                        Text("Fijada al despertar en \(recovery.score). Con las medidas que el reloj pasó después, ahora sería \(changed.score) (anillo interno).")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                } else {
                    Text("Calibrando").font(.title3.bold())
                    Text("Necesito al menos \(Recovery.minimumBaseline) días con VFC del Apple Watch para conocer tu línea base. Llevo \(daysWithHRV).")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct TipsCard: View {
    let tips: [Advice.Tip]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Consejo del día", systemImage: "sparkles").font(.headline).foregroundStyle(.yellow)
                ForEach(tips) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: tip.icon).foregroundStyle(tip.signal.color).frame(width: 22)
                        Text(tip.text).font(.callout)
                    }
                }
            }
        }
    }
}

private struct AlertsCard: View {
    let alerts: [WatchAlert]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Avisos del reloj (30 días)", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.red)
                ForEach(alerts.prefix(5)) { alert in
                    HStack {
                        Image(systemName: alert.kind.icon).foregroundStyle(.red).frame(width: 22)
                        Text(alert.kind.title).font(.callout)
                        Spacer()
                        Text(alert.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Revisa los detalles en la app Salud y, si se repiten, coméntalos con tu médico.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HeartRateCard: View {
    let heartRate: HeartRateToday

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Frecuencia cardiaca", systemImage: "heart.fill").font(.headline).foregroundStyle(.pink)
                    Spacer()
                    Text(heartRate.latestDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(heartRate.latest.rounded()))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(heartRate.latest <= 100 ? Color.green : heartRate.latest <= 120 ? .orange : .red)
                    Text("lpm, última medida").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    fact("Mínima hoy", heartRate.minimum)
                    fact("Media hoy", heartRate.average)
                    fact("Máxima hoy", heartRate.maximum)
                }
            }
        }
    }

    private func fact(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(value.rounded())) lpm").font(.callout.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SleepCard: View {
    let sleep: SleepNight?
    let debt: TimeInterval
    let bedtime: (average: DateComponents, spread: Double)?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Sueño", systemImage: "bed.double.fill").font(.headline).foregroundStyle(.indigo)
                if let sleep {
                    HStack(alignment: .firstTextBaseline) {
                        Text(hours(sleep.asleep))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(sleep.signal.color)
                        Text("de \(hours(Recovery.sleepGoal))").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(sleep.start.formatted(date: .omitted, time: .shortened)) – \(sleep.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if sleep.hasStages {
                        StageBar(sleep: sleep)
                        HStack {
                            stage("Profundo", sleep.deep, .indigo)
                            stage("REM", sleep.rem, .cyan)
                            stage("Ligero", sleep.core, .blue)
                            stage("Despierto", sleep.awake, .orange)
                        }
                    }
                } else {
                    Text("Anoche no hay sueño registrado. Duerme con el Apple Watch puesto.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Divider().overlay(.white.opacity(0.15))
                HStack(alignment: .top) {
                    if let bedtime, let time = Calendar.current.date(from: bedtime.average) {
                        fact("Te acuestas", time.formatted(date: .omitted, time: .shortened), .white)
                        // Acostarse a horas parecidas ayuda tanto como dormir más.
                        fact("Regularidad", "± \(Int(bedtime.spread.rounded())) min",
                             (bedtime.spread < 30 ? Signal.good : bedtime.spread < 60 ? .fair : .poor).color)
                    }
                    fact("Deuda (7 días)", hours(debt),
                         (debt < 3 * 3600 ? Signal.good : debt < 6 * 3600 ? .fair : .poor).color)
                }
            }
        }
    }

    private func stage(_ name: String, _ time: TimeInterval, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); Text(name) }
                .font(.caption2).foregroundStyle(.secondary)
            Text(hours(time)).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).foregroundStyle(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func hours(_ t: TimeInterval) -> String {
    let minutes = Int((t / 60).rounded())
    return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
}

private struct StageBar: View {
    let sleep: SleepNight
    var body: some View {
        GeometryReader { geo in
            let total = max(1, sleep.asleep + sleep.awake)
            HStack(spacing: 2) {
                ForEach([(sleep.deep, Color.indigo), (sleep.rem, .cyan), (sleep.core, .blue), (sleep.awake, .orange)], id: \.1) { part in
                    RoundedRectangle(cornerRadius: 3).fill(part.1)
                        .frame(width: max(0, geo.size.width * part.0 / total - 2))
                }
            }
        }
        .frame(height: 10)
    }
}

private struct MetricCard: View {
    let metric: Metric
    let value: Double?
    let base: Double?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(metric.title, systemImage: metric.icon)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                if let value {
                    let signal = metric.signal(value, base: base)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(metric.display(value, base: base))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(signal.color)
                        Text(metric.unit).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(metric.detail(value, base: base) ?? " ").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    Text("Sin datos anoche").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TrendCard: View {
    @ObservedObject var model: VitalModel

    private var points: [(day: Date, score: Int, color: Color)] {
        model.days.suffix(14).compactMap { day in
            model.recoveries[day.day].map { (day.day, $0.score, $0.signal.color) }
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recuperación, últimos 14 días").font(.headline)
                if points.isEmpty {
                    Text("Aparecerá cuando haya días con recuperación.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Chart(points, id: \.day) { point in
                        BarMark(x: .value("Día", point.day, unit: .day), y: .value("Recuperación", point.score))
                            .foregroundStyle(point.color.gradient)
                            .cornerRadius(4)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                            AxisValueLabel(format: .dateTime.day(), centered: true)
                        }
                    }
                    .frame(height: 140)
                }
            }
        }
    }
}

private struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Cómo se calcula") {
                    Text("Tu recuperación compara la noche con tu propia línea base de los 30 días anteriores, no con promedios de otras personas.")
                    Text("**VFC:** lo que más pesa. Más alta que tu normal suele indicar que el cuerpo se recuperó.")
                    Text("**FC en reposo:** más baja que tu normal es buena señal; más alta puede ser cansancio, estrés, alcohol o que te estás enfermando.")
                    Text("**Restan puntos:** dormir menos de 7 h 30, la temperatura de la muñeca fuera de tu rango, respirar más rápido de lo normal y la SpO₂ bajo 95 %.")
                }
                Section("Colores") {
                    Label("Verde: en tu rango", systemImage: "circle.fill").foregroundStyle(.green)
                    Label("Naranja: se aleja un poco", systemImage: "circle.fill").foregroundStyle(.orange)
                    Label("Rojo: se aleja mucho", systemImage: "circle.fill").foregroundStyle(.red)
                }
                Section {
                    Text("Vital solo lee Salud en tu iPhone. No envía nada a internet. Es una guía, no un consejo médico.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sobre la recuperación")
            .toolbar { Button("Listo") { dismiss() } }
        }
    }
}
