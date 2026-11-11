import AppKit
import SwiftUI

/// Explicación al pasar el mouse sobre un botón o icono. Sale enseguida (la de macOS tarda más de un
/// segundo y es fácil no verla), al lado del icono y por encima de todo, también en las hojas.
/// Uso: `.hint("Abrir el PDF de la resolución")`. Todo botón o icono sin texto debe llevar una.
extension View {
    func hint(_ text: String) -> some View {
        modifier(HintModifier(text: text))
    }
}

private struct HintModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        // Una capa transparente encima sigue el mouse sin quitarle los clics al botón. Así funciona
        // también con los menús, que no avisan a SwiftUI cuando el mouse pasa por encima.
        content
            .accessibilityHint(text)
            .overlay(HintTracker(text: text))
    }
}

private struct HintTracker: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> HintTrackingView {
        let view = HintTrackingView()
        view.text = text
        return view
    }

    func updateNSView(_ view: HintTrackingView, context: Context) {
        view.text = text
    }

    static func dismantleNSView(_ view: HintTrackingView, coordinator: ()) {
        view.leave()
    }
}

final class HintTrackingView: NSView {
    var text = "" {
        didSet {
            // Si cambia mientras el mouse está encima («Marcar como revisada» → «Marcar como nueva»).
            if inside, oldValue != text { HintPanel.shared.show(text, token: token, anchor: self) }
        }
    }
    private let token = UUID()
    private var inside = false

    /// No recibe clics ni desplazamientos: pasan al botón de abajo.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        track()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        track()
    }

    /// La zona sigue sola el tamaño visible de la capa (.inVisibleRect).
    private func track() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        track()
    }

    override func mouseEntered(with event: NSEvent) {
        inside = true
        HintPanel.shared.show(text, token: token, anchor: self)
    }

    override func mouseExited(with event: NSEvent) {
        leave()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { leave() }
    }

    func leave() {
        inside = false
        HintPanel.shared.hide(token)
    }
}

@MainActor
final class HintPanel {
    static let shared = HintPanel()

    private var panel: NSPanel?
    private var token: UUID?
    private var pending: Task<Void, Never>?
    private var monitor: Any?

    func show(_ text: String, token: UUID, anchor: NSView?) {
        guard !text.isEmpty else { return }
        // Al desplazar una lista, AppKit a veces avisa con la posición vieja de un icono que ya se
        // movió: solo vale si el mouse está de verdad sobre él.
        if let anchor, !Self.isUnderMouse(anchor) { return }
        self.token = token
        pending?.cancel()
        pending = Task { @MainActor [weak self, weak anchor] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled, self.token == token else { return }
            self.present(text, anchor: anchor)
            // Si el mouse se queda quieto, la explicación se va sola.
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled, self.token == token { self.close() }
        }
    }

    /// Para la prueba sin manos: muestra una explicación y devuelve dónde quedó.
    func debugShow(_ text: String, anchor: NSView? = nil) -> NSRect? {
        present(text, anchor: anchor)
        return panel?.isVisible == true ? panel?.frame : nil
    }

    /// Lista cada capa de explicación de las ventanas abiertas con su lugar en la pantalla.
    static func dump() {
        func walk(_ view: NSView, _ out: inout [HintTrackingView]) {
            if let tracker = view as? HintTrackingView { out.append(tracker) }
            view.subviews.forEach { walk($0, &out) }
        }
        for window in NSApp.windows where window.isVisible {
            guard let root = window.contentView else { continue }
            var trackers: [HintTrackingView] = []
            walk(root, &trackers)
            print("Ventana \(Int(window.frame.minX)),\(Int(window.frame.minY)) \(Int(window.frame.width))×\(Int(window.frame.height)): \(trackers.count) capas")
            for tracker in trackers {
                let rect = window.convertToScreen(tracker.convert(tracker.bounds, to: nil))
                print("  \(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)) · frame \(Int(tracker.frame.minX)),\(Int(tracker.frame.minY)) \(Int(tracker.frame.width))×\(Int(tracker.frame.height)) · \(tracker.text.prefix(50))")
            }
        }
    }

    func hide(_ token: UUID) {
        guard self.token == token else { return }
        self.token = nil
        pending?.cancel()
        close()
    }

    /// El mouse está sobre la capa (con un margen de 3 puntos).
    static func isUnderMouse(_ view: NSView) -> Bool {
        guard let window = view.window, window.isVisible else { return false }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        return rect.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation)
    }

    private func present(_ text: String, anchor: NSView?) {
        // Hasta 300 puntos de ancho; lo que no cabe pasa a otra línea (no se corta).
        let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let single = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
        let host = NSHostingView(rootView: HintBubble(text: text, width: min(single, 300)))
        let size = host.fittingSize
        let panel = self.panel ?? makePanel()
        panel.contentView = host
        panel.setContentSize(size)
        panel.setFrameOrigin(Self.origin(for: size, anchor: anchor))
        panel.orderFront(nil)
        installMonitor()
    }

    /// Al lado del icono, a su misma altura. Si el elemento es ancho (una fila entera), al lado
    /// del puntero. Si no cabe a la derecha, a la izquierda; siempre dentro de la pantalla.
    static func origin(for size: NSSize, anchor: NSView?) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let gap: CGFloat = 8
        var target = NSRect(x: mouse.x, y: mouse.y - 20, width: 14, height: 20)  // el puntero
        if let anchor, let window = anchor.window, isUnderMouse(anchor) {
            let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            if rect.width <= 180 { target = rect }
        }
        var origin = NSPoint(x: target.maxX + gap, y: target.midY - size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if origin.x + size.width > visible.maxX - 4 { origin.x = target.minX - gap - size.width }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }
        return origin
    }

    private func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        self.panel = panel
        return panel
    }

    /// Un clic, una tecla o un desplazamiento cierran la explicación.
    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { event in
            MainActor.assumeIsolated {
                HintPanel.shared.token = nil
                HintPanel.shared.pending?.cancel()
                HintPanel.shared.close()
            }
            return event
        }
    }
}

private struct HintBubble: View {
    let text: String
    let width: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(red: 0.13, green: 0.14, blue: 0.18).opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .padding(1)
    }
}
