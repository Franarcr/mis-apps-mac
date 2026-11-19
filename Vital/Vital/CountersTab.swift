import SwiftUI
import UserNotifications
import WidgetKit

/// Las cuentas de días, guardadas en el grupo compartido; al cambiar se avisa al widget y se programa el aviso.
@MainActor
final class CounterStore: ObservableObject {
    @Published private(set) var counters: [Counter] = Counter.load()

    func save(_ counter: Counter) {
        var c = counter
        if c.inWidget { for i in counters.indices { counters[i].inWidget = false } }
        if let i = counters.firstIndex(where: { $0.id == c.id }) { counters[i] = c } else {
            if !counters.contains(where: \.inWidget) { c.inWidget = true }
            counters.append(c)
        }
        persist()
    }

    func delete(_ id: UUID) {
        counters.removeAll { $0.id == id }
        if !counters.contains(where: \.inWidget), let first = counters.first(where: { !$0.isFinished }) {
            counters[counters.firstIndex(of: first)!].inWidget = true
        }
        persist()
    }

    /// «Volví a empezar»: guarda el intento y pone la cuenta en cero desde ahora.
    func restart(_ id: UUID) {
        guard let i = counters.firstIndex(where: { $0.id == id }) else { return }
        let now = Date.now
        if counters[i].date < now { counters[i].attempts.append(.init(start: counters[i].date, end: now)) }
        counters[i].date = now
        persist()
    }

    private func persist() {
        Counter.save(counters)
        WidgetCenter.shared.reloadTimelines(ofKind: "VitalCuentas")
        Task { await Self.scheduleNotifications(counters) }
    }

    /// Un aviso el día que llega cada cuenta «Hasta» (a la hora puesta, o a las 8:00).
    static func scheduleNotifications(_ counters: [Counter]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("cuenta-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let upcoming = counters.filter { $0.kind == .until && $0.date > .now }
        guard !upcoming.isEmpty, (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        for c in upcoming {
            var when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: c.date)
            if !c.useTime { when.hour = 8; when.minute = 0 }
            let content = UNMutableNotificationContent()
            content.title = c.name
            content.body = "¡Llegó el día!"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "cuenta-\(c.id)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }
}

struct CountersTab: View {
    @StateObject private var store = CounterStore()
    @State private var editing: Counter?

    private var active: [Counter] { store.counters.filter { !$0.isFinished } }
    private var finished: [Counter] { store.counters.filter(\.isFinished) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.counters.isEmpty {
                        ContentUnavailableView {
                            Label("Sin cuentas", systemImage: "calendar.badge.clock")
                        } description: {
                            Text("Cuenta días desde algo (sin azúcar, sin fumar) o hasta algo (un viaje, un cumpleaños).")
                        } actions: {
                            Button("Crear una cuenta") { editing = Counter(name: "", kind: .since, date: .now) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 80)
                    }
                    ForEach(active) { counter in
                        NavigationLink(value: counter.id) { CounterCard(counter: counter) }.buttonStyle(.plain)
                    }
                    if !finished.isEmpty {
                        Text("Terminadas").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        ForEach(finished) { counter in
                            NavigationLink(value: counter.id) { CounterCard(counter: counter).opacity(0.6) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Cuentas")
            .toolbar {
                Button { editing = Counter(name: "", kind: .since, date: .now) } label: { Image(systemName: "plus") }
            }
            .navigationDestination(for: UUID.self) { id in
                if let counter = store.counters.first(where: { $0.id == id }) {
                    CounterDetail(counter: counter, store: store) { editing = counter }
                }
            }
            .sheet(item: $editing) { counter in
                CounterEditor(counter: counter, isNew: !store.counters.contains { $0.id == counter.id }) { store.save($0) }
            }
        }
    }
}

private struct CounterCard: View {
    let counter: Counter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 14) {
                Image(systemName: counter.icon)
                    .font(.title2).foregroundStyle(counter.tint)
                    .frame(width: 48, height: 48)
                    .background(counter.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(counter.name).font(.headline)
                    Text(counter.kind == .since ? "Desde \(counter.date.formatted(date: .abbreviated, time: counter.useTime ? .shortened : .omitted))"
                                                : "Hasta \(counter.date.formatted(date: .abbreviated, time: counter.useTime ? .shortened : .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                    if counter.useTime { Text(counter.detail(at: context.date)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(counter.number(at: context.date))
                        .font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(counter.tint)
                    Text(counter.caption(at: context.date)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct CounterDetail: View {
    let counter: Counter
    @ObservedObject var store: CounterStore
    let edit: () -> Void
    @State private var confirmRestart = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 4) {
                        Image(systemName: counter.icon).font(.largeTitle).foregroundStyle(counter.tint)
                        Text(counter.number(at: context.date))
                            .font(.system(size: 72, weight: .bold, design: .rounded)).foregroundStyle(counter.tint)
                        Text(counter.caption(at: context.date)).foregroundStyle(.secondary)
                        Text(counter.detail(at: context.date)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
            if counter.kind == .since {
                Section("Racha") {
                    LabeledContent("Récord", value: Self.days(counter.best))
                    LabeledContent("Intentos anteriores", value: "\(counter.attempts.count)")
                    Button("Volví a empezar", role: .destructive) { confirmRestart = true }
                }
                if !counter.attempts.isEmpty {
                    Section("Historial") {
                        ForEach(counter.attempts.reversed(), id: \.self) { a in
                            LabeledContent("\(a.start.formatted(date: .abbreviated, time: .omitted)) – \(a.end.formatted(date: .abbreviated, time: .omitted))",
                                           value: Self.days(a.duration))
                        }
                    }
                }
            }
            Section {
                Button(counter.inWidget ? "Se muestra en el widget" : "Mostrar en el widget") {
                    var c = counter; c.inWidget = true; store.save(c)
                }
                .disabled(counter.inWidget)
                Button("Borrar cuenta", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(counter.name)
        .toolbar { Button("Editar", action: edit) }
        .confirmationDialog("¿Empezar de cero? El intento actual se guarda en el historial.", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Volver a empezar", role: .destructive) { store.restart(counter.id) }
        }
        .confirmationDialog("¿Borrar «\(counter.name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { dismiss(); store.delete(counter.id) }
        }
    }

    static func days(_ t: TimeInterval) -> String {
        let d = Int(t / 86400)
        return d == 1 ? "1 día" : d == 0 ? "\(Int(t / 3600)) h" : "\(d) días"
    }
}

private struct CounterEditor: View {
    @State var counter: Counter
    let isNew: Bool
    let save: (Counter) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (p. ej. Sin azúcar)", text: $counter.name)
                    Picker("Tipo", selection: $counter.kind) {
                        Text("Desde (cuenta hacia arriba)").tag(Counter.Kind.since)
                        Text("Hasta (cuenta hacia atrás)").tag(Counter.Kind.until)
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                Section {
                    Toggle("Con hora", isOn: $counter.useTime)
                    DatePicker(counter.kind == .since ? "Desde" : "Hasta", selection: $counter.date,
                               displayedComponents: counter.useTime ? [.date, .hourAndMinute] : [.date])
                } footer: {
                    Text(counter.kind == .since ? "Puede ser hoy o una fecha pasada." : "El día que llegue te aviso a las 8:00 (o a la hora que pongas).")
                }
                Section("Icono") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Counter.icons, id: \.self) { icon in
                            Image(systemName: icon).font(.title3)
                                .frame(width: 44, height: 44)
                                .background(counter.icon == icon ? counter.tint.opacity(0.3) : .clear, in: Circle())
                                .foregroundStyle(counter.icon == icon ? counter.tint : .secondary)
                                .onTapGesture { counter.icon = icon }
                        }
                    }
                }
                Section("Color") {
                    HStack {
                        ForEach(Counter.colors, id: \.self) { name in
                            let c = Counter(name: "", kind: .since, date: .now, color: name)
                            Circle().fill(c.tint).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.white, lineWidth: counter.color == name ? 3 : 0))
                                .onTapGesture { counter.color = name }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Nueva cuenta" : "Editar cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save(counter); dismiss() }
                        .disabled(counter.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
