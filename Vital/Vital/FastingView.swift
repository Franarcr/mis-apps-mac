import Charts
import SwiftData
import SwiftUI

/// «13 h 05 min», «45 min».
func fastingDuration(_ hours: Double) -> String {
    let total = max(0, Int((hours * 60).rounded(.down)))
    let h = total / 60, m = total % 60
    return h == 0 ? "\(m) min" : String(format: "%d h %02d min", h, m)
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

struct StartPickerSheet: View {
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
                        FastingSync.refresh()
                        dismiss()
                    }.bold()
                }
            }
        }
    }
}

struct FastingEditSheet: View {
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
                        FastingSync.refresh(in: context)
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
                        FastingSync.refresh(in: context)
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
    @Environment(\.openFastingTab) private var openFastingTab

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
          Button { openFastingTab() } label: {
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
          .buttonStyle(.plain)
        }
    }
}
