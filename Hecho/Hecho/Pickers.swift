import SwiftData
import SwiftUI

/// Las ventanas que se abren desde una tarea o un proyecto.
enum PickerSheet: Identifiable {
    case when(TodoItem), deadline(TodoItem), tags(TodoItem), move(TodoItem), repeats(TodoItem), calendar(TodoItem)
    case projectWhen(Project), projectDeadline(Project), projectArea(Project)

    var id: String {
        switch self {
        case .when(let t): "when-\(t.persistentModelID.hashValue)"
        case .deadline(let t): "deadline-\(t.persistentModelID.hashValue)"
        case .tags(let t): "tags-\(t.persistentModelID.hashValue)"
        case .move(let t): "move-\(t.persistentModelID.hashValue)"
        case .repeats(let t): "repeat-\(t.persistentModelID.hashValue)"
        case .calendar(let t): "calendar-\(t.persistentModelID.hashValue)"
        case .projectWhen(let p): "pwhen-\(p.persistentModelID.hashValue)"
        case .projectDeadline(let p): "pdeadline-\(p.persistentModelID.hashValue)"
        case .projectArea(let p): "parea-\(p.persistentModelID.hashValue)"
        }
    }
}

struct PickerSheetView: View {
    let sheet: PickerSheet
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            switch sheet {
            case .when(let t):
                WhenPicker(allowEvening: true, allowReminder: true, currentReminder: t.reminderAt) { choice, time in
                    withAnimation {
                        // Al cambiar la fecha la tarjeta se cierra (la tarea puede irse a otra lista).
                        if state.expanded == t.persistentModelID { state.expanded = nil }
                        t.setWhen(choice, reminder: time, today: state.today)
                    }
                }
            case .repeats(let t):
                RepeatPicker(item: t)
            case .calendar(let t):
                CalendarPicker(item: t)
            case .deadline(let t):
                DeadlinePicker(current: t.deadline) { t.deadline = $0 }
            case .tags(let t):
                TagPicker(item: t)
            case .move(let t):
                MovePicker(item: t)
            case .projectWhen(let p):
                WhenPicker(allowEvening: false) { choice, _ in p.setWhen(choice, today: state.today) }
            case .projectDeadline(let p):
                DeadlinePicker(current: p.deadline) { p.deadline = $0 }
            case .projectArea(let p):
                AreaPicker(project: p)
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 340, idealHeight: 520)
        #endif
    }
}

private struct CancelToolbar: ToolbarContent {
    var dismiss: DismissAction
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cerrar") { dismiss() }
        }
    }
}

// MARK: - ¿Cuándo?

struct WhenPicker: View {
    var allowEvening = true
    /// Si se puede poner un aviso con hora (las tareas sí, los proyectos no).
    var allowReminder = false
    /// Hora del aviso que ya tiene la tarea.
    var currentReminder: Date?
    var onPick: (WhenChoice, DateComponents?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @State private var text = ""
    @State private var date = Date().adding(days: 1)
    @State private var remind = false
    @State private var time = Calendar.hecho.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()

    private var parsed: (WhenChoice?, DateComponents?) { WhenParser.parseWithTime(text, today: state.today) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(allowReminder ? "Escribe: mañana, viernes 3pm, en 3 días…" : "Escribe: mañana, viernes, en 3 días…",
                              text: $text)
                        .onSubmit { if let c = parsed.0 { pick(c, typedTime: parsed.1) } }
                    if !text.isEmpty {
                        if let c = parsed.0 {
                            Button { pick(c, typedTime: parsed.1) } label: {
                                Label(describe(c, parsed.1), systemImage: "arrow.turn.down.right")
                            }
                        } else {
                            Text("No entiendo esa fecha").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    option("Hoy", "sun.max.fill", Theme.today, .today)
                    if allowEvening { option("Esta noche", "moon.fill", Theme.evening, .evening) }
                    option("Mañana", "sunrise.fill", .orange, .date(state.today.adding(days: 1)))
                    option("Algún día", "archivebox.fill", Theme.someday, .someday)
                    option("Cuando sea (sin fecha)", "square.stack.fill", Theme.accent, .anytime)
                }
                if allowReminder {
                    Section {
                        Toggle(isOn: $remind.animation()) { Label("Avisarme", systemImage: "bell") }
                            .onChange(of: remind) { _, on in
                                if on { Task { _ = await Reminders.requestPermission() } }
                            }
                        if remind {
                            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    } footer: {
                        Text("Elige la hora y luego el día. El aviso llega ese día a esa hora.")
                    }
                }
                Section("Otro día") {
                    DatePicker("Fecha", selection: $date, in: state.today..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    Button("Elegir \(Fmt.long(date))") { pick(.date(date)) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("¿Cuándo?")
            .toolbar { CancelToolbar(dismiss: dismiss) }
            .onAppear {
                if let currentReminder {
                    remind = true
                    time = currentReminder
                }
            }
        }
    }

    private func option(_ title: String, _ icon: String, _ color: Color, _ choice: WhenChoice) -> some View {
        Button { pick(choice) } label: {
            Label { Text(title) } icon: { Image(systemName: icon).foregroundStyle(color) }
        }
        .buttonStyle(.borderless)
        .tint(.primary)
    }

    private func describe(_ c: WhenChoice, _ t: DateComponents?) -> String {
        let day: String
        switch c {
        case .today: day = "Hoy"
        case .evening: day = "Esta noche"
        case .date(let d): day = "\(Fmt.long(d)) (\(Fmt.day(d, today: state.today)))"
        case .someday: day = "Algún día"
        case .anytime: day = "Cuando sea"
        case .inbox: day = "Entrada"
        }
        guard allowReminder, let t else { return day }
        return day + ", aviso a las " + Fmt.time(state.today.at(t))
    }

    private func pick(_ c: WhenChoice, typedTime: DateComponents? = nil) {
        let reminder = allowReminder ? (typedTime ?? (remind ? time.timeComponents : nil)) : nil
        if typedTime != nil { Task { _ = await Reminders.requestPermission() } }
        onPick(c, reminder)
        dismiss()
    }
}

// MARK: - Calendario de la tarea

struct CalendarPicker: View {
    let item: TodoItem
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarFeed.self) private var calendar

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "El de siempre" + (calendar.exportCalendar.map { " (\($0.title))" } ?? ""), color: nil, id: nil)
                }
                Section("Otro calendario") {
                    ForEach(calendar.writableCalendars, id: \.calendarIdentifier) { cal in
                        row(title: cal.title + " · " + cal.source.title, color: Color(cgColor: cal.cgColor), id: cal.calendarIdentifier)
                    }
                }
            }
            .navigationTitle("Calendario")
            .toolbar { CancelToolbar(dismiss: dismiss) }
        }
    }

    private func row(title: String, color: Color?, id: String?) -> some View {
        Button {
            item.calendarID = id
            dismiss()
        } label: {
            HStack {
                if let color { Circle().fill(color).frame(width: 10, height: 10) }
                Text(title).foregroundStyle(.primary)
                Spacer()
                if item.calendarID == id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Repetir

struct RepeatPicker: View {
    let item: TodoItem
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @State private var on = false
    @State private var rule = RepeatRule()

    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    private let weekdayNames = ["", "D", "L", "K", "M", "J", "V", "S"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Repetir esta tarea", isOn: $on.animation())
                }
                if on {
                    Section {
                        Picker("Tipo", selection: $rule.mode) {
                            Text("En fechas fijas").tag(RepeatRule.Mode.fixed)
                            Text("Después de completarla").tag(RepeatRule.Mode.afterCompletion)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } footer: {
                        Text(rule.mode == .fixed
                             ? "Por ejemplo, todos los lunes o el 15 de cada mes, aunque la completes tarde."
                             : "La siguiente aparece contando desde el día en que completas esta. Ideal para regar las plantas o cortarte el pelo.")
                    }
                    Section {
                        Stepper(value: $rule.every, in: 1...365) {
                            Text(rule.mode == .fixed ? "Cada \(rule.every)" : "\(rule.every) después")
                        }
                        Picker("Unidad", selection: $rule.unit) {
                            Text(rule.every == 1 ? "Día" : "Días").tag(RepeatRule.Unit.day)
                            Text(rule.every == 1 ? "Semana" : "Semanas").tag(RepeatRule.Unit.week)
                            Text(rule.every == 1 ? "Mes" : "Meses").tag(RepeatRule.Unit.month)
                            Text(rule.every == 1 ? "Año" : "Años").tag(RepeatRule.Unit.year)
                        }
                        if rule.mode == .fixed && rule.unit == .week {
                            HStack(spacing: 6) {
                                ForEach(weekdayOrder, id: \.self) { d in
                                    let selected = rule.weekdays.contains(d)
                                    Button {
                                        if selected { rule.weekdays.removeAll { $0 == d } } else { rule.weekdays.append(d) }
                                    } label: {
                                        Text(weekdayNames[d])
                                            .font(.callout.weight(.semibold))
                                            .frame(width: 34, height: 34)
                                            .foregroundStyle(selected ? .white : .primary)
                                            .background(selected ? Theme.accent : Color.secondary.opacity(0.15), in: Circle())
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    } footer: {
                        Text(rule.summary + (item.startDate == nil ? ". Empieza hoy." : ", desde el \(Fmt.long(item.startDate!))."))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Repetir")
            .toolbar {
                CancelToolbar(dismiss: dismiss)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if on {
                            item.repeatRule = rule
                            if item.startDate == nil { item.setWhen(.today, today: state.today) }
                        } else {
                            item.repeatRule = nil
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let r = item.repeatRule {
                    on = true
                    rule = r
                } else if let s = item.startDate {
                    rule.weekdays = [Calendar.hecho.component(.weekday, from: s)]
                }
            }
        }
    }
}

// MARK: - Fecha límite

struct DeadlinePicker: View {
    var current: Date?
    var onPick: (Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @State private var text = ""
    @State private var date = Date().adding(days: 7)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Escribe: viernes, en 2 semanas, 15 dic…", text: $text)
                        .onSubmit { if let d = WhenParser.parseDay(text, today: state.today) { pick(d) } }
                    if !text.isEmpty {
                        if let d = WhenParser.parseDay(text, today: state.today) {
                            Button { pick(d) } label: { Label(Fmt.long(d), systemImage: "arrow.turn.down.right") }
                        } else {
                            Text("No entiendo esa fecha").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    DatePicker("Fecha límite", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    Button("Poner límite el \(Fmt.long(date))") { pick(date) }
                }
                if current != nil {
                    Section {
                        Button("Quitar fecha límite", role: .destructive) { onPick(nil); dismiss() }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Fecha límite")
            .toolbar { CancelToolbar(dismiss: dismiss) }
            .onAppear { if let current { date = current } }
        }
    }

    private func pick(_ d: Date) {
        onPick(d.startOfDay)
        dismiss()
    }
}

// MARK: - Etiquetas

struct TagPicker: View {
    let item: TodoItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TagItem.order) private var tags: [TagItem]
    @State private var newTag = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(tags) { tag in
                        let on = item.tags.contains(tag)
                        Button {
                            if on { item.tags.removeAll { $0 == tag } } else { item.tags.append(tag) }
                        } label: {
                            HStack {
                                Label(tag.title, systemImage: "tag").foregroundStyle(.primary)
                                Spacer()
                                if on { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .contextMenu {
                            Button("Eliminar etiqueta", systemImage: "trash", role: .destructive) { context.delete(tag) }
                        }
                    }
                    .onDelete { idx in idx.map { tags[$0] }.forEach(context.delete) }
                } footer: {
                    if !tags.isEmpty { Text("Para borrar una etiqueta de todas las tareas, deslízala o haz clic derecho.") }
                }
                Section {
                    TextField("Nueva etiqueta", text: $newTag).onSubmit(add)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Etiquetas")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }

    private func add() {
        let title = newTag.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let tag = tags.first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame } ?? {
            let t = TagItem(title: title)
            context.insert(t)
            return t
        }()
        if !item.tags.contains(tag) { item.tags.append(tag) }
        newTag = ""
    }
}

// MARK: - Mover

struct MovePicker: View {
    let item: TodoItem
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    var body: some View {
        let live = projects.filter { $0.status == .open && !$0.trashed }
        NavigationStack {
            List {
                Section {
                    row("Entrada (sin proyecto)", icon: "tray", selected: item.project == nil && item.area == nil) {
                        item.move(project: nil, area: nil)
                    }
                    ForEach(live.filter { $0.area == nil }) { p in projectRows(p) }
                }
                ForEach(areas) { a in
                    Section {
                        row(a.displayTitle, icon: "folder.fill", selected: item.area == a && item.project == nil) {
                            item.move(project: nil, area: a)
                        }
                        ForEach(live.filter { $0.area == a }) { p in projectRows(p) }
                    }
                }
            }
            .navigationTitle("Mover a…")
            .toolbar { CancelToolbar(dismiss: dismiss) }
        }
    }

    @ViewBuilder private func projectRows(_ p: Project) -> some View {
        row(p.displayTitle, icon: "circle.dashed", selected: item.project == p && item.heading == nil, indent: 1) {
            item.move(project: p, heading: nil, area: nil)
        }
        ForEach(p.sortedHeadings) { h in
            row(h.title, icon: "text.alignleft", selected: item.heading == h, indent: 2) {
                item.move(project: p, heading: h, area: nil)
            }
        }
    }

    private func row(_ title: String, icon: String, selected: Bool, indent: Int = 0, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
            dismiss()
        } label: {
            HStack {
                Label {
                    Text(title).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: icon).foregroundStyle(icon == "folder.fill" ? Theme.area : Theme.accent)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .padding(.leading, CGFloat(indent) * 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

struct AreaPicker: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.order) private var areas: [Area]

    var body: some View {
        NavigationStack {
            List {
                choice("Sin área", icon: "circle.dashed", area: nil)
                ForEach(areas) { a in choice(a.displayTitle, icon: "folder.fill", area: a) }
            }
            .navigationTitle("Mover proyecto a…")
            .toolbar { CancelToolbar(dismiss: dismiss) }
        }
    }

    private func choice(_ title: String, icon: String, area: Area?) -> some View {
        Button {
            project.area = area
            dismiss()
        } label: {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(.primary)
                Spacer()
                if project.area == area { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
