import SwiftData
import SwiftUI

/// Ajustes del perfil de entrenamiento, compartidos por las pantallas de rutinas.
struct TrainingProfile {
    @AppStorage("nivel") var level: TrainingLevel = .intermediate
    @AppStorage("unidad") var unit: WeightUnit = .kg
    @AppStorage("pesoCorporal") var bodyWeight: Double = 75
    @AppStorage("mujer") var female = false
    @AppStorage("perfilLeidoDeSalud") var readFromHealth = false
}

struct RoutinesView: View {
    @ObservedObject var health: VitalModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(sort: \CustomExercise.name) private var customExercises: [CustomExercise]
    @State private var naming = false
    @State private var newName = ""
    @State private var showingProfile = false
    @State private var session: Routine?
    private var profile = TrainingProfile()

    init(health: VitalModel) { self.health = health }

    var body: some View {
        NavigationStack {
            List {
                if routines.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Crea tu primera rutina").font(.headline)
                            Text("Ponle nombre (p. ej. «Pecho y tríceps»), añade ejercicios por músculo o por equipo, y Vital te propone el peso de cada uno.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                ForEach(routines) { routine in
                    Section {
                        NavigationLink(value: routine) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.name).font(.headline)
                                Text(routine.sortedItems.compactMap { $0.exercise?.name }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Button {
                            session = routine
                        } label: {
                            Label("Empezar", systemImage: "play.fill").font(.callout.weight(.semibold))
                        }
                        .disabled(routine.items.isEmpty)
                        .tint(.cyan)
                    }
                }
                .onDelete { offsets in
                    let ordered = routines
                    offsets.forEach { context.delete(ordered[$0]) }
                }
            }
            .navigationTitle("Rutinas")
            .navigationDestination(for: Routine.self) { RoutineEditor(routine: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingProfile = true } label: { Image(systemName: "person.crop.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; naming = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("Nueva rutina", isPresented: $naming) {
                TextField("Nombre", text: $newName)
                Button("Crear") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    context.insert(Routine(name: name.isEmpty ? "Rutina \(routines.count + 1)" : name))
                }
                Button("Cancelar", role: .cancel) {}
            }
            .sheet(isPresented: $showingProfile) { ProfileSheet() }
            .fullScreenCover(item: $session) { routine in
                SessionView(routine: routine, recovery: health.todayRecovery)
            }
            .task { await readProfileOnce() }
            .onAppear { ExerciseCatalog.custom = customExercises.map(\.asExercise) }
            .onChange(of: customExercises.count) { ExerciseCatalog.custom = customExercises.map(\.asExercise) }
        }
        .tint(.white)
    }

    /// La primera vez, toma peso y sexo de Salud (luego se pueden cambiar en el perfil).
    private func readProfileOnce() async {
        guard !profile.readFromHealth, !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        let body = await BodyProfile.read()
        if let weight = body.weight { profile.bodyWeight = weight }
        if let female = body.female { profile.female = female }
        profile.readFromHealth = true
    }
}

// MARK: - Perfil

private struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nivel") private var level: TrainingLevel = .intermediate
    @AppStorage("unidad") private var unit: WeightUnit = .kg
    @AppStorage("pesoCorporal") private var bodyWeight: Double = 75
    @AppStorage("mujer") private var female = false
    @AppStorage("piramide") private var pyramid = "12,10,8,6"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Pirámide")
                        Spacer()
                        TextField("12-10-8-6", text: Binding(get: { pyramid.replacingOccurrences(of: ",", with: "-") },
                                                             set: { pyramid = $0.replacingOccurrences(of: "-", with: ",") }))
                            .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).frame(width: 120)
                    }
                } footer: {
                    Text("Repeticiones de cada serie con las que se crean los ejercicios nuevos. El peso sube en cada serie.")
                }
                Section {
                    Picker("Nivel", selection: $level) {
                        ForEach(TrainingLevel.allCases) { Text($0.name).tag($0) }
                    }
                    HStack {
                        Text("Peso corporal")
                        Spacer()
                        TextField("kg", value: Binding(get: { unit.show(bodyWeight).rounded() }, set: { bodyWeight = unit.store($0) }),
                                  format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text(unit.rawValue).foregroundStyle(.secondary)
                    }
                    Picker("Sexo", selection: $female) {
                        Text("Hombre").tag(false)
                        Text("Mujer").tag(true)
                    }
                    Picker("Unidad de peso", selection: $unit) {
                        Text("Kilos").tag(WeightUnit.kg)
                        Text("Libras").tag(WeightUnit.lb)
                    }
                } footer: {
                    Text("Con esto se estima el peso de la primera vez que haces cada ejercicio. Después, Vital ajusta las cargas con lo que anotas.")
                }
            }
            .tint(.cyan)
            .navigationTitle("Tu perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Listo") { dismiss() } }
        }
    }
}

// MARK: - Editor de rutina

private struct RoutineEditor: View {
    @Bindable var routine: Routine
    @Environment(\.modelContext) private var context
    @State private var picking = false
    @AppStorage("piramide") private var pyramidDefault = "12,10,8,6"

    var body: some View {
        List {
            Section {
                TextField("Nombre", text: $routine.name).font(.headline)
            }
            Section {
                ForEach(routine.sortedItems) { item in
                    ItemRow(item: item)
                }
                .onDelete { offsets in
                    let items = routine.sortedItems
                    offsets.forEach { context.delete(items[$0]) }
                    renumber()
                }
                .onMove { from, to in
                    var items = routine.sortedItems
                    items.move(fromOffsets: from, toOffset: to)
                    for (i, item) in items.enumerated() { item.order = i }
                }
                Button {
                    picking = true
                } label: {
                    Label("Añadir ejercicios", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Ejercicios")
            } footer: {
                Text("Desliza para borrar. Mantén pulsado para reordenar.")
            }
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $picking) {
            ExercisePicker { chosen in
                let start = routine.items.count
                for (i, exercise) in chosen.enumerated() {
                    let compound = exercise.isCompound
                    let item = RoutineItem(exerciseID: exercise.id, order: start + i,
                                           sets: compound ? 4 : 3, repMin: compound ? 6 : 10, repMax: compound ? 10 : 15,
                                           restSeconds: compound ? 120 : 75)
                    // Tu forma de entrenar: pirámide 12-10-8-6 en los ejercicios con peso (cámbiala en cada ejercicio).
                    if exercise.equipment.isWeighted {
                        item.pyramid = true
                        item.pyramidReps = pyramidDefault
                        item.sets = item.targetReps.count
                    }
                    item.routine = routine
                    context.insert(item)
                }
            }
        }
    }

    private func renumber() {
        for (i, item) in routine.sortedItems.enumerated() { item.order = i }
    }
}

private struct ItemRow: View {
    @Bindable var item: RoutineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.exercise?.name ?? item.exerciseID).font(.callout.weight(.semibold))
                Spacer()
                if let exercise = item.exercise {
                    Text(exercise.equipment.name).font(.caption2).foregroundStyle(.secondary)
                }
            }
            // Dos botones en vez de un interruptor: en la fila de la lista el interruptor quedaba encima de los Stepper.
            Picker("Tipo", selection: $item.pyramid) {
                Text("Pirámide").tag(true)
                Text("Series fijas").tag(false)
            }
            .pickerStyle(.segmented)
            if item.pyramid {
                HStack {
                    Text("Repeticiones").font(.caption).foregroundStyle(.secondary)
                    TextField("12-10-8-6", text: Binding(
                        get: { item.pyramidReps.replacingOccurrences(of: ",", with: "-") },
                        set: { item.pyramidReps = $0.replacingOccurrences(of: "-", with: ","); item.sets = item.targetReps.count }))
                        .font(.callout.monospacedDigit()).keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                    Text("\(item.targetReps.count) series").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 14) {
                    Stepper("\(item.sets) series", value: $item.sets, in: 1...10).font(.caption).fixedSize()
                    Stepper("\(item.repMin)–\(item.repMax) reps", onIncrement: {
                        item.repMin += 1; item.repMax += 1
                    }, onDecrement: {
                        if item.repMin > 1 { item.repMin -= 1; item.repMax -= 1 }
                    }).font(.caption).fixedSize()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Buscador de ejercicios

struct ExercisePicker: View {
    let onAdd: ([Exercise]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var creating = false
    @State private var text = ""
    @State private var muscle: Muscle?
    @State private var equipment: Equipment?
    @State private var stretching = false
    @State private var chosen: [Exercise] = []

    var body: some View {
        let results = ExerciseCatalog.search(text, muscle: muscle, equipment: equipment, includeStretching: stretching)
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Muscle.allCases) { m in chip(m.name, selected: muscle == m) { muscle = muscle == m ? nil : m } }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Equipment.allCases) { e in
                                chip(e.name, selected: equipment == e, icon: e.icon) { equipment = equipment == e ? nil : e }
                            }
                        }
                    }
                    Toggle("Incluir estiramientos", isOn: $stretching).font(.caption).tint(.cyan)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                Section {
                    Button {
                        creating = true
                    } label: {
                        Label(text.isEmpty ? "Crear ejercicio propio" : "Crear «\(text)»", systemImage: "plus.circle.fill")
                    }
                } footer: {
                    Text("Si no encuentras un ejercicio de tu gimnasio, créalo tú.")
                }

                Section("\(results.count) ejercicios") {
                    ForEach(results.prefix(200)) { exercise in
                        HStack {
                            Button {
                                if let i = chosen.firstIndex(of: exercise) { chosen.remove(at: i) } else { chosen.append(exercise) }
                            } label: {
                                HStack {
                                    Image(systemName: chosen.contains(exercise) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(chosen.contains(exercise) ? .cyan : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(exercise.name).font(.callout)
                                            if exercise.isCustom { Image(systemName: "person.fill").font(.caption2).foregroundStyle(.cyan) }
                                        }
                                        Text("\(exercise.primaryMuscles.map(\.name).joined(separator: ", ")) · \(exercise.equipment.name)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            NavigationLink { ExerciseDetail(exercise: exercise) } label: { Image(systemName: "info.circle") }
                                .fixedSize()
                        }
                    }
                }
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar (español o inglés)")
            .sheet(isPresented: $creating) {
                CustomExerciseForm(name: text, muscle: muscle, equipment: equipment) { custom in
                    context.insert(custom)
                    try? context.save()
                    let exercise = custom.asExercise
                    ExerciseCatalog.custom.append(exercise)
                    chosen.append(exercise)
                }
            }
            .navigationTitle("Ejercicios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.isEmpty ? "Añadir" : "Añadir (\(chosen.count))") {
                        onAdd(chosen)
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption2) }
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(selected ? Color.cyan : Color.white.opacity(0.1), in: Capsule())
            .foregroundStyle(selected ? .black : .white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ejercicio propio

private struct CustomExerciseForm: View {
    let onSave: (CustomExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var muscles: Set<Muscle>
    @State private var equipment: Equipment
    @State private var compound = true
    @State private var unilateral = false

    init(name: String, muscle: Muscle?, equipment: Equipment?, onSave: @escaping (CustomExercise) -> Void) {
        self.onSave = onSave
        _name = State(initialValue: name)
        _muscles = State(initialValue: muscle.map { [$0] } ?? [])
        _equipment = State(initialValue: equipment ?? .machine)
        // Si el nombre ya lo dice, se marca solo.
        let lower = name.lowercased()
        _unilateral = State(initialValue: ["una pierna", "un brazo", "una mano", "unilateral"].contains { lower.contains($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (p. ej. Prensa a una pierna)", text: $name)
                }
                Section("Músculos que trabaja") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 8) {
                        ForEach(Muscle.allCases) { m in
                            Button {
                                if muscles.contains(m) { muscles.remove(m) } else { muscles.insert(m) }
                            } label: {
                                Text(m.name).font(.caption.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(muscles.contains(m) ? Color.cyan : Color.white.opacity(0.1), in: Capsule())
                                    .foregroundStyle(muscles.contains(m) ? .black : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Picker("Equipo", selection: $equipment) {
                        ForEach(Equipment.allCases) { Text($0.name).tag($0) }
                    }
                    Toggle("Compuesto (varias articulaciones)", isOn: $compound)
                    Toggle("A una pierna o un brazo", isOn: $unilateral)
                } footer: {
                    Text("Con esto Vital estima el primer peso. Si es a una pierna o un brazo con barra, máquina o polea, propone más o menos la mitad.")
                }
            }
            .tint(.cyan)
            .navigationTitle("Ejercicio propio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        // Orden fijo de músculos, como en la base.
                        let ordered = Muscle.allCases.filter { muscles.contains($0) }
                        onSave(CustomExercise(name: name.trimmingCharacters(in: .whitespaces), muscles: ordered,
                                              equipment: equipment, compound: compound, unilateral: unilateral))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || muscles.isEmpty)
                }
            }
        }
    }
}

// MARK: - Ficha del ejercicio

struct ExerciseDetail: View {
    let exercise: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Las fotos se bajan la primera vez y quedan en la caché del iPhone.
                HStack(spacing: 8) {
                    ForEach(exercise.imageURLs, id: \.self) { url in
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)).overlay(ProgressView())
                                .aspectRatio(1.3, contentMode: .fit)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        row("Músculos", exercise.primaryMuscles.map(\.name).joined(separator: ", "))
                        if !exercise.secondaryMuscles.isEmpty {
                            row("Secundarios", exercise.secondaryMuscles.map(\.name).joined(separator: ", "))
                        }
                        row("Equipo", exercise.equipment.name)
                        row("Tipo", "\(exercise.categoryName)\(exercise.k.map { $0 == "compound" ? " · compuesto" : " · aislamiento" } ?? "")")
                        if exercise.isUnilateral { row("Lado", "A una pierna o un brazo") }
                        if !exercise.isCustom { row("Nivel", exercise.levelName) }
                    }
                }
                if !exercise.i.isEmpty { Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cómo se hace (en inglés)").font(.headline)
                        ForEach(Array(exercise.i.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                } }
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value)
        }
        .font(.callout)
    }
}
