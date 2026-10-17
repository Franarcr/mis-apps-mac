import AppKit
import SwiftUI

/// Borde que marca la zona que se graba o se desplaza. No recibe clics, así que se puede
/// seguir usando la app de debajo, y no aparece en la captura (se excluye la propia app).
final class RegionBorderWindow: NSWindow {
    init(globalRect: NSRect, color: NSColor, dashed: Bool) {
        let frame = globalRect.insetBy(dx: -3, dy: -3)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = BorderView(frame: NSRect(origin: .zero, size: frame.size), color: color, dashed: dashed)
    }

    private final class BorderView: NSView {
        let color: NSColor
        let dashed: Bool

        init(frame: NSRect, color: NSColor, dashed: Bool) {
            self.color = color
            self.dashed = dashed
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 2
            if dashed { path.setLineDash([6, 4], count: 2, phase: 0) }
            color.setStroke()
            path.stroke()
        }
    }
}

/// Estado del panel de control (en una clase porque `@State` necesita las macros de Xcode).
final class RegionPanelModel: ObservableObject {
    @Published var title = ""
    @Published var detail = ""
}

/// Panel flotante con el estado y los botones (Terminar / Cancelar) junto a la zona.
@MainActor
final class RegionControlPanel {
    let model = RegionPanelModel()
    private let panel: FloatingPanel

    init(symbol: String, tint: Color, primary: String, onPrimary: @escaping () -> Void,
         secondary: String?, onSecondary: (() -> Void)?) {
        let view = RegionControlView(model: model, symbol: symbol, tint: tint, primary: primary, onPrimary: onPrimary,
                                     secondary: secondary, onSecondary: onSecondary)
        let host = FirstMouseHostingView(rootView: view)
        host.frame.size = host.fittingSize
        panel = FloatingPanel(content: host)
    }

    /// Lo coloca centrado debajo de la zona; si no cabe, encima; y si tampoco, dentro.
    func show(near rect: NSRect, on screen: NSScreen) {
        let size = panel.frame.size
        let vf = screen.visibleFrame
        var y = rect.minY - size.height - 12
        if y < vf.minY { y = rect.maxY + 12 }
        if y + size.height > vf.maxY { y = rect.minY + 12 }
        let x = min(max(rect.midX - size.width / 2, vf.minX + 8), vf.maxX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    func close() { panel.orderOut(nil) }
}

private struct RegionControlView: View {
    @ObservedObject var model: RegionPanelModel
    let symbol: String
    let tint: Color
    let primary: String
    let onPrimary: () -> Void
    let secondary: String?
    let onSecondary: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.headline).monospacedDigit()
                Text(model.detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 230, alignment: .leading)
            if let secondary, let onSecondary {
                Button(secondary, action: onSecondary).buttonStyle(.bordered)
            }
            Button(primary, action: onPrimary).buttonStyle(.borderedProminent).tint(tint)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
