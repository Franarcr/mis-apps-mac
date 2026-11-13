import Charts
import SwiftUI

struct ChartsView: View {
    let networks: [WiFiNetwork]
    let selection: Set<String>

    enum Kind: String, CaseIterable, Identifiable {
        case channels, history
        var id: String { rawValue }
        var title: String { self == .channels ? "Canales" : "Señal en el tiempo" }
    }

    @AppStorage("graficoTipo") private var kind: Kind = .channels
    @AppStorage("graficoBanda") private var band: Double = Band.b24.rawValue
    @AppStorage("graficoMinutos") private var minutes: Double = 2

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                Spacer()
                if kind == .channels {
                    Picker("", selection: $band) {
                        ForEach(Band.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                } else {
                    Picker("", selection: $minutes) {
                        Text("1 min").tag(1.0)
                        Text("2 min").tag(2.0)
                        Text("5 min").tag(5.0)
                        Text("15 min").tag(15.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if kind == .channels {
                ChannelChart(networks: networks.filter { $0.band.rawValue == band }, band: Band(rawValue: band) ?? .b24, selection: selection)
            } else {
                HistoryChart(networks: networks, selection: selection, minutes: minutes)
            }
        }
        .background(.background)
    }
}

private func dimFactor(_ id: String, _ selection: Set<String>) -> Double {
    selection.isEmpty || selection.contains(id) ? 1 : 0.18
}

/// Cada red dibujada como un trapecio que ocupa su ancho de canal, con la altura de su señal.
struct ChannelChart: View {
    let networks: [WiFiNetwork]
    let band: Band
    let selection: Set<String>

    struct Point: Identifiable {
        let id = UUID()
        var x: Double
        var y: Double
    }

    var domain: ClosedRange<Double> {
        switch band {
        case .b24: return -1...16
        case .b5: return 30...179
        case .b6: return -3...237
        }
    }

    var ticks: [Double] {
        switch band {
        case .b24: return Array(1...14).map(Double.init)
        case .b5: return [36, 52, 68, 84, 100, 116, 132, 149, 165, 177]
        case .b6: return stride(from: 1, through: 233, by: 16).map(Double.init)
        }
    }

    /// Solo la red más fuerte de cada nombre y canal lleva etiqueta, para que no se amontonen.
    var labeled: [WiFiNetwork] {
        var best: [String: WiFiNetwork] = [:]
        for n in networks where !n.ssid.isEmpty {
            let k = "\(n.ssid)|\(n.centerChannel)"
            if let b = best[k], b.rssi >= n.rssi { continue }
            best[k] = n
        }
        return Array(best.values)
    }

    func shape(_ n: WiFiNetwork) -> [Point] {
        // En 2,4 GHz un canal de 20 MHz ocupa ~22 MHz (unos 4,4 canales).
        let half = band == .b24 ? Double(n.width) / 10 + 0.2 : Double(n.width) / 10
        let edge = half * 0.15
        let c = n.centerChannel
        let y = Double(n.rssi)
        return [Point(x: c - half, y: -100), Point(x: c - half + edge, y: y),
                Point(x: c + half - edge, y: y), Point(x: c + half, y: -100)]
    }

    var body: some View {
        if networks.isEmpty {
            Text("No hay redes en \(band.title)").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(networks) { n in
                    let pts = shape(n)
                    ForEach(pts) { p in
                        AreaMark(x: .value("Canal", p.x), yStart: .value("Base", -100), yEnd: .value("Señal", p.y))
                            .foregroundStyle(by: .value("Red", n.id))
                            .opacity(0.18 * dimFactor(n.id, selection))
                    }
                    ForEach(pts) { p in
                        LineMark(x: .value("Canal", p.x), y: .value("Señal", p.y), series: .value("Red", n.id))
                            .foregroundStyle(by: .value("Red", n.id))
                            .lineStyle(StrokeStyle(lineWidth: selection.contains(n.id) ? 2.5 : 1.5))
                            .opacity(dimFactor(n.id, selection))
                    }
                }
                ForEach(labeled) { n in
                    PointMark(x: .value("Canal", n.centerChannel), y: .value("Señal", Double(n.rssi)))
                        .symbolSize(0)
                        .annotation(position: .top, spacing: 1) {
                            Text(n.displayName).font(.caption2).foregroundStyle(networkColor(n.id))
                                .opacity(dimFactor(n.id, selection))
                        }
                }
            }
            .chartForegroundStyleScale(domain: networks.map(\.id), range: networks.map { networkColor($0.id) })
            .chartLegend(.hidden)
            .chartXScale(domain: domain)
            .chartYScale(domain: -100 ... -20)
            .chartXAxis {
                AxisMarks(values: ticks) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))") } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [-100, -90, -80, -70, -60, -50, -40, -30, -20]) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)") } }
                }
            }
            .chartXAxisLabel("Canal")
            .chartYAxisLabel("dBm")
            .padding(10)
        }
    }
}

struct HistoryChart: View {
    let networks: [WiFiNetwork]
    let selection: Set<String>
    let minutes: Double

    var body: some View {
        let start = Date().addingTimeInterval(-minutes * 60)
        let shown = networks.filter { selection.isEmpty || selection.contains($0.id) }
        if shown.isEmpty {
            Text("Sin datos todavía").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(shown) { n in
                    ForEach(n.history.filter { $0.date >= start }, id: \.date) { s in
                        LineMark(x: .value("Hora", s.date), y: .value("Señal", s.rssi), series: .value("Red", n.id))
                            .foregroundStyle(by: .value("Red", n.id))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: selection.contains(n.id) ? 2.5 : 1.5))
                    }
                }
            }
            .chartForegroundStyleScale(domain: shown.map(\.id), range: shown.map { networkColor($0.id) })
            .chartLegend(.hidden)
            .chartXScale(domain: start...Date())
            .chartYScale(domain: -100 ... -20)
            .chartYAxis {
                AxisMarks(position: .leading, values: [-100, -90, -80, -70, -60, -50, -40, -30, -20])
            }
            .chartYAxisLabel("dBm")
            .padding(10)
        }
    }
}
