import AppIntents
import SwiftUI
import WidgetKit

@main
struct HechoWidgetsBundle: WidgetBundle {
    var body: some Widget { TodayWidget() }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let tasks: [SnapTask]
}

struct TodayProvider: TimelineProvider {
    private static let samples = [
        SnapTask(uid: "1", title: "Llamar para pedir cita", context: "Personal", evening: false, order: 0),
        SnapTask(uid: "2", title: "Comprar café", context: nil, evening: false, order: 1),
        SnapTask(uid: "3", title: "Preparar el informe", context: "Trabajo", evening: true, order: 2),
    ]

    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: .now, tasks: Self.samples) }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let tasks = SharedToday.today()
        completion(TodayEntry(date: .now, tasks: context.isPreview && tasks.isEmpty ? Self.samples : tasks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        // Se redibuja pasada la medianoche, cuando cambian las tareas de Hoy.
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 + 60)
        let entries = [TodayEntry(date: now, tasks: SharedToday.today(now)),
                       TodayEntry(date: midnight, tasks: SharedToday.today(midnight))]
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

private extension SnapTask {
    init(uid: String, title: String, context: String?, evening: Bool, order: Double) {
        self.init(uid: uid, title: title, context: context, evening: evening, startDate: Date(), deadline: nil,
                  reminderAt: nil, order: order)
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private let accent = Color(red: 0.10, green: 0.53, blue: 0.50)
    private let sun = Color(red: 0.96, green: 0.62, blue: 0.10)

    private var maxRows: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        default: 9
        }
    }

    var body: some View {
        content
            .widgetURL(URL(string: "hecho://hoy"))
            .containerBackground(.background, for: .widget)
    }

    @ViewBuilder private var content: some View {
        let n = entry.tasks.count
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "sun.max.fill").font(.caption)
                    Text("\(n)").font(.headline)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(n == 0 ? "Hoy: nada" : "Hoy · \(n)", systemImage: "sun.max.fill").font(.headline)
                ForEach(entry.tasks.prefix(2)) { t in Text(t.title).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text(n == 1 ? "Hoy: 1 tarea" : "Hoy: \(n) tareas")
        default:
            list
        }
    }

    private var list: some View {
        let n = entry.tasks.count
        return VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 7) {
            HStack {
                Image(systemName: "sun.max.fill").foregroundStyle(sun)
                Text("Hoy").font(.headline)
                Spacer()
                if n > 0 { Text("\(n)").font(.headline.monospacedDigit()).foregroundStyle(.secondary) }
            }
            if n == 0 {
                Spacer(minLength: 0)
                Text("Nada para hoy").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.tasks.prefix(maxRows)) { t in row(t) }
                Spacer(minLength: 0)
                if n > maxRows {
                    Text("y \(n - maxRows) más").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ t: SnapTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(intent: CompleteTaskIntent(uid: t.uid)) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.secondary, lineWidth: 1.4)
                    .frame(width: 15, height: 15)
            }
            .buttonStyle(.plain)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            VStack(alignment: .leading, spacing: 0) {
                Text(t.title).font(.subheadline).lineLimit(1)
                if family == .systemLarge, let c = t.context {
                    Text(c).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if t.evening {
                Image(systemName: "moon.fill").font(.caption2).foregroundStyle(.indigo)
            } else if t.reminderAt != nil {
                Image(systemName: "bell.fill").font(.caption2).foregroundStyle(accent)
            }
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedToday.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Hoy")
        .description("Tus tareas de hoy. Toca la casilla para completarlas.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
