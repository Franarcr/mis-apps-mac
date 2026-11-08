import SwiftUI
import Vision
import VisionKit

// MARK: - Open Food Facts

/// Busca un código de barras en Open Food Facts (base abierta y gratuita; incluye muchos productos de Costa Rica).
/// Solo se envía el código del producto.
enum OpenFoodFacts {
    static func product(barcode: String) async -> Food? {
        let fields = "product_name,product_name_es,brands,nutriments,ingredients_text_es,ingredients_text,additives_tags,categories_tags,serving_quantity,quantity"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Vital/0.1 (app personal de iPhone)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1, let p = json["product"] as? [String: Any] else { return nil }

        let n = p["nutriments"] as? [String: Any] ?? [:]
        func num(_ key: String) -> Double? {
            if let d = n[key] as? Double { return d }
            if let s = n[key] as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            if let i = n[key] as? Int { return Double(i) }
            return nil
        }
        let kcal = num("energy-kcal_100g") ?? num("energy_100g").map { $0 / 4.184 } ?? 0
        let nutrients = Nutrients(kcal: kcal, protein: num("proteins_100g") ?? 0, carbs: num("carbohydrates_100g") ?? 0,
                                  fat: num("fat_100g") ?? 0, saturated: num("saturated-fat_100g"), trans: num("trans-fat_100g"),
                                  fiber: num("fiber_100g"), sugar: num("sugars_100g"),
                                  sodium: num("sodium_100g").map { $0 * 1000 } ?? num("salt_100g").map { $0 * 400 })
        let categories = p["categories_tags"] as? [String] ?? []
        let quantity = (p["quantity"] as? String ?? "").lowercased()
        let drink = categories.contains { $0.contains("beverages") || $0.contains("bebidas") } || quantity.contains("ml") || quantity.hasSuffix(" l")
        var portions: [Portion] = []
        if let serving = p["serving_quantity"] as? Double ?? (p["serving_quantity"] as? String).flatMap(Double.init), serving > 0 {
            portions.append(Portion(name: "1 porción", grams: serving))
        }
        // «500 g», «1,5 l», «2 x 250 ml» → el contenido de un envase.
        if let m = quantity.firstMatch(of: /(\d+(?:[.,]\d+)?)\s*(kg|g|ml|cl|l)\b/),
           let n = Double(m.output.1.replacingOccurrences(of: ",", with: ".")),
           case let total = n * (["kg", "l"].contains(m.output.2) ? 1000 : m.output.2 == "cl" ? 10 : 1), total > 0, total < 3000 {
            portions.append(Portion(name: "Envase completo", grams: total))
        }
        let name = (p["product_name_es"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? p["product_name"] as? String ?? "Producto \(barcode)"
        let ingredients = (p["ingredients_text_es"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? p["ingredients_text"] as? String
        return Food(id: "codigo-\(barcode)", name: name, brand: p["brands"] as? String, per100: nutrients,
                    portions: portions, isDrink: drink, ingredients: ingredients,
                    additives: p["additives_tags"] as? [String] ?? [], barcode: barcode, source: "código")
    }
}

// MARK: - Foto de la etiqueta

/// Lee la tabla nutricional y la lista de ingredientes de una foto, en el iPhone.
/// Devuelve los valores por 100 g/ml (si la tabla viene por porción, los convierte) y la porción.
enum NutritionLabelReader {
    struct Result {
        var per100 = Nutrients()
        var portion: Double?
        var ingredients: String?
        var isDrink = false
    }

    private struct Line { let text: String; let box: CGRect }

    /// Solo la lista de ingredientes de una foto: desde «ingredientes» si aparece; si no, todo el texto leído.
    static func ingredients(_ image: UIImage) async -> String? {
        let lines = await recognize(image)
        let start = lines.firstIndex(where: { fold($0.text).contains("ingrediente") }) ?? 0
        var parts: [String] = []
        for line in lines.dropFirst(start) {
            let f = fold(line.text)
            if !parts.isEmpty && (f.contains("informacion nutricional") || f.hasPrefix("porcion") || f.contains("tamano de la porcion")) { break }
            parts.append(line.text)
        }
        let text = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func recognize(_ image: UIImage) async -> [Line] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let found = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { obs -> Line? in
                    guard let t = obs.topCandidates(1).first?.string else { return nil }
                    return Line(text: t, box: obs.boundingBox)
                }
                continuation.resume(returning: found)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es-ES", "en-US"]
            request.usesLanguageCorrection = true
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            do { try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request]) } catch { continuation.resume(returning: []) }
        }
    }

    static func read(_ image: UIImage) async -> Result {
        let lines = await recognize(image)
        guard !lines.isEmpty else { return Result() }
        let norm = lines.map { Line(text: fold($0.text), box: $0.box) }
        var result = Result()

        // Valor junto a una etiqueta: en la misma línea, o la línea más cercana a la derecha en la misma fila.
        func value(_ labels: [String], excluding: [String] = []) -> Double? {
            guard let label = norm.first(where: { l in labels.contains { l.text.contains($0) } && !excluding.contains { l.text.contains($0) } }) else { return nil }
            if let v = number(after: labels, in: label.text) { return v }
            let row = norm.filter { $0.box != label.box && abs($0.box.midY - label.box.midY) < max($0.box.height, label.box.height) * 0.7 && $0.box.minX > label.box.minX }
                .sorted { $0.box.minX < $1.box.minX }
            return row.lazy.compactMap { number(after: [], in: $0.text) }.first
        }

        result.portion = portionGrams(in: norm)
        let kcal = value(["calorias", "energia", "valor energetico", "calories"], excluding: ["de grasa", "kj"])
        let fat = value(["grasa total", "grasas totales", "total fat", "grasa"], excluding: ["saturad", "trans", "poli", "mono"])
        let saturated = value(["grasa saturada", "grasas saturadas", "saturada", "saturated"])
        let trans = value(["grasa trans", "grasas trans", "trans"])
        let sodium = value(["sodio", "sodium"])
        let carbs = value(["carbohidratos", "hidratos de carbono", "carbohidrato", "total carbohydrate"])
        let fiber = value(["fibra", "fiber"])
        let sugar = value(["azucares totales", "azucares", "azucar", "sugars"], excluding: ["anadid", "added"])
        let protein = value(["proteina", "protein"])

        // Si la tabla trae una columna «por 100 g», ya está por 100; si no, se convierte desde la porción.
        let per100Column = norm.contains { $0.text.contains("100 g") || $0.text.contains("100g") || $0.text.contains("100 ml") || $0.text.contains("100ml") }
        let factor = !per100Column ? (result.portion.map { $0 > 0 ? 100 / $0 : 1 } ?? 1) : 1
        result.per100 = Nutrients(kcal: (kcal ?? 0) * factor, protein: (protein ?? 0) * factor, carbs: (carbs ?? 0) * factor,
                                  fat: (fat ?? 0) * factor, saturated: saturated.map { $0 * factor }, trans: trans.map { $0 * factor },
                                  fiber: fiber.map { $0 * factor }, sugar: sugar.map { $0 * factor }, sodium: sodium.map { $0 * factor })
        result.isDrink = norm.contains { $0.text.contains(" ml") || $0.text.contains("ml)") }

        // Ingredientes: desde «ingredientes» hasta «contiene», «puede contener» o la tabla.
        if let start = lines.firstIndex(where: { fold($0.text).contains("ingrediente") }) {
            var text = ""
            for line in lines[start...] {
                let f = fold(line.text)
                if line.text != lines[start].text && (f.contains("contiene") || f.contains("informacion nutricional") || f.contains("porcion")) { break }
                text += (text.isEmpty ? "" : " ") + line.text
            }
            result.ingredients = text
        }
        return result
    }

    /// Gramos o mililitros de la porción: «1 lata (56 g)», «1/4 taza (30 g)», «Porción: 250 ml».
    /// Solo vale un número con unidad; el «1» de «1 lata» no es la porción.
    private static func portionGrams(in lines: [Line]) -> Double? {
        let labels = ["tamano de la porcion", "tamano por porcion", "porcion", "serving size"]
        let excluded = ["porciones por", "por envase", "porciones"]
        for label in lines where labels.contains(where: { label.text.contains($0) }) && !excluded.contains(where: { label.text.contains($0) }) {
            let row = lines.filter { abs($0.box.midY - label.box.midY) < max($0.box.height, label.box.height) * 0.7 && $0.box.minX >= label.box.minX }
                .sorted { $0.box.minX < $1.box.minX }
            for line in [label] + row.filter({ $0.box != label.box }) {
                if let m = line.text.firstMatch(of: /(\d+(?:[.,]\d+)?)\s*(g|ml|gr|mL)\b/),
                   let v = Double(m.output.1.replacingOccurrences(of: ",", with: ".")), v >= 5, v <= 2000 {
                    return v
                }
            }
        }
        return nil
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }

    private static func number(after labels: [String], in text: String) -> Double? {
        var rest = Substring(text)
        if let label = labels.first(where: { text.contains($0) }), let r = text.range(of: label) { rest = text[r.upperBound...] }
        guard let m = rest.firstMatch(of: /(\d+(?:[.,]\d+)?)\s*(mg|g|kcal|ml)?/) else { return nil }
        guard let v = Double(m.output.1.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return v
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Escáner de códigos de barras (cámara)

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case let .barcode(code) in items {
                if let value = code.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}

/// Cámara del sistema para fotografiar una etiqueta.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
