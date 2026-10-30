import CoreML
import Foundation

/// Un modelo de Core ML publicado en Hugging Face. No va dentro de la app: se descarga una vez,
/// Core ML lo compila para el chip de este Mac (sin Xcode) y queda en Application Support/Revela/Modelos.
struct RemoteModel {
    let repo: String    // "apple/coreml-depth-anything-v2-small"
    let name: String    // nombre del .mlpackage, sin extensión

    private static let files = ["Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"]

    static var folder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Revela/Modelos")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    var compiledURL: URL { Self.folder.appendingPathComponent("\(name).mlmodelc") }
    var isInstalled: Bool { FileManager.default.fileExists(atPath: compiledURL.path) }

    /// Descarga y compila. `progress` recibe 0…1. Bloquea: llamar fuera del hilo principal.
    func install(progress: @escaping (Double) -> Void) throws {
        let package = Self.folder.appendingPathComponent("\(name).mlpackage")
        try? FileManager.default.removeItem(at: package)
        let base = "https://huggingface.co/\(repo)/resolve/main/\(name).mlpackage/"
        for (index, file) in Self.files.enumerated() {
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
                progress((Double(index) + p.fractionCompleted) / Double(Self.files.count))
            }
            task.resume()
            semaphore.wait()
            observation.invalidate()
            if let failure { throw failure }
        }
        let compiled = try MLModel.compileModel(at: package)
        try? FileManager.default.removeItem(at: compiledURL)
        try FileManager.default.moveItem(at: compiled, to: compiledURL)
        try? FileManager.default.removeItem(at: package)
    }

    private static var cache: [String: MLModel] = [:]
    private static let lock = NSLock()

    func load() throws -> MLModel {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let model = Self.cache[name] { return model }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: compiledURL, configuration: config)
        Self.cache[name] = model
        return model
    }

    /// Entradas y salidas del modelo (para comprobarlo).
    func describe() -> String {
        guard let model = try? load() else { return "\(name): no instalado" }
        func list(_ items: [String: MLFeatureDescription]) -> String {
            items.values.sorted { $0.name < $1.name }.map { f in
                if let c = f.imageConstraint { return "\(f.name): imagen \(c.pixelsWide)×\(c.pixelsHigh) formato \(c.pixelFormatType)" }
                if let c = f.multiArrayConstraint { return "\(f.name): matriz \(c.shape) \(c.dataType.rawValue)" }
                return "\(f.name): \(f.type.rawValue)"
            }.joined(separator: "; ")
        }
        let d = model.modelDescription
        return "\(name)\n  entradas: \(list(d.inputDescriptionsByName))\n  salidas: \(list(d.outputDescriptionsByName))"
    }
}
