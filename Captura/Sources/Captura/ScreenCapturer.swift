import AppKit
import ScreenCaptureKit

struct DisplayShot {
    let screen: NSScreen
    let image: CGImage
    let display: SCDisplay
    /// La propia app, para que sus ventanas (bordes, paneles) no salgan en capturas ni vídeos.
    let ownApp: [SCRunningApplication]

    /// Convierte un rectángulo de la vista (origen abajo a la izquierda, en puntos)
    /// al sistema de ScreenCaptureKit (origen arriba a la izquierda).
    func displayRect(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// El mismo rectángulo en coordenadas globales de pantalla (para colocar ventanas).
    func globalRect(_ rect: NSRect) -> NSRect {
        rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    /// Recorta la captura congelada al rectángulo seleccionado.
    func crop(_ rect: NSRect) -> CGImage? {
        let scale = CGFloat(image.width) / screen.frame.width
        let pixels = CGRect(x: rect.minX * scale, y: (screen.frame.height - rect.maxY) * scale,
                            width: rect.width * scale, height: rect.height * scale).integral
        return image.cropping(to: pixels)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Pantalla bajo el puntero del ratón.
    static var underMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main ?? screens[0]
    }
}

enum ScreenCapturer {
    /// Captura cada pantalla a resolución nativa, excluyendo las ventanas de la propia app.
    @MainActor
    static func captureAllScreens() async throws -> [DisplayShot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApp = content.applications.filter { $0.processID == getpid() }

        var shots: [DisplayShot] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            shots.append(DisplayShot(screen: screen, image: image, display: display, ownApp: ownApp))
        }
        return shots
    }

    /// Captura en vivo solo una zona de la pantalla (para la captura con desplazamiento).
    static func captureRegion(_ shot: DisplayShot, rect: CGRect, scale: CGFloat) async throws -> CGImage {
        let filter = SCContentFilter(display: shot.display, excludingApplications: shot.ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int((rect.width * scale).rounded())
        config.height = Int((rect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
