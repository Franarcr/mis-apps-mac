import SwiftUI
import WidgetKit

struct CounterEntry: TimelineEntry {
    let date: Date
    let counter: Counter?
}

/// Muestra la cuenta marcada «en el widget». Se repinta cada hora (y a medianoche cambia el día).
struct CounterProvider: TimelineProvider {
    func placeholder(in context: Context) -> CounterEntry {
        CounterEntry(date: .now, counter: Counter(name: "Sin azúcar", kind: .since, date: .now.addingTimeInterval(-12 * 86400),
                                                  icon: "cube.fill", color: "orange"))
    }

    func getSnapshot(in context: Context, completion: @escaping (CounterEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : CounterEntry(date: .now, counter: Self.current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CounterEntry>) -> Void) {
        let counter = Self.current()
        let hour = Calendar.current.dateInterval(of: .hour, for: .now)?.start ?? .now
        let entries = (0..<48).map { CounterEntry(date: $0 == 0 ? .now : hour.addingTimeInterval(Double($0) * 3600), counter: counter) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func current() -> Counter? {
        let all = Counter.load()
        return all.first(where: \.inWidget) ?? all.first(where: { !$0.isFinished })
    }
}

struct CounterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitalCuentas", provider: CounterProvider()) { entry in
            CounterWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Cuenta de días")
        .description("La cuenta que marcaste en Vital › Cuentas: días desde algo o hasta algo.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CounterWidgetView: View {
    let entry: CounterEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let c = entry.counter {
            switch family {
            case .accessoryInline:
                Text("\(Image(systemName: c.icon)) \(c.number(at: entry.date)) \(c.caption(at: entry.date)) · \(c.name)")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: c.icon).font(.caption)
                    Text(c.number(at: entry.date)).font(.title3.bold()).minimumScaleFactor(0.5)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 0) {
                    Label(c.name, systemImage: c.icon).font(.headline).lineLimit(1)
                    Text("\(c.number(at: entry.date)) \(c.caption(at: entry.date))").font(.title3.bold()).minimumScaleFactor(0.6)
                }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: c.icon).font(.title3).foregroundStyle(c.tint)
                    Spacer(minLength: 0)
                    Text(c.number(at: entry.date))
                        .font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(c.tint)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(c.caption(at: entry.date)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(c.name).font(.caption.bold()).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(.indigo)
                Text("Cuentas").font(.headline)
                Text("Crea una en Vital › Cuentas.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
