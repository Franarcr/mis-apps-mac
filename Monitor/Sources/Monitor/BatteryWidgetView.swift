import AppKit
import SwiftUI

/// Color de la barra según la carga: verde ≥ 50 %, amarillo ≥ 25 %, naranja ≥ 10 %, rojo por debajo.
func batteryColor(_ percent: Int) -> Color {
    switch percent {
    case 50...: .green
    case 25..<50: .yellow
    case 10..<25: .orange
    default: .red
    }
}

struct BatteryWidgetView: View {
    @ObservedObject var batteries: BatteryMonitor
    /// En la imagen de prueba no se puede dibujar el material translúcido.
    var opaqueBackground = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "battery.75percent")
                Text("Baterías").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            if batteries.devices.isEmpty {
                Text("No hay dispositivos con batería conectados")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(batteries.devices) { device in
                DeviceRow(device: device)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(opaqueBackground ? AnyShapeStyle(Color(white: 0.12)) : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1)))
        .environment(\.colorScheme, .dark)
    }
}

private struct DeviceRow: View {
    let device: DeviceBattery

    /// El nivel principal: el único, o el más bajo de los auriculares (sin contar el estuche).
    private var main: Int {
        let buds = device.levels.filter { $0.label != "Estuche" }
        return (buds.isEmpty ? device.levels : buds).map(\.percent).min() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: device.symbol)
                    .font(.system(size: 13))
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if device.charging {
                    Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                }
                if device.levels.count == 1 {
                    Text("\(main) %")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(batteryColor(main))
                }
            }
            if device.levels.count == 1 {
                LevelBar(percent: main)
            } else {
                // AirPods: una barra por auricular y otra para el estuche.
                ForEach(device.levels, id: \.label) { level in
                    HStack(spacing: 6) {
                        Text(level.label ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .leading)
                        LevelBar(percent: level.percent)
                        Text("\(level.percent) %")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(batteryColor(level.percent))
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            if let detail = device.detail {
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LevelBar: View {
    let percent: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(batteryColor(percent).gradient)
                    .frame(width: max(6, geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100))
            }
        }
        .frame(height: 6)
    }
}

/// Imagen de prueba del widget de baterías.
@MainActor
enum BatterySnapshot {
    static func render(to url: URL, demo: Bool) {
        let batteries = BatteryMonitor()
        if demo { batteries.loadDemo() } else { batteries.refreshNow() }
        let renderer = ImageRenderer(content: BatteryWidgetView(batteries: batteries, opaqueBackground: true))
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

extension BatteryMonitor {
    /// Datos de ejemplo con todos los colores y unos AirPods, para revisar el diseño.
    func loadDemo() {
        setDevices([
            DeviceBattery(id: "mac", name: "MacBook Air", symbol: "laptopcomputer",
                          levels: [.init(label: nil, percent: 83)], charging: true, detail: "Carga completa en 45 min"),
            DeviceBattery(id: "airpods", name: "AirPods Pro", symbol: "airpodspro",
                          levels: [.init(label: "Izq.", percent: 64), .init(label: "Der.", percent: 38),
                                   .init(label: "Estuche", percent: 15)]),
            DeviceBattery(id: "kb", name: "Magic Keyboard", symbol: "keyboard", levels: [.init(label: nil, percent: 42)]),
            DeviceBattery(id: "mouse", name: "Magic Mouse", symbol: "magicmouse", levels: [.init(label: nil, percent: 18)]),
            DeviceBattery(id: "pad", name: "Magic Trackpad", symbol: "rectangle.and.hand.point.up.left",
                          levels: [.init(label: nil, percent: 6)]),
        ])
    }
}
