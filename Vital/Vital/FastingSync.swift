import ActivityKit
import AppIntents
import SwiftData
import WidgetKit

/// La base de datos de Vital, una sola para la app y para las acciones de Siri y los widgets.
enum VitalStore {
    static let container: ModelContainer = try! ModelContainer(
        for: Routine.self, RoutineItem.self, SetLog.self, CustomExercise.self, ScaleReading.self,
        FoodEntry.self, SavedFood.self, FastingSession.self)
}

/// Lleva el estado del ayuno a los widgets y a la Actividad en vivo después de cada cambio.
@MainActor
enum FastingSync {
    static func refresh(in context: ModelContext = VitalStore.container.mainContext) {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: "ayunoActivo")
        let goal = defaults.object(forKey: "ayunoMeta") as? Double ?? 16
        let sessions = (try? context.fetch(FetchDescriptor<FastingSession>(sortBy: [SortDescriptor(\.start)]))) ?? []
        let active = enabled ? sessions.last(where: \.isActive) : nil

        let snapshot = FastingSnapshot(enabled: enabled, activeStart: active?.start, goalHours: active?.goalHours ?? goal,
                                       lastEnd: sessions.last(where: { !$0.isActive })?.end,
                                       streak: FastingStats(sessions: sessions).streak)
        if FastingSnapshot.load() != snapshot {
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }

        let showActivity = defaults.object(forKey: "ayunoActividad") as? Bool ?? true
        let state = active.map { FastingActivityAttributes.ContentState(start: $0.start, goalHours: $0.goalHours) }
        Task { await syncActivity(showActivity ? state : nil) }
    }

    /// Una sola Actividad en vivo mientras hay ayuno; ninguna si no.
    /// Apple la cierra a las 8 h: al abrir Vital se vuelve a crear.
    private static func syncActivity(_ state: FastingActivityAttributes.ContentState?) async {
        let current = Activity<FastingActivityAttributes>.activities
        guard let state else {
            for a in current { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        // Pasada la meta se marca «stale» y la vista muestra «Meta cumplida» sin que la app tenga que actualizarla.
        let content = ActivityContent(state: state, staleDate: state.goalDate)
        let alive = current.filter { $0.activityState == .active || $0.activityState == .stale }
        if let keep = alive.first {
            if keep.content.state != state { await keep.update(content) }
            for other in current where other.id != keep.id { await other.end(nil, dismissalPolicy: .immediate) }
        } else {
            for a in current { await a.end(nil, dismissalPolicy: .immediate) }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            _ = try? Activity.request(attributes: FastingActivityAttributes(), content: content)
        }
    }
}

/// Lo que hacen los botones de los widgets y Siri, dentro de la app.
@MainActor
enum FastingActions {
    static func start() -> String {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "ayunoActivo") else { return "Activa el control de ayuno en Vital › Comida." }
        let context = VitalStore.container.mainContext
        if let active = Fasting.active(in: context) {
            return "Ya llevas \(fastingDuration(active.hours)) de ayuno."
        }
        let goal = defaults.object(forKey: "ayunoMeta") as? Double ?? 16
        Fasting.start(at: .now, goalHours: goal, in: context)
        let end = Date.now.addingTimeInterval(goal * 3600).formatted(date: .omitted, time: .shortened)
        return "Ayuno empezado. Meta de \(Int(goal)) h, a las \(end)."
    }

    static func end() -> String {
        let context = VitalStore.container.mainContext
        guard let active = Fasting.active(in: context) else { return "No hay un ayuno en curso." }
        Fasting.finish(active, in: context)
        return active.reachedGoal
            ? "Ayuno de \(fastingDuration(active.hours)) terminado. ¡Meta cumplida!"
            : "Ayuno de \(fastingDuration(active.hours)) terminado (meta \(Int(active.goalHours)) h)."
    }

    static func status() -> String {
        let context = VitalStore.container.mainContext
        guard UserDefaults.standard.bool(forKey: "ayunoActivo") else { return "El control de ayuno está desactivado." }
        if let active = Fasting.active(in: context) {
            let phase = FastingPhase.at(hours: active.hours).title.lowercased()
            return active.reachedGoal
                ? "Llevas \(fastingDuration(active.hours)): meta cumplida. Fase: \(phase)."
                : "Llevas \(fastingDuration(active.hours)) de \(Int(active.goalHours)) h. Fase: \(phase). Te faltan \(fastingDuration(active.goalHours - active.hours))."
        }
        if let closes = FastingSnapshot.load()?.windowCloses, closes > .now {
            return "No estás en ayuno. Tu ventana para comer cierra a las \(closes.formatted(date: .omitted, time: .shortened))."
        }
        return "No hay un ayuno en curso."
    }
}

struct FastingStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "¿Cuánto llevo de ayuno?"
    static var description = IntentDescription("Dice cuánto llevas de ayuno y en qué fase estás.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await FastingActions.status()))
    }
}

/// Frases para Siri y la app Atajos (aparecen solas, sin configurar nada).
struct VitalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFastIntent(),
                    phrases: ["Empezar ayuno en \(.applicationName)", "Empieza mi ayuno en \(.applicationName)"],
                    shortTitle: "Empezar ayuno", systemImageName: "timer")
        AppShortcut(intent: EndFastIntent(),
                    phrases: ["Terminar ayuno en \(.applicationName)", "Termina mi ayuno en \(.applicationName)"],
                    shortTitle: "Terminar ayuno", systemImageName: "fork.knife")
        AppShortcut(intent: FastingStatusIntent(),
                    phrases: ["Cuánto llevo de ayuno en \(.applicationName)", "Estado del ayuno en \(.applicationName)"],
                    shortTitle: "Estado del ayuno", systemImageName: "hourglass")
    }
}
