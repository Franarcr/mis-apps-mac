import AppKit

// Uso sin interfaz (también sirve para automatizar):
//   Compresor --self-test
//   Compresor --list archivo.zip
//   Compresor --extract archivo.zip carpeta-destino [contraseña]
//   Compresor --compress zip|7z|tar.gz|tar.xz salida.zip [--password X] elemento…
let args = CommandLine.arguments
if args.count >= 2, args[1].hasPrefix("--") {
    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
    do {
        switch args[1] {
        case "--self-test":
            exit(SelfTest.run() ? 0 : 1)
        case "--volumes" where args.count == 3:
            ArchiveEngine.volumes(of: URL(fileURLWithPath: args[2])).forEach { print($0.lastPathComponent) }
        case "--list" where args.count == 3:
            let listing = try ArchiveEngine.list(URL(fileURLWithPath: args[2]))
            print("Formato: \(listing.format)")
            for item in listing.items {
                print("\(item.isDirectory ? "d" : "-")\(item.encrypted ? "🔒" : " ") \(item.size.map(String.init) ?? "?") \(item.path)")
            }
        case "--extract" where args.count >= 4:
            try ArchiveEngine.extract(URL(fileURLWithPath: args[2]), to: URL(fileURLWithPath: args[3]),
                                      password: args.count > 4 ? args[4] : nil, progress: Progress())
            print("Extraído en \(args[3])")
        case "--compress" where args.count >= 5:
            guard let format = CreateFormat.allCases.first(where: { $0.fileExtension == args[2] }) else {
                fail("Formato no válido: \(args[2])")
            }
            var rest = Array(args.dropFirst(4))
            var password: String?
            if rest.first == "--password", rest.count >= 2 {
                password = rest[1]
                rest.removeFirst(2)
            }
            try ArchiveEngine.create(from: rest.map { URL(fileURLWithPath: $0) }, to: URL(fileURLWithPath: args[3]),
                                     format: format, password: password, progress: Progress())
            print("Creado \(args[3])")
        default:
            fail("Opción no reconocida")
        }
    } catch {
        fail("Error: \(error.localizedDescription)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
