import SwiftData
import SwiftUI

/// Dónde está cada fila en pantalla, para saber dónde se suelta el botón + al arrastrarlo.
/// No se observa a propósito: cambia mucho al desplazarse y solo se consulta durante el arrastre.
final class RowSlots {
    struct Slot { var section: String; var index: Int; var frame: CGRect; var empty: Bool }
    var slots: [String: Slot] = [:]

    func set(_ section: String, _ index: Int, _ frame: CGRect, empty: Bool = false) {
        slots["\(section)#\(index)"] = Slot(section: section, index: index, frame: frame, empty: empty)
    }
    func remove(_ section: String, _ index: Int) { slots["\(section)#\(index)"] = nil }

    /// Sección y posición donde caería algo soltado en `p`, y la altura de la línea que lo indica.
    func target(at p: CGPoint) -> (section: String, index: Int, lineY: CGFloat)? {
        var best: (String, Int, CGFloat, CGFloat)?
        for s in slots.values {
            let f = s.frame
            let dist: CGFloat = p.y < f.minY ? f.minY - p.y : (p.y > f.maxY ? p.y - f.maxY : 0)
            guard dist < 44 else { continue }
            let pick: (String, Int, CGFloat, CGFloat)
            if s.empty {
                pick = (s.section, 0, f.midY, dist)
            } else if p.y < f.midY {
                pick = (s.section, s.index, f.minY, dist)
            } else {
                pick = (s.section, s.index + 1, f.maxY, dist)
            }
            if best == nil || pick.3 < best!.3 { best = pick }
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }
}

/// Una próxima repetición (todavía no existe como tarea; se muestra en gris en Próximo).
struct Ghost: Identifiable, Hashable {
    var id: String
    var title: String
    var rule: String
}

/// Un grupo de tareas dentro de una lista (un día, un proyecto, un encabezado, «Esta noche»…).
struct TaskSection: Identifiable {
    enum Style { case plain, day, evening, link, heading }
    var id: String
    var title: String?
    var detail: String?
    var style: Style = .plain
    var link: Destination?
    var pie: Double?
    var heading: Heading?
    var items: [TodoItem]
    var todayOrdering = false
    var movable = true
    var showEmpty = false
    var rowStyle = RowStyle()
    /// Día de la sección (Hoy o un día de Próximo): una tarea soltada aquí queda para ese día.
    var date: Date?
    var evening = false
    var events: [CalEvent] = []
    var ghosts: [Ghost] = []
}

/// La columna derecha: cualquier lista (Hoy, un proyecto, un área, una etiqueta…).
struct ListScreen: View {
    let destination: Destination
    @Environment(AppState.self) private var state
    @Environment(CalendarFeed.self) private var calendar
    @Environment(\.modelContext) private var context
    @Query private var todos: [TodoItem]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \TagItem.order) private var tags: [TagItem]
    @State private var sheet: PickerSheet?
    @State private var tagFilter: TagItem?
    @State private var showDone = false
    @State private var renaming: Heading?
    @State private var renameText = ""
    @State private var confirmEmptyTrash = false
    @State private var confirmDeleteArea = false
    @State private var rowSlots = RowSlots()
    /// Dónde va el botón + mientras se arrastra (coordenadas de pantalla).
    @State private var dragPoint: CGPoint?

    private var rules: ListRules { state.rules }
    private var today: Date { state.today }

    private var smart: SmartList? { if case .smart(let s) = destination { s } else { nil } }
    private var project: Project? {
        guard case .project(let id) = destination else { return nil }
        return projects.first { $0.persistentModelID == id }
    }
    private var area: Area? {
        guard case .area(let id) = destination else { return nil }
        return areas.first { $0.persistentModelID == id }
    }
    private var tag: TagItem? {
        guard case .tag(let id) = destination else { return nil }
        return tags.first { $0.persistentModelID == id }
    }

    var body: some View {
        let sections = filtered(buildSections())
        let isEmpty = sections.allSatisfy { $0.items.isEmpty && $0.events.isEmpty } && extraProjects.isEmpty
        List {
            header
            tagBar(sections)
            ForEach(sections) { sec in
                if !sec.items.isEmpty || sec.showEmpty || !sec.events.isEmpty {
                    Section {
                        ForEach(sec.events) { e in
                            EventRow(event: e)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                        }
                        ForEach(Array(sec.items.enumerated()), id: \.element.id) { i, t in
                            row(t, sec)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rowSlots.set(sec.id, i, $0) }
                                .onDisappear { rowSlots.remove(sec.id, i) }
                                .listRowSeparator(.hidden)
                        }
                        .onMove(perform: sec.movable && tagFilter == nil ? { reorder(sec, $0, $1) } : nil)
                        ForEach(sec.ghosts) { g in ghostRow(g) }
                        if sec.items.isEmpty && sec.showEmpty && canAdd {
                            // Hueco para soltar el + en una sección vacía (un día de Próximo, un encabezado).
                            Color.clear
                                .frame(height: 12)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                    rowSlots.set(sec.id, 0, $0, empty: true)
                                }
                                .onDisappear { rowSlots.remove(sec.id, 0) }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                        }
                    } header: {
                        sectionHeader(sec)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            extras
            doneToggle
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 34)
        .overlay {
            if isEmpty && project == nil && area == nil {
                ContentUnavailableView {
                    Label(title, systemImage: smart?.icon ?? "tag")
                } description: {
                    Text(smart?.emptyText ?? "No hay tareas con esta etiqueta.")
                }
                .allowsHitTesting(false)
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(project != nil || area != nil ? .inline : .large)
        #endif
        .toolbar { toolbar }
        .overlay { dragOverlay }
        .overlay(alignment: .bottomTrailing) { if canAdd && state.expanded == nil { addButton(sections) } }
        .sheet(item: $sheet) { PickerSheetView(sheet: $0) }
        .alert("Encabezado", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") {
                renaming?.title = renameText.trimmingCharacters(in: .whitespaces).isEmpty ? "Sin nombre" : renameText
                renaming = nil
            }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("¿Vaciar la papelera?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
            Button("Vaciar papelera", role: .destructive, action: emptyTrash)
        } message: {
            Text("Las tareas y proyectos de la papelera se borrarán para siempre.")
        }
        .confirmationDialog("¿Eliminar esta área?", isPresented: $confirmDeleteArea, titleVisibility: .visible) {
            Button("Eliminar área", role: .destructive) {
                if let area {
                    state.selection = .smart(.today)
                    context.delete(area)
                }
            }
        } message: {
            Text("Se borrarán también sus proyectos y tareas.")
        }
        .onChange(of: state.newTaskTick) { _, _ in newTask() }
        .onChange(of: state.expanded) { old, new in
            discardIfEmpty(old)
            if new == nil { hideKeyboard() }
        }
        .onAppear {
            state.recentlyDone.removeAll()
            state.expanded = state.pendingExpand
            state.pendingExpand = nil
        }
    }

    private var title: String {
        if let smart { return smart.title }
        if let project { return project.displayTitle }
        if let area { return area.displayTitle }
        if let tag { return tag.title }
        return ""
    }

    private var canAdd: Bool {
        if let smart { return smart != .logbook && smart != .trash }
        return true
    }

    // MARK: - Secciones

    private func sorted(_ items: [TodoItem], today: Bool = false) -> [TodoItem] {
        items.sorted { today ? ($0.todayOrder, $0.order) < ($1.todayOrder, $1.order) : $0.order < $1.order }
    }

    private func buildSections() -> [TaskSection] {
        if let smart {
            switch smart {
            case .inbox:
                return [TaskSection(id: "inbox", items: sorted(todos.filter(rules.inbox)))]
            case .today:
                let all = todos.filter(rules.inToday)
                let style = RowStyle(showContext: true)
                return [
                    TaskSection(id: "cal", items: [], movable: false, events: calendar.events(on: today)),
                    TaskSection(id: "day", items: sorted(all.filter { !rules.isEvening($0) }, today: true),
                                todayOrdering: true, showEmpty: true, rowStyle: style, date: today),
                    TaskSection(id: "evening", title: "Esta noche", style: .evening,
                                items: sorted(all.filter(rules.isEvening), today: true), todayOrdering: true, rowStyle: style,
                                date: today, evening: true),
                ]
            case .upcoming:
                return upcomingSections()
            case .anytime:
                return grouped(todos.filter(rules.anytime))
            case .someday:
                return grouped(todos.filter(rules.someday))
            case .logbook:
                return logbookSections()
            case .trash:
                let items = todos.filter(\.trashed).sorted { $0.order > $1.order }
                return [TaskSection(id: "trash", items: items, movable: false, rowStyle: RowStyle(showContext: true))]
            }
        }
        let style = RowStyle(showWhen: true, showTodayMark: true)
        if let project {
            let mine = project.todos.filter(rules.inContainer)
            var result = [TaskSection(id: "loose", items: sorted(mine.filter { $0.heading == nil }), rowStyle: style)]
            for h in project.sortedHeadings {
                result.append(TaskSection(id: "h-\(h.persistentModelID.hashValue)", title: h.title, style: .heading,
                                          heading: h, items: sorted(mine.filter { $0.heading == h }), showEmpty: true,
                                          rowStyle: style))
            }
            return result
        }
        if let area {
            return [TaskSection(id: "area", items: sorted(area.todos.filter { $0.project == nil && rules.inContainer($0) }),
                                rowStyle: style)]
        }
        if let tag {
            let items = todos.filter { rules.visible($0) && $0.tags.contains(tag) }
            return [TaskSection(id: "tag", items: sorted(items), rowStyle: RowStyle(showContext: true, showWhen: true, showTodayMark: true))]
        }
        return []
    }

    /// Agrupa por «sueltas», áreas y proyectos (para Cuando sea y Algún día).
    private func grouped(_ items: [TodoItem]) -> [TaskSection] {
        let style = RowStyle(showWhen: smart == .someday, showTodayMark: true)
        var result = [TaskSection(id: "loose", items: sorted(items.filter { $0.project == nil && $0.area == nil }), rowStyle: style)]
        func addProjects(_ list: [Project]) {
            for p in list {
                let mine = items.filter { $0.project == p }
                guard !mine.isEmpty else { continue }
                result.append(TaskSection(id: "p-\(p.persistentModelID.hashValue)", title: p.displayTitle, style: .link,
                                          link: .project(p.persistentModelID), pie: p.progress, items: sorted(mine),
                                          rowStyle: style))
            }
        }
        addProjects(projects.filter { $0.area == nil })
        for a in areas {
            let mine = items.filter { $0.area == a && $0.project == nil }
            if !mine.isEmpty {
                result.append(TaskSection(id: "a-\(a.persistentModelID.hashValue)", title: a.displayTitle, style: .link,
                                          link: .area(a.persistentModelID), items: sorted(mine), rowStyle: style))
            }
            addProjects(projects.filter { $0.area == a })
        }
        return result
    }

    private func upcomingSections() -> [TaskSection] {
        let dated = todos.compactMap { t in rules.upcomingDate(t).map { (t, $0.startOfDay) } }
        var result: [TaskSection] = []
        let dayStyle = RowStyle(showContext: true)
        // Próximas repeticiones de las tareas con calendario fijo (aún no existen como tareas).
        let week = today.adding(days: 7)
        var ghosts: [Date: [Ghost]] = [:]
        for t in todos where !t.trashed && t.status == .open && t.parentActive {
            guard let rule = t.repeatRule, rule.mode == .fixed else { continue }
            for d in rule.upcoming(from: t.startDate ?? today, until: week) where d > today {
                ghosts[d, default: []].append(Ghost(id: "\(t.uid)-\(d.timeIntervalSinceReferenceDate)", title: t.displayTitle,
                                                    rule: rule.summary))
            }
        }
        for i in 1...7 {
            let day = today.adding(days: i)
            let items = dated.filter { $0.1 == day }.map(\.0)
            result.append(TaskSection(id: "d\(i)", title: i == 1 ? "Mañana" : Fmt.weekday(day), detail: Fmt.dayNumber(day),
                                      style: .day, items: sorted(items), movable: false, showEmpty: true, rowStyle: dayStyle,
                                      date: day, events: calendar.events(on: day), ghosts: ghosts[day] ?? []))
        }
        let later = dated.filter { $0.1 > today.adding(days: 7) }.sorted { ($0.1, $0.0.order) < ($1.1, $1.0.order) }
        let cal = Calendar.hecho
        var months: [Date: [TodoItem]] = [:]
        for (t, d) in later {
            let m = cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
            months[m, default: []].append(t)
        }
        for m in months.keys.sorted() {
            result.append(TaskSection(id: "m\(m.timeIntervalSinceReferenceDate)", title: Fmt.month(m, today: today),
                                      items: months[m] ?? [], movable: false,
                                      rowStyle: RowStyle(showContext: true, showWhen: true)))
        }
        return result
    }

    private func logbookSections() -> [TaskSection] {
        let done = todos.filter { !$0.trashed && $0.isDone }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(500)
        var days: [(Date, [TodoItem])] = []
        for t in done {
            let d = (t.completedAt ?? .distantPast).startOfDay
            if let last = days.last, last.0 == d { days[days.count - 1].1.append(t) } else { days.append((d, [t])) }
        }
        return days.map { d, items in
            TaskSection(id: "l\(d.timeIntervalSinceReferenceDate)", title: Fmt.day(d, today: today), items: items,
                        movable: false, rowStyle: RowStyle(showContext: true))
        }
    }

    private func filtered(_ sections: [TaskSection]) -> [TaskSection] {
        guard let tagFilter else { return sections }
        return sections.map { s in
            var s = s
            s.items = s.items.filter { $0.tags.contains(tagFilter) }
            s.showEmpty = s.showEmpty && s.style != .heading
            return s
        }
    }

    /// Proyectos que se muestran como filas (área, Algún día, Registro, Papelera).
    private var extraProjects: [Project] {
        if let area { return projects.filter { $0.area == area && $0.status == .open && !$0.trashed } }
        switch smart {
        case .someday: return projects.filter { $0.status == .open && !$0.trashed && $0.start == .someday && $0.startDate == nil }
        case .upcoming: return projects.filter { $0.status == .open && !$0.trashed && ($0.startDate.map { $0 > today } ?? false) }
        case .logbook: return projects.filter { $0.status != .open && !$0.trashed }
        case .trash: return projects.filter(\.trashed)
        default: return []
        }
    }

    // MARK: - Filas

    @ViewBuilder private func row(_ t: TodoItem, _ sec: TaskSection) -> some View {
        let id = t.persistentModelID
        Group {
            if state.expanded == id {
                TaskCard(item: t) { sheet = $0 }
            } else {
                TaskRow(item: t, style: sec.rowStyle)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy) { state.expanded = id }
                    }
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
        .swipeActions(edge: .leading) {
            if smart == .trash {
                Button { restore(t) } label: { Label("Restaurar", systemImage: "arrow.uturn.backward") }
                    .tint(Theme.accent)
            } else if !t.isDone {
                Button { sheet = .when(t) } label: { Label("Cuándo", systemImage: "calendar") }
                    .tint(Theme.accent)
            }
        }
        .swipeActions(edge: .trailing) {
            if smart == .trash {
                Button(role: .destructive) { context.delete(t) } label: { Label("Eliminar", systemImage: "trash") }
            } else {
                Button(role: .destructive) { trash(t) } label: { Label("Papelera", systemImage: "trash") }
            }
        }
        .contextMenu { menu(t) }
    }

    @ViewBuilder private func menu(_ t: TodoItem) -> some View {
        if smart == .trash {
            Button("Restaurar", systemImage: "arrow.uturn.backward") { restore(t) }
            Button("Eliminar para siempre", systemImage: "trash", role: .destructive) { context.delete(t) }
        } else {
            Button(t.isDone ? "Marcar como pendiente" : "Completar", systemImage: "checkmark.square") {
                withAnimation { t.toggleDone(state) }
            }
            if !t.isDone {
                Menu("Cuándo", systemImage: "calendar") {
                    Button("Hoy", systemImage: "sun.max") { withAnimation { t.setWhen(.today, today: today) } }
                    Button("Esta noche", systemImage: "moon") { withAnimation { t.setWhen(.evening, today: today) } }
                    Button("Mañana", systemImage: "sunrise") { withAnimation { t.setWhen(.date(today.adding(days: 1)), today: today) } }
                    Button("Algún día", systemImage: "archivebox") { withAnimation { t.setWhen(.someday, today: today) } }
                    Button("Quitar fecha", systemImage: "xmark") { withAnimation { t.setWhen(.inbox, today: today) } }
                    Divider()
                    Button("Otro día…", systemImage: "calendar") { sheet = .when(t) }
                }
            }
            Button("Fecha límite…", systemImage: "flag") { sheet = .deadline(t) }
            Button("Etiquetas…", systemImage: "tag") { sheet = .tags(t) }
            Button("Mover a…", systemImage: "folder") { sheet = .move(t) }
            Button("Duplicar", systemImage: "plus.square.on.square") {
                _ = t.duplicate(in: context)
            }
            if t.status == .open {
                Button("Cancelar tarea", systemImage: "xmark.square") {
                    withAnimation { t.finish(.canceled, state: state) }
                }
            }
            Divider()
            Button("Mover a la papelera", systemImage: "trash", role: .destructive) { trash(t) }
        }
    }

    @ViewBuilder private func sectionHeader(_ sec: TaskSection) -> some View {
        switch sec.style {
        case .plain:
            if let t = sec.title { Text(t).font(.headline).foregroundStyle(.secondary) }
        case .day:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(sec.detail ?? "").font(.title2.bold()).foregroundStyle(.primary)
                Text(sec.title ?? "").font(.headline).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        case .evening:
            Label("Esta noche", systemImage: "moon.fill")
                .font(.headline)
                .foregroundStyle(Theme.evening)
                .padding(.top, 10)
        case .link:
            Button {
                if let link = sec.link { state.selection = link }
            } label: {
                HStack(spacing: 8) {
                    if let pie = sec.pie { ProgressPie(progress: pie) } else {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.area)
                    }
                    Text(sec.title ?? "").font(.headline).foregroundStyle(.primary)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        case .heading:
            HStack {
                Text(sec.title ?? "").font(.headline).foregroundStyle(Theme.accent)
                Spacer()
                if let h = sec.heading {
                    Menu {
                        Button("Nueva tarea aquí", systemImage: "plus") { newTask(heading: h) }
                        Button("Renombrar", systemImage: "pencil") { renameText = h.title; renaming = h }
                        Button("Eliminar encabezado", systemImage: "trash", role: .destructive) { context.delete(h) }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(.top, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.accent.opacity(0.3)).frame(height: 1).offset(y: 4) }
        }
    }

    // MARK: - Cabeceras de proyecto y área

    @ViewBuilder private var header: some View {
        if let project {
            ProjectHeader(project: project) { sheet = $0 }
                .listRowSeparator(.hidden)
        } else if let area {
            AreaHeader(area: area)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private func tagBar(_ sections: [TaskSection]) -> some View {
        let used = Set(buildSections().flatMap { $0.items.flatMap(\.tags) })
        let shown = tags.filter { used.contains($0) }
        if !shown.isEmpty && tag == nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    tagButton("Todas", selected: tagFilter == nil) { tagFilter = nil }
                    ForEach(shown) { t in
                        tagButton(t.title, selected: tagFilter == t) { tagFilter = tagFilter == t ? nil : t }
                    }
                }
            }
            .listRowSeparator(.hidden)
        }
    }

    private func tagButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? .white : .primary)
                .background(selected ? Theme.accent : Color.secondary.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var extras: some View {
        let list = extraProjects
        if !list.isEmpty {
            Section {
                ForEach(list) { p in projectRow(p) }
            } header: {
                Text(smart == .logbook ? "Proyectos completados" : smart == .trash ? "Proyectos" : smart == .upcoming ? "Proyectos programados" : "Proyectos")
                    .font(.headline).foregroundStyle(.secondary)
            }
        }
    }

    private func projectRow(_ p: Project) -> some View {
        Button {
            state.selection = .project(p.persistentModelID)
        } label: {
            HStack(spacing: 10) {
                ProgressPie(progress: p.progress, done: p.status != .open)
                Text(p.displayTitle).foregroundStyle(p.status == .open ? .primary : .secondary)
                Spacer()
                if let s = p.startDate, s > today {
                    Text(Fmt.day(s, today: today)).font(.caption).foregroundStyle(.secondary)
                } else if p.openCount > 0 && p.status == .open {
                    Text("\(p.openCount)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .contextMenu {
            if p.trashed {
                Button("Restaurar", systemImage: "arrow.uturn.backward") { p.trashed = false }
                Button("Eliminar para siempre", systemImage: "trash", role: .destructive) { context.delete(p) }
            } else if p.status != .open {
                Button("Reabrir proyecto", systemImage: "arrow.uturn.backward") { p.status = .open }
            } else {
                Button("Mover a la papelera", systemImage: "trash", role: .destructive) { p.trashed = true }
            }
        }
    }

    /// En un proyecto o área: muestra u oculta lo ya completado.
    @ViewBuilder private var doneToggle: some View {
        let done: [TodoItem] = {
            if let project { return project.liveTodos.filter { $0.isDone && !state.recentlyDone.contains($0.persistentModelID) } }
            if let area { return area.todos.filter { $0.project == nil && !$0.trashed && $0.isDone && !state.recentlyDone.contains($0.persistentModelID) } }
            return []
        }()
        if !done.isEmpty {
            Section {
                Button(showDone ? "Ocultar completadas" : "Mostrar \(done.count) completada\(done.count == 1 ? "" : "s")") {
                    withAnimation { showDone.toggle() }
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
                if showDone {
                    ForEach(done.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) { t in
                        row(t, TaskSection(id: "done", items: [], movable: false))
                    }
                }
            }
        }
    }

    // MARK: - Barra de herramientas

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let project {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Nuevo encabezado", systemImage: "text.badge.plus") { newHeading(project) }
                    Button("Cuándo…", systemImage: "calendar") { sheet = .projectWhen(project) }
                    Button("Fecha límite…", systemImage: "flag") { sheet = .projectDeadline(project) }
                    Button("Mover a un área…", systemImage: "folder") { sheet = .projectArea(project) }
                    Divider()
                    if project.status == .open {
                        Button("Completar proyecto", systemImage: "checkmark.circle") {
                            project.complete()
                            state.selection = .smart(.logbook)
                        }
                    } else {
                        Button("Reabrir proyecto", systemImage: "arrow.uturn.backward") { project.status = .open }
                    }
                    Button("Mover a la papelera", systemImage: "trash", role: .destructive) {
                        project.trashed = true
                        state.selection = .smart(.trash)
                    }
                } label: {
                    Label("Opciones del proyecto", systemImage: "ellipsis.circle")
                }
            }
        }
        if let area {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Nuevo proyecto en esta área", systemImage: "plus") {
                        let p = Project(title: "", area: area)
                        context.insert(p)
                        try? context.save()
                        state.selection = .project(p.persistentModelID)
                    }
                    Button("Eliminar área", systemImage: "trash", role: .destructive) { confirmDeleteArea = true }
                } label: {
                    Label("Opciones del área", systemImage: "ellipsis.circle")
                }
            }
        }
        if smart == .trash {
            ToolbarItem(placement: .primaryAction) {
                Button("Vaciar") { confirmEmptyTrash = true }
                    .disabled(todos.allSatisfy { !$0.trashed } && projects.allSatisfy { !$0.trashed })
            }
        }
    }

    /// El botón +: tócalo para una tarea nueva, o mantenlo presionado y arrástralo al lugar exacto donde la quieres.
    private func addButton(_ sections: [TaskSection]) -> some View {
        Image(systemName: "plus")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Theme.accent, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .opacity(dragPoint == nil ? 1 : 0.35)
            .contentShape(Circle())
            .onTapGesture { newTask() }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { dragPoint = $0.location }
                    .onEnded { value in
                        dragPoint = nil
                        if let t = rowSlots.target(at: value.location), let sec = sections.first(where: { $0.id == t.section }) {
                            insertNew(in: sec, at: t.index)
                        } else if value.translation.height < -80 {
                            newTask()
                        }
                    }
            )
            .padding(20)
            .help("Nueva tarea (⌘N). Arrástralo para ponerla en un lugar exacto.")
            .accessibilityLabel("Nueva tarea")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { newTask() }
    }

    /// Mientras se arrastra el +: el botón sigue al dedo y una línea marca dónde caerá la tarea.
    @ViewBuilder private var dragOverlay: some View {
        if let p = dragPoint {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                ZStack(alignment: .topLeading) {
                    if let t = rowSlots.target(at: p) {
                        HStack(spacing: 0) {
                            Circle().fill(Theme.accent).frame(width: 8, height: 8)
                            Rectangle().fill(Theme.accent).frame(height: 2)
                        }
                        .padding(.horizontal, 12)
                        .offset(y: t.lineY - origin.y - 4)
                    }
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        .position(x: p.x - origin.x, y: p.y - origin.y - 30)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func ghostRow(_ g: Ghost) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat")
                .font(.caption)
                .frame(width: 18)
            Text(g.title)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tertiary)
        .padding(.vertical, 3)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
        .help(g.rule)
    }

    // MARK: - Acciones

    private func newTask(heading: Heading? = nil) {
        guard canAdd else { return }
        let t = TodoItem()
        context.insert(t)
        switch destination {
        case .smart(.inbox): t.start = .inbox
        case .smart(.today): t.setWhen(.today, today: today)
        case .smart(.upcoming): t.setWhen(.date(today.adding(days: 1)), today: today)
        case .smart(.anytime): t.start = .anytime
        case .smart(.someday): t.start = .someday
        case .project: if let project { t.move(project: project, heading: heading, area: nil) }
        case .area: if let area { t.move(project: nil, area: area) }
        case .tag: if let tag { t.tags = [tag] }
        default: break
        }
        t.order = Date().timeIntervalSinceReferenceDate
        try? context.save()
        withAnimation(.snappy) { state.expanded = t.persistentModelID }
    }

    /// Crea una tarea en un lugar exacto: esa sección (día, «Esta noche», encabezado, proyecto) y esa posición.
    private func insertNew(in sec: TaskSection, at index: Int) {
        guard canAdd else { return }
        let t = TodoItem()
        context.insert(t)
        switch destination {
        case .smart(.inbox): t.start = .inbox
        case .smart(.anytime): t.start = .anytime
        case .smart(.someday): t.start = .someday
        case .project: if let project { t.move(project: project, heading: sec.heading, area: nil) }
        case .area: if let area { t.move(project: nil, area: area) }
        case .tag: if let tag { t.tags = [tag] }
        default: break
        }
        if case .project(let id) = sec.link, let p = projects.first(where: { $0.persistentModelID == id }) {
            t.move(project: p, area: nil)
        } else if case .area(let id) = sec.link, let a = areas.first(where: { $0.persistentModelID == id }) {
            t.move(project: nil, area: a)
        }
        if smart == .someday { t.setWhen(.someday, today: today) }
        if let d = sec.date { t.setWhen(sec.evening ? .evening : (d <= today ? .today : .date(d)), today: today) }

        // Orden: justo entre la tarea de arriba y la de abajo.
        let key: (TodoItem) -> Double = sec.todayOrdering ? { $0.todayOrder } : { $0.order }
        let above = index > 0 && index - 1 < sec.items.count ? key(sec.items[index - 1]) : nil
        let below = index < sec.items.count ? key(sec.items[index]) : nil
        let value: Double
        switch (above, below) {
        case let (a?, b?): value = (a + b) / 2
        case let (a?, nil): value = a + 1
        case let (nil, b?): value = b - 1
        default: value = Date().timeIntervalSinceReferenceDate
        }
        if sec.todayOrdering { t.todayOrder = value } else { t.order = value }
        try? context.save()
        withAnimation(.snappy) { state.expanded = t.persistentModelID }
    }

    private func newHeading(_ p: Project) {
        let h = Heading(title: "Nuevo encabezado", project: p)
        context.insert(h)
        renameText = ""
        renaming = h
    }

    /// Al cerrar una tarea nueva sin escribir nada, se descarta.
    private func discardIfEmpty(_ id: PersistentIdentifier?) {
        guard let id, let t = todos.first(where: { $0.persistentModelID == id }) else { return }
        if t.title.trimmingCharacters(in: .whitespaces).isEmpty && t.notes.isEmpty && t.checklist.isEmpty {
            context.delete(t)
        }
    }

    private func reorder(_ sec: TaskSection, _ from: IndexSet, _ to: Int) {
        var items = sec.items
        items.move(fromOffsets: from, toOffset: to)
        for (i, t) in items.enumerated() {
            if sec.todayOrdering { t.todayOrder = Double(i) } else { t.order = Double(i) }
        }
    }

    private func trash(_ t: TodoItem) {
        withAnimation {
            if state.expanded == t.persistentModelID { state.expanded = nil }
            t.trashed = true
            t.order = Date().timeIntervalSinceReferenceDate
        }
    }

    private func restore(_ t: TodoItem) {
        withAnimation { t.trashed = false }
    }

    private func emptyTrash() {
        for t in todos where t.trashed { context.delete(t) }
        for p in projects where p.trashed { context.delete(p) }
        try? context.save()
    }
}

// MARK: - Cabeceras

/// Cierra el teclado (si la tarjeta que lo tenía abierto desapareció, iOS a veces lo deja visible).
func hideKeyboard() {
    #if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

private struct ProjectHeader: View {
    @Bindable var project: Project
    var onPick: (PickerSheet) -> Void
    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ProgressPie(progress: project.progress, done: project.status != .open)
                    .scaleEffect(1.4)
                    .padding(.leading, 3)
                TextField("Nuevo proyecto", text: $project.title)
                    .textFieldStyle(.plain)
                    .font(.title.bold())
                    .focused($focused)
            }
            TextField("Notas", text: $project.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)
                .lineLimit(1...20)
            FlowLayout(spacing: 6) {
                if let a = project.area {
                    Chip(icon: "folder", text: a.displayTitle, onTap: { onPick(.projectArea(project)) })
                }
                if let s = project.startDate, s > state.today {
                    Chip(icon: "calendar", text: Fmt.day(s, today: state.today), onTap: { onPick(.projectWhen(project)) },
                         onClear: { project.setWhen(.anytime, today: state.today) })
                } else if project.start == .someday {
                    Chip(icon: "archivebox.fill", text: "Algún día", color: Theme.someday, onTap: { onPick(.projectWhen(project)) },
                         onClear: { project.setWhen(.anytime, today: state.today) })
                }
                if let d = project.deadline {
                    Chip(icon: "flag.fill", text: Fmt.deadline(d, today: state.today),
                         color: d <= state.today ? Theme.deadline : .secondary,
                         onTap: { onPick(.projectDeadline(project)) }, onClear: { project.deadline = nil })
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear { if project.title.isEmpty { focused = true } }
    }
}

private struct AreaHeader: View {
    @Bindable var area: Area
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(Theme.area)
            TextField("Nueva área", text: $area.title)
                .textFieldStyle(.plain)
                .font(.title.bold())
                .focused($focused)
        }
        .padding(.vertical, 8)
        .onAppear { if area.title.isEmpty { focused = true } }
    }
}
