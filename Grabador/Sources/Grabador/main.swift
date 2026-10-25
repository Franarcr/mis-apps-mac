import AppKit
import SwiftUI

let arguments = CommandLine.arguments

if arguments.contains("--unidades") {
    // Lista las unidades donde se podría grabar.
    let drives = DiskUtil.externalDrives(includeVirtual: arguments.contains("--virtuales"))
    if drives.isEmpty { print("No hay unidades externas conectadas") }
    for drive in drives { print("\(drive.id)\t\(drive.summary)\t\(drive.volumes.joined(separator: ", "))") }
    exit(0)
}

if let index = arguments.firstIndex(of: "--prueba"), arguments.count > index + 2 {
    // Graba una imagen en un ARCHIVO (nunca en un disco) y la verifica: grabador --prueba imagen salida
    do {
        let image = try DiskImage.open(URL(fileURLWithPath: arguments[index + 1]))
        print("Imagen: \(image.name) · \(image.kind) · \(image.displaySize)\(image.warning.map { " · aviso: \($0)" } ?? "")")
        let result = try Flasher().run(image: image, target: .file(URL(fileURLWithPath: arguments[index + 2]))) { _ in }
        print("Grabados \(result.bytes) bytes en \(String(format: "%.1f", result.seconds)) s · verificado: \(result.verified) · SHA-256 \(result.sha256)")
        exit(0)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

if let index = arguments.firstIndex(of: "--captura"), arguments.count > index + 1 {
    // Dibuja la ventana en un PNG para revisarla: grabador --captura salida.png [imagen]
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let model = FlashModel()
        if arguments.count > index + 2 { model.selectImage(URL(fileURLWithPath: arguments[index + 2])) }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let view = NSHostingView(rootView: MainView(model: model))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(x: 0, y: 0, width: 780, height: 440)
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[index + 1]))
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
