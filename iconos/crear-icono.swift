// Genera el icono de una app (.icns): fondo con degradado y un símbolo SF en blanco.
// Uso: swift crear-icono.swift <salida.icns> <símbolo SF> <color1 hex> <color2 hex> [color de detalles hex]
// El color de detalles pinta la capa principal de símbolos de varias capas (p. ej. las líneas de list.clipboard).
import AppKit

let args = CommandLine.arguments
guard args.count == 5 || args.count == 6 else {
    print("Uso: swift crear-icono.swift <salida.icns> <símbolo> <color1> <color2>")
    exit(1)
}
let output = URL(fileURLWithPath: args[1])
let symbolName = args[2]

func color(_ hex: String) -> NSColor {
    let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// Dibuja el icono a 1024×1024 px siguiendo la rejilla de iconos de macOS (forma de 824 px centrada).
func render() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

    // Sombra suave bajo la forma.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(args[3]).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Degradado diagonal y brillo superior.
    NSGradient(starting: color(args[3]), ending: color(args[4]))!.draw(in: shape, angle: -55)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0),
                        NSColor.white.withAlphaComponent(0)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: shape, angle: -90)

    // Símbolo en blanco con una ligera sombra.
    let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: args.count == 6 ? [color(args[5]), .white] : [.white]))
    if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        let scale = min(470 / s.width, 470 / s.height)
        let w = s.width * scale, h = s.height * scale
        NSGraphicsContext.saveGraphicsState()
        let glyphShadow = NSShadow()
        glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        glyphShadow.shadowOffset = NSSize(width: 0, height: -8)
        glyphShadow.shadowBlurRadius = 16
        glyphShadow.set()
        symbol.draw(in: NSRect(x: 512 - w / 2, y: 512 - h / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
    } else {
        print("Símbolo no encontrado: \(symbolName)")
        exit(1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Crea el .iconset con todos los tamaños y lo convierte con iconutil.
let master = render()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let px = base * factor
        let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current?.imageInterpolation = .high
        master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try small.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try master.representation(using: .png, properties: [:])!
    .write(to: output.deletingPathExtension().appendingPathExtension("png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Icono creado: \(output.path)" : "iconutil falló")
