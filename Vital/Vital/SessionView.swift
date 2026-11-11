import SwiftData
import SwiftUI
import UserNotifications

/// La sesión en curso, guardada en cada cambio para no perder nada si la app se cierra.
struct SessionDraft: Codable, Equatable {
    struct Row: Codable, Equatable, Identifiable {
        var id = UUID()
        var weight: Double?      // en la unidad elegida
        var reps: Int?
        var done = false
        var doneAt: Date?
    }

    var routineKey: String
    var routineName: String
    var sessionID = UUID()
    var started = Date.now
    /// Ejercicios añadidos solo para hoy (no están en la rutina).
    var extra: [String] = []
    var rows: [String: [Row]] = [:]
    var restEnd: Date?
    var restTotal: Int = 0

    private static let key = "sesionEnCurso"

    static func load() -> SessionDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SessionDraft.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// Identifica la rutina aunque cambie de nombre.
    static func key(for routine: Routine) -> String { "\(routine.createdAt.timeIntervalSinceReferenceDate)" }
}

/// Aviso cuando termina el descanso, aunque el iPhone esté bloqueado.
enum RestNotification {
    private static let id = "descanso"

    static func schedule(at date: Date, next: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let seconds = date.timeIntervalSinceNow
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Descanso terminado"
        content.body = next
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }

    static func cancel() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
}

/// La sesión en el gimnasio: peso propuesto por ejercicio y una fila por serie para anotar lo que hiciste.
/// Cada serie marcada se guarda al momento; al tocar «Terminar» el entreno pasa a Salud.
struct SessionView: View {
    let routine: Routine
    let recovery: Recovery?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var history: [SetLog]
    @State private var draft: SessionDraft
    @State private var extraItems: [RoutineItem]
    @State private var suggestions: [String: LoadAdvisor.Suggestion] = [:]
    @State private var confirmingExit = false
    @State private var picking = false
    @State private var pendingExercises: [Exercise] = []
    @State private var askingWhere = false
    @State private var saving = false
    @State private var healthMessage: String?
    @State private var restFinished = 0
    private let profile = TrainingProfile()

    init(routine: Routine, recovery: Recovery?) {
        self.routine = routine
        self.recovery = recovery
        let key = SessionDraft.key(for: routine)
        let saved = SessionDraft.load().flatMap { $0.routineKey == key ? $0 : nil }
        let draft = saved ?? SessionDraft(routineKey: key, routineName: routine.name)
        _draft = State(initialValue: draft)
        _extraItems = State(initialValue: draft.extra.enumerated().map { Self.extraItem($0.element, order: 1000 + $0.offset) })
    }

    private var items: [RoutineItem] { routine.sortedItems + extraItems }

    var body: some View {
        NavigationStack {
            List {
                if recovery?.signal == .poor {
                    Label("Recuperación baja: las cargas de hoy van un 10 % por debajo.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                ForEach(items, id: \.exerciseID) { item in
                    if let exercise = item.exercise {
                        exerciseSection(item: item, exercise: exercise)
                    }
                }
                Section {
                    Button {
                        pendingExercises = []
                        picking = true
                    } label: {
                        Label("Añadir ejercicio", systemImage: "plus.circle.fill").font(.callout.weight(.semibold))
                    }
                    .tint(.cyan)
                }
            }
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { if draft.restEnd != nil { restBar } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Salir") { confirmingExit = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminar") { finish() }.bold().disabled(saving)
                }
            }
            .confirmationDialog("¿Qué hacemos con esta sesión?", isPresented: $confirmingExit, titleVisibility: .visible) {
                Button("Seguir después") { dismiss() }
                Button("Descartar la sesión", role: .destructive) { discard() }
            } message: {
                Text("«Seguir después» la deja guardada tal cual; la retomas desde Rutinas.")
            }
            .confirmationDialog("¿Guardar también en la rutina?", isPresented: $askingWhere, titleVisibility: .visible) {
                Button("Sí, añadirlo a «\(routine.name)»") { add(pendingExercises, toRoutine: true) }
                Button("Solo para hoy") { add(pendingExercises, toRoutine: false) }
            }
            .sheet(isPresented: $picking) {
                ExercisePicker { chosen in
                    let existing = Set(items.map(\.exerciseID))
                    pendingExercises = chosen.filter { !existing.contains($0.id) }
                }
            }
            .onChange(of: picking) { _, open in
                // El aviso sale cuando la hoja ya se cerró (dos ventanas a la vez no se muestran).
                if !open, !pendingExercises.isEmpty { askingWhere = true }
            }
            .alert("Entreno guardado", isPresented: Binding(get: { healthMessage != nil }, set: { if !$0 { healthMessage = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                Text(healthMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: restFinished)
            .onAppear(perform: prepare)
            .onChange(of: draft) { _, new in
                new.save()
                syncLogs()
            }
            .task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        }
    }

    // MARK: Ejercicio

    private func exerciseSection(item: RoutineItem, exercise: Exercise) -> some View {
        Section {
            if let s = suggestions[item.exerciseID] {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(summary(s.plan)).font(.callout.bold()).foregroundStyle(.cyan)
                        if s.isEstimate {
                            Text("estimado").font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.25), in: Capsule())
                        }
                    }
                    Text(s.reason).font(.caption).foregroundStyle(.secondary)
                    if let last = lastTime(item.exerciseID) {
                        Text(last).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(Array((draft.rows[item.exerciseID] ?? []).enumerated()), id: \.element.id) { index, _ in
                setRow(item: item, exercise: exercise, index: index)
            }
            .onDelete { offsets in draft.rows[item.exerciseID]?.remove(atOffsets: offsets) }
            Button {
                let last = draft.rows[item.exerciseID]?.last
                draft.rows[item.exerciseID, default: []].append(SessionDraft.Row(weight: last?.weight, reps: last?.reps))
            } label: {
                Label("Añadir serie", systemImage: "plus").font(.caption)
            }
        } header: {
            HStack {
                Text(exercise.name)
                Spacer()
                Text(item.pyramid ? "Pirámide \(item.targetReps.map(String.init).joined(separator: "-"))"
                                  : "\(item.sets) × \(item.repMin)–\(item.repMax) · \(item.restSeconds) s")
            }
        }
    }

    private func setRow(item: RoutineItem, exercise: Exercise, index: Int) -> some View {
        let id = item.exerciseID
        let binding = Binding(
            get: { draft.rows[id]?[safe: index] ?? SessionDraft.Row() },
            set: { if draft.rows[id]?.indices.contains(index) == true { draft.rows[id]?[index] = $0 } })
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
                var row = binding.wrappedValue
                row.done.toggle()
                row.doneAt = row.done ? .now : nil
                binding.wrappedValue = row
                if row.done { startRest(item: item, exercise: exercise, after: index) }
            } label: {
                Image(systemName: binding.wrappedValue.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(binding.wrappedValue.done ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// «La última vez (3 nov): 36 kg × 10 · 36 × 9 …», de la sesión anterior (no la de hoy).
    private func lastTime(_ exerciseID: String) -> String? {
        let past = history.filter { $0.exerciseID == exerciseID && $0.session != draft.sessionID }
        guard let newest = past.max(by: { $0.date < $1.date }) else { return nil }
        let sets = past.filter { $0.session == newest.session }.sorted { $0.index < $1.index }
        let text = sets.map { $0.weight > 0 ? "\(profile.unit.format($0.weight)) × \($0.reps)" : "\($0.reps) reps" }
            .joined(separator: " · ")
        return "La última vez (\(newest.date.formatted(.dateTime.day().month(.abbreviated)))): \(text)"
    }

    // MARK: Descanso

    private var restBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let left = max(0, Int(((draft.restEnd ?? .now).timeIntervalSince(timeline.date)).rounded(.up)))
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(left > 0 ? "Descanso" : "¡A la siguiente serie!").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(left > 0 ? Color.cyan : .green)
                }
                Spacer()
                Button("−15") { moveRest(-15) }.buttonStyle(.bordered)
                Button("+15") { moveRest(15) }.buttonStyle(.bordered)
                Button {
                    draft.restEnd = nil
                    RestNotification.cancel()
                } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .onChange(of: left == 0) { _, done in if done { restFinished += 1 } }
        }
    }

    private func startRest(item: RoutineItem, exercise: Exercise, after index: Int) {
        let end = Date.now.addingTimeInterval(TimeInterval(item.restSeconds))
        draft.restEnd = end
        draft.restTotal = item.restSeconds
        let rows = draft.rows[item.exerciseID] ?? []
        let next: String
        if let pending = rows.firstIndex(where: { !$0.done }) {
            next = "\(exercise.name): serie \(pending + 1)."
        } else if let following = items.first(where: { other in !(draft.rows[other.exerciseID] ?? []).contains(where: \.done) }),
                  let name = following.exercise?.name {
            next = "Sigue con \(name)."
        } else {
            next = "Vamos con la siguiente."
        }
        RestNotification.schedule(at: end, next: next)
    }

    private func moveRest(_ seconds: Int) {
        guard let end = draft.restEnd else { return }
        let new = max(Date.now, end.addingTimeInterval(TimeInterval(seconds)))
        draft.restEnd = new
        RestNotification.schedule(at: new, next: "Vamos con la siguiente serie.")
    }

    // MARK: Ejercicios añadidos

    private static func extraItem(_ id: String, order: Int) -> RoutineItem {
        let compound = ExerciseCatalog.exercise(id)?.isCompound ?? false
        return RoutineItem(exerciseID: id, order: order, sets: 3, repMin: compound ? 6 : 10, repMax: compound ? 10 : 15,
                           restSeconds: compound ? 120 : 75)
    }

    private func add(_ exercises: [Exercise], toRoutine: Bool) {
        for exercise in exercises {
            if toRoutine {
                let next = (routine.items.map(\.order).max() ?? -1) + 1
                let item = Self.extraItem(exercise.id, order: next)
                context.insert(item)
                item.routine = routine
            } else {
                draft.extra.append(exercise.id)
                extraItems.append(Self.extraItem(exercise.id, order: 1000 + draft.extra.count))
            }
        }
        try? context.save()
        pendingExercises = []
        prepare()
    }

    // MARK: Guardado

    /// Calcula el peso propuesto de cada ejercicio y rellena las series que falten (no toca las ya anotadas).
    private func prepare() {
        let past = history.filter { $0.session != draft.sessionID }
        var rows = draft.rows
        for item in items {
            let s = LoadAdvisor.suggest(for: item, history: past, bodyWeight: profile.bodyWeight, female: profile.female,
                                        level: profile.level, recovery: recovery)
            suggestions[item.exerciseID] = s
            if rows[item.exerciseID] == nil {
                rows[item.exerciseID] = s.plan.map { set in
                    SessionDraft.Row(weight: set.weight.map { (profile.unit.show($0) * 2).rounded() / 2 }, reps: set.reps)
                }
            }
        }
        if rows != draft.rows { draft.rows = rows } else { draft.save() }
    }

    /// Las series marcadas quedan en la base al momento (se reescriben las de esta sesión).
    private func syncLogs() {
        let session = draft.sessionID
        let existing = (try? context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.session == session }))) ?? []
        existing.forEach(context.delete)
        for (exerciseID, rows) in draft.rows {
            for (index, row) in rows.enumerated() where row.done {
                context.insert(SetLog(exerciseID: exerciseID, date: draft.started, session: session,
                                      weight: profile.unit.store(row.weight ?? 0), reps: row.reps ?? 0,
                                      index: index, doneAt: row.doneAt))
            }
        }
        try? context.save()
    }

    private func discard() {
        let session = draft.sessionID
        let existing = (try? context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.session == session }))) ?? []
        existing.forEach(context.delete)
        try? context.save()
        SessionDraft.clear()
        RestNotification.cancel()
        dismiss()
    }

    /// Guarda la sesión en Salud como entrenamiento de fuerza (sin duplicar el del reloj).
    private func finish() {
        syncLogs()
        RestNotification.cancel()
        let done = draft.rows.values.flatMap { $0 }.filter(\.done)
        let sets = done.count
        let volume = done.reduce(0.0) { $0 + profile.unit.store($1.weight ?? 0) * Double($1.reps ?? 0) }
        guard sets > 0 else { SessionDraft.clear(); dismiss(); return }
        saving = true
        let setsText = sets == 1 ? "1 serie" : "\(sets) series"
        let name = routine.name, start = draft.started
        // El final es la última serie marcada (por si tocas «Terminar» mucho después), con 2 min de margen.
        let lastSet = done.compactMap(\.doneAt).max() ?? .now
        let end = min(.now, lastSet.addingTimeInterval(120))
        Task {
            let result = await HealthWriter.saveStrengthWorkout(name: name, start: start, end: end, sets: sets, volumeKg: volume)
            saving = false
            SessionDraft.clear()
            switch result {
            case .saved(let kcal):
                healthMessage = "Vital guardó \(setsText). El entreno quedó en Salud como fuerza tradicional"
                    + (kcal.map { " con \(Int($0.rounded())) kcal activas medidas por tu reloj." }
                        ?? ", pero el reloj no registró calorías en ese rato.")
            case .watchHadIt:
                healthMessage = "Vital guardó \(setsText) y las unió al entreno que grabó tu reloj (con su pulso y calorías)."
            case .failed:
                healthMessage = "Vital guardó \(setsText). No se pudo escribir en Salud (revisa los permisos en Salud > Apps > Vital)."
            }
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
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
