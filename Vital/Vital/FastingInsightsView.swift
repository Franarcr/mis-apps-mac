import Charts
import SwiftData
import SwiftUI

/// Una línea con el consejo de ayuno más útil ahora (en la tarjeta de Comida y en Salud).
struct FastingTipRow: View {
    let sessions: [FastingSession]
    let goal: Double
    @EnvironmentObject private var health: VitalModel
    @EnvironmentObject private var training: TrainingModel
    @AppStorage("pesoCorporal") private var weight: Double = 75

    var body: some View {
        if let tip = FastingInsights.tip(health: health, workouts: training.workouts, sessions: sessions, weight: weight, goal: goal) {
            Label { Text(tip.text).font(.caption) } icon: { Image(systemName: tip.icon).foregroundStyle(tip.signal.color) }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tip.signal.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Secciones del detalle del ayuno que lo cruzan con sueño, proteína, peso y glucosa.
struct FastingInsightSections: View {
    let sessions: [FastingSession]
    let goal: Double
    @EnvironmentObject private var health: VitalModel
    @EnvironmentObject private var bodyData: BodyModel
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @AppStorage("pesoCorporal") private var weight: Double = 75
    @State private var glucose: [(date: Date, mgdl: Double)] = []

    var body: some View {
        Group {
            sleep
            protein
            weightSection
            if !glucose.isEmpty { glucoseSection }
        }
        // La glucosa se pide aquí y la sección solo aparece si el sensor tiene datos de este ayuno.
        .task(id: sessions.first?.start) { await loadGlucose() }
    }

    // MARK: Sueño

    @ViewBuilder private var sleep: some View {
        let gaps = FastingInsights.nightGaps(days: health.days, entries: entries, sessions: sessions)
        Section {
            if let c = FastingInsights.sleepComparison(gaps) {
                Chart {
                    ForEach(gaps.filter { $0.hrv != nil }) { g in
                        PointMark(x: .value("Horas entre cenar y dormir", g.gapHours), y: .value("VFC", g.hrv!))
                            .foregroundStyle(g.gapHours >= 3 ? Color.green : .orange)
                    }
                    RuleMark(x: .value("3 h", 3)).foregroundStyle(.white.opacity(0.4)).lineStyle(StrokeStyle(dash: [4, 4]))
                }
                .chartXAxisLabel("Horas entre la última comida y dormir")
                .chartYAxisLabel("VFC (ms)")
                .frame(height: 170)
                .padding(.vertical, 6)
                let pct = Int((c.hrvChange * 100).rounded())
                Text("Cenando 3 h o más antes de dormir tu VFC fue \(Int(c.earlyHRV)) ms frente a \(Int(c.lateHRV)) ms " +
                     "(\(pct >= 0 ? "+" : "")\(pct) %) y dormiste \(String(format: "%.1f", c.earlySleep)) h frente a \(String(format: "%.1f", c.lateSleep)) h " +
                     "(\(c.earlyNights) y \(c.lateNights) noches).")
                    .font(.callout)
            } else {
                Text("Cuando haya al menos 3 noches cenando temprano y 3 cenando tarde, aquí verás cómo cambia tu VFC. Llevo \(gaps.count) noches con dato.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let t = FastingInsights.lastMealTime(bedtime: health.bedtime?.average), let h = t.hour, let m = t.minute {
                Label(String(format: "Te acuestas en promedio a las %d:%02d: termina de comer hacia las %d:%02d.",
                             health.bedtime!.average.hour!, health.bedtime!.average.minute!, h, m),
                      systemImage: "moon.zzz.fill")
                    .font(.callout)
            }
        } header: {
            Text("Ayuno y sueño")
        } footer: {
            Text("Es una comparación de tus noches, no prueba causa y efecto. Cenar tarde suele subir el pulso y bajar la VFC al dormir.")
        }
    }

    // MARK: Proteína

    @ViewBuilder private var protein: some View {
        let plan = FastingInsights.proteinPlan(weight: weight, goal: goal)
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meta diaria").font(.caption).foregroundStyle(.secondary)
                    Text("\(Int(plan.target)) g").font(.title3.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("En \(Int(24 - goal)) h de ventana").font(.caption).foregroundStyle(.secondary)
                    Text("\(plan.meals) × \(Int(plan.perMeal)) g").font(.title3.bold()).foregroundStyle(plan.isHard ? .orange : .primary)
                }
            }
            if plan.isHard {
                Label("Más de 45 g por comida cuesta y se aprovecha peor. Una ventana más amplia o un batido de proteína ayudan.",
                      systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            if let p = FastingInsights.proteinOnFastingDays(entries: entries, sessions: sessions) {
                let pct = Int((p.fasting / plan.target * 100).rounded())
                Text("Los días con ayuno cumplido comiste \(Int(p.fasting)) g de proteína (\(pct) % de la meta)" +
                     (p.other > 0 ? " frente a \(Int(p.other)) g los demás días." : "."))
                    .font(.callout)
                    .foregroundStyle(pct < 80 ? .orange : .primary)
            }
        } header: {
            Text("Proteína en tu ventana")
        } footer: {
            Text("1,8 g por kg de peso, la misma meta de Comida. En los estudios, el ayuno sin cuidar la proteína hizo perder más músculo.")
        }
    }

    // MARK: Peso

    @ViewBuilder private var weightSection: some View {
        let weeks = FastingInsights.weeks(weights: bodyData.series[.weight] ?? [], sessions: sessions)
        if weeks.contains(where: { $0.weight != nil }) {
            Section {
                Chart {
                    ForEach(weeks) { w in
                        BarMark(x: .value("Semana", w.week, unit: .weekOfYear), y: .value("Ayunos", w.fastsMet))
                            .foregroundStyle(.indigo.opacity(0.5))
                    }
                }
                .chartYAxisLabel("Ayunos cumplidos")
                .frame(height: 90)
                Chart {
                    ForEach(weeks.filter { $0.weight != nil }) { w in
                        LineMark(x: .value("Semana", w.week, unit: .weekOfYear), y: .value("Peso", w.weight!))
                        PointMark(x: .value("Semana", w.week, unit: .weekOfYear), y: .value("Peso", w.weight!))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("Peso medio (kg)")
                .frame(height: 140)
                if let s = FastingInsights.weightSummary(weeks) {
                    Text("\(s.change <= 0 ? "" : "+")\(String(format: "%.1f", s.change)) kg en \(s.weeks) semanas, con \(String(format: "%.1f", s.fastsPerWeek)) ayunos cumplidos por semana.")
                        .font(.callout)
                }
            } header: {
                Text("Ayuno y peso (8 semanas)")
            } footer: {
                Text("El peso baja si comes menos de lo que gastas; el ayuno solo es una forma de lograrlo. Mira la tendencia de semanas, no de días.")
            }
        }
    }

    // MARK: Glucosa

    private var glucoseSection: some View {
        Section {
            Chart(glucose, id: \.date) { g in
                LineMark(x: .value("Hora", g.date), y: .value("mg/dL", g.mgdl)).interpolationMethod(.catmullRom)
                    .foregroundStyle(.teal)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 150)
            let values = glucose.map(\.mgdl)
            Text("Mínima \(Int(values.min()!)) · media \(Int(values.reduce(0, +) / Double(values.count))) · máxima \(Int(values.max()!)) mg/dL")
                .font(.callout).monospacedDigit()
        } header: {
            Text("Glucosa durante el ayuno")
        } footer: {
            Text("Del sensor de glucosa que escribe en Salud. En ayunas lo normal es entre 70 y 100 mg/dL.")
        }
    }

    private func loadGlucose() async {
        guard let s = sessions.first(where: \.isActive) ?? sessions.first else { return }
        glucose = await FastingInsights.glucose(from: s.start, to: s.end ?? .now)
    }
}
