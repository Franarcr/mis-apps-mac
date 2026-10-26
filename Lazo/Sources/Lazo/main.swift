import AppKit
import SwiftUI

// Modo de prueba: guarda una imagen de la ventana principal sin abrir la app.
//   Lazo --snapshot /ruta/imagen.png
let args = CommandLine.arguments
if args.count == 3, args[1] == "--snapshot" {
    MainActor.assumeIsolated {
        let store = LayoutStore()
        let model = AppModel(store: store)
        model.trusted = true
        model.targetName = "Safari"
        model.targetIcon = NSWorkspace.shared.icon(forFile: "/Applications/Safari.app")
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            model.targetFrame = CGRect(x: vf.minX + vf.width * 0.1, y: vf.minY + vf.height * 0.2, width: vf.width * 0.5, height: vf.height * 0.6)
        }
        model.selection = (0, 3, 0, 5, 2)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 660), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: MainView(model: model, store: store, workspace: Workspace()))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[2]))
            print("Imagen guardada")
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
