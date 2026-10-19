import AppKit

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
// A diferencia de las otras apps, esta vive en el Dock: es un lector de documentos con ventanas normales.
app.setActivationPolicy(.regular)
app.run()
