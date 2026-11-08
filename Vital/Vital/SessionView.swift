import SwiftData
import SwiftUI

/// La sesión en el gimnasio: peso propuesto por ejercicio y una fila por serie para anotar lo que hiciste.
struct SessionView: View {
    let routine: Routine
    let recovery: Recovery?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var history: [SetLog]
    @State private var rows: [String: [SetRow]] = [:]
    @State private var suggestions: [String: LoadAdvisor.Suggestion] = [:]
    @State private var confirmingExit = false
    @State private var saving = false
    @State private var healthMessage: String?
    private let profile = TrainingProfile()
    private let sessionID = UUID()
    private let started = Date.now

    struct SetRow: Identifiable {
        let id = UUID()
        var weight: Double?      // en la unidad elegida
        var reps: Int?
        var done = false
    }

    var body: some View {
        NavigationStack {
            List {
                if recovery?.signal == .poor {
                    Label("Recuperación baja: las cargas de hoy van un 10 % por debajo.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                ForEach(routine.sortedItems) { item in
                    if let exercise = item.exercise {
                        Section {
                            if let s = suggestions[item.exerciseID] {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(summary(s.plan))
                                            .font(.callout.bold()).foregroundStyle(.cyan)
                                        if s.isEstimate {
                                            Text("estimado").font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.orange.opacity(0.25), in: Capsule())
                                        }
                                    }
                                    Text(s.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            ForEach(Array((rows[item.exerciseID] ?? []).enumerated()), id: \.element.id) { index, _ in
                                setRow(item: item, exercise: exercise, index: index)
                            }
                            Button {
                                rows[item.exerciseID, default: []].append(SetRow(weight: rows[item.exerciseID]?.last?.weight,
                                                                                 reps: rows[item.exerciseID]?.last?.reps))
                            } label: {
                                Label("Añadir serie", systemImage: "plus").font(.caption)
                            }
                        } header: {
                            HStack {
                                Text(exercise.name)
                                Spacer()
                                Text(item.pyramid ? "Pirámide \(item.targetReps.map(String.init).joined(separator: "-"))"
                                                  : "\(item.sets) × \(item.repMin)–\(item.repMax)")
                            }
                        }
                    }
                }
            }
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Salir") { confirmingExit = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminar") { finish() }.bold().disabled(saving)
                }
            }
            .confirmationDialog("¿Salir sin guardar?", isPresented: $confirmingExit) {
                Button("Salir sin guardar", role: .destructive) { dismiss() }
            }
            .alert("Entreno guardado", isPresented: Binding(get: { healthMessage != nil }, set: { if !$0 { healthMessage = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                Text(healthMessage ?? "")
            }
            .onAppear(perform: prepare)
        }
    }

    private func setRow(item: RoutineItem, exercise: Exercise, index: Int) -> some View {
        let binding = Binding(
            get: { rows[item.exerciseID]?[index] ?? SetRow() },
            set: { rows[item.exerciseID]?[index] = $0 })
        return HStack(spacing: 12) {
            Text("\(index + 1)").font(.callout.weight(.bold)).foregroundStyle(.secondary).frame(width: 20)
            if exercise.equipment.isWeighted {
                TextField("Peso", value: binding.weight, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                Text(profile.unit.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            TextField("Reps", value: binding.reps, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder).frame(width: 60)
            Text("reps").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                binding.wrappedValue.done.toggle()
            } label: {
                Image(systemName: binding.wrappedValue.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(binding.wrappedValue.done ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// «52,5 kg × 12 · 57,5 × 10 …» o, si todas las series son iguales, «4 × 6 con 52,5 kg».
    private func summary(_ plan: [(weight: Double?, reps: Int)]) -> String {
        guard let first = plan.first else { return "" }
        if plan.allSatisfy({ $0.weight == first.weight && $0.reps == first.reps }) {
            return "\(plan.count) × \(first.reps)" + (first.weight.map { " con \(profile.unit.format($0))" } ?? "")
        }
        return plan.map { set in set.weight.map { "\(profile.unit.format($0)) × \(set.reps)" } ?? "\(set.reps)" }
            .joined(separator: " · ")
    }

    /// Calcula el peso propuesto de cada ejercicio y rellena las series con él.
    private func prepare() {
        guard rows.isEmpty else { return }
        for item in routine.sortedItems {
            let s = LoadAdvisor.suggest(for: item, history: history, bodyWeight: profile.bodyWeight, female: profile.female,
                                        level: profile.level, recovery: recovery)
            suggestions[item.exerciseID] = s
            rows[item.exerciseID] = s.plan.map { set in
                SetRow(weight: set.weight.map { (profile.unit.show($0) * 2).rounded() / 2 }, reps: set.reps)
            }
        }
    }

    /// Guarda solo las series marcadas como hechas.
    /// Y, si hubo series, guarda la sesión en Salud como entrenamiento de fuerza (sin duplicar el del reloj).
    private func finish() {
        var sets = 0
        var volume = 0.0
        for item in routine.sortedItems {
            for (index, row) in (rows[item.exerciseID] ?? []).enumerated() where row.done {
                let kg = profile.unit.store(row.weight ?? 0)
                context.insert(SetLog(exerciseID: item.exerciseID, date: started, session: sessionID,
                                      weight: kg, reps: row.reps ?? 0, index: index))
                sets += 1
                volume += kg * Double(row.reps ?? 0)
            }
        }
        try? context.save()
        guard sets > 0 else { dismiss(); return }
        saving = true
        let name = routine.name, start = started
        Task {
            let result = await HealthWriter.saveStrengthWorkout(name: name, start: start, end: .now, sets: sets, volumeKg: volume)
            saving = false
            switch result {
            case .saved: healthMessage = "\(sets) series guardadas. El entreno quedó en Salud como entrenamiento de fuerza."
            case .watchHadIt: healthMessage = "\(sets) series guardadas. El reloj ya grabó este entreno en Salud, así que no se duplicó."
            case .failed: healthMessage = "\(sets) series guardadas en Vital. No se pudo escribir en Salud (revisa los permisos en Salud > Apps > Vital)."
            }
        }
    }
}
