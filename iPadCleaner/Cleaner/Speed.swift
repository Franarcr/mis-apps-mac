import SwiftUI

struct SpeedResult {
    /// Megabits por segundo.
    let download: Double
    let upload: Double
    /// Ida y vuelta mínima al servidor, en milisegundos.
    let latency: Double?
    let date: Date
}

/// Cuenta los bytes que pasan por la red mientras dura la prueba.
private final class ByteCounter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var received: Int64 = 0
    private var sentByTask: [Int: Int64] = [:]
    private var sentDone: Int64 = 0
    var onFinish: ((URLSessionTask) -> Void)?

    var receivedBytes: Int64 { lock.withLock { received } }
    var sentBytes: Int64 { lock.withLock { sentDone + sentByTask.values.reduce(0, +) } }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock { received += Int64(data.count) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        lock.withLock { sentByTask[task.taskIdentifier] = totalBytesSent }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.withLock {
            if let sent = sentByTask.removeValue(forKey: task.taskIdentifier) { sentDone += sent }
        }
        onFinish?(task)
    }
}

/// Prueba de velocidad con los servidores de Cloudflare (speed.cloudflare.com).
/// iPadOS no trae la herramienta `networkQuality` de la Mac.
@MainActor
final class SpeedTestModel: ObservableObject {
    @Published var result: SpeedResult?
    @Published var isRunning = false
    @Published var phase = ""
    @Published var live: Double = 0
    @Published var error: String?

    private let base = "https://speed.cloudflare.com"
    private let seconds: Double = 8
    private let streams = 4

    func run() async {
        isRunning = true
        error = nil
        live = 0
        defer { isRunning = false; phase = "" }

        phase = "Latencia"
        let latency = await measureLatency()
        guard latency != nil else {
            error = "No se pudo conectar. Revisa tu conexión a internet."
            return
        }
        phase = "Descarga"
        let down = await measure(upload: false)
        phase = "Subida"
        let up = await measure(upload: true)
        result = SpeedResult(download: down, upload: up, latency: latency, date: Date())
    }

    private func measureLatency() async -> Double? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var best: Double?
        for _ in 0..<6 {
            var req = URLRequest(url: URL(string: "\(base)/__down?bytes=0")!)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let start = Date()
            guard (try? await session.data(for: req)) != nil else { continue }
            let ms = Date().timeIntervalSince(start) * 1000
            best = min(best ?? ms, ms)
        }
        return best
    }

    /// Varias conexiones a la vez durante unos segundos; cuenta lo transferido después del primer segundo.
    private func measure(upload: Bool) async -> Double {
        let counter = ByteCounter()
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: counter, delegateQueue: nil)
        let payload = Data(count: 25_000_000)
        let base = self.base
        var stopped = false
        let lock = NSLock()

        func startTask() {
            if lock.withLock({ stopped }) { return }
            if upload {
                var req = URLRequest(url: URL(string: "\(base)/__up")!)
                req.httpMethod = "POST"
                session.uploadTask(with: req, from: payload).resume()
            } else {
                session.dataTask(with: URL(string: "\(base)/__down?bytes=100000000")!).resume()
            }
        }
        counter.onFinish = { _ in startTask() }
        for _ in 0..<streams { startTask() }

        let start = Date()
        var warmBytes: Int64 = 0
        var warmTime = start
        var speed: Double = 0
        while Date().timeIntervalSince(start) < seconds {
            try? await Task.sleep(for: .milliseconds(250))
            let now = Date()
            let bytes = upload ? counter.sentBytes : counter.receivedBytes
            if now.timeIntervalSince(start) < 1 {
                warmBytes = bytes
                warmTime = now
                continue
            }
            let elapsed = now.timeIntervalSince(warmTime)
            if elapsed > 0 {
                speed = Double(bytes - warmBytes) * 8 / elapsed / 1_000_000
                live = speed
            }
        }
        lock.withLock { stopped = true }
        session.invalidateAndCancel()
        return speed
    }
}

struct SpeedTestView: View {
    @ObservedObject var model: SpeedTestModel
    @State private var pulse = false
    private let palette = Palette.speed

    var body: some View {
        ScrollArea {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(
                    title: "Velocidad de internet",
                    subtitle: model.error ?? "Mide tu conexión con los servidores de Cloudflare. Tarda unos 20 segundos.",
                    icon: "wifi",
                    palette: palette
                )

                HStack(spacing: 24) {
                    gaugeCard(title: "Descarga", icon: "arrow.down.circle.fill",
                              mbps: model.phase == "Descarga" ? model.live : model.result?.download,
                              colors: [Color(hex: 0x7DF9E9), Color(hex: 0x3FB8FF)])
                    VStack(spacing: 18) {
                        BigCircleButton(
                            title: model.isRunning ? "\(model.phase)…" : (model.result == nil ? "Iniciar" : "Repetir"),
                            palette: palette,
                            isEnabled: !model.isRunning
                        ) {
                            Task { await model.run() }
                        }
                        .scaleEffect(model.isRunning && pulse ? 1.06 : 1)
                        .animation(model.isRunning ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: pulse)
                        .onChange(of: model.isRunning) { _, running in pulse = running }
                        if let result = model.result, !model.isRunning {
                            Text("Medido a las \(result.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    gaugeCard(title: "Subida", icon: "arrow.up.circle.fill",
                              mbps: model.phase == "Subida" ? model.live : model.result?.upload,
                              colors: [Color(hex: 0xC3B6FF), Color(hex: 0xFF7EB3)])
                }
                .frame(maxWidth: .infinity)

                if let result = model.result, !model.isRunning {
                    HStack(spacing: 16) {
                        infoCard(icon: "timer", title: "Latencia",
                                 value: result.latency.map { "\(Int($0.rounded())) ms" } ?? "—",
                                 detail: "Tiempo de respuesta. Menos es mejor; menos de 50 ms va muy bien para videollamadas.")
                        infoCard(icon: "play.tv.fill", title: "Alcanza para",
                                 value: usageLabel(result.download),
                                 detail: "Estimación según tu velocidad de descarga.")
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Consejo", systemImage: "lightbulb.fill").font(.headline)
                            Text(advice(result)).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func gaugeCard(title: String, icon: String, mbps: Double?, colors: [Color]) -> some View {
        GlassCard(padding: 22) {
            VStack(spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                ZStack {
                    ArcGauge(fraction: mbps.map(Self.gaugeFraction) ?? 0, colors: colors, lineWidth: 16)
                        .frame(width: 180, height: 180)
                    VStack(spacing: 0) {
                        Text(mbps.map { $0 >= 100 ? "\(Int($0.rounded()))" : String(format: "%.1f", $0) } ?? "—")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("Mbps")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 280)
    }

    private func infoCard(icon: String, title: String, value: String, detail: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Escala logarítmica: 1 Mbps al inicio, 1000 Mbps al final.
    static func gaugeFraction(_ mbps: Double) -> Double {
        guard mbps > 0 else { return 0 }
        return min(max(log10(max(mbps, 1)) / 3, 0), 1)
    }

    private func usageLabel(_ mbps: Double) -> String {
        switch mbps {
        case 100...: "Todo, en 4K y a la vez"
        case 25..<100: "Video 4K"
        case 10..<25: "Video HD"
        case 3..<10: "Videollamadas"
        default: "Lo básico"
        }
    }

    private func advice(_ r: SpeedResult) -> String {
        if r.download < 10 {
            return "La conexión está lenta. Acércate al router, o reinícialo si pasa seguido."
        }
        if let lat = r.latency, lat > 100 {
            return "La velocidad está bien pero la respuesta es lenta. Puede ser la distancia al router o mucha gente usando la red."
        }
        return "Tu conexión está bien."
    }
}
