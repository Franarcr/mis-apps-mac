import AppKit
import SwiftUI

/// Aviso flotante arriba a la derecha: «Llamada en WhatsApp — ¿grabar?» o «Grabando…».
@MainActor
final class Prompt {
    private var panel: NSPanel?
    private var closeTimer: Timer?

    func ask(_ app: CallApp, record: @escaping () -> Void) {
        show(seconds: 40) {
            PromptView(icon: "phone.fill", title: "Llamada en \(app.name)",
                       text: "¿La grabo? Recuerda avisar que la llamada se graba.",
                       primary: "Grabar", secondary: "Ahora no",
                       onPrimary: { [weak self] in self?.close(); record() },
                       onSecondary: { [weak self] in self?.close() })
        }
    }

    func recording(_ app: CallApp, stop: @escaping () -> Void) {
        show(seconds: 8) {
            PromptView(icon: "record.circle", title: "Grabando \(app.name)",
                       text: "Recuerda avisar que la llamada se graba.",
                       primary: "Detener", secondary: "Cerrar",
                       onPrimary: { [weak self] in self?.close(); stop() },
                       onSecondary: { [weak self] in self?.close() })
        }
    }

    /// Mientras graba queda una barrita fija arriba a la derecha con el tiempo y «Detener»,
    /// por si el icono de la barra de menús queda tapado (muchos iconos o el notch).
    func recordingBar(_ app: CallApp, stop: @escaping () -> Void) {
        close()
        let host = NSHostingView(rootView: RecordingBar(name: app.name, onStop: { [weak self] in self?.close(); stop() }))
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = host
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 12))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    var isShowing: Bool { panel != nil }

    func close() {
        closeTimer?.invalidate()
        panel?.orderOut(nil)
        panel = nil
    }

    private func show(seconds: TimeInterval, @ViewBuilder content: () -> PromptView) {
        close()
        let host = NSHostingView(rootView: content())
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = host
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 12))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        closeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}

struct PromptView: View {
    let icon: String
    let title: String
    let text: String
    let primary: String
    let secondary: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(.red).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(secondary, action: onSecondary)
                    Button(primary, action: onPrimary).keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
        }
        .padding(14)
        .frame(width: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RecordingBar: View {
    let name: String
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "record.circle.fill").foregroundStyle(.red)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("\(name) · \(Call.clock(Recorder.shared.elapsed))").monospacedDigit()
            }
            .font(.callout)
            Button("Detener", action: onStop).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }
}
