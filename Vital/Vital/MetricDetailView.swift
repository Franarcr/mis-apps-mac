import Charts
import SwiftUI

/// Historial de 30 días de una medida, con tu rango normal (base ± desviación) sombreado.
struct MetricDetailView: View {
    @ObservedObject var model: VitalModel
    let metric: Metric

    private struct Point: Identifiable {
        var id: Date { day }
        let day: Date
        let value: Double
        let signal: Signal
    }

    private var points: [Point] {
        let days = model.days
        return days.indices.suffix(30).compactMap { index in
            guard let value = days[index][keyPath: metric.keyPath] else { return nil }
            // Cada día se compara con su propia base (los 30 días anteriores), como en la pantalla principal.
            let base = Recovery.baseline(Array(days[max(0, index - Recovery.baselineDays)..<index]), metric.keyPath)
            return Point(day: days[index].day, value: value, signal: metric.signal(value, base: base?.mean))
        }
    }

    var body: some View {
        let base = model.baseline(metric.keyPath)
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Últimos 30 días").font(.headline)
                        if points.isEmpty {
                            Text("Todavía no hay datos.").foregroundStyle(.secondary)
                        } else {
                            Chart {
                                if let base {
                                    RectangleMark(yStart: .value("Desde", base.mean - base.sd),
                                                  yEnd: .value("Hasta", base.mean + base.sd))
                                        .foregroundStyle(.white.opacity(0.08))
                                    RuleMark(y: .value("Tu base", base.mean))
                                        .foregroundStyle(.white.opacity(0.35))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }
                                ForEach(points) { point in
                                    LineMark(x: .value("Día", point.day, unit: .day), y: .value(metric.title, point.value))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .interpolationMethod(.monotone)
                                    PointMark(x: .value("Día", point.day, unit: .day), y: .value(metric.title, point.value))
                                        .foregroundStyle(point.signal.color)
                                        .symbolSize(40)
                                }
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                }
                            }
                            .frame(height: 220)
                        }
                    }
                }
                Card {
                    HStack {
                        stat("Hoy", model.today?[keyPath: metric.keyPath])
                        stat("Tu base", base?.mean)
                        stat("Rango normal", base.map { ($0.mean - $0.sd, $0.mean + $0.sd) })
                    }
                }
                Card {
                    Text(metric.explanation).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func format(_ value: Double) -> String {
        switch metric {
        case .respiratory, .temperature, .breathing: String(format: "%.1f", value)
        default: "\(Int(value.rounded()))"
        }
    }

    private func stat(_ title: String, _ value: Double?) -> some View {
        statView(title, value.map { "\(format($0)) \(metric.unit)" } ?? "—")
    }

    private func stat(_ title: String, _ range: (Double, Double)?) -> some View {
        statView(title, range.map { "\(format($0.0))–\(format($0.1))" } ?? "—")
    }

    private func statView(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
