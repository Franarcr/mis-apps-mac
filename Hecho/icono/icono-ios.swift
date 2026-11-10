// Dibuja el icono de iPhone de Hecho (1024×1024, a sangre: iOS redondea las esquinas).
// Uso: swift icono-ios.swift <salida.png>
import AppKit
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let c1 = NSColor(srgbRed: 0.16, green: 0.66, blue: 0.60, alpha: 1)
let c2 = NSColor(srgbRed: 0.06, green: 0.40, blue: 0.42, alpha: 1)
NSGradient(starting: c1, ending: c2)!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: -90)
let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .bold).applying(.init(paletteColors: [.white]))
let img = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let s = img.size
img.draw(in: NSRect(x: (1024 - s.width) / 2, y: (1024 - s.height) / 2, width: s.width, height: s.height))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
