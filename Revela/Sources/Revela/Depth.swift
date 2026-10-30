import CoreImage
import CoreML
import Foundation

/// Profundidad de la foto con Depth Anything V2 (versión de Apple para Core ML, licencia Apache 2.0).
/// El modelo (~50 MB) no va dentro de la app: se descarga una vez desde Hugging Face.
enum DepthModel {
    static let name = "DepthAnythingV2SmallF16"
    private static let base = "https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/main/\(name).mlpackage/"
    private static let files = ["Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"]

    static var folder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Revela/Modelos")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Modelo ya compilado para este Mac.
    private static var compiledURL: URL { folder.appendingPathComponent("\(name).mlmodelc") }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: compiledURL.path) }

    /// Descarga y compila el modelo. `progress` recibe 0…1. Bloquea: llamar fuera del hilo principal.
    static func install(progress: @escaping (Double) -> Void) throws {
        let package = folder.appendingPathComponent("\(name).mlpackage")
        try? FileManager.default.removeItem(at: package)
        for (index, file) in files.enumerated() {
            guard let url = URL(string: base + file) else { continue }
            let destination = package.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let semaphore = DispatchSemaphore(value: 0)
            var failure: Error?
            let task = URLSession.shared.downloadTask(with: url) { temp, response, error in
                defer { semaphore.signal() }
                if let error { failure = error; return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let temp else {
                    failure = URLError(.badServerResponse); return
                }
                do { try FileManager.default.moveItem(at: temp, to: destination) } catch { failure = error }
            }
            let observation = task.progress.observe(\.fractionCompleted) { p, _ in
                progress((Double(index) + p.fractionCompleted) / Double(files.count))
            }
            task.resume()
            semaphore.wait()
            observation.invalidate()
            if let failure { throw failure }
        }
        // Core ML compila el modelo para el chip de este Mac (no hace falta Xcode).
        let compiled = try MLModel.compileModel(at: package)
        try? FileManager.default.removeItem(at: compiledURL)
        try FileManager.default.moveItem(at: compiled, to: compiledURL)
        try? FileManager.default.removeItem(at: package)
    }

    private static var loaded: MLModel?

    private static func model() throws -> MLModel {
        if let loaded { return loaded }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: compiledURL, configuration: config)
        loaded = model
        return model
    }

    /// Descripción de entradas y salidas (para comprobar el modelo).
    static func describe() -> String {
        guard let model = try? model() else { return "modelo no instalado" }
        let d = model.modelDescription
        func list(_ items: [String: MLFeatureDescription]) -> String {
            items.values.map { f in
                if let c = f.imageConstraint { return "\(f.name): imagen \(c.pixelsWide)×\(c.pixelsHigh) formato \(c.pixelFormatType)" }
                if let c = f.multiArrayConstraint { return "\(f.name): matriz \(c.shape)" }
                return "\(f.name): \(f.type.rawValue)"
            }.joined(separator: "; ")
        }
        return "entradas: \(list(d.inputDescriptionsByName)) · salidas: \(list(d.outputDescriptionsByName))"
    }

    /// Mapa de profundidad del tamaño de `image`: blanco = cerca, negro = lejos.
    static func depthMap(for image: CIImage, context: CIContext) -> CIImage? {
        guard let model = try? model(),
              let input = model.modelDescription.inputDescriptionsByName.values.first(where: { $0.imageConstraint != nil }),
              let constraint = input.imageConstraint else { return nil }
        let size = CGSize(width: constraint.pixelsWide, height: constraint.pixelsHigh)
        // El modelo pide un tamaño fijo: la foto se estira a ese tamaño y el resultado se devuelve a su tamaño.
        let scaled = image.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width,
                                                             y: size.height / image.extent.height))
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX * size.width / image.extent.width,
                                               y: -image.extent.minY * size.height / image.extent.height))
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), constraint.pixelFormatType,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard let buffer else { return nil }
        context.render(scaled, to: buffer)
        guard let output = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: [input.name: buffer])),
              let name = model.modelDescription.outputDescriptionsByName.keys.first,
              let value = output.featureValue(for: name) else { return nil }

        var depth: CIImage?
        if let pixels = value.imageBufferValue {
            depth = CIImage(cvPixelBuffer: pixels)
        } else if let array = value.multiArrayValue {
            depth = Self.image(from: array)
        }
        guard var depth else { return nil }
        depth = normalized(depth, context: context)
        return depth.transformed(by: CGAffineTransform(scaleX: image.extent.width / depth.extent.width,
                                                       y: image.extent.height / depth.extent.height))
            .transformed(by: CGAffineTransform(translationX: image.extent.minX, y: image.extent.minY))
    }

    private static func image(from array: MLMultiArray) -> CIImage? {
        let shape = array.shape.map(\.intValue)
        guard shape.count >= 2 else { return nil }
        let height = shape[shape.count - 2], width = shape[shape.count - 1]
        var values = [Float](repeating: 0, count: width * height)
        for i in 0..<values.count { values[i] = array[i].floatValue }
        let data = Data(bytes: values, count: values.count * 4)
        return CIImage(bitmapData: data, bytesPerRow: width * 4, size: CGSize(width: width, height: height),
                       format: .Rf, colorSpace: nil)
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(height)))
    }

    /// Lleva los valores a 0…1 (el modelo da una profundidad relativa sin unidades).
    private static func normalized(_ depth: CIImage, context: CIContext) -> CIImage {
        let minMax = depth.applyingFilter("CIAreaMinMaxRed", parameters: [kCIInputExtentKey: CIVector(cgRect: depth.extent)])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(minMax, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        let low = pixel[0], high = pixel[1]
        let range = max(high - low, 1e-6)
        let scale = CGFloat(1 / range), bias = CGFloat(-low / range)
        return depth.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
        ])
    }
}

/// Profundidad de una foto y el plano que queda enfocado (0 = lejos, 1 = cerca).
struct DepthInfo {
    let map: CIImage
    let focus: Double

    /// El foco va al sujeto (si se encontró) o al centro de la foto.
    static func compute(for image: CIImage, subject: CIImage?, context: CIContext) -> DepthInfo? {
        guard let map = DepthModel.depthMap(for: image, context: context) else { return nil }
        func average(_ img: CIImage, in rect: CGRect) -> Float {
            let avg = img.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
            var pixel = [Float](repeating: 0, count: 4)
            context.render(avg, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBAf, colorSpace: nil)
            return pixel[0]
        }
        var focus: Float
        if let subject {
            // Media de la profundidad dentro del sujeto = media(profundidad × máscara) / media(máscara).
            let weighted = map.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: subject])
            let area = average(subject, in: image.extent)
            focus = area > 0.01 ? average(weighted, in: image.extent) / area : average(map, in: image.extent)
        } else {
            let e = image.extent
            focus = average(map, in: CGRect(x: e.midX - e.width * 0.1, y: e.midY - e.height * 0.1,
                                             width: e.width * 0.2, height: e.height * 0.2))
        }
        return DepthInfo(map: map, focus: Double(focus))
    }
}
