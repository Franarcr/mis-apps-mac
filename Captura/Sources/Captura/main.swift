import AppKit

// Modo línea de comandos para probar el OCR sin permisos de pantalla:
//   Captura --ocr /ruta/imagen.png
let args = CommandLine.arguments
if args.count == 3, args[1] == "--ocr" {
    let url = URL(fileURLWithPath: args[2])
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        FileHandle.standardError.write("No se pudo leer la imagen\n".data(using: .utf8)!)
        exit(1)
    }
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        do { print(try await TextRecognizer.recognize(image)) } catch { print("Error: \(error)") }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

if args.count >= 3, args[1] == "--stitch-test" {
    let source = URL(fileURLWithPath: args[2])
    let output = args.count > 3 ? URL(fileURLWithPath: args[3]) : nil
    let results = [
        StitchTest.run(source: source, output: nil),
        StitchTest.run(source: source, output: nil, footer: true),
        StitchTest.run(source: source, output: nil, footer: true, scrollbar: true),
        StitchTest.run(source: source, output: output, footer: true, scrollbar: true, noise: true),
    ]
    exit(results.allSatisfy { $0 } ? 0 : 1)
}

// Pruebas sin pantalla del editor de anotaciones y del GIF:
//   Captura --annotate-test imagen.png salida.png
//   Captura --gif-test video.mp4 salida.gif
if args.count == 4, args[1] == "--annotate-test" {
    MainActor.assumeIsolated { AnnotationTest.run(source: URL(fileURLWithPath: args[2]), output: URL(fileURLWithPath: args[3])) }
    exit(0)
}
if args.count == 4, args[1] == "--gif-test" {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let start = Date()
            try await GifMaker.make(from: URL(fileURLWithPath: args[2]), to: URL(fileURLWithPath: args[3]))
            print(String(format: "GIF creado en %.1f s", Date().timeIntervalSince(start)))
        } catch { print("Error: \(error.localizedDescription)") }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
