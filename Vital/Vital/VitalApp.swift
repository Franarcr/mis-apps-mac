import SwiftData
import SwiftUI

@main
struct VitalApp: App {
    @StateObject private var model = VitalModel()
    @StateObject private var training = TrainingModel()
    @StateObject private var bodyData = BodyModel()
    @StateObject private var stress = StressModel()
    private let container = try! ModelContainer(for: Routine.self, RoutineItem.self, SetLog.self, CustomExercise.self, ScaleReading.self, FoodEntry.self, SavedFood.self)

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Salud", systemImage: "heart.text.square.fill") {
                    TodayView(model: model, bodyData: bodyData, stress: stress)
                }
                Tab("Entreno", systemImage: "figure.run") {
                    TrainingView(model: training, health: model)
                }
                Tab("Rutinas", systemImage: "dumbbell.fill") {
                    RoutinesView(health: model)
                }
                Tab("Comida", systemImage: "fork.knife") {
                    NutritionView(bodyData: bodyData)
                }
            }
            .task {
                await maintenance()
                await model.load()
                await bodyData.load()
                // El último pesaje de la báscula es el peso corporal con el que se estiman las cargas.
                if let weight = bodyData.latestWeight { UserDefaults.standard.set(weight, forKey: "pesoCorporal") }
                // El entreno usa tu pulso en reposo para calcular la carga.
                await training.load(restingHR: model.baseline(\.restingHR)?.mean)
                // Estrés y energía necesitan la recuperación, el pulso máximo y los entrenamientos de hoy.
                await stress.load(health: model, training: training)
            }
            .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }

    /// Ayudas para probar desde el Mac (se pasan al abrir la app con devicectl o simctl):
    /// - `-leer captura.jpg`: imprime lo que el lector saca de una captura (ruta o archivo en Documentos).
    /// - `-borrar-lecturas-guardadas-el 2026-11-04`: borra las lecturas de la báscula guardadas ese día.
    @MainActor private func maintenance() async {
        let args = ProcessInfo.processInfo.arguments
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let i = args.firstIndex(of: "-leer"), i + 1 < args.count,
           let image = UIImage(contentsOfFile: args[i + 1]) ?? UIImage(contentsOfFile: documents.appendingPathComponent(args[i + 1]).path) {
            let read = await ScaleScreenshotReader.read(image)
            print("LECTURA fecha:", read.date as Any)
            for metric in ScaleMetric.allCases { print("LECTURA", metric.title, read.values[metric] as Any) }
        }
        if let i = args.firstIndex(of: "-borrar-lecturas-guardadas-el"), i + 1 < args.count,
           let day = ISO8601DateFormatter.dayFormatter.date(from: args[i + 1]) {
            let context = container.mainContext
            let all = (try? context.fetch(FetchDescriptor<ScaleReading>())) ?? []
            let doomed = all.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            doomed.forEach { context.delete($0) }
            try? context.save()
            print("BORRADAS", doomed.count, "de", all.count)
        }
    }
}

private extension ISO8601DateFormatter {
    static let dayFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}
