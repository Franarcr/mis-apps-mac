import SwiftData
import SwiftUI

@main
struct VitalApp: App {
    @StateObject private var model = VitalModel()
    @StateObject private var training = TrainingModel()
    @StateObject private var bodyData = BodyModel()
    @StateObject private var stress = StressModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = "salud"
    private let container = VitalStore.container

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                Tab("Salud", systemImage: "heart.text.square.fill", value: "salud") {
                    TodayView(model: model, bodyData: bodyData, stress: stress)
                }
                Tab("Entreno", systemImage: "figure.run", value: "entreno") {
                    TrainingView(model: training, health: model)
                }
                Tab("Rutinas", systemImage: "dumbbell.fill", value: "rutinas") {
                    RoutinesView(health: model)
                }
                Tab("Comida", systemImage: "fork.knife", value: "comida") {
                    NutritionView(bodyData: bodyData)
                }
                Tab("Ayuno", systemImage: "timer", value: "ayuno") {
                    FastingTab()
                }
            }
            .environment(\.openFastingTab, OpenFastingTab { tab = "ayuno" })
            .task {
                PhoneWatchLink.shared.activate(container: container)
                await maintenance()
                // Widgets y Actividad en vivo con el ayuno de ahora (Apple cierra la actividad a las 8 h).
                FastingSync.refresh()
                await AppExpiry.scheduleReminder()
                await model.load()
                await bodyData.load()
                // El último pesaje de la báscula es el peso corporal con el que se estiman las cargas.
                if let weight = bodyData.latestWeight { UserDefaults.standard.set(weight, forKey: "pesoCorporal") }
                // Entrenos de fuerza guardados sin calorías por versiones anteriores: se completan con lo que midió el reloj.
                let repaired = await HealthWriter.repairStrengthWorkouts()
                if ProcessInfo.processInfo.arguments.contains("-depurar") { repaired.forEach { print("ENTRENO", $0) } }
                if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-inicio-entreno"),
                   i + 1 < ProcessInfo.processInfo.arguments.count {
                    let parts = ProcessInfo.processInfo.arguments[i + 1].split(separator: ":").compactMap { Int($0) }
                    if parts.count >= 2, let start = Calendar.current.date(bySettingHour: parts[0], minute: parts[1],
                                                                                second: parts.count > 2 ? parts[2] : 0, of: .now) {
                        print("ENTRENO", await HealthWriter.fixTodayStart(start))
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("-traza-manana") {
                    let day = Calendar.current.startOfDay(for: .now)
                    for line in await HealthWriter.morningTrace(from: day.addingTimeInterval(4.5 * 3600), to: day.addingTimeInterval(7.5 * 3600)) { print("TRAZA", line) }
                }
                // El entreno usa tu pulso en reposo para calcular la carga.
                await training.load(restingHR: model.baseline(\.restingHR)?.mean)
                // Estrés y energía necesitan la recuperación, el pulso máximo y los entrenamientos de hoy.
                await stress.load(health: model, training: training)
                PhoneWatchLink.shared.publish(health: model, stress: stress)
            }
            .onChange(of: scenePhase) { _, phase in
                // Al volver a Vital (p. ej. después de editar una rutina o de un entreno), el reloj recibe lo último.
                if phase == .active { FastingSync.refresh() }
                if phase == .active, model.state == .ready { PhoneWatchLink.shared.publish(health: model, stress: stress) }
            }
            // El ayuno cruza datos de todas las pestañas (sueño, entreno, peso).
            .environmentObject(model)
            .environmentObject(training)
            .environmentObject(bodyData)
            .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }

    /// Ayudas para probar desde el Mac (se pasan al abrir la app con devicectl o simctl):
    /// - `-leer captura.jpg`: imprime lo que el lector saca de una captura (ruta o archivo en Documentos).
    /// - `-borrar-lecturas-guardadas-el 2026-11-04`: borra las lecturas de la báscula guardadas ese día.
    /// - `-ayuno-demo`: activa el control de ayuno, carga una semana de ayunos de ejemplo (si no hay ninguno)
    ///   y muestra una curva de glucosa de ejemplo mientras la app siga abierta con este argumento.
    /// - `-ayuno-demo-borrar`: borra los ayunos de ejemplo.
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
        if args.contains("-ayuno-demo") {
            let context = container.mainContext
            if ((try? context.fetchCount(FetchDescriptor<FastingSession>())) ?? 0) == 0 {
                let cal = Calendar.current
                let today = cal.startOfDay(for: .now)
                for (daysAgo, startHour, hours) in [(7, 20.0, 15.5), (6, 19.5, 16.2), (5, 21.0, 14.0), (4, 19.75, 16.5), (3, 20.25, 16.1), (2, 19.5, 17.0)] {
                    let start = cal.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(startHour * 3600)
                    let s = FastingSession(start: start, goalHours: 16)
                    s.end = start.addingTimeInterval(hours * 3600)
                    s.endedBy = "ejemplo"
                    context.insert(s)
                }
                let current = FastingSession(start: .now.addingTimeInterval(-13.4 * 3600), goalHours: 16)
                current.endedBy = "ejemplo"
                context.insert(current)
                try? context.save()
            }
            UserDefaults.standard.set(true, forKey: "ayunoActivo")
        }
        if args.contains("-ayuno-demo-borrar") {
            let context = container.mainContext
            let all = (try? context.fetch(FetchDescriptor<FastingSession>())) ?? []
            let demo = all.filter { $0.endedBy == "ejemplo" }
            demo.forEach { context.delete($0) }
            try? context.save()
            if demo.contains(where: \.isActive) { FastingNotifications.cancelAll() }
            print("AYUNOS DE EJEMPLO BORRADOS", demo.count)
        }
    }
}

extension ISO8601DateFormatter {
    static let dayFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}
