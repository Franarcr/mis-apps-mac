import HealthKit
import PhotosUI
import SwiftData
import SwiftUI

enum WeightGoal: String, CaseIterable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lose: "Bajar grasa"
        case .maintain: "Mantener"
        case .gain: "Ganar músculo"
        }
    }
    /// Ajuste sobre lo que gastas en el día.
    var factor: Double {
        switch self {
        case .lose: 0.85
        case .maintain: 1
        case .gain: 1.1
        }
    }
}

/// Objetivos del día: lo que gastas (metabolismo basal + la energía activa del reloj) ajustado a tu objetivo.
/// Proteína 1,8 g por kg; grasa ~28 % de las calorías; carbohidratos, el resto. Azúcar y sodio con los límites de la OMS.
struct DailyTargets {
    let kcal: Double
    let protein: Double
    let fat: Double
    let carbs: Double
    let bmr: Double
    let active: Double
    static let sugarLimit = 50.0
    static let sodiumLimit = 2000.0

    init(bmr: Double, active: Double, weight: Double, goal: WeightGoal) {
        self.bmr = bmr
        self.active = active
        kcal = (bmr * 1.15 + active) * goal.factor
        protein = weight * 1.8
        fat = kcal * 0.28 / 9
        carbs = max(0, (kcal - protein * 4 - fat * 9) / 4)
    }
}

struct NutritionView: View {
    @ObservedObject var bodyData: BodyModel
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @Query(sort: \ScaleReading.date) private var readings: [ScaleReading]
    @AppStorage("pesoCorporal") private var weight: Double = 75
    @AppStorage("mujer") private var female = false
    @AppStorage("objetivoPeso") private var goal: WeightGoal = .maintain
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var adding: Meal?
    @State private var activeEnergy: Double = 0

    private var dayEntries: [FoodEntry] { entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) } }
    private var total: Nutrients { dayEntries.map(\.nutrients).reduce(Nutrients(), +) }

    private var targets: DailyTargets {
        // Metabolismo basal: el de la báscula si lo hay; si no, una estimación por peso y edad (Mifflin-St Jeor con 175 cm).
        let age = Double(bodyData.age ?? 40)
        let estimated = 10 * weight + 6.25 * 175 - 5 * age + (female ? -161 : 5)
        let bmr = readings.last?.values[.bmr] ?? estimated
        return DailyTargets(bmr: bmr, active: activeEnergy, weight: weight, goal: goal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dayPicker
                    if Calendar.current.isDateInToday(day) { FastingCard(entries: entries) }
                    SummaryCard(total: total, targets: targets, goal: $goal)
                    ForEach(Meal.allCases) { meal in
                        MealCard(meal: meal, entries: dayEntries.filter { $0.meal == meal.rawValue }) { adding = meal }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Comida")
            .toolbar {
                Button { adding = .now } label: { Image(systemName: "plus") }
            }
            .sheet(item: $adding) { meal in
                AddFoodSheet(meal: meal, day: day)
            }
            .task(id: day) { activeEnergy = await Self.activeEnergy(on: day) }
            .task {
                // Los registros de antes de que Vital escribiera en Salud se envían una vez.
                let pending = entries.filter { $0.healthID == nil }
                pending.forEach { $0.syncToHealth() }
                if !pending.isEmpty { try? context.save() }
            }
        }
        .tint(.white)
    }

    private var dayPicker: some View {
        HStack {
            Button { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(Calendar.current.isDateInToday(day) ? "Hoy" : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .font(.headline)
            Spacer()
            Button { day = Calendar.current.date(byAdding: .day, value: 1, to: day)! } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDateInToday(day))
        }
        .padding(.top, 4)
    }

    /// Calorías activas del reloj en el día (lo que gastas moviéndote, además del metabolismo basal).
    static func activeEnergy(on day: Date) async -> Double {
        if ProcessInfo.processInfo.arguments.contains("-demo") { return 520 }
        let store = HKHealthStore()
        let type = HKQuantityType(.activeEnergyBurned)
        try? await store.requestAuthorization(toShare: [], read: [type])
        let end = min(.now, Calendar.current.date(byAdding: .day, value: 1, to: day)!)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: day, end: end)),
            options: .cumulativeSum)
        return (try? await descriptor.result(for: store))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
    }
}

// MARK: - Resumen del día

private struct SummaryCard: View {
    let total: Nutrients
    let targets: DailyTargets
    @Binding var goal: WeightGoal

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.1), lineWidth: 12)
                        Circle().trim(from: 0, to: min(1, total.kcal / max(1, targets.kcal)))
                            .stroke(kcalColor.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(Int(total.kcal.rounded()))").font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("de \(Int(targets.kcal.rounded())) kcal").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        let left = targets.kcal - total.kcal
                        Text(left >= 0 ? "Te quedan \(Int(left.rounded())) kcal" : "Te pasaste \(Int(-left.rounded())) kcal")
                            .font(.headline).foregroundStyle(kcalColor)
                        Text("Basal \(Int(targets.bmr)) + activa \(Int(targets.active)) kcal").font(.caption).foregroundStyle(.secondary)
                        Menu {
                            Picker("Objetivo", selection: $goal) { ForEach(WeightGoal.allCases) { Text($0.title).tag($0) } }
                        } label: {
                            Label(goal.title, systemImage: "target").font(.caption.weight(.semibold))
                        }
                    }
                }
                macro("Proteína", total.protein, targets.protein, "g", .pink, higherIsGood: true)
                macro("Carbohidratos", total.carbs, targets.carbs, "g", .orange)
                macro("Grasa", total.fat, targets.fat, "g", .yellow)
                Divider().overlay(.white.opacity(0.15))
                HStack {
                    limit("Azúcares", total.sugar ?? 0, DailyTargets.sugarLimit, "g")
                    limit("Sodio", total.sodium ?? 0, DailyTargets.sodiumLimit, "mg")
                    limit("Fibra", total.fiber ?? 0, 30, "g", higherIsGood: true)
                }
            }
        }
    }

    /// Verde hasta el objetivo; naranja si te pasas hasta un 10 %; rojo si más.
    private var kcalColor: Color {
        let r = total.kcal / max(1, targets.kcal)
        return r <= 1 ? .green : r <= 1.1 ? .orange : .red
    }

    private func macro(_ name: String, _ value: Double, _ target: Double, _ unit: String, _ color: Color, higherIsGood: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.callout)
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(target.rounded())) \(unit)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(color.gradient).frame(width: geo.size.width * min(1, value / max(1, target)))
                }
            }
            .frame(height: 8)
        }
    }

    private func limit(_ name: String, _ value: Double, _ max: Double, _ unit: String, higherIsGood: Bool = false) -> some View {
        let r = value / max
        let color: Color = higherIsGood ? (r >= 0.8 ? .green : r >= 0.5 ? .orange : .red) : (r <= 0.8 ? .green : r <= 1 ? .orange : .red)
        return VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(value.rounded())) \(unit)").font(.callout.bold()).foregroundStyle(color)
            Text("\(higherIsGood ? "meta" : "límite") \(Int(max)) \(unit)").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MealCard: View {
    let meal: Meal
    let entries: [FoodEntry]
    let onAdd: () -> Void
    @State private var editing: FoodEntry?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(meal.title, systemImage: meal.icon).font(.headline)
                    Spacer()
                    let kcal = entries.map(\.nutrients.kcal).reduce(0, +)
                    if kcal > 0 { Text("\(Int(kcal.rounded())) kcal").font(.callout).foregroundStyle(.secondary) }
                    Button(action: onAdd) { Image(systemName: "plus.circle.fill").font(.title3) }.buttonStyle(.plain)
                }
                ForEach(entries) { entry in
                    Button { editing = entry } label: {
                        HStack {
                            if let food = entry.food {
                                Circle().fill(LabelAnalysis.analyze(food).rating.color).frame(width: 8, height: 8)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.food?.name ?? "—").font(.callout)
                                Text("\(Int(entry.grams.rounded())) \(entry.food?.isDrink == true ? "ml" : "g") · P \(Int(entry.nutrients.protein.rounded())) · C \(Int(entry.nutrients.carbs.rounded())) · G \(Int(entry.nutrients.fat.rounded()))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(entry.nutrients.kcal.rounded()))").font(.callout.monospacedDigit())
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if entries.isEmpty {
                    Text("Sin registros").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Toca un registro para cambiarlo o borrarlo").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .sheet(item: $editing) { entry in
            NavigationStack {
                if let food = entry.food {
                    FoodAmountView(food: food, meal: Meal(rawValue: entry.meal) ?? meal, day: entry.date, entry: entry) { editing = nil }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { editing = nil } } }
                }
            }
        }
    }
}

// MARK: - Añadir comida

private enum AddRoute: Hashable {
    case amount(Food)
    case label(Food)
}

struct AddFoodSheet: View {
    let meal: Meal
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedFood.lastUsed, order: .reverse) private var saved: [SavedFood]
    @State private var path: [AddRoute] = []
    @State private var text = ""
    @State private var scanning = false
    @State private var photographing = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var looking: String?
    @State private var notFound: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 10) {
                        sourceButton("Escanear código", "barcode.viewfinder") { scanning = true }
                            .disabled(!BarcodeScannerView.isAvailable)
                        sourceButton("Foto de etiqueta", "camera.fill") { photographing = true }
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.on.rectangle").font(.title3)
                                Text("Desde fotos").font(.caption2)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        path.append(.label(Food(id: "propio-\(UUID().uuidString)", name: text, per100: Nutrients(), portions: [], source: "propio")))
                    } label: {
                        Label("Crear comida a mano", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    if let looking { HStack { ProgressView(); Text("Buscando \(looking)…").foregroundStyle(.secondary) } }
                    if let notFound {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("El código \(notFound) no está en Open Food Facts.").font(.callout)
                            Button("Fotografiar la etiqueta") { photographing = true }.font(.callout.bold())
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                let savedFoods = saved.compactMap(\.food).filter { matches($0) }
                if !savedFoods.isEmpty {
                    Section("Tus productos") { ForEach(savedFoods) { row($0) } }
                }
                Section("Comida tica") {
                    ForEach(TicoFoods.all.filter { matches($0) }) { row($0) }
                }
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar: gallo pinto, natilla…")
            .navigationTitle("Añadir a \(meal.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .navigationDestination(for: AddRoute.self) { route in
                switch route {
                case .amount(let food): FoodAmountView(food: food, meal: meal, day: day) { dismiss() }
                case .label(let food): LabelEditView(food: food) { path.append(.amount($0)) }
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                ZStack(alignment: .topTrailing) {
                    BarcodeScannerView { code in
                        scanning = false
                        Task { await lookUp(code) }
                    }
                    .ignoresSafeArea()
                    Button { scanning = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white)
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $photographing) {
                CameraPicker { image in Task { await readLabel(image) } }.ignoresSafeArea()
            }
            .onChange(of: pickedPhoto) {
                Task {
                    if let data = try? await pickedPhoto?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await readLabel(image)
                    }
                }
            }
        }
    }

    private func matches(_ food: Food) -> Bool {
        guard !text.isEmpty else { return true }
        let fold = { (s: String) in s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")) }
        let haystack = fold(food.name + " " + (food.brand ?? ""))
        return fold(text).split(separator: " ").allSatisfy { haystack.contains($0) }
    }

    private func row(_ food: Food) -> some View {
        NavigationLink(value: AddRoute.amount(food)) {
            HStack {
                Circle().fill(LabelAnalysis.analyze(food).rating.color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(food.name)
                    Text("\(Int(food.per100.kcal.rounded())) kcal por 100 \(food.isDrink ? "ml" : "g")\(food.brand.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sourceButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func lookUp(_ code: String) async {
        notFound = nil
        if let known = saved.compactMap(\.food).first(where: { $0.barcode == code }) { path.append(.amount(known)); return }
        looking = code
        let product = await OpenFoodFacts.product(barcode: code)
        looking = nil
        if let product {
            // Sin tabla nutricional en la base: se completa con la foto o a mano.
            path.append(product.per100.kcal > 0 ? .amount(product) : .label(product))
        } else {
            notFound = code
        }
    }

    private func readLabel(_ image: UIImage) async {
        looking = "en la etiqueta"
        let read = await NutritionLabelReader.read(image)
        looking = nil
        var food = Food(id: "etiqueta-\(UUID().uuidString)", name: "", per100: read.per100,
                        portions: read.portion.map { [Portion(name: "1 porción", grams: $0)] } ?? [],
                        isDrink: read.isDrink, ingredients: read.ingredients, source: "etiqueta")
        if let code = notFound { food.barcode = code; food.id = "codigo-\(code)" }
        notFound = nil
        path.append(.label(food))
    }
}

// MARK: - Revisar lo leído de la etiqueta

/// Problemas que hacen imposible un valor por 100 g (p. ej. 45 000 kcal por leer mal la porción).
enum NutrientCheck {
    static func errors(_ n: Nutrients) -> [String] {
        var out: [String] = []
        if n.kcal > 900 { out.append("Más de 900 kcal por 100 g es imposible (el aceite puro tiene 884).") }
        if n.protein > 100 || n.carbs > 100 || n.fat > 100 { out.append("Ningún nutriente puede pasar de 100 g en 100 g.") }
        else if n.protein + n.carbs + n.fat > 101 { out.append("Proteína + carbohidratos + grasa suman más de 100 g por cada 100 g.") }
        if (n.sodium ?? 0) > 40000 { out.append("El sodio es demasiado alto (ni la sal pura llega a 40 000 mg por 100 g).") }
        return out
    }

    /// Las calorías no cuadran con los macros (4 kcal por g de proteína y carbohidrato, 9 por g de grasa).
    static func warning(_ n: Nutrients) -> String? {
        let fromMacros = n.protein * 4 + n.carbs * 4 + n.fat * 9
        guard n.kcal > 0 || fromMacros > 0 else { return nil }
        if abs(n.kcal - fromMacros) > max(40, n.kcal * 0.3) {
            return "Las calorías (\(Int(n.kcal.rounded()))) no cuadran con los macros (≈ \(Int(fromMacros.rounded())) kcal). Revisa los números."
        }
        return nil
    }
}

struct LabelEditView: View {
    @State var food: Food
    var buttonTitle = "Continuar"
    let onContinue: (Food) -> Void
    /// Se editan los números tal como vienen en la etiqueta: por porción (lo usual en Costa Rica) o por 100 g.
    @State private var perPortion: Bool
    @State private var shootingIngredients = false
    @State private var pickedIngredients: PhotosPickerItem?
    @State private var readingIngredients = false

    init(food: Food, buttonTitle: String = "Continuar", onContinue: @escaping (Food) -> Void) {
        _food = State(initialValue: food)
        self.buttonTitle = buttonTitle
        self.onContinue = onContinue
        _perPortion = State(initialValue: !food.portions.isEmpty)
    }

    private var portion: Double? { food.portions.first?.grams }
    private var unit: String { food.isDrink ? "ml" : "g" }
    /// De lo mostrado a lo guardado (por 100).
    private var factor: Double { perPortion ? (portion.map { $0 > 0 ? $0 / 100 : 1 } ?? 1) : 1 }
    private var errors: [String] { NutrientCheck.errors(food.per100) }

    var body: some View {
        Form {
            Section("Producto") {
                TextField("Nombre", text: $food.name)
                TextField("Marca", text: Binding(get: { food.brand ?? "" }, set: { food.brand = $0.isEmpty ? nil : $0 }))
                Toggle("Es una bebida", isOn: $food.isDrink)
                HStack {
                    Text("Porción")
                    Spacer()
                    TextField(unit, value: Binding(get: { portion }, set: { v in
                        // Si los números se ven por porción, al cambiar la porción se mantienen los de la etiqueta.
                        let shown = perPortion ? food.per100.scaled(portion ?? 100) : nil
                        food.portions = v.flatMap { $0 > 0 ? [Portion(name: "1 porción", grams: $0)] : nil } ?? []
                        if let shown, let p = food.portions.first?.grams { food.per100 = shown.scaled(10000 / p) }
                        if food.portions.isEmpty { perPortion = false }
                    }), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                    Text(unit).foregroundStyle(.secondary)
                }
            }
            Section {
                if portion != nil {
                    Picker("La etiqueta dice", selection: $perPortion) {
                        Text("Por porción").tag(true)
                        Text("Por 100 \(unit)").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                field("Calorías", \.kcal, "kcal")
                field("Proteína", \.protein, "g")
                field("Carbohidratos", \.carbs, "g")
                optional("Azúcares", \.sugar, "g")
                optional("Fibra", \.fiber, "g")
                field("Grasa total", \.fat, "g")
                optional("Grasa saturada", \.saturated, "g")
                optional("Grasa trans", \.trans, "g")
                optional("Sodio", \.sodium, "mg")
            } header: {
                Text(perPortion ? "Por porción (\(LabelAnalysis.fmt(portion ?? 0)) \(unit))" : "Por 100 \(unit)")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(errors, id: \.self) { Label($0, systemImage: "xmark.octagon.fill").foregroundStyle(.red) }
                    if errors.isEmpty, let w = NutrientCheck.warning(food.per100) { Label(w, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    Text("Copia los números tal como aparecen en la etiqueta y corrige los que estén mal.")
                }
            }
            Section {
                HStack {
                    Button { shootingIngredients = true } label: { Label("Tomar foto", systemImage: "camera.fill") }
                        .buttonStyle(.borderless)
                    Spacer()
                    PhotosPicker(selection: $pickedIngredients, matching: .images) { Label("Desde fotos", systemImage: "photo.on.rectangle") }
                        .buttonStyle(.borderless)
                }
                if readingIngredients { HStack { ProgressView(); Text("Leyendo los ingredientes…").foregroundStyle(.secondary) } }
                TextEditor(text: Binding(get: { food.ingredients ?? "" }, set: { food.ingredients = $0 }))
                    .frame(minHeight: 100)
            } header: {
                Text("Ingredientes")
            } footer: {
                Text("Fotografía la lista de ingredientes del empaque y se escribe sola; revísala por si algo se leyó mal.")
            }
            Section("Análisis") { LabelAnalysisView(food: food) }
        }
        .tint(.cyan)
        .sheet(isPresented: $shootingIngredients) {
            CameraPicker { image in Task { await readIngredients(image) } }.ignoresSafeArea()
        }
        .onChange(of: pickedIngredients) {
            Task {
                if let data = try? await pickedIngredients?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await readIngredients(image)
                }
                pickedIngredients = nil
            }
        }
        .navigationTitle("Etiqueta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(buttonTitle) {
                if food.name.trimmingCharacters(in: .whitespaces).isEmpty { food.name = "Producto" }
                onContinue(food)
            }
            .disabled(!errors.isEmpty)
        }
    }

    private func readIngredients(_ image: UIImage) async {
        readingIngredients = true
        let text = await NutritionLabelReader.ingredients(image)
        readingIngredients = false
        if let text { food.ingredients = text }
    }

    private func field(_ title: String, _ key: WritableKeyPath<Nutrients, Double>, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: Binding(get: { round(food.per100[keyPath: key] * factor) }, set: { food.per100[keyPath: key] = $0 / factor }), format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    private func optional(_ title: String, _ key: WritableKeyPath<Nutrients, Double?>, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: Binding(get: { food.per100[keyPath: key].map { round($0 * factor) } }, set: { food.per100[keyPath: key] = $0.map { $0 / factor } }), format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    /// Dos decimales, para que la conversión por porción no muestre 3,9999.
    private func round(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}

// MARK: - Cantidad (al añadir o al editar un registro)

private struct FoodAmountView: View {
    @State private var food: Food
    let meal: Meal
    let day: Date
    /// Registro que se está editando; nil al añadir uno nuevo.
    let entry: FoodEntry?
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @State private var portionIndex = 0       // -1 = gramos
    @State private var quantity = 1.0
    @State private var grams = 100.0
    @State private var chosenMeal: Meal
    @State private var correcting = false

    init(food: Food, meal: Meal, day: Date, entry: FoodEntry? = nil, onDone: @escaping () -> Void) {
        _food = State(initialValue: food)
        self.meal = meal
        self.day = day
        self.entry = entry
        self.onDone = onDone
        _chosenMeal = State(initialValue: meal)
        if let entry {
            // Se vuelve a mostrar como porciones si la cantidad es un múltiplo de media porción; si no, en gramos.
            let match = food.portions.enumerated().first { _, p in
                let q = entry.grams / p.grams
                return p.grams > 0 && q >= 0.5 && q <= 20 && abs(q * 2 - (q * 2).rounded()) < 0.01
            }
            _portionIndex = State(initialValue: match?.offset ?? -1)
            _quantity = State(initialValue: match.map { (entry.grams / $0.element.grams * 2).rounded() / 2 } ?? 1)
            _grams = State(initialValue: entry.grams)
        } else {
            _portionIndex = State(initialValue: food.portions.isEmpty ? -1 : 0)
        }
    }

    private var totalGrams: Double { portionIndex >= 0 && portionIndex < food.portions.count ? food.portions[portionIndex].grams * quantity : grams }
    private var amount: Nutrients { food.per100.scaled(totalGrams) }
    private var unit: String { food.isDrink ? "ml" : "g" }
    private var errors: [String] { NutrientCheck.errors(food.per100) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).font(.title3.bold())
                    if let brand = food.brand { Text(brand).foregroundStyle(.secondary) }
                }
                Picker("Comida", selection: $chosenMeal) { ForEach(Meal.allCases) { Text($0.title).tag($0) } }
                Picker("Medida", selection: $portionIndex) {
                    ForEach(Array(food.portions.enumerated()), id: \.offset) { i, p in
                        Text("\(p.name) (\(LabelAnalysis.fmt(p.grams)) \(unit))").tag(i)
                    }
                    Text(food.isDrink ? "Mililitros" : "Gramos").tag(-1)
                }
                if portionIndex >= 0 {
                    Stepper("Cantidad: \(quantity.formatted(.number.precision(.fractionLength(0...1))))", value: $quantity, in: 0.5...20, step: 0.5)
                } else {
                    HStack {
                        Text("Cantidad")
                        Spacer()
                        TextField("100", value: $grams, format: .number).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                        Text(unit).foregroundStyle(.secondary)
                    }
                }
            }
            if !errors.isEmpty {
                Section {
                    ForEach(errors, id: \.self) { Label($0, systemImage: "xmark.octagon.fill").foregroundStyle(.red) }
                    Button("Corregir los valores del producto") { correcting = true }.bold()
                }
            }
            Section("En esta cantidad (\(Int(totalGrams.rounded())) \(unit))") {
                row("Calorías", amount.kcal, "kcal")
                row("Proteína", amount.protein, "g")
                row("Carbohidratos", amount.carbs, "g")
                if let s = amount.sugar { row("  Azúcares", s, "g", note: "\(LabelAnalysis.fmt(s / 4)) cucharaditas") }
                row("Grasa", amount.fat, "g")
                if let s = amount.sodium { row("Sodio", s, "mg", note: "\(Int((s / DailyTargets.sodiumLimit * 100).rounded())) % del límite diario") }
            }
            if food.source != "tico" && errors.isEmpty {
                Section { Button("Corregir los valores del producto") { correcting = true } }
            }
            Section("Calificación") { LabelAnalysisView(food: food) }
            if let entry {
                Section {
                    Button("Borrar este registro", role: .destructive) {
                        entry.removeFromHealth()
                        context.delete(entry)
                        try? context.save()
                        onDone()
                    }
                }
            }
        }
        .tint(.cyan)
        .navigationTitle(entry == nil ? "Cantidad" : "Editar registro")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $correcting) {
            LabelEditView(food: food, buttonTitle: "Listo") { fixed in
                food = fixed
                if portionIndex >= food.portions.count { portionIndex = food.portions.isEmpty ? -1 : 0 }
                correcting = false
            }
        }
        .toolbar {
            Button(entry == nil ? "Añadir" : "Guardar") { save() }
                .bold()
                .disabled(!errors.isEmpty || totalGrams <= 0)
        }
    }

    private func save() {
        if let entry {
            entry.meal = chosenMeal.rawValue
            entry.grams = totalGrams
            entry.foodJSON = String(data: (try? JSONEncoder().encode(food)) ?? Data(), encoding: .utf8) ?? entry.foodJSON
            entry.syncToHealth()
        } else {
            // Se registra a la hora actual si es hoy; si es otro día, a mediodía de ese día.
            let date = Calendar.current.isDateInToday(day) ? Date.now : Calendar.current.date(byAdding: .hour, value: 12, to: day)!
            let new = FoodEntry(date: date, meal: chosenMeal, food: food, grams: totalGrams)
            context.insert(new)
            new.syncToHealth()
            // Comer rompe el ayuno en curso (solo si es comida de verdad y de ahora).
            if Calendar.current.isDateInToday(day) { Fasting.foodLogged(at: date, kcal: amount.kcal, in: context) }
        }
        if food.source != "tico" {
            // Se guarda (o se corrige) el producto para la próxima vez.
            let id = food.id
            let existing = (try? context.fetch(FetchDescriptor<SavedFood>(predicate: #Predicate { $0.id == id }))) ?? []
            existing.forEach { context.delete($0) }
            context.insert(SavedFood(food: food))
        }
        try? context.save()
        onDone()
    }

    private func row(_ title: String, _ value: Double, _ unit: String, note: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(LabelAnalysis.fmt(value)) \(unit)").monospacedDigit()
                if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}
