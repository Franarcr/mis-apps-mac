import AppKit
import SwiftUI

enum Format {
    static func percent(_ value: Double) -> String { String(format: "%.0f %%", value * 100) }

    static func bytes(_ value: Int64, style: ByteCountFormatter.CountStyle = .memory) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: style)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(Int64(bytesPerSecond), style: .file) + "/s"
    }
}

struct WidgetView: View {
    @ObservedObject var monitor: SystemMonitor
    /// En la imagen de prueba no se puede dibujar el material translúcido.
    var opaqueBackground = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            MetricView(title: "CPU", value: Text(Format.percent(monitor.cpu.last)),
                       series: [monitor.cpu.values], colors: [.blue], maxValue: 1)
            MetricView(title: "Memoria",
                       value: Text("\(Format.bytes(Int64(monitor.memoryUsed))) de \(Format.bytes(Int64(MemoryStats.total)))"),
                       series: [monitor.memory.values], colors: [.green], maxValue: 1)
            if monitor.gpuAvailable {
                MetricView(title: "GPU", value: Text(Format.percent(monitor.gpu.last)),
                           series: [monitor.gpu.values], colors: [.purple], maxValue: 1)
            }
            MetricView(title: "Red",
                       value: Text("↓ ").foregroundColor(.cyan) + Text(Format.rate(monitor.download.last))
                           + Text("  ↑ ").foregroundColor(.pink) + Text(Format.rate(monitor.upload.last)),
                       series: [monitor.download.values, monitor.upload.values], colors: [.cyan, .pink])
            MetricView(title: "Disco",
                       value: Text("L ").foregroundColor(.orange) + Text(Format.rate(monitor.diskRead.last))
                           + Text("  E ").foregroundColor(.yellow) + Text(Format.rate(monitor.diskWrite.last)),
                       series: [monitor.diskRead.values, monitor.diskWrite.values], colors: [.orange, .yellow],
                       footer: monitor.diskSpace.map {
                           "Libre: \(Format.bytes($0.free, style: .file)) de \(Format.bytes($0.total, style: .file))"
                       })
            if let battery = monitor.battery { BatteryView(battery: battery) }
            if !monitor.topProcesses.isEmpty { processes }
        }
        .padding(14)
        .frame(width: 280)
        .background(background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1)))
        .environment(\.colorScheme, .dark)
    }

    private var background: AnyShapeStyle {
        opaqueBackground ? AnyShapeStyle(Color(white: 0.12)) : AnyShapeStyle(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "laptopcomputer")
            Text(monitor.machineName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer()
        }
        .foregroundStyle(.primary)
    }

    private var processes: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Más CPU")
            ForEach(monitor.topProcesses, id: \.name) { process in
                HStack {
                    Text(process.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.0f %%", process.cpu)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct MetricView: View {
    let title: String
    let value: Text
    let series: [[Double]]
    let colors: [Color]
    /// Escala fija (1 para porcentajes); si es `nil` se ajusta al máximo visible.
    var maxValue: Double?
    var footer: String?

    private var scale: Double {
        maxValue ?? max(series.flatMap { $0 }.max() ?? 0, 1024)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title)
                Spacer()
                value.font(.system(size: 11, weight: .medium)).monospacedDigit()
            }
            ZStack {
                ForEach(series.indices, id: \.self) { i in
                    Sparkline(values: series[i], maxValue: scale, closed: true)
                        .fill(LinearGradient(colors: [colors[i].opacity(0.35), colors[i].opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom))
                    Sparkline(values: series[i], maxValue: scale, closed: false)
                        .stroke(colors[i], style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
            .frame(height: 32)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            if let footer {
                Text(footer).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Línea de los últimos valores, alineada a la derecha (lo más reciente al final).
private struct Sparkline: Shape {
    let values: [Double]
    let maxValue: Double
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, maxValue > 0 else { return path }
        let step = rect.width / CGFloat(Series.capacity - 1)
        let startX = rect.maxX - CGFloat(values.count - 1) * step
        let points = values.enumerated().map { index, value in
            CGPoint(x: startX + CGFloat(index) * step,
                    y: rect.maxY - 1 - CGFloat(min(value / maxValue, 1)) * (rect.height - 3))
        }
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        if closed {
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
            path.addLine(to: CGPoint(x: points[0].x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

private struct BatteryView: View {
    let battery: BatteryInfo

    private var color: Color {
        battery.percent <= 20 && !battery.pluggedIn ? .red : .green
    }

    private var status: String {
        if battery.charging { return "Cargando" }
        return battery.pluggedIn ? "Conectada" : "Con batería"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Batería")
                Spacer()
                if battery.charging { Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(.yellow) }
                Text("\(battery.percent) % · \(status)").font(.system(size: 11, weight: .medium)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color.gradient)
                        .frame(width: geo.size.width * CGFloat(battery.percent) / 100)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Genera una imagen del widget sin abrir ventanas (para revisar el diseño).
@MainActor
enum Snapshot {
    static func render(to url: URL) {
        let monitor = SystemMonitor()
        for _ in 0..<8 {
            monitor.tick()
            Thread.sleep(forTimeInterval: 0.5)
        }
        // Espera a que lleguen los procesos, que se leen en segundo plano.
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let renderer = ImageRenderer(content: WidgetView(monitor: monitor, opaqueBackground: true))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("No se pudo generar la imagen")
            return
        }
        try? png.write(to: url)
        print("Imagen guardada en \(url.path)")
    }
}
