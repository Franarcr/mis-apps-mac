import Charts
import SwiftData
import SwiftUI

/// «13 h 05 min», «45 min».
func fastingDuration(_ hours: Double) -> String {
    let total = max(0, Int((hours * 60).rounded(.down)))
    let h = total / 60, m = total % 60
    return h == 0 ? "\(m) min" : String(format: "%d h %02d min", h, m)
}

// MARK: - Tarjeta en la pestaña Comida

struct FastingCard: View {
    /// Comidas registradas (de la pestaña Comida), para proponer empezar desde la última.
    let entries: [FoodEntry]
    @Environment(\.modelContext) private var context
    @Query(sort: \FastingSession.start) private var sessions: [FastingSession]
    @AppStorage("ayunoActivo") private var enabled = false
    @AppStorage("ayunoMeta") private var goal: Double = 16
    @State private var showingSafety = false
    @State private var showingDetail = false
    @State private var pickingStart = false

    private var active: FastingSession? { sessions.last { $0.isActive } }
    private var lastFinished: FastingSession? { sessions.last { !$0.isActive } }

    /// La última comida que rompería un ayuno, si es posterior al último ayuno terminado.
    private var lastMeal: FoodEntry? {
        let after = lastFinished?.end ?? .distantPast
        return entries.last { $0.date > after && $0.date <= .now && $0.nutrients.kcal >= Fasting.breakingKcal }
    }

    var body: some View {
        Card {
            if !enabled {
                disabled
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        if let active { running(active) } else { window }
                        FastingTipRow(sessions: sessions, goal: goal)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSafety) { FastingSafetySheet() }
        .sheet(isPresented: $pickingStart) { StartPickerSheet(goal: goal) }
        .navigationDestination(isPresented: $showingDetail) { FastingDetailView() }
    }

    private var disabled: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Control de ayuno", systemImage: "timer").font(.headline)
            Text("Cuenta las horas desde tu última comida, te avisa al llegar a la meta y cierra el ayuno solo cuando registras comida.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Activar") { showingSafety = true }.bold().buttonStyle(.borderedProminent).tint(.indigo)
        }
    }

    private var header: some View {
        Button { showingDetail = true } label: {
            HStack {
                Label("Ayuno", systemImage: "timer").font(.headline)
                Spacer()
                let streak = FastingStats(sessions: sessions).streak
                if streak > 1 { Label("\(streak) días", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(.orange) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func running(_ s: FastingSession) -> some View {
        let phase = FastingPhase.at(hours: s.hours)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                FastingRing(progress: s.hours / s.goalHours, reached: s.reachedGoal) {
                    VStack(spacing: 0) {
                        Text(fastingDuration(s.hours)).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("de \(Int(s.goalHours)) h").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    if s.reachedGoal {
                        Text("¡Meta cumplida!").font(.headline).foregroundStyle(.green)
                        Text("Puedes comer cuando quieras").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Meta a las \(s.goalDate.formatted(date: .omitted, time: .shortened))").font(.headline)
                        Text("Faltan \(fastingDuration(s.goalHours - s.hours))").font(.caption).foregroundStyle(.secondary)
                    }
                    Label(phase.title, systemImage: phase.icon).font(.caption.weight(.semibold)).foregroundStyle(.indigo)
                    Text("Desde \(s.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Button {
                Fasting.finish(s, in: context)
            } label: {
                Text("Terminar ayuno").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(s.reachedGoal ? .green : .indigo)
            Text("Se cierra solo cuando registras comida de \(Int(Fasting.breakingKcal)) kcal o más.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var window: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let last = lastFinished, let end = last.end, Date.now.timeIntervalSince(end) < 24 * 3600 {
                let closes = end.addingTimeInterval((24 - goal) * 3600)
                Text(closes > .now ? "Ventana para comer abierta" : "Tu ventana ya cerró").font(.headline)
                Text("Último ayuno: \(fastingDuration(last.hours))\(last.reachedGoal ? " ✓" : "") · " +
                     (closes > .now ? "cierra a las \(closes.formatted(date: .omitted, time: .shortened))" : "toca empezar el siguiente"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Sin ayuno en curso").font(.headline)
                Text("Plan \(Int(goal)):\(24 - Int(goal))").font(.caption).foregroundStyle(.secondary)
            }
            if let meal = lastMeal {
                Button {
                    Fasting.start(at: meal.date, goalHours: goal, in: context)
                    Task { await FastingNotifications.requestPermission() }
                } label: {
                    Label("Empezar desde tu última comida (\(meal.date.formatted(date: .omitted, time: .shortened)))", systemImage: "play.fill")
                        .bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.indigo)
            }
            HStack {
                Button {
                    Fasting.start(at: .now, goalHours: goal, in: context)
                    Task { await FastingNotifications.requestPermission() }
                } label: { Text("Empezar ahora").frame(maxWidth: .infinity) }
                Button { pickingStart = true } label: { Text("Otra hora…").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)
        }
    }
}

struct FastingRing<Label: View>: View {
    let progress: Double
    let reached: Bool
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 12)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke((reached ? Color.green : .indigo).gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
    }
}

private struct StartPickerSheet: View {
    let goal: Double
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Última comida", selection: $date, in: Date.now.addingTimeInterval(-48 * 3600)...Date.now)
                Text("El ayuno cuenta desde que terminaste de comer.").font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Empezar ayuno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Empezar") {
                        Fasting.start(at: date, goalHours: goal, in: context)
                        Task { await FastingNotifications.requestPermission() }
                        dismiss()
                    }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Antes de activar

struct FastingSafetySheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ayunoActivo") private var enabled = false
    @AppStorage("ayunoPrecaucion") private var caution = false
    @AppStorage("ayunoMeta") private var goal: Double = 16
    @State private var pregnant = false
    @State private var eatingDisorder = false
    @State private var glucoseMeds = false
    @State private var minor = false

    private var anyRisk: Bool { pregnant || eatingDisorder || glucoseMeds || minor }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("El ayuno no es para todo el mundo. Marca lo que aplique:").font(.callout)
                    Toggle("Estoy embarazada o dando de mamar", isOn: $pregnant)
                    Toggle("Tengo o tuve un trastorno de la conducta alimentaria", isOn: $eatingDisorder)
                    Toggle("Uso insulina u otros medicamentos que bajan el azúcar", isOn: $glucoseMeds)
                    Toggle("Soy menor de 18 años", isOn: $minor)
                }
                if anyRisk {
                    Section {
                        Label("Antes de ayunar, coméntalo con tu médico. Vital solo te dejará planes suaves (12:12 y 14:10).",
                              systemImage: "stethoscope")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Lo que dicen los estudios") {
                    Text("Para bajar de peso, comer en una ventana funciona más o menos igual que contar calorías: ayuda porque comes menos, no por magia.")
                    Text("Cerrar la ventana temprano (cenar antes y lejos de dormir) mejora más el azúcar en sangre que la misma ventana tarde.")
                    Text("Llega a tu proteína dentro de la ventana para no perder músculo.")
                }
                .font(.callout)
            }
            .navigationTitle("Control de ayuno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Activar") {
                        caution = anyRisk
                        if caution { goal = min(goal, 14) }
                        enabled = true
                        dismiss()
                    }.bold()
                }
            }
        }
    }
}

// MARK: - Detalle

struct FastingDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FastingSession.start, order: .reverse) private var sessions: [FastingSession]
    @AppStorage("ayunoActivo") private var enabled = false
    @AppStorage("ayunoPrecaucion") private var caution = false
    @AppStorage("ayunoMeta") private var goal: Double = 16
    @AppStorage("ayunoAvisoVentana") private var windowAlert = true
    @State private var editing: FastingSession?

    private var stats: FastingStats { FastingStats(sessions: sessions) }
    private var active: FastingSession? { sessions.first { $0.isActive } }
    private var maxGoal: Double { caution ? 14 : 24 }

    var body: some View {
        List {
            Section("Plan") {
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
            }

            if let active {
                Section("Ahora") {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        let current = FastingPhase.at(hours: active.hours)
                        VStack(alignment: .leading, spacing: 10) {
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

            Section("Últimos 7 días") {
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
                Text("Empezar a la misma hora cada día ayuda a tu reloj interno tanto como las horas de ayuno.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            FastingInsightSections(sessions: sessions, goal: goal)

            Section("Historial") {
                if sessions.isEmpty { Text("Todavía no hay ayunos").foregroundStyle(.secondary) }
                ForEach(sessions.prefix(60)) { s in
                    Button { editing = s } label: {
                        HStack {
                            Image(systemName: s.isActive ? "timer" : s.reachedGoal ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(s.isActive ? AnyShapeStyle(.indigo) : s.reachedGoal ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                                Text(s.isActive ? "En curso · meta \(Int(s.goalHours)) h" :
                                        "\(s.endedBy == "comida" ? "Cerrado al registrar comida" : "Terminado a mano") · meta \(Int(s.goalHours)) h")
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

            Section {
                Button("Desactivar control de ayuno", role: .destructive) {
                    FastingNotifications.cancelAll()
                    enabled = false
                }
            } footer: {
                Text("Tu historial se guarda; puedes volver a activarlo cuando quieras.")
            }
        }
        .navigationTitle("Ayuno")
        .sheet(item: $editing) { FastingEditSheet(session: $0) }
    }

    private func setGoal(_ hours: Double) {
        goal = min(hours, maxGoal)
        // La meta del ayuno en curso cambia con el plan.
        if let active {
            active.goalHours = goal
            try? context.save()
            FastingNotifications.scheduleGoal(for: active)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.bold()).monospacedDigit()
        }
    }
}

private struct FastingEditSheet: View {
    @Bindable var session: FastingSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ayunoPrecaucion") private var caution = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Inicio", selection: $session.start, in: ...(session.end ?? .now))
                    if let end = session.end {
                        DatePicker("Fin", selection: Binding(get: { end }, set: { session.end = $0 }), in: session.start...Date.now)
                    } else {
                        LabeledContent("Fin", value: "En curso")
                    }
                    Stepper("Meta: \(Int(session.goalHours)) h", value: $session.goalHours, in: 12...(caution ? 14 : 24), step: 1)
                    LabeledContent("Duración", value: fastingDuration(session.hours))
                }
                Section {
                    Button("Borrar este ayuno", role: .destructive) {
                        if session.isActive { FastingNotifications.cancelAll() }
                        context.delete(session)
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Editar ayuno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        try? context.save()
                        if session.isActive { FastingNotifications.scheduleGoal(for: session) }
                        dismiss()
                    }.bold()
                }
            }
        }
    }
}

// MARK: - Resumen en la pestaña Salud

struct FastingSummaryCard: View {
    @Query(sort: \FastingSession.start) private var sessions: [FastingSession]
    @AppStorage("ayunoMeta") private var goal: Double = 16

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Card {
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    if let s = sessions.last(where: \.isActive) {
                        FastingRing(progress: s.hours / s.goalHours, reached: s.reachedGoal) { Image(systemName: "timer").font(.callout) }
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ayuno: \(fastingDuration(s.hours)) de \(Int(s.goalHours)) h").font(.headline)
                            Text(s.reachedGoal ? "Meta cumplida" : FastingPhase.at(hours: s.hours).title)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "fork.knife.circle").font(.largeTitle).foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ventana para comer").font(.headline)
                            if let end = sessions.last?.end {
                                let closes = end.addingTimeInterval((24 - goal) * 3600)
                                Text(closes > .now ? "Cierra a las \(closes.formatted(date: .omitted, time: .shortened))" : "Sin ayuno en curso")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    let streak = FastingStats(sessions: sessions).streak
                    if streak > 0 { Label("\(streak)", systemImage: "flame.fill").font(.callout.bold()).foregroundStyle(.orange) }
                }
                FastingTipRow(sessions: sessions, goal: goal)
              }
            }
        }
    }
}
