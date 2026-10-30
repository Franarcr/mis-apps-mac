import AppKit
import SwiftUI

let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--prueba"), arguments.count > index + 2 {
    // Revela una foto con ajustes de ejemplo (incluida la IA) y la exporta: Revela --prueba foto salida.jpg [look]
    do {
        let photo = try Photo(url: URL(fileURLWithPath: arguments[index + 1]))
        var a = Adjustments()
        a.exposure = 0.3; a.contrast = 20; a.shadows = 40; a.highlights = -40; a.vibrance = 30; a.clarity = 30
        a.temperature = 10; a.vignette = 25; a.sharpness = 30
        a.backgroundBlur = arguments.contains("--lente") ? 0 : 60; a.subjectLight = 25; a.backgroundLight = -20
        if arguments.contains("--lente") { a.lensBlur = 80 }
        a.look = arguments.count > index + 3 && !arguments[index + 3].hasPrefix("--") ? arguments[index + 3] : "cine"
        a.lookAmount = 70
        let context = CIContext()
        let start = Date()
        let mask = Intelligence.subjectMask(for: photo.preview, context: context)
        print("Foto \(Int(photo.fullSize.width))×\(Int(photo.fullSize.height))\(photo.isRAW ? " RAW" : "") · sujeto: \(mask == nil ? "no" : "sí") · horizonte: \(Intelligence.horizonCorrection(for: photo.preview, context: context).map { String(format: "%.2f°", $0) } ?? "recto")")
        try Exporter.export(photo, adjustments: a, to: URL(fileURLWithPath: arguments[index + 2]), format: .jpeg, quality: 0.9, context: context)
        print(String(format: "Exportada en %.1f s", Date().timeIntervalSince(start)))
        exit(0)
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

if arguments.contains("--profundidad") {
    // Descarga el modelo de profundidad si falta y muestra sus entradas y salidas.
    if !DepthModel.isInstalled {
        var last = -1
        do {
            try DepthModel.install { p in
                let percent = Int(p * 100)
                if percent / 10 != last / 10 { last = percent; print("Descargando… \(percent) %") }
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    print(DepthModel.describe())
    exit(0)
}

if let index = arguments.firstIndex(of: "--captura"), arguments.count > index + 1 {
    // Dibuja la ventana en un PNG para revisar el diseño: Revela --captura salida.png [foto]
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let model = EditorModel()
        if arguments.count > index + 2 {
            model.open(URL(fileURLWithPath: arguments[index + 2]))
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            model.adjustments.vibrance = 30
            model.adjustments.look = "cine"
            model.adjustments.backgroundBlur = 50
        }
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        let view = NSHostingView(rootView: EditorView(model: model))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
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
