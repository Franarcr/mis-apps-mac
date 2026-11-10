import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var todos: [TodoItem]
    @Query(sort: \TagItem.order) private var tags: [TagItem]
    @State private var search = ""
    @State private var searchShown = false
    @State private var showSettings = false

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            Group {
                if search.trimmingCharacters(in: .whitespaces).isEmpty {
                    sidebar
                } else {
                    SearchResults(query: search, todos: todos, projects: projects, areas: areas, tags: tags) {
                        search = ""
                        searchShown = false
                    }
                }
            }
            .searchable(text: $search, isPresented: $searchShown, placement: searchPlacement, prompt: "Buscar")
            .navigationTitle("Hecho")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            #endif
        } detail: {
            if let sel = state.selection {
                ListScreen(destination: sel)
                    .id(sel)
            } else {
                ContentUnavailableView("Elige una lista", systemImage: "checklist")
            }
        }
        .onChange(of: state.newProjectTick) { _, _ in newProject(area: nil) }
        .onChange(of: state.searchTick) { _, _ in searchShown = true }
    }

    private var searchPlacement: SearchFieldPlacement {
        #if os(macOS)
        .sidebar
        #else
        .navigationBarDrawer(displayMode: .automatic)
        #endif
    }

    // MARK: - Barra lateral

    private var rules: ListRules { state.rules }

    private var sidebar: some View {
        @Bindable var state = state
        let live = projects.filter { $0.status == .open && !$0.trashed }
        let loose = live.filter { $0.area == nil }
        return List(selection: $state.selection) {
            Section {
                ForEach(SmartList.main, id: \.self) { list in
                    NavigationLink(value: Destination.smart(list)) {
                        SmartRow(list: list, count: count(list))
                    }
                }
            }
            Section {
                ForEach(SmartList.archive, id: \.self) { list in
                    NavigationLink(value: Destination.smart(list)) {
                        SmartRow(list: list, count: nil)
                    }
                }
            }
            if !loose.isEmpty {
                Section {
                    ForEach(loose) { p in projectLink(p) }
                }
            }
            ForEach(areas) { area in
                Section {
                    NavigationLink(value: Destination.area(area.persistentModelID)) {
                        Label {
                            Text(area.displayTitle).fontWeight(.semibold)
                        } icon: {
                            Image(systemName: "folder.fill").foregroundStyle(Theme.area)
                        }
                    }
                    .contextMenu {
                        Button("Nuevo proyecto en esta área", systemImage: "plus") { newProject(area: area) }
                        Button("Eliminar área", systemImage: "trash", role: .destructive) { deleteArea(area) }
                    }
                    ForEach(live.filter { $0.area == area }) { p in projectLink(p) }
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #endif
        .sheet(isPresented: $showSettings) { SettingsView() }
        .toolbar {
            ToolbarItem(placement: newListPlacement) {
                Button { showSettings = true } label: { Label("Ajustes", systemImage: "gearshape") }
            }
            ToolbarItem(placement: newListPlacement) {
                Menu {
                    Button("Nuevo proyecto", systemImage: "circle.dashed") { newProject(area: nil) }
                    Button("Nueva área", systemImage: "folder") { newArea() }
                } label: {
                    Label("Nueva lista", systemImage: "plus")
                }
            }
        }
    }

    private var newListPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .bottomBar
        #endif
    }

    private func projectLink(_ p: Project) -> some View {
        NavigationLink(value: Destination.project(p.persistentModelID)) {
            Label {
                Text(p.displayTitle)
                    .foregroundStyle(p.start == .someday ? .secondary : .primary)
            } icon: {
                ProgressPie(progress: p.progress)
            }
        }
        .contextMenu {
            Button("Completar proyecto", systemImage: "checkmark.circle") { p.complete() }
            Button("Mover a la papelera", systemImage: "trash", role: .destructive) {
                p.trashed = true
                if state.selection == .project(p.persistentModelID) { state.selection = .smart(.today) }
            }
        }
    }

    private func count(_ list: SmartList) -> Int? {
        let n: Int
        switch list {
        case .inbox: n = todos.filter { rules.inbox($0) && !$0.isDone }.count
        case .today: n = todos.filter { rules.inToday($0) && !$0.isDone }.count
        default: return nil
        }
        return n == 0 ? nil : n
    }

    private func newProject(area: Area?) {
        let p = Project(title: "", area: area)
        context.insert(p)
        try? context.save()
        state.selection = .project(p.persistentModelID)
    }

    private func newArea() {
        let a = Area(title: "")
        context.insert(a)
        try? context.save()
        state.selection = .area(a.persistentModelID)
    }

    private func deleteArea(_ area: Area) {
        if state.selection == .area(area.persistentModelID) { state.selection = .smart(.today) }
        context.delete(area)
        try? context.save()
    }
}

private struct SmartRow: View {
    var list: SmartList
    var count: Int?

    var body: some View {
        Label {
            HStack {
                Text(list.title)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(list == .today ? Theme.today : .secondary)
                }
            }
        } icon: {
            Image(systemName: list.icon).foregroundStyle(list.color)
        }
    }
}

// MARK: - Búsqueda

private struct SearchResults: View {
    @Environment(AppState.self) private var state
    var query: String
    var todos: [TodoItem]
    var projects: [Project]
    var areas: [Area]
    var tags: [TagItem]
    var onPick: () -> Void

    private func matches(_ s: String) -> Bool {
        s.range(of: query.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var body: some View {
        let foundTags = tags.filter { matches($0.title) }
        let foundAreas = areas.filter { matches($0.title) }
        let foundProjects = projects.filter { !$0.trashed && matches($0.title) }
        let foundTodos = todos
            .filter { !$0.trashed && (matches($0.title) || matches($0.notes)) }
            .sorted { ($0.isDone ? 1 : 0, $0.title) < ($1.isDone ? 1 : 0, $1.title) }
            .prefix(60)

        List {
            if foundTags.isEmpty && foundAreas.isEmpty && foundProjects.isEmpty && foundTodos.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            if !foundTags.isEmpty {
                Section("Etiquetas") {
                    ForEach(foundTags) { t in
                        Button { go(.tag(t.persistentModelID)) } label: {
                            Label(t.title, systemImage: "tag")
                        }
                    }
                }
            }
            if !foundAreas.isEmpty || !foundProjects.isEmpty {
                Section("Listas") {
                    ForEach(foundAreas) { a in
                        Button { go(.area(a.persistentModelID)) } label: {
                            Label(a.displayTitle, systemImage: "folder.fill")
                        }
                    }
                    ForEach(foundProjects) { p in
                        Button { go(.project(p.persistentModelID)) } label: {
                            Label { Text(p.displayTitle) } icon: { ProgressPie(progress: p.progress, done: p.status != .open) }
                        }
                    }
                }
            }
            if !foundTodos.isEmpty {
                Section("Tareas") {
                    ForEach(Array(foundTodos)) { t in
                        Button { open(t) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: t.isDone ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(t.isDone ? Theme.accent : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.displayTitle).foregroundStyle(t.isDone ? .secondary : .primary)
                                    if let c = t.contextName {
                                        Text(c).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func go(_ d: Destination) {
        state.selection = d
        onPick()
    }

    private func open(_ t: TodoItem) {
        state.open(t)
        onPick()
    }
}
