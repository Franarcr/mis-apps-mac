import AppKit

// Modo de prueba: guarda una imagen del editor con un texto de ejemplo, sin abrir la app.
//   Puntos --snapshot /ruta/imagen.png
let args = CommandLine.arguments
if args.count == 3, args[1] == "--snapshot" {
    MainActor.assumeIsolated { Snapshot.render(to: URL(fileURLWithPath: args[2])) }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
