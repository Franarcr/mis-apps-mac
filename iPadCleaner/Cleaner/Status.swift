import SwiftUI
import UIKit

struct DiskInfo {
    let total: Int64
    let free: Int64
    var used: Int64 { total - free }
    var freeFraction: Double { total > 0 ? Double(free) / Double(total) : 0 }
}

struct ScoreFactor: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let detail: String
    let points: Double
    let maxPoints: Double
    let fix: AppSection?

    var fraction: Double { maxPoints > 0 ? points / maxPoints : 1 }
}

/// Lee el estado del iPad. iPadOS solo deja ver lo general: disco, batería,
/// temperatura y memoria total; no el uso de otras apps.
@MainActor
final class StatusModel: ObservableObject {
    @Published var disk: DiskInfo?
    @Published var batteryLevel: Float = -1
    @Published var batteryState: UIDevice.BatteryState = .unknown
    @Published var lowPower = false
    @Published var thermal: ProcessInfo.ThermalState = .nominal
    @Published var score: Int?
    @Published var factors: [ScoreFactor] = []
    @Published var previous: (score: Int, date: Date)?

    private let defaults = UserDefaults.standard

    init() {
        if let date = defaults.object(forKey: "lastScoreDate") as? Date {
            previous = (defaults.integer(forKey: "lastScore"), date)
        }
    }

    func refresh(photoJunk: Int64?) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermal = ProcessInfo.processInfo.thermalState
        disk = Self.readDisk()

        var list: [ScoreFactor] = []
        if let disk {
            let pct = Int((disk.freeFraction * 100).rounded())
            list.append(ScoreFactor(
                title: "Espacio libre",
                icon: "internaldrive.fill",
                detail: "\(Format.bytes(disk.free)) libres (\(pct) %). Lo ideal es más del 20 %.",
                points: Self.scale(disk.freeFraction, good: 0.20, bad: 0.05, max: 50),
                maxPoints: 50,
                fix: .largeFiles
            ))
            if let photoJunk {
                let share = Double(photoJunk) / Double(max(disk.total, 1))
                list.append(ScoreFactor(
                    title: "Fotos para limpiar",
                    icon: "photo.on.rectangle.angled",
                    detail: photoJunk > 0
                        ? "\(Format.bytes(photoJunk)) en fotos repetidas y capturas viejas."
                        : "No quedan fotos repetidas ni capturas viejas.",
                    points: Self.scale(share, good: 0, bad: 0.05, max: 30),
                    maxPoints: 30,
                    fix: .photos
                ))
            }
        }
        let thermalPoints: Double = switch thermal {
        case .nominal: 20
        case .fair: 14
        case .serious: 6
        default: 0
        }
        list.append(ScoreFactor(
            title: "Temperatura",
            icon: "thermometer.medium",
            detail: thermalText,
            points: thermalPoints,
            maxPoints: 20,
            fix: nil
        ))

        factors = list
        let maxTotal = list.reduce(0) { $0 + $1.maxPoints }
        let total = list.reduce(0) { $0 + $1.points }
        let newScore = Int((total / max(maxTotal, 1) * 100).rounded())
        // «Antes» es la última calificación guardada al abrir la app (se carga en init).
        score = newScore
        defaults.set(newScore, forKey: "lastScore")
        defaults.set(Date(), forKey: "lastScoreDate")
    }

    var thermalText: String {
        switch thermal {
        case .nominal: "Normal."
        case .fair: "Algo tibio. Es normal mientras carga o con juegos."
        case .serious: "Caliente. Cierra apps pesadas y quítale la funda un rato."
        default: "Muy caliente. Déjalo descansar."
        }
    }

    var batteryText: String {
        guard batteryLevel >= 0 else { return "—" }
        return "\(Int((batteryLevel * 100).rounded())) %"
    }

    var batteryDetail: String {
        var parts: [String] = []
        switch batteryState {
        case .charging: parts.append("Cargando")
        case .full: parts.append("Carga completa")
        case .unplugged: parts.append("Sin cargador")
        default: break
        }
        if lowPower { parts.append("modo de bajo consumo activo") }
        return parts.isEmpty ? "iPadOS no deja ver la salud de la batería a otras apps." : parts.joined(separator: ", ") + "."
    }

    private static func scale(_ value: Double, good: Double, bad: Double, max: Double) -> Double {
        let t = (value - bad) / (good - bad)
        return Swift.max(0, Swift.min(1, t)) * max
    }

    static func readDisk() -> DiskInfo? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskInfo(total: Int64(total), free: free)
    }
}

struct StatusView: View {
    @ObservedObject var model: StatusModel
    @ObservedObject var photos: PhotosModel
    let go: (AppSection) -> Void
    private let palette = Palette.status
    @State private var width: CGFloat = 1000

    var body: some View {
        ScrollArea {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(
                    title: "Estado",
                    subtitle: "Cómo está tu iPad ahora. iPadOS no deja que una app limpie la caché de otras, así que aquí se limpia lo que sí se puede: fotos y archivos.",
                    icon: "gauge.with.dots.needle.67percent",
                    palette: palette
                )

                // En vertical (o con la barra lateral abierta) las tarjetas van una debajo de otra.
                let layout = width > 760 ? AnyLayout(HStackLayout(alignment: .top, spacing: 20)) : AnyLayout(VStackLayout(spacing: 20))
                layout {
                    scoreCard
                    VStack(spacing: 16) {
                        diskCard
                        HStack(spacing: 16) {
                            smallCard(icon: "battery.75percent", title: "Batería", value: model.batteryText, detail: model.batteryDetail)
                            smallCard(icon: "thermometer.medium", title: "Temperatura", value: thermalShort, detail: model.thermalText)
                        }
                        HStack(spacing: 16) {
                            smallCard(icon: "memorychip", title: "Memoria", value: Format.bytes(Int64(ProcessInfo.processInfo.physicalMemory)), detail: "RAM total del iPad.")
                            smallCard(icon: "power", title: "Encendido hace", value: uptimeText, detail: "Reiniciar de vez en cuando ayuda si va lento.")
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Qué cuenta en la calificación")
                            .font(.headline)
                        ForEach(model.factors) { factor in
                            HStack(spacing: 14) {
                                IconTile(icon: factor.icon, colors: palette.accentColors, size: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(factor.title).font(.callout.weight(.semibold))
                                        Spacer()
                                        Text("\(Int(factor.points.rounded())) / \(Int(factor.maxPoints))")
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    SizeBar(fraction: factor.fraction, colors: palette.accentColors)
                                    Text(factor.detail)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                if let fix = factor.fix, factor.fraction < 0.95 {
                                    Button("Mejorar") { go(fix) }
                                        .buttonStyle(PillButtonStyle(palette: palette))
                                }
                            }
                        }
                        if photos.lastScan == nil {
                            Button {
                                go(.photos)
                            } label: {
                                Label("Revisa Fotos para sumar ese punto a la calificación", systemImage: "arrow.right.circle")
                                    .font(.callout)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
            .padding(24)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear { model.refresh(photoJunk: photos.lastScan == nil ? nil : photos.suggestedBytes) }
        .refreshable { model.refresh(photoJunk: photos.lastScan == nil ? nil : photos.suggestedBytes) }
    }

    private var scoreCard: some View {
        GlassCard(padding: 24) {
            VStack(spacing: 14) {
                RingGauge(fraction: Double(model.score ?? 0) / 100, colors: palette.accentColors, lineWidth: 18) {
                    VStack(spacing: 2) {
                        Text(model.score.map(String.init) ?? "—")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("de 100")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(width: 200, height: 200)
                Text(verdict)
                    .font(.headline)
                if let previous = model.previous {
                    Text("Antes: \(previous.score) (\(previous.date.formatted(date: .abbreviated, time: .shortened)))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Button("Volver a calificar") {
                    model.refresh(photoJunk: photos.lastScan == nil ? nil : photos.suggestedBytes)
                }
                .buttonStyle(PillButtonStyle(palette: palette))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 300)
    }

    private var diskCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Almacenamiento", systemImage: "internaldrive.fill")
                    .font(.headline)
                if let disk = model.disk {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.bytes(disk.free))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("libres de \(Format.bytes(disk.total))")
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    SizeBar(fraction: 1 - disk.freeFraction, colors: palette.accentColors, height: 10)
                    Text("Usado: \(Format.bytes(disk.used))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("No se pudo leer el disco.")
                }
            }
        }
    }

    private func smallCard(icon: String, title: String, value: String, detail: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var verdict: String {
        guard let score = model.score else { return "" }
        switch score {
        case 85...: return "Excelente"
        case 65..<85: return "Bien"
        case 45..<65: return "Necesita limpieza"
        default: return "Hay que limpiar"
        }
    }

    private var thermalShort: String {
        switch model.thermal {
        case .nominal: "Normal"
        case .fair: "Tibio"
        case .serious: "Caliente"
        default: "Muy caliente"
        }
    }

    private var uptimeText: String {
        let seconds = ProcessInfo.processInfo.systemUptime
        let days = Int(seconds / 86_400)
        let hours = Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3600)
        return days > 0 ? "\(days) d \(hours) h" : "\(hours) h"
    }
}
