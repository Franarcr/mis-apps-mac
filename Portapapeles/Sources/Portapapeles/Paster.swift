import AppKit
import ApplicationServices
import SwiftUI

/// Simula ⌘V en la app activa. Requiere el permiso de Accesibilidad; sin él, solo deja el elemento copiado.
@MainActor
enum Paster {
    static var hasAccess: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func paste() {
        guard hasAccess else {
            Toast.show("Copiado al portapapeles",
                       detail: "Para pegar automáticamente, activa Accesibilidad desde el menú › Activar pegado automático.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vKey: CGKeyCode = 0x09
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}

@MainActor
enum Toast {
    private static var panel: NSPanel?

    static func show(_ title: String, detail: String? = nil) {
        panel?.orderOut(nil)
        let host = NSHostingView(rootView: ToastView(title: title, detail: detail))
        host.frame.size = host.fittingSize
        let p = NSPanel(contentRect: host.frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        let vf = NSScreen.underMouse.visibleFrame
        p.setFrameOrigin(NSPoint(x: vf.midX - host.frame.width / 2, y: vf.maxY - host.frame.height - 24))
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if panel === p {
                p.orderOut(nil)
                panel = nil
            }
        }
    }
}

private struct ToastView: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "doc.on.clipboard.fill").font(.headline)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.secondary).frame(maxWidth: 360, alignment: .leading)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
