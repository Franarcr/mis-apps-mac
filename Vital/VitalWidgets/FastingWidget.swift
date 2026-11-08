import AppIntents
import SwiftUI
import WidgetKit

struct FastingEntry: TimelineEntry {
    let date: Date
    let snapshot: FastingSnapshot?
}

/// Lee lo que la app dejó en el grupo compartido. Durante un ayuno genera una entrada cada 15 min
/// (para el anillo y la fase); el reloj de horas corre solo.
struct FastingProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingEntry {
        FastingEntry(date: .now, snapshot: FastingSnapshot(enabled: true, activeStart: .now.addingTimeInterval(-13 * 3600),
                                                           goalHours: 16, lastEnd: nil, streak: 5))
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : FastingEntry(date: .now, snapshot: FastingSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingEntry>) -> Void) {
        let snapshot = FastingSnapshot.load()
        let now = Date.now
        if let snapshot, snapshot.enabled, snapshot.activeStart != nil {
            let entries = (0..<48).map { FastingEntry(date: now.addingTimeInterval(Double($0) * 15 * 60), snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .atEnd))
        } else {
            // Ventana abierta: se vuelve a pintar cuando cierra (pasa a «Tu ventana ya cerró»).
            let closes = snapshot?.windowCloses.flatMap { $0 > now ? $0 : nil }
            completion(Timeline(entries: [FastingEntry(date: now, snapshot: snapshot)], policy: closes.map { .after($0) } ?? .never))
        }
    }
}

struct FastingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitalAyuno", provider: FastingProvider()) { entry in
            FastingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Ayuno")
        .description("Cuánto llevas de ayuno, la fase y un botón para empezar o terminar.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct FastingWidgetView: View {
    let entry: FastingEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: FastingSnapshot? { entry.snapshot }
    private var hours: Double { snapshot?.activeStart.map { entry.date.timeIntervalSince($0) / 3600 } ?? 0 }
    private var progress: Double { min(1, hours / max(1, snapshot?.goalHours ?? 16)) }
    private var reached: Bool { hours >= (snapshot?.goalHours ?? 16) }
    private var tint: Color { reached ? .green : .indigo }

    var body: some View {
        if let snapshot, snapshot.enabled {
            if let start = snapshot.activeStart {
                fasting(start: start, snapshot: snapshot)
            } else {
                window(snapshot)
            }
        } else {
            switch family {
            case .accessoryInline: Text("Ayuno: abre Vital")
            case .accessoryCircular: Image(systemName: "timer")
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "timer").font(.title2).foregroundStyle(.indigo)
                    Text("Activa el control de ayuno en Vital › Comida").font(.caption)
                }
            }
        }
    }

    @ViewBuilder private func fasting(start: Date, snapshot: FastingSnapshot) -> some View {
        let phase = FastingPhase.at(hours: hours)
        switch family {
        case .accessoryInline:
            Text("\(Image(systemName: "timer")) \(Int(hours)) h · \(phase.title)")
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "timer")
            } currentValueLabel: {
                Text("\(Int(hours))h")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(reached ? "Meta cumplida" : "Ayuno · \(phase.title)", systemImage: "timer").font(.caption2)
                Text(timerInterval: start...Date.distantFuture, countsDown: false).font(.title3.bold()).monospacedDigit()
                Gauge(value: progress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ZStack {
                        Circle().stroke(.white.opacity(0.15), lineWidth: 7)
                        Circle().trim(from: 0, to: progress)
                            .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: phase.icon).font(.caption).foregroundStyle(tint)
                    }
                    .frame(width: 44, height: 44)
                    Spacer()
                    if snapshot.streak > 1 {
                        Label("\(snapshot.streak)", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(.orange)
                    }
                }
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.title3.bold()).monospacedDigit()
                Text(reached ? "Meta cumplida" : "\(phase.title) · meta \(Int(snapshot.goalHours)) h")
                    .font(.caption2).foregroundStyle(reached ? .green : .secondary).lineLimit(1)
                Button(intent: EndFastIntent()) {
                    Label("Terminar", systemImage: "fork.knife").font(.caption.bold()).frame(maxWidth: .infinity)
                }
                .tint(tint)
            }
        }
    }

    @ViewBuilder private func window(_ snapshot: FastingSnapshot) -> some View {
        let closes = snapshot.windowCloses
        let open = closes.map { $0 > entry.date } ?? false
        let closesText = closes?.formatted(date: .omitted, time: .shortened) ?? ""
        switch family {
        case .accessoryInline:
            Text(open ? "\(Image(systemName: "fork.knife")) Ventana hasta las \(closesText)" : "\(Image(systemName: "timer")) Sin ayuno")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "fork.knife")
                if open { Text(closesText).font(.system(size: 10)).minimumScaleFactor(0.6) }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(open ? "Ventana abierta" : "Sin ayuno", systemImage: "fork.knife").font(.caption2)
                Text(open ? "Cierra a las \(closesText)" : "Toca para empezar en Vital").font(.headline)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "fork.knife.circle.fill").font(.title).foregroundStyle(.indigo)
                    Spacer()
                    if snapshot.streak > 0 {
                        Label("\(snapshot.streak)", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(.orange)
                    }
                }
                Text(open ? "Ventana abierta" : "Sin ayuno").font(.headline)
                Text(open ? "Cierra a las \(closesText)" : "Plan \(Int(snapshot.goalHours)):\(24 - Int(snapshot.goalHours))")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(intent: StartFastIntent()) {
                    Label("Empezar", systemImage: "play.fill").font(.caption.bold()).frame(maxWidth: .infinity)
                }
                .tint(.indigo)
            }
        }
    }
}
