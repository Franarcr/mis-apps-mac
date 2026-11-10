import SwiftData
import SwiftUI

/// Qué detalles muestra una fila según la lista donde está.
struct RowStyle {
    var showContext = false
    var showWhen = false
    var showTodayMark = false
}

/// Casilla para completar una tarea.
struct CheckBox: View {
    let item: TodoItem
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            withAnimation(.snappy) { item.toggleDone(state) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(item.status == .completed ? Theme.accent : .clear)
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(item.isDone ? Theme.accent.opacity(item.status == .canceled ? 0.4 : 1) : .secondary.opacity(0.7),
                                  lineWidth: 1.5)
                if item.status == .completed {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                } else if item.status == .canceled {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isDone ? "Marcar como pendiente" : "Completar")
    }
}

/// Una tarea cerrada, como se ve en la lista.
struct TaskRow: View {
    let item: TodoItem
    var style = RowStyle()
    @Environment(AppState.self) private var state

    private var today: Date { state.today }
    private var tomorrow: Date { today.adding(days: 1) }
    private var isToday: Bool { item.startDate.map { $0 < tomorrow } ?? false }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            CheckBox(item: item)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if style.showTodayMark && isToday && !item.isDone {
                        Image(systemName: item.evening ? "moon.fill" : "sun.max.fill")
                            .font(.caption)
                            .foregroundStyle(item.evening ? Theme.evening : Theme.today)
                    }
                    Text(item.displayTitle)
                        .foregroundStyle(item.isDone || item.title.isEmpty ? .secondary : .primary)
                        .strikethrough(item.status == .canceled)
                }
                if hasMeta { meta }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var whenText: (String, String, Color)? {
        guard style.showWhen, !item.isDone else { return nil }
        if let s = item.startDate, s >= tomorrow { return (Fmt.day(s, today: today), "calendar", .secondary) }
        if item.startDate == nil && item.start == .someday { return ("Algún día", "archivebox", Theme.someday) }
        return nil
    }

    private var hasMeta: Bool {
        (style.showContext && item.contextName != nil) || whenText != nil || !item.tags.isEmpty
            || !item.notes.isEmpty || !item.checklist.isEmpty || item.deadline != nil
            || item.reminderAt != nil || item.repeatRaw != nil
    }

    private var meta: some View {
        HStack(spacing: 10) {
            if style.showContext, let c = item.contextName {
                Text(c).lineLimit(1)
            }
            if let w = whenText {
                Label(w.0, systemImage: w.1).foregroundStyle(w.2)
            }
            if !item.tags.isEmpty {
                Label(item.sortedTags.map(\.title).joined(separator: ", "), systemImage: "tag").lineLimit(1)
            }
            if let r = item.reminderAt, !item.isDone {
                Label(Fmt.time(r), systemImage: "bell")
            }
            if item.repeatRaw != nil {
                Image(systemName: "repeat")
            }
            if !item.notes.isEmpty {
                Image(systemName: "note.text")
            }
            if !item.checklist.isEmpty {
                Label("\(item.checklist.filter(\.done).count)/\(item.checklist.count)", systemImage: "checklist")
            }
            if let d = item.deadline, !item.isDone {
                Label(Fmt.deadline(d, today: today), systemImage: "flag.fill")
                    .foregroundStyle(d <= today ? Theme.deadline : .secondary)
            }
        }
        .labelStyle(CompactLabel())
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

/// Una tarea abierta: la tarjeta con todos sus detalles editables.
struct TaskCard: View {
    @Bindable var item: TodoItem
    var onPick: (PickerSheet) -> Void
    @Environment(AppState.self) private var state
    @Environment(CalendarFeed.self) private var calendar
    @Environment(\.modelContext) private var context
    @FocusState private var focus: Field?
    @State private var newStep = ""
    @State private var addingStep = false

    enum Field: Hashable { case title, notes, newStep }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                CheckBox(item: item)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                TextField("Nueva tarea", text: $item.title)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.semibold))
                    .focused($focus, equals: .title)
                    .onSubmit(close)
            }
            TextField("Notas", text: $item.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1...12)
                .focused($focus, equals: .notes)
                .padding(.leading, 28)

            if !item.checklist.isEmpty || addingStep {
                checklist.padding(.leading, 28)
            }

            FlowLayout(spacing: 6) {
                Chip(icon: item.project != nil ? "circle.dashed" : item.area != nil ? "folder" : "tray",
                     text: item.project?.displayTitle ?? item.area?.displayTitle ?? "Entrada",
                     onTap: { onPick(.move(item)) })
                ForEach(item.sortedTags) { tag in
                    Chip(icon: "tag", text: tag.title, onTap: { onPick(.tags(item)) })
                }
                if let w = whenChip {
                    Chip(icon: w.1, text: w.0, color: w.2, onTap: { onPick(.when(item)) },
                         onClear: { withAnimation { item.setWhen(.inbox, today: state.today) } })
                }
                if calendar.exportEnabled && calendar.authorized && item.startDate != nil,
                   let cal = calendar.calendar(id: item.calendarID) ?? calendar.exportCalendar {
                    Chip(icon: "calendar.badge.checkmark", text: cal.title, color: Color(cgColor: cal.cgColor),
                         onTap: { onPick(.calendar(item)) })
                }
                if let rule = item.repeatRule {
                    Chip(icon: "repeat", text: rule.summary, color: Theme.accent, onTap: { onPick(.repeats(item)) },
                         onClear: { item.repeatRule = nil })
                }
                if let d = item.deadline {
                    Chip(icon: "flag.fill", text: "Límite: \(Fmt.day(d, today: state.today))",
                         color: d <= state.today ? Theme.deadline : .secondary,
                         onTap: { onPick(.deadline(item)) }, onClear: { item.deadline = nil })
                }
            }
            .padding(.leading, 28)

            HStack(spacing: 16) {
                Spacer()
                icon("calendar", "Cuándo") { onPick(.when(item)) }
                icon("repeat", "Repetir") { onPick(.repeats(item)) }
                icon("tag", "Etiquetas") { onPick(.tags(item)) }
                icon("checklist", "Pasos") { addingStep = true; focus = .newStep }
                icon("flag", "Fecha límite") { onPick(.deadline(item)) }
                icon("trash", "Papelera") {
                    withAnimation {
                        state.expanded = nil
                        item.trashed = true
                    }
                }
                Button("Listo", action: close)
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
        .padding(.vertical, 6)
        .onAppear { if item.title.isEmpty { focus = .title } }
        #if os(macOS)
        .onExitCommand(perform: close)
        #endif
    }

    private func icon(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name) }
            .help(label)
            .accessibilityLabel(label)
    }

    private var whenChip: (String, String, Color)? {
        if let s = item.startDate {
            let time = item.reminderAt.map { " · " + Fmt.time($0) } ?? ""
            if s < state.today.adding(days: 1) {
                return item.evening ? ("Esta noche" + time, item.reminderAt == nil ? "moon.fill" : "bell.fill", Theme.evening)
                    : ("Hoy" + time, item.reminderAt == nil ? "sun.max.fill" : "bell.fill", Theme.today)
            }
            return (Fmt.day(s, today: state.today) + time, item.reminderAt == nil ? "calendar" : "bell.fill", .secondary)
        }
        if item.start == .someday { return ("Algún día", "archivebox.fill", Theme.someday) }
        return nil
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.sortedChecklist) { step in
                ChecklistRow(step: step) {
                    addingStep = true
                    focus = .newStep
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.caption).foregroundStyle(.tertiary).frame(width: 14)
                TextField("Añadir paso", text: $newStep)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($focus, equals: .newStep)
                    .onSubmit(addStep)
            }
        }
    }

    private func addStep() {
        let text = newStep.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { addingStep = !item.checklist.isEmpty; return }
        let step = ChecklistItem(title: text)
        context.insert(step)
        step.todo = item
        newStep = ""
        focus = .newStep
    }

    private func close() {
        withAnimation(.snappy) { state.expanded = nil }
    }
}

private struct ChecklistRow: View {
    @Bindable var step: ChecklistItem
    var onSubmit: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) { step.done.toggle() }
            } label: {
                Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(step.done ? Theme.accent : .secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.borderless)
            TextField("Paso", text: $step.title)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(step.done ? .secondary : .primary)
                .strikethrough(step.done)
                .onSubmit {
                    if step.title.trimmingCharacters(in: .whitespaces).isEmpty {
                        context.delete(step)
                    } else {
                        onSubmit()
                    }
                }
        }
        .contextMenu {
            Button("Eliminar paso", systemImage: "trash", role: .destructive) { context.delete(step) }
        }
    }
}

/// Coloca sus elementos en filas, pasando a la siguiente cuando no caben.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width + 0.5 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        guard !subviews.isEmpty else { return .zero }
        let w = proposal.width.map { $0.isFinite ? $0 : maxX } ?? maxX
        return CGSize(width: w, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX + 0.5 {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

extension Theme {
    static var card: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}
