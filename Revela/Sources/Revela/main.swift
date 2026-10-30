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
        if let i = arguments.firstIndex(of: "--cielo"), arguments.count > i + 1 {
            a = Adjustments(); a.skyReplacement = arguments[i + 1]; a.skyEnhance = 20; a.vibrance = 20
            if let h = arguments.firstIndex(of: "--armonizar"), arguments.count > h + 1 { a.skyHarmonize = Double(arguments[h + 1]) ?? 0 }
            if let h = arguments.firstIndex(of: "--bruma"), arguments.count > h + 1 { a.skyHaze = Double(arguments[h + 1]) ?? 0 }
        }
        if !arguments.contains("--cielo") {
            a.look = arguments.count > index + 3 && !arguments[index + 3].hasPrefix("--") ? arguments[index + 3] : "cine"
        }
        a.lookAmount = 70
        let context = CIContext()
        let start = Date()
        let mask = Intelligence.subjectMask(for: photo.preview, context: context)
        print("Foto \(Int(photo.fullSize.width))×\(Int(photo.fullSize.height))\(photo.isRAW ? " RAW" : "") · sujeto: \(mask == nil ? "no" : "sí") · horizonte: \(Intelligence.horizonCorrection(for: photo.preview, context: context).map { String(format: "%.2f°", $0) } ?? "recto")")
        try Exporter.export(photo, adjustments: a, to: URL(fileURLWithPath: arguments[index + 2]), format: .jpeg, quality: 0.9,
                            upscale: arguments.contains("--x2") ? 2 : 1, context: context)
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

if let i = arguments.firstIndex(of: "--revelar"), arguments.count > i + 2 {
    // Exporta una foto con sus ajustes guardados en Revela (sin cambiarlos): Revela --revelar foto salida.jpg
    let url = URL(fileURLWithPath: arguments[i + 1])
    guard let photo = try? Photo(url: url), var a = EditStore.load(for: url) else { print("Sin ajustes guardados"); exit(1) }
    // --quitar a,b,…: prueba sin algunos ajustes (agua, look, auto, realce, luz) para aislar un problema.
    if let q = arguments.firstIndex(of: "--quitar"), arguments.count > q + 1 {
        for name in arguments[q + 1].split(separator: ",") {
            switch name {
            case "agua": a.water = []
            case "look": a.look = nil
            case "auto": a.autoEnhance = false
            case "realce": a.skyEnhance = 0
            case "luz": a.skyLight = 0
            case "intensidad": a.skyAmount = 100
            case "borrado": a.erase = []
            default: break
            }
        }
    }
    if let h = arguments.firstIndex(of: "--bruma"), arguments.count > h + 1 { a.skyHaze = Double(arguments[h + 1]) ?? 0 }
    // --agua x,y tono reflejo luz: prueba los ajustes de agua sin guardarlos.
    if let w = arguments.firstIndex(of: "--agua"), arguments.count > w + 4 {
        let v = arguments[w + 1].split(separator: ",").compactMap { Double($0) }
        a.water = [SelectionPoint(x: v[0], y: v[1])]
        a.waterTint = Double(arguments[w + 2]) ?? 0
        a.waterReflection = Double(arguments[w + 3]) ?? 0
        a.waterLight = Double(arguments[w + 4]) ?? 0
    }
    let start = Date()
    do { try Exporter.export(photo, adjustments: a, to: URL(fileURLWithPath: arguments[i + 2]), format: .jpeg, quality: 0.92,
                         usePreview: arguments.contains("--previa"), context: CIContext()) } catch { print("Error: \(error)") }
    print(String(format: "Revelada en %.1f s", Date().timeIntervalSince(start)))
    exit(0)
}

if let i = arguments.firstIndex(of: "--mascara-cielo"), arguments.count > i + 2 {
    // Guarda la máscara del cielo (a tamaño de vista previa o completa con --completa) para revisarla.
    let photo = try! Photo(url: URL(fileURLWithPath: arguments[i + 1]))
    let image = arguments.contains("--completa") ? photo.fullImage()! : photo.preview
    let context = CIContext()
    let embedding = SegmentModel.encode(image, context: context)!
    let coarse = SegmentModel.mask(embedding, points: SegmentModel.skyPoints, extent: image.extent, connectedToTop: true)!
    let fine = SegmentModel.mask(embedding, points: SegmentModel.skyPoints, extent: image.extent, connectedToTop: true, guide: image)!
    for (name, m) in [("gruesa", coarse), ("fina", fine)] {
        try? context.writePNGRepresentation(of: m, to: URL(fileURLWithPath: arguments[i + 2] + "-\(name).png"), format: .RGBA8,
                                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    exit(0)
}

if arguments.contains("--ampliar") {
    // Descarga Real-ESRGAN si falta y muestra sus entradas y salidas.
    if !UpscaleModel.isInstalled {
        var last = -1
        do {
            try UpscaleModel.install { p in
                let percent = Int(p * 100)
                if percent / 10 != last / 10 { last = percent; print("Descargando… \(percent) %") }
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    print(UpscaleModel.remote.describe())
    // Revela --ampliar foto salida-prefijo factor x,y,ancho,alto: amplía un recorte (en píxeles) y lo compara con Lanczos.
    if let i = arguments.firstIndex(of: "--ampliar"), arguments.count > i + 4,
       let photo = try? Photo(url: URL(fileURLWithPath: arguments[i + 1])), let full = photo.fullImage() {
        let factor = Int(arguments[i + 3]) ?? 4
        let v = arguments[i + 4].split(separator: ",").compactMap { Double($0) }
        let crop = full.cropped(to: CGRect(x: v[0], y: v[1], width: v[2], height: v[3]))
        let context = CIContext()
        let start = Date()
        do {
            let big = try UpscaleModel.upscale(crop, factor: factor, context: context)
            print(String(format: "Ampliada ×%d a %.0f×%.0f en %.1f s", factor, big.extent.width, big.extent.height, Date().timeIntervalSince(start)))
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            try context.writePNGRepresentation(of: big, to: URL(fileURLWithPath: arguments[i + 2] + "-ia.png"), format: .RGBA8, colorSpace: space)
            let plain = crop.transformed(by: CGAffineTransform(translationX: -v[0], y: -v[1]))
                .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: factor, kCIInputAspectRatioKey: 1])
            try context.writePNGRepresentation(of: plain, to: URL(fileURLWithPath: arguments[i + 2] + "-normal.png"), format: .RGBA8, colorSpace: space)
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
    exit(0)
}

if arguments.contains("--borrar") {
    // Descarga LaMa si falta y muestra sus entradas y salidas.
    if !EraseModel.isInstalled {
        var last = -1
        do {
            try EraseModel.install { p in
                let percent = Int(p * 100)
                if percent / 10 != last / 10 { last = percent; print("Descargando… \(percent) %") }
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    print(EraseModel.remote.describe())
    // Revela --borrar foto salida.jpg x,y,radio …: borra círculos (0…1, origen abajo a la izquierda).
    if let index = arguments.firstIndex(of: "--borrar"), arguments.count > index + 3,
       let photo = try? Photo(url: URL(fileURLWithPath: arguments[index + 1])), let full = photo.fullImage() {
        let strokes = arguments[(index + 3)...].map { arg -> EraseStroke in
            let v = arg.split(separator: ",").compactMap { Double($0) }
            return EraseStroke(points: [SelectionPoint(x: v[0], y: v[1])], radius: v[2])
        }
        let context = CIContext()
        let start = Date()
        guard let result = EraseModel.inpaint(full, strokes: strokes, context: context) else { print("No se pudo borrar"); exit(1) }
        try? context.writeJPEGRepresentation(of: result, to: URL(fileURLWithPath: arguments[index + 2]),
                                             colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        print(String(format: "Borrado en %.1f s", Date().timeIntervalSince(start)))
    }
    exit(0)
}

if arguments.contains("--seleccion") {
    // Descarga SAM 2.1 si falta y muestra entradas y salidas de sus tres partes.
    if !SegmentModel.isInstalled {
        var last = -1
        do {
            try SegmentModel.install { p in
                let percent = Int(p * 100)
                if percent / 10 != last / 10 { last = percent; print("Descargando… \(percent) %") }
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    SegmentModel.all.forEach { print($0.describe()) }
    // Revela --seleccion foto salida-prefijo x,y [x,y…]: guarda la máscara de esos clics (0…1, origen abajo-izquierda).
    if let index = arguments.firstIndex(of: "--seleccion"), arguments.count > index + 3 {
        let context = CIContext()
        guard let photo = try? Photo(url: URL(fileURLWithPath: arguments[index + 1])) else { exit(1) }
        var start = Date()
        guard let embedding = SegmentModel.encode(photo.preview, context: context) else { print("No se pudo codificar"); exit(1) }
        print(String(format: "Codificada en %.2f s", Date().timeIntervalSince(start)))
        // x,y para sumar; x,y,0 para quitar esa zona.
        let points = arguments[(index + 3)...].map { arg -> SelectionPoint in
            let v = arg.split(separator: ",").compactMap { Double($0) }
            return SelectionPoint(x: v[0], y: v[1], include: v.count < 3 || v[2] != 0)
        }
        start = Date()
        guard let mask = SegmentModel.objectMask(embedding, points: points, extent: photo.preview.extent) else { print("Sin máscara"); exit(1) }
        print(String(format: "Máscara en %.2f s", Date().timeIntervalSince(start)))
        // Vista de comprobación: lo seleccionado en color y lo demás oscurecido.
        let dark = Develop.exposure(photo.preview, ev: -2)
        let view = Develop.blend(photo.preview, over: dark, mask: mask)
        try? context.writeJPEGRepresentation(of: view, to: URL(fileURLWithPath: arguments[index + 2]),
                                             colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    exit(0)
}

if let index = arguments.firstIndex(of: "--captura"), arguments.count > index + 1 {
    // Dibuja la ventana en un PNG para revisar el diseño: Revela --captura salida.png [foto]
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        EditStore.readOnly = true
        let model = EditorModel()
        if arguments.count > index + 2 {
            model.open(URL(fileURLWithPath: arguments[index + 2]))
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            if arguments.contains("--tal-cual") {
                // Con los ajustes guardados de la foto, sin tocar nada.
            } else if arguments.contains("--con-borrado") {
                model.adjustments.erase = [EraseStroke(points: [SelectionPoint(x: 0.54, y: 0.345), SelectionPoint(x: 0.56, y: 0.345)],
                                                       radius: 0.02)]
                model.erasing = true
            } else {
                model.adjustments.vibrance = 30
                model.adjustments.look = "cine"
                model.adjustments.skyReplacement = "nubes"
                model.adjustments.selection = [SelectionPoint(x: 0.46, y: 0.42)]
                model.selecting = true
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(arguments.contains("--con-borrado") || arguments.contains("--tal-cual") ? 12 : 3))
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
