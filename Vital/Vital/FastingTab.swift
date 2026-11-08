import Charts
import SwiftData
import SwiftUI

/// Pestaña «Ayuno»: el ayuno y, los días que no ayunas, «Comer menos». Tres secciones para no amontonar:
/// Hoy (lo de ahora), Progreso (gráficas e historial) y Plan (ajustes).
struct FastingTab: View {
    enum Page: String, CaseIterable, Identifiable {
        case today = "Hoy", progress = "Progreso", plan = "Plan"
        var id: String { rawValue }
    }

    @AppStorage("ayunoPagina") private var page: Page = .today

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .today: FastingTodayView()
                case .progress: FastingProgressList()
                case .plan: FastingPlanList()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Sección", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle("Ayuno")
        }
        .tint(.white)
    }
}

/// Para abrir la pestaña Ayuno desde otras pestañas (la tarjeta de ayuno de Salud).
struct OpenFastingTab {
    var action: () -> Void = {}
    func callAsFunction() { action() }
}

private struct OpenFastingTabKey: EnvironmentKey {
    static let defaultValue = OpenFastingTab()
}

extension EnvironmentValues {
    var openFastingTab: OpenFastingTab {
        get { self[OpenFastingTabKey.self] }
        set { self[OpenFastingTabKey.self] = newValue }
    }
}

// MARK: - Hoy

private struct FastingTodayView: View {
    @Query(sort: \FastingSession.start) private var sessions: [FastingSession]
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @AppStorage("ayunoActivo") private var enabled = false
    @AppStorage("ayunoMeta") private var goal: Double = 16
    @AppStorage("comerMenosActivo") private var eatLessOn = true

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                VStack(spacing: 16) {
                    if enabled, let active = sessions.last(where: \.isActive) {
                        FastingNowCard(session: active)
                        FastingTipRow(sessions: sessions, goal: goal)
                        FastingPhasesCard(session: active)
                    } else {
                        if eatLessOn { EatLessCard(entries: entries) }
                        FastingStartCard(entries: entries, sessions: sessions)
                        if enabled { FastingTipRow(sessions: sessions, goal: goal) }
                        if eatLessOn { EatLessIdeaCard() }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
        }
    }
}

/// El ayuno en curso, grande.
private struct FastingNowCard: View {
    let session: FastingSession
    @Environment(\.modelContext) private var context
    @Query(sort: \FastingSession.start) private var sessions: [FastingSession]

    var body: some View {
        let s = session
        let phase = FastingPhase.at(hours: s.hours)
        Card {
            VStack(spacing: 14) {
                HStack {
                    Label("Ayunando", systemImage: "timer").font(.headline)
                    Spacer()
                    let streak = FastingStats(sessions: sessions).streak
                    if streak > 1 { Label("\(streak) días", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(.orange) }
                }
                FastingRing(progress: s.hours / s.goalHours, reached: s.reachedGoal) {
                    VStack(spacing: 2) {
                        Text(fastingDuration(s.hours)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("de \(Int(s.goalHours)) h").font(.caption).foregroundStyle(.secondary)
                        Label(phase.title, systemImage: phase.icon).font(.caption.weight(.semibold)).foregroundStyle(.indigo)
                            .padding(.top, 2)
                    }
                }
                .frame(width: 190, height: 190)
                .padding(.vertical, 4)
                if s.reachedGoal {
                    Text("¡Meta cumplida! Puedes comer cuando quieras").font(.callout.bold()).foregroundStyle(.green)
                } else {
                    Text("Meta a las \(s.goalDate.formatted(date: .omitted, time: .shortened)) · faltan \(fastingDuration(s.goalHours - s.hours))")
                        .font(.callout)
                }
                Button {
                    Fasting.finish(s, in: context)
                } label: {
                    Text("Terminar ayuno").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(s.reachedGoal ? .green : .indigo)
                Text("Desde \(s.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())). Se cierra solo al registrar comida de \(Int(Fasting.breakingKcal)) kcal o más.")
                    .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FastingPhasesCard: View {
    let session: FastingSession

    var body: some View {
        let current = FastingPhase.at(hours: session.hours)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fases").font(.headline)
                ForEach(FastingPhase.allCases) { phase in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: phase.icon).frame(width: 22)
                            .foregroundStyle(phase == current ? AnyShapeStyle(.indigo) : AnyShapeStyle(phase.rawValue < current.rawValue ? .secondary : .tertiary))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(phase.title) · \(Int(phase.startHour)) h").font(.callout.weight(phase == current ? .bold : .regular))
                            if phase == current { Text(phase.explanation).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Text("Horas aproximadas: dependen de lo que comiste y de cuánto te moviste.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Sin ayuno en curso: cómo está la ventana y los botones para empezar (o la invitación a activar el ayuno).
private struct FastingStartCard: View {
    let entries: [FoodEntry]
    let sessions: [FastingSession]
    @Environment(\.modelContext) private var context
    @AppStorage("ayunoActivo") private var enabled = false
    @AppStorage("ayunoMeta") private var goal: Double = 16
    @State private var showingSafety = false
    @State private var pickingStart = false

    private var lastFinished: FastingSession? { sessions.last { !$0.isActive } }
    private var lastMeal: FoodEntry? {
        let after = lastFinished?.end ?? .distantPast
        return entries.last { $0.date > after && $0.date <= .now && $0.nutrients.kcal >= Fasting.breakingKcal }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if !enabled {
                    Label("Ayuno intermitente", systemImage: "timer").font(.headline)
                    Text("Cuenta las horas desde tu última comida, te avisa al llegar a la meta y se cierra solo al registrar comida.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Activar ayuno") { showingSafety = true }.bold().buttonStyle(.borderedProminent).tint(.indigo)
                } else {
                    Label("Ayuno", systemImage: "timer").font(.headline)
                    if let last = lastFinished, let end = last.end, Date.now.timeIntervalSince(end) < 24 * 3600 {
                        let closes = end.addingTimeInterval((24 - goal) * 3600)
                        Text(closes > .now ? "Ventana para comer abierta hasta las \(closes.formatted(date: .omitted, time: .shortened))"
                                           : "Tu ventana ya cerró: buen momento para empezar")
                            .font(.callout)
                        Text("Último ayuno: \(fastingDuration(last.hours))\(last.reachedGoal ? " ✓" : "") · plan \(Int(goal)):\(24 - Int(goal))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Hoy sin ayuno · plan \(Int(goal)):\(24 - Int(goal))").font(.callout).foregroundStyle(.secondary)
                    }
                    if let meal = lastMeal {
                        Button {
                            start(at: meal.date)
                        } label: {
                            Label("Empezar desde tu última comida (\(meal.date.formatted(date: .omitted, time: .shortened)))", systemImage: "play.fill")
                                .bold().frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                    }
                    HStack {
                        Button { start(at: .now) } label: { Text("Empezar ahora").frame(maxWidth: .infinity) }
                        Button { pickingStart = true } label: { Text("Otra hora…").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(isPresented: $showingSafety) { FastingSafetySheet() }
        .sheet(isPresented: $pickingStart) { StartPickerSheet(goal: goal) }
    }

    private func start(at date: Date) {
        Fasting.start(at: date, goalHours: goal, in: context)
        Task { await FastingNotifications.requestPermission() }
    }
}

// MARK: - Comer menos

/// Lo que llevas comido hoy frente al reto, y la cocina.
private struct EatLessCard: View {
    let entries: [FoodEntry]
    @EnvironmentObject private var bodyData: BodyModel
    @Query(sort: \ScaleReading.date) private var readings: [ScaleReading]
    @AppStorage("pesoCorporal") private var weight: Double = 75
    @AppStorage("mujer") private var female = false
    @AppStorage("comerMenosPorcentaje") private var percent: Double = 10
    @AppStorage("cocinaHora") private var closeHour = 20
    @AppStorage("cocinaMinuto") private var closeMinute = 0

    var body: some View {
        let cal = Calendar.current
        let today = entries.filter { cal.isDateInToday($0.date) }.map(\.nutrients.kcal).reduce(0, +)
        let bmr = DailyTargets.basalRate(weight: weight, age: bodyData.age, female: female, scale: readings.last?.values[.bmr])
        let usual = EatLess.usualIntake(entries)
        let challenge = EatLess.challenge(usual: usual, bmr: bmr, female: female, percent: percent)
        let left = challenge - today
        let ratio = today / challenge
        let color: Color = ratio <= 1 ? .green : ratio <= 1.1 ? .orange : .red
        let close = cal.date(bySettingHour: closeHour, minute: closeMinute, second: 0, of: .now)!
        let late = EatLess.lateBites(entries, closeHour: closeHour, closeMinute: closeMinute)

        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Comer menos hoy", systemImage: "leaf.fill").font(.headline).foregroundStyle(.green)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(today))").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("de \(Int(challenge)) kcal").foregroundStyle(.secondary)
                    Spacer()
                    Text(left >= 0 ? "Te quedan \(Int(left))" : "Te pasaste \(Int(-left))")
                        .font(.callout.bold()).foregroundStyle(color)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(color.gradient).frame(width: geo.size.width * min(1, ratio))
                    }
                }
                .frame(height: 10)
                if let usual {
                    Text("Reto: \(Int(percent)) % menos de lo que sueles comer (\(Int(usual)) kcal de media esta semana).")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Registra 3 días en Comida y el reto se ajusta a lo que sueles comer. Por ahora sale de tu gasto estimado.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider().overlay(.white.opacity(0.15))
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Date.now >= close ? "Cocina cerrada desde las \(close.formatted(date: .omitted, time: .shortened))"
                                               : "La cocina cierra a las \(close.formatted(date: .omitted, time: .shortened))")
                            .font(.callout)
                        Text(late == 0 ? "Esta semana no picaste de noche. ¡Bien!"
                                       : "Esta semana comiste \(late) \(late == 1 ? "vez" : "veces") después del cierre.")
                            .font(.caption).foregroundStyle(late == 0 ? .green : .orange)
                    }
                }
            }
        }
    }
}

/// La idea práctica del día.
private struct EatLessIdeaCard: View {
    var body: some View {
        let idea = EatLess.idea()
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: idea.icon).font(.title2).foregroundStyle(.green).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Idea para hoy · \(idea.title)").font(.headline)
                    Text(idea.text).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Progreso

private struct FastingProgressList: View {
    @Query(sort: \FastingSession.start, order: .reverse) private var sessions: [FastingSession]
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @Query(sort: \ScaleReading.date) private var readings: [ScaleReading]
    @EnvironmentObject private var bodyData: BodyModel
    @AppStorage("ayunoActivo") private var enabled = false
    @AppStorage("ayunoMeta") private var goal: Double = 16
    @AppStorage("comerMenosActivo") private var eatLessOn = true
    @AppStorage("comerMenosPorcentaje") private var percent: Double = 10
    @AppStorage("pesoCorporal") private var weight: Double = 75
    @AppStorage("mujer") private var female = false
    @State private var editing: FastingSession?

    private var stats: FastingStats { FastingStats(sessions: sessions) }

    var body: some View {
        List {
            if enabled || !sessions.isEmpty { fastingWeek }
            if eatLessOn { eatLessWeek }
            FastingInsightSections(sessions: sessions, goal: goal)
            if !sessions.isEmpty { history }
        }
        .sheet(item: $editing) { FastingEditSheet(session: $0) }
    }

    private var fastingWeek: some View {
        Section("Ayuno · últimos 7 días") {
            Chart(stats.lastWeek, id: \.day) { item in
                BarMark(x: .value("Día", item.day, unit: .day), y: .value("Horas", item.hours))
                    .foregroundStyle(item.goal > 0 && item.hours >= item.goal ? Color.green.gradient : Color.indigo.gradient)
                    .cornerRadius(4)
                RuleMark(y: .value("Meta", goal)).foregroundStyle(.white.opacity(0.4)).lineStyle(StrokeStyle(dash: [4, 4]))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 150)
            .padding(.vertical, 6)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                stat("Racha", "\(stats.streak) días")
                stat("Metas cumplidas", stats.completion.map { "\(Int(($0 * 100).rounded())) %" } ?? "—")
                stat("Promedio", stats.averageHours.map(fastingDuration) ?? "—")
                stat("Horario", stats.regularityText.map { t in "\(t) (±\(Int(stats.startVariability ?? 0)) min)" } ?? "—")
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var eatLessWeek: some View {
        let days = EatLess.pastDays(entries)
        let bmr = DailyTargets.basalRate(weight: weight, age: bodyData.age, female: female, scale: readings.last?.values[.bmr])
        let challenge = EatLess.challenge(usual: EatLess.usualIntake(entries), bmr: bmr, female: female, percent: percent)
        let logged = days.filter { $0.kcal >= 500 }
        Section {
            if logged.isEmpty {
                Text("Cuando registres comidas en Comida, aquí verás cada día frente a tu reto.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(days, id: \.day) { d in
                        BarMark(x: .value("Día", d.day, unit: .day), y: .value("kcal", d.kcal))
                            .foregroundStyle(d.kcal == 0 ? Color.gray.gradient : d.kcal <= challenge ? Color.green.gradient : Color.orange.gradient)
                            .cornerRadius(4)
                    }
                    RuleMark(y: .value("Reto", challenge)).foregroundStyle(.white.opacity(0.4)).lineStyle(StrokeStyle(dash: [4, 4]))
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 150)
                .padding(.vertical, 6)
                let met = logged.filter { $0.kcal <= challenge }.count
                Text("\(met) de \(logged.count) días con registro por debajo del reto de \(Int(challenge)) kcal.")
                    .font(.callout)
            }
        } header: {
            Text("Comer menos · últimos 7 días")
        } footer: {
            Text("Los días en gris no tienen comidas registradas.")
        }
    }

    private var history: some View {
        Section("Historial de ayunos") {
            ForEach(sessions.prefix(60)) { s in
                Button { editing = s } label: {
                    HStack {
                        Image(systemName: s.isActive ? "timer" : s.reachedGoal ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(s.isActive ? AnyShapeStyle(.indigo) : s.reachedGoal ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                            Text(s.isActive ? "En curso · meta \(Int(s.goalHours)) h" :
                                    "\(s.endedBy == "ejemplo" ? "Ejemplo" : s.endedBy == "comida" ? "Cerrado al registrar comida" : "Terminado a mano") · meta \(Int(s.goalHours)) h")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(fastingDuration(s.hours)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.bold()).monospacedDigit()
        }
    }
}

// MARK: - Plan

private struct FastingPlanList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FastingSession.start, order: .reverse) private var sessions: [FastingSession]
    @AppStorage("ayunoActivo") private var enabled = false
    @AppStorage("ayunoPrecaucion") private var caution = false
    @AppStorage("ayunoMeta") private var goal: Double = 16
    @AppStorage("ayunoAvisoVentana") private var windowAlert = true
    @AppStorage("ayunoActividad") private var liveActivity = true
    @AppStorage("comerMenosActivo") private var eatLessOn = true
    @AppStorage("comerMenosPorcentaje") private var percent: Double = 10
    @AppStorage("cocinaHora") private var closeHour = 20
    @AppStorage("cocinaMinuto") private var closeMinute = 0
    @AppStorage("cocinaAviso") private var kitchenAlert = false
    @State private var showingSafety = false

    private var active: FastingSession? { sessions.first { $0.isActive } }
    private var maxGoal: Double { caution ? 14 : 24 }

    private var closeTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: closeHour, minute: closeMinute, second: 0, of: .now)!
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            closeHour = c.hour ?? 20
            closeMinute = c.minute ?? 0
            EatLess.scheduleKitchenReminder(enabled: kitchenAlert, hour: closeHour, minute: closeMinute)
        }
    }

    var body: some View {
        List {
            Section {
                if enabled {
                    ForEach(FastingPlan.allCases.filter { $0.rawValue <= maxGoal }) { plan in
                        Button { setGoal(plan.rawValue) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(plan.title).bold()
                                    Text(plan.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if goal == plan.rawValue { Image(systemName: "checkmark").foregroundStyle(.indigo) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Stepper("Meta: \(Int(goal)) h de ayuno", value: Binding(get: { goal }, set: setGoal), in: 12...maxGoal, step: 1)
                    if goal > 20 {
                        Label("Más de 20 h al día es exigente; no lo hagas a diario sin consultarlo.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Toggle("Avisar 30 min antes de cerrar la ventana", isOn: $windowAlert)
                    Toggle("Mostrar en la pantalla bloqueada y la Dynamic Island", isOn: $liveActivity)
                        .onChange(of: liveActivity) { FastingSync.refresh(in: context) }
                } else {
                    Button("Activar ayuno") { showingSafety = true }.bold()
                }
            } header: {
                Text("Ayuno")
            }

            Section {
                Toggle("Mostrar «Comer menos» los días sin ayuno", isOn: $eatLessOn)
                if eatLessOn {
                    Picker("Reto", selection: $percent) {
                        Text("5 % menos").tag(5.0)
                        Text("10 % menos").tag(10.0)
                        Text("15 % menos").tag(15.0)
                    }
                    DatePicker("Cerrar la cocina", selection: closeTime, displayedComponents: .hourAndMinute)
                    Toggle("Avisarme a esa hora", isOn: $kitchenAlert)
                        .onChange(of: kitchenAlert) {
                            EatLess.scheduleKitchenReminder(enabled: kitchenAlert, hour: closeHour, minute: closeMinute)
                        }
                }
            } header: {
                Text("Comer menos")
            } footer: {
                Text("El reto es un poco menos de lo que sueles comer, nunca por debajo de tu metabolismo basal. Bajar poco y seguido funciona mejor que dietas duras.")
            }

            if enabled {
                Section {
                    Button("Desactivar ayuno", role: .destructive) {
                        FastingNotifications.cancelAll()
                        enabled = false
                        FastingSync.refresh(in: context)
                    }
                } footer: {
                    Text("Tu historial se guarda; puedes volver a activarlo cuando quieras.")
                }
            }
        }
        .sheet(isPresented: $showingSafety) { FastingSafetySheet() }
    }

    private func setGoal(_ hours: Double) {
        goal = min(hours, maxGoal)
        // La meta del ayuno en curso cambia con el plan.
        if let active {
            active.goalHours = goal
            try? context.save()
            FastingNotifications.scheduleGoal(for: active)
        }
        FastingSync.refresh(in: context)
    }
}
