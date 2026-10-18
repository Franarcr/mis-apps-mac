import AppKit
import SwiftUI

class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Panel flotante sin bordes que no roba el foco a la app activa.
final class FloatingPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: content.fittingSize),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = content
    }

    override var canBecomeKey: Bool { false }
}

// MARK: - Miniatura de acceso rápido (como la de CleanShot)

/// Vista contenedora que avisa cuando el ratón entra o sale, aunque la app no esté activa.
final class HoverHostingView<Content: View>: FirstMouseHostingView<Content> {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

@MainActor
enum QuickAccess {
    private static var panel: NSPanel?
    private static var timer: Timer?
    private static var seconds = 3

    /// Muestra la miniatura y la oculta tras `seconds` segundos (la cuenta se pausa con el ratón encima).
    /// Con `onAnnotate`, la miniatura muestra el botón de anotar y el doble clic abre el editor.
    static func show(image: CGImage, fileURL: URL, saved: Bool, seconds: Int,
                     onCopy: @escaping () -> Void, onSave: @escaping () -> URL?,
                     onAnnotate: (() -> Void)? = nil) {
        dismiss()
        self.seconds = seconds
        let view = QuickAccessView(
            image: NSImage(cgImage: image, size: .zero),
            url: fileURL,
            saved: saved,
            onCopy: { onCopy(); Toast.show("Imagen copiada") },
            onSave: {
                guard let url = onSave() else { return }
                dismiss()
                Toast.show("Captura guardada", detail: url.deletingLastPathComponent().path)
            },
            onClose: { dismiss() },
            onAnnotate: onAnnotate.map { annotate in { dismiss(); annotate() } }
        )
        let host = HoverHostingView(rootView: view)
        host.frame.size = host.fittingSize
        host.onHover = { inside in
            if inside { timer?.invalidate() } else { startTimer() }
        }
        let p = FloatingPanel(content: host)
        let vf = NSScreen.underMouse.visibleFrame
        p.setFrameOrigin(NSPoint(x: vf.minX + 16, y: vf.minY + 16))
        p.orderFrontRegardless()
        panel = p
        startTimer()
    }

    private static func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { _ in
            Task { @MainActor in dismiss() }
        }
    }

    static func dismiss() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct QuickAccessView: View {
    let image: NSImage
    let url: URL
    let saved: Bool
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void
    let onAnnotate: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 240, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                .onTapGesture(count: 2) { if let onAnnotate { onAnnotate() } else { NSWorkspace.shared.open(url) } }
                .help(onAnnotate == nil ? "Arrástrala a otra app o haz doble clic para abrirla"
                                        : "Arrástrala a otra app o haz doble clic para anotarla")
            HStack(spacing: 6) {
                if let onAnnotate { action("pencil.tip.crop.circle", "Anotar (flechas, cuadros y texto)", onAnnotate) }
                action("doc.on.doc", "Copiar", onCopy)
                if saved {
                    action("folder", "Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } else {
                    action("square.and.arrow.down", "Guardar en la carpeta de capturas", onSave)
                }
                action("arrow.up.forward.app", "Abrir") { NSWorkspace.shared.open(url) }
                action("xmark", "Cerrar", onClose)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func action(_ symbol: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).frame(width: 30, height: 20)
        }
        .buttonStyle(.bordered)
        .help(help)
    }
}

// MARK: - Aviso breve

@MainActor
enum Toast {
    private static var panel: NSPanel?

    static func show(_ title: String, symbol: String = "checkmark.circle.fill", detail: String? = nil) {
        panel?.orderOut(nil)
        let host = FirstMouseHostingView(rootView: ToastView(title: title, symbol: symbol, detail: detail))
        host.frame.size = host.fittingSize
        let p = FloatingPanel(content: host)
        p.ignoresMouseEvents = true
        let vf = NSScreen.underMouse.visibleFrame
        p.setFrameOrigin(NSPoint(x: vf.midX - host.frame.width / 2, y: vf.maxY - host.frame.height - 24))
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if panel === p {
                p.orderOut(nil)
                panel = nil
            }
        }
    }
}

private struct ToastView: View {
    let title: String
    let symbol: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.headline)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: 360, alignment: .leading)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
