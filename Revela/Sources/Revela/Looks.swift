import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Estilos de color: unos incluidos y los LUT .cube que añadas tú (los de Lightroom, cámaras de cine…).
enum Looks {
    struct Look: Identifiable, Hashable {
        let id: String      // nombre interno o ruta del .cube
        let name: String
    }

    static let builtIn: [Look] = [
        Look(id: "cine", name: "Cine"),
        Look(id: "calido", name: "Cálido"),
        Look(id: "frio", name: "Frío"),
        Look(id: "pelicula", name: "Película"),
        Look(id: "vintage", name: "Vintage"),
        Look(id: "cromo", name: "Cromo"),
        Look(id: "instant", name: "Instantánea"),
        Look(id: "byn", name: "Blanco y negro"),
        Look(id: "byn-contraste", name: "B y N dramático"),
    ]

    /// Carpeta donde se guardan los .cube importados.
    static var lutFolder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Revela/LUT")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func imported() -> [Look] {
        ((try? FileManager.default.contentsOfDirectory(at: lutFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "cube" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { Look(id: $0.path, name: $0.deletingPathExtension().lastPathComponent) }
    }

    /// Copia un .cube a la carpeta de LUT y devuelve su look.
    static func importCube(_ url: URL) throws -> Look {
        _ = try parseCube(url) // comprobar que se puede leer antes de copiarlo
        let destination = lutFolder.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        cubeCache[destination.path] = nil
        return Look(id: destination.path, name: url.deletingPathExtension().lastPathComponent)
    }

    static func name(of id: String) -> String {
        builtIn.first { $0.id == id }?.name ?? URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent
    }

    static func apply(_ id: String, to image: CIImage) -> CIImage? {
        switch id {
        case "cine": return cube("cine", tealOrange, to: image)
        case "calido": return cube("calido", { r, g, b in (min(1, r * 1.06 + 0.02), g * 1.01, b * 0.9) }, to: image)
        case "frio": return cube("frio", { r, g, b in (r * 0.92, g * 0.99, min(1, b * 1.08 + 0.02)) }, to: image)
        case "pelicula": return cube("pelicula", film, to: image)
        case "vintage": return photoEffect(CIFilter.photoEffectTransfer(), image)
        case "cromo": return photoEffect(CIFilter.photoEffectChrome(), image)
        case "instant": return photoEffect(CIFilter.photoEffectInstant(), image)
        case "byn": return photoEffect(CIFilter.photoEffectTonal(), image)
        case "byn-contraste": return photoEffect(CIFilter.photoEffectNoir(), image)
        default: return lut(atPath: id, to: image)
        }
    }

    private static func photoEffect(_ filter: CIFilter & CIPhotoEffect, _ image: CIImage) -> CIImage? {
        filter.inputImage = image
        return filter.outputImage
    }

    // MARK: Looks generados

    private typealias ColorMap = (Double, Double, Double) -> (Double, Double, Double)

    /// Sombras azul verdoso y tonos de piel cálidos (el «look» de muchas películas).
    private static let tealOrange: ColorMap = { r, g, b in
        let l = 0.299 * r + 0.587 * g + 0.114 * b
        let shadow = max(0, 0.5 - l) * 2, light = max(0, l - 0.5) * 2
        return (r - 0.05 * shadow + 0.06 * light, g + 0.01 * shadow + 0.02 * light, b + 0.07 * shadow - 0.06 * light)
    }

    /// Negros algo levantados y colores un poco apagados, como un negativo escaneado.
    private static let film: ColorMap = { r, g, b in
        let l = 0.299 * r + 0.587 * g + 0.114 * b
        func tone(_ c: Double) -> Double { 0.06 + 0.9 * (l + (c - l) * 0.85) }
        return (tone(r) + 0.01, tone(g), tone(b) - 0.01)
    }

    /// Los cubos generados se calculan una sola vez.
    private static var generatedCache: [String: Data] = [:]

    private static func cube(_ key: String, _ map: ColorMap, to image: CIImage) -> CIImage? {
        let size = 33
        if let data = generatedCache[key] { return colorCube(size: size, data: data, image: image) }
        var values = [Float]()
        values.reserveCapacity(size * size * size * 4)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let (nr, ng, nb) = map(Double(r) / Double(size - 1), Double(g) / Double(size - 1), Double(b) / Double(size - 1))
                    values += [Float(min(max(nr, 0), 1)), Float(min(max(ng, 0), 1)), Float(min(max(nb, 0), 1)), 1]
                }
            }
        }
        let data = Data(bytes: values, count: values.count * 4)
        generatedCache[key] = data
        return colorCube(size: size, data: data, image: image)
    }

    private static func colorCube(size: Int, data: Data, image: CIImage) -> CIImage? {
        let f = CIFilter.colorCubeWithColorSpace()
        f.inputImage = image
        f.cubeDimension = Float(size)
        f.cubeData = data
        f.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        return f.outputImage
    }

    // MARK: Archivos .cube

    private static var cubeCache: [String: (size: Int, data: Data)] = [:]

    private static func lut(atPath path: String, to image: CIImage) -> CIImage? {
        if cubeCache[path] == nil { cubeCache[path] = try? parseCube(URL(fileURLWithPath: path)) }
        guard let cube = cubeCache[path] else { return nil }
        return colorCube(size: cube.size, data: cube.data, image: image)
    }

    enum CubeError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let detail): return "El archivo .cube no es válido: \(detail)" }
        }
    }

    /// Formato .cube de Adobe/Resolve: LUT_3D_SIZE N y N³ líneas "r g b" (el rojo cambia más rápido).
    static func parseCube(_ url: URL) throws -> (size: Int, data: Data) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .isoLatin1) else {
            throw CubeError.invalid("no se puede leer")
        }
        var size = 0
        var domainMin = [0.0, 0.0, 0.0], domainMax = [1.0, 1.0, 1.0]
        var values = [Float]()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "LUT_3D_SIZE", parts.count > 1 { size = Int(parts[1]) ?? 0; continue }
            if parts.first == "LUT_1D_SIZE" { throw CubeError.invalid("es un LUT 1D, solo se admiten 3D") }
            if parts.first == "DOMAIN_MIN", parts.count == 4 { domainMin = parts.dropFirst().compactMap { Double($0) }; continue }
            if parts.first == "DOMAIN_MAX", parts.count == 4 { domainMax = parts.dropFirst().compactMap { Double($0) }; continue }
            guard parts.count == 3, let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]) else { continue }
            let rgb = [r, g, b].enumerated().map { i, v in (v - domainMin[i]) / max(domainMax[i] - domainMin[i], 1e-6) }
            values += [Float(rgb[0]), Float(rgb[1]), Float(rgb[2]), 1]
        }
        guard size >= 2, size <= 128 else { throw CubeError.invalid("falta LUT_3D_SIZE") }
        guard values.count == size * size * size * 4 else {
            throw CubeError.invalid("tiene \(values.count / 4) colores y debería tener \(size * size * size)")
        }
        return (size, Data(bytes: values, count: values.count * 4))
    }
}
