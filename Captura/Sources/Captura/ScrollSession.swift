import AppKit

/// Captura con desplazamiento: captura la zona varias veces por segundo mientras el usuario
/// se desplaza y va uniendo el contenido nuevo.
@MainActor
final class ScrollSession {
    private let shot: DisplayShot
    private let rect: CGRect
    private let stitcher = ScrollStitcher()
    private let border: RegionBorderWindow
    private var panel: RegionControlPanel!
    private var running = true
    private var keepResult = false
    private let onFinish: (CGImage?) -> Void
    private var log: (String) -> Void = { _ in }

    init(shot: DisplayShot, selection: NSRect, onFinish: @escaping (CGImage?) -> Void) {
        self.shot = shot
        rect = shot.displayRect(selection)
        self.onFinish = onFinish
        border = RegionBorderWindow(globalRect: shot.globalRect(selection), color: .systemBlue, dashed: true)
        panel = RegionControlPanel(symbol: "arrow.down.doc", tint: .blue,
                                   primary: "Terminar", onPrimary: { [weak self] in self?.finish() },
                                   secondary: "Cancelar", onSecondary: { [weak self] in self?.cancel() })
        panel.model.title = "Desplázate hacia abajo"
        panel.model.detail = "Usa la rueda o el trackpad sobre la zona"
        border.orderFrontRegardless()
        panel.show(near: shot.globalRect(selection), on: shot.screen)
        let log = Self.logger()
        log("— Nueva captura con desplazamiento · zona \(Int(rect.width))×\(Int(rect.height)) pt")
        stitcher.log = log
        self.log = log
        Task { await loop() }
    }

    func finish() {
        keepResult = true
        running = false
    }

    func cancel() {
        keepResult = false
        running = false
    }

    private func loop() async {
        let scale = shot.screen.backingScaleFactor
        let stitcher = self.stitcher
        while running {
            do {
                let frame = try await ScreenCapturer.captureRegion(shot, rect: rect, scale: scale)
                let result = await Task.detached(priority: .userInitiated) { stitcher.add(frame) }.value
                update(result)
                if stitcher.height >= ScrollStitcher.maxHeight {
                    keepResult = true
                    break
                }
            } catch {
                log("Error al capturar: \(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        border.orderOut(nil)
        panel.close()
        guard keepResult, !stitcher.isEmpty else {
            onFinish(nil)
            return
        }
        let image = await Task.detached(priority: .userInitiated) { stitcher.compose() }.value
        log("Resultado: \(image.map { "\($0.width)×\($0.height) px" } ?? "sin imagen")")
        onFinish(image)
    }

    /// Registro en ~/Library/Logs/Captura/desplazamiento.log (se reinicia en cada captura).
    private static func logger() -> (String) -> Void {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Captura")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("desplazamiento.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return { _ in } }
        let start = Date()
        return { line in
            let stamp = String(format: "%6.2f s  ", Date().timeIntervalSince(start))
            handle.write(Data((stamp + line + "\n").utf8))
        }
    }

    private func update(_ result: ScrollStitcher.Result) {
        let height = "\(stitcher.height.formatted()) px de alto"
        switch result {
        case .added, .unchanged:
            panel.model.title = "Desplázate hacia abajo"
            panel.model.detail = height
        case .lost:
            panel.model.title = "Demasiado rápido"
            panel.model.detail = "Vuelve un poco hacia arriba · \(height)"
        }
    }
}
