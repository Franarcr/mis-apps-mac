import SwiftData
import SwiftUI

@main
struct HechoApp: App {
    @State private var state = AppState()
    @State private var calendar = CalendarFeed.shared
    @Environment(\.scenePhase) private var scenePhase
    private let container = Store.container

    init() { Reminders.setUp() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(calendar)
                .tint(Theme.accent)
                .task {
                    Store.seedIfNeeded(container.mainContext)
                    Store.removeEmpty(container.mainContext)
                    Sync.run(container.mainContext, state: state)
                    PeerSync.shared.start(container.mainContext)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { state.refreshDay() }
                    PeerSync.shared.scenePhaseChanged(to: phase)
                    if phase != .inactive { Sync.run(container.mainContext, state: state) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    state.refreshDay()
                    Sync.run(container.mainContext, state: state)
                }
                .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                    state.scheduleSync { Sync.run(container.mainContext, state: state) }
                }
                .onOpenURL { url in
                    if url.host() == "hoy" { state.selection = .smart(.today) }
                    // Desde un evento del calendario: hecho://tarea/<id>
                    if url.host() == "tarea" {
                        let uid = url.lastPathComponent
                        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.uid == uid })
                        if let t = try? container.mainContext.fetch(descriptor).first { state.open(t) }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 480)
                #endif
        }
        .modelContainer(container)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nueva tarea") { state.newTaskTick += 1 }
                    .keyboardShortcut("n")
                Button("Nuevo proyecto") { state.newProjectTick += 1 }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
            CommandGroup(after: .sidebar) {
                Button("Buscar") { state.searchTick += 1 }
                    .keyboardShortcut("f")
            }
            CommandMenu("Ir") {
                ForEach(Array((SmartList.main + SmartList.archive).enumerated()), id: \.offset) { i, list in
                    Button(list.title) { state.selection = .smart(list) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
        }
        #endif
    }
}

/// Lo que se muestra en la columna derecha.
enum Destination: Hashable {
    case smart(SmartList)
    case project(PersistentIdentifier)
    case area(PersistentIdentifier)
    case tag(PersistentIdentifier)
}

/// Estado de la sesión, compartido por todas las pantallas.
@Observable final class AppState {
    #if os(macOS)
    var selection: Destination? = .smart(.today)
    #else
    var selection: Destination?
    #endif
    /// Tareas completadas en esta visita: siguen a la vista, tachadas, hasta cambiar de lista.
    var recentlyDone: Set<PersistentIdentifier> = []
    /// La tarea abierta como tarjeta.
    var expanded: PersistentIdentifier?
    /// Tarea que se abrirá al llegar a la próxima lista (desde la búsqueda).
    var pendingExpand: PersistentIdentifier?
    var today = Date().startOfDay
    var newTaskTick = 0
    var newProjectTick = 0
    var searchTick = 0

    @ObservationIgnored private var syncTask: Task<Void, Never>?

    /// Agrupa varios guardados seguidos en una sola sincronización.
    func scheduleSync(_ work: @escaping @MainActor () -> Void) {
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { work() }
        }
    }

    func refreshDay() {
        let now = Date().startOfDay
        if now != today { today = now }
    }

    var rules: ListRules { ListRules(today: today, recent: recentlyDone) }

    /// Abre la lista donde vive la tarea y despliega su tarjeta.
    func open(_ t: TodoItem) {
        let dest: Destination
        if t.trashed {
            dest = .smart(.trash)
        } else if t.isDone {
            dest = .smart(.logbook)
        } else if let p = t.project {
            dest = .project(p.persistentModelID)
        } else if let a = t.area {
            dest = .area(a.persistentModelID)
        } else if rules.inbox(t) {
            dest = .smart(.inbox)
        } else if rules.inToday(t) {
            dest = .smart(.today)
        } else if rules.upcomingDate(t) != nil {
            dest = .smart(.upcoming)
        } else if t.start == .someday {
            dest = .smart(.someday)
        } else {
            dest = .smart(.anytime)
        }
        if selection == dest {
            expanded = t.persistentModelID
        } else {
            pendingExpand = t.persistentModelID
            selection = dest
        }
    }
}
