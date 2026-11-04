import PhotosUI
import SwiftData
import SwiftUI
import Vision

/// Medidas de la báscula que Fitdays no pasa a Salud. Se leen de una captura de su informe.
enum ScaleMetric: String, CaseIterable, Identifiable, Codable {
    case visceral, subcutaneous, water, muscle, skeletal, bone, protein, bmr, bodyAge, score, whr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visceral: "Grasa visceral"
        case .subcutaneous: "Grasa subcutánea"
        case .skeletal: "Músculo esquelético"
        case .water: "Agua corporal"
        case .muscle: "Masa muscular"
        case .bone: "Masa ósea"
        case .protein: "Proteína"
        case .bmr: "Metabolismo basal"
        case .bodyAge: "Edad corporal"
        case .score: "Puntuación"
        case .whr: "Cintura-cadera"
        }
    }

    var unit: String {
        switch self {
        case .visceral, .score, .whr: ""
        case .water, .protein, .subcutaneous: "%"
        case .muscle, .bone, .skeletal: "kg"
        case .bmr: "kcal"
        case .bodyAge: "años"
        }
    }

    /// Cómo aparece en el informe de la báscula (sin tildes ni mayúsculas), de más a menos preciso.
    /// Fitdays en español llama «masa esquelética» a la masa ósea y «músculo esquelético» al músculo de brazos y piernas.
    var labels: [String] {
        switch self {
        case .visceral: ["grasa visceral", "visceral"]
        case .subcutaneous: ["grasa subcutanea", "subcutanea"]
        case .water: ["contenido de agua", "agua corporal", "agua", "humedad", "water"]
        case .muscle: ["masa muscular", "muscle mass"]
        case .skeletal: ["musculo esqueletico", "skeletal muscle"]
        case .bone: ["masa esqueletica", "masa osea", "osea", "hueso", "bone"]
        case .protein: ["cantidad de proteina", "proteina", "protein"]
        case .bmr: ["metabolismo basal", "tasa metabolica", "bmr"]
        case .bodyAge: ["edad corporal", "edad metabolica", "body age"]
        case .score: ["puntuacion", "puntaje", "score"]
        case .whr: ["whr", "cintura-cadera", "cintura cadera", "cintura/cadera"]
        }
    }

    /// Valores posibles, para descartar números que el lector pegó a la etiqueta equivocada.
    var range: ClosedRange<Double> {
        switch self {
        case .visceral: 1...59
        case .subcutaneous: 3...60
        case .skeletal: 10...80
        case .water: 20...80
        case .muscle: 10...150
        case .bone: 0.5...10
        case .protein: 5...40
        case .bmr: 700...4000
        case .bodyAge: 10...100
        case .score: 1...100
        case .whr: 0.5...1.5
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .bmr, .bodyAge, .score: "\(Int(v.rounded()))"
        case .whr: String(format: "%.2f", v)
        default: String(format: "%.1f", v)
        }
    }

    /// Semáforo con los rangos que usan las básculas de bioimpedancia.
    func signal(_ v: Double, female: Bool, age: Int?) -> Signal? {
        switch self {
        case .visceral: return v <= 9 ? .good : v <= 14 ? .fair : .poor
        case .water: return female ? (v >= 45 ? .good : v >= 40 ? .fair : .poor) : (v >= 50 ? .good : v >= 45 ? .fair : .poor)
        case .protein: return v >= 16 ? .good : v >= 14 ? .fair : .poor
        case .score: return v >= 80 ? .good : v >= 60 ? .fair : .poor
        case .whr: return female ? (v < 0.80 ? .good : v < 0.86 ? .fair : .poor) : (v < 0.90 ? .good : v < 1.0 ? .fair : .poor)
        case .bodyAge:
            guard let age else { return nil }
            return v <= Double(age) ? .good : v <= Double(age + 5) ? .fair : .poor
        case .subcutaneous: return female ? (v < 30 ? .good : v < 35 ? .fair : .poor) : (v < 20 ? .good : v < 25 ? .fair : .poor)
        case .muscle, .skeletal, .bone, .bmr: return nil
        }
    }

    /// Si subir es bueno, malo o neutro (para colorear la tendencia).
    var higherIsBetter: Bool? {
        switch self {
        case .visceral, .subcutaneous, .bodyAge, .whr: false
        case .water, .muscle, .skeletal, .protein, .score, .bone: true
        case .bmr: nil
        }
    }
}

@Model
final class ScaleReading {
    var date: Date
    /// Valores por `ScaleMetric.rawValue`, guardados como JSON para poder añadir medidas sin migrar.
    var valuesJSON: String

    init(date: Date, values: [ScaleMetric: Double]) {
        self.date = date
        let dict = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        valuesJSON = String(data: (try? JSONEncoder().encode(dict)) ?? Data(), encoding: .utf8) ?? "{}"
    }

    var values: [ScaleMetric: Double] {
        let dict = (try? JSONDecoder().decode([String: Double].self, from: Data(valuesJSON.utf8))) ?? [:]
        return Dictionary(uniqueKeysWithValues: dict.compactMap { key, value in ScaleMetric(rawValue: key).map { ($0, value) } })
    }
}

// MARK: - Lector de capturas

enum ScaleScreenshotReader {
    private struct Line {
        let text: String          // sin tildes, minúsculas
        let box: CGRect           // coordenadas de Vision (0–1, origen abajo a la izquierda)
    }

    /// Lee el texto de la captura (en el iPhone, sin internet) y busca cada medida junto a su etiqueta.
    static func read(_ image: UIImage) async -> (values: [ScaleMetric: Double], date: Date?) {
        guard let original = image.cgImage else { return ([:], nil) }
        let cg = enlarged(original)
        let lines: [Line] = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let found = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { obs -> Line? in
                    guard let text = obs.topCandidates(1).first?.string else { return nil }
                    return Line(text: normalize(text), box: obs.boundingBox)
                }
                continuation.resume(returning: found)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es-ES", "en-US"]
            request.usesLanguageCorrection = false
            do { try VNImageRequestHandler(cgImage: cg).perform([request]) } catch { continuation.resume(returning: []) }
        }

        var result: [ScaleMetric: Double] = [:]
        for metric in ScaleMetric.allCases {
            // La etiqueta más precisa primero («masa muscular» antes que «muscular»).
            guard let label = metric.labels.lazy.compactMap({ name in lines.first { $0.text.contains(name) } }).first else { continue }
            // 1) Un número en la misma línea, después de la etiqueta.
            // 2) Si no, la línea con número más cercana: a la derecha en la misma fila, o justo debajo.
            var candidates: [(Double, Double)] = []   // (valor, distancia)
            if let v = number(in: label.text, after: metric.labels), metric.range.contains(v) { candidates.append((v, 0)) }
            for other in lines where other.box != label.box {
                guard let v = number(in: other.text, after: []), metric.range.contains(v) else { continue }
                let dy = abs(other.box.midY - label.box.midY)
                let sameRow = dy < max(label.box.height, other.box.height) * 0.8 && other.box.minX > label.box.minX
                let below = label.box.minY - other.box.maxY
                let justBelow = below > -0.005 && below < label.box.height * 2.5 && abs(other.box.midX - label.box.midX) < 0.2
                // En las tablas «kg (rango) | %», las medidas en % están en la columna sin rango entre paréntesis.
                let wrongColumn = metric.unit == "%" && other.text.contains("(")
                if sameRow { candidates.append((v, 1 + other.box.minX - label.box.maxX + (wrongColumn ? 1 : 0))) }
                else if justBelow { candidates.append((v, 3 + below)) }
            }
            if let best = candidates.min(by: { $0.1 < $1.1 }) {
                result[metric] = best.0
            } else if let v = readRow(cg, after: label.box), metric.range.contains(v) {
                // Un número suelto y pequeño al final de la fila (el «8» de la grasa visceral) a veces no se
                // reconoce en la imagen entera: se vuelve a leer solo ese trozo, ampliado.
                result[metric] = v
            }
        }
        return (result, testDate(lines.map(\.text)))
    }

    /// La fecha del pesaje si el informe la trae (Fitdays: «Hora de la prueba:19/10/2026 07:48:53»).
    private static func testDate(_ texts: [String]) -> Date? {
        for text in texts {
            guard let m = text.firstMatch(of: /(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})(?:\s+(\d{1,2}):(\d{2}))?/) else { continue }
            var c = DateComponents()
            c.day = Int(m.output.1); c.month = Int(m.output.2); c.year = Int(m.output.3)
            c.hour = m.output.4.flatMap { Int($0) }; c.minute = m.output.5.flatMap { Int($0) }
            if let date = Calendar.current.date(from: c), date <= .now.addingTimeInterval(86_400) { return date }
        }
        return nil
    }

    /// Lee el resto de la fila a la derecha de una etiqueta, recortado. Vision casi nunca reconoce un número
    /// de una sola cifra suelto, así que el recorte se repite varias veces en una tira («8 8 8»), que sí lee.
    private static func readRow(_ image: CGImage, after box: CGRect) -> Double? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect = CGRect(x: box.maxX * w, y: (1 - box.maxY - box.height * 0.6) * h,
                          width: (1 - box.maxX) * w, height: box.height * 2.2 * h).integral
        guard rect.width > 4, rect.height > 4, let crop = image.cropping(to: rect) else { return nil }
        for (times, scale) in [(3, 2.0), (2, 2.0), (3, 3.0), (4, 3.0)] as [(Int, CGFloat)] {
            guard let strip = tiled(crop, times: times, scale: scale) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: strip).perform([request])
            let texts = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }
            if let v = texts.lazy.compactMap({ number(in: normalize($0), after: []) }).first { return v }
        }
        return nil
    }

    private static func tiled(_ image: CGImage, times: Int, scale: CGFloat) -> CGImage? {
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        guard let context = CGContext(data: nil, width: Int(w * CGFloat(times)), height: Int(h * 1.6), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.interpolationQuality = .high
        for i in 0..<times { context.draw(image, in: CGRect(x: CGFloat(i) * w, y: h * 0.3, width: w, height: h)) }
        return context.makeImage()
    }

    /// Las capturas pequeñas (p. ej. recortes) se leen mucho mejor al doble o triple de tamaño.
    private static func enlarged(_ image: CGImage, target: CGFloat = 2400) -> CGImage {
        let scale = max(1, min(4, target / CGFloat(max(image.width, image.height))))
        guard scale > 1.2,
              let context = CGContext(data: nil, width: Int(CGFloat(image.width) * scale), height: Int(CGFloat(image.height) * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage() ?? image
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }

    /// Primer número del texto (acepta coma decimal), buscado después de la etiqueta si la hay.
    private static func number(in text: String, after labels: [String]) -> Double? {
        var rest = Substring(text)
        if let label = labels.first(where: { text.contains($0) }), let r = text.range(of: label) { rest = text[r.upperBound...] }
        // «1,866» o «1.866» con tres cifras detrás son miles (el metabolismo basal); si no, la coma es decimal.
        if let thousands = rest.firstMatch(of: /\b(\d{1,2})[.,](\d{3})\b/), rest.firstMatch(of: /\d+(?:[.,]\d+)?/)?.range == thousands.range {
            return Double(thousands.output.1 + thousands.output.2)
        }
        guard let match = rest.firstMatch(of: /\d+(?:[.,]\d+)?/) else { return nil }
        return Double(match.output.replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - Importar

struct ScaleImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var values: [ScaleMetric: Double] = [:]
    @State private var date = Date.now
    @State private var reading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $item, matching: .screenshots) {
                        Label(image == nil ? "Elegir captura de Fitdays" : "Elegir otra captura", systemImage: "photo.on.rectangle")
                    }
                    if reading { HStack { ProgressView(); Text("Leyendo la captura…").foregroundStyle(.secondary) } }
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } footer: {
                    Text("Se lee en tu iPhone, sin internet. Revisa los números antes de guardar: puedes corregirlos o rellenar los que falten.")
                }
                Section {
                    DatePicker("Fecha del pesaje", selection: $date)
                    ForEach(ScaleMetric.allCases) { metric in
                        HStack {
                            Text(metric.title)
                            Spacer()
                            TextField("—", value: Binding(get: { values[metric] }, set: { values[metric] = $0 }), format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                            Text(metric.unit).font(.caption).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                        }
                    }
                }
            }
            .tint(.cyan)
            .navigationTitle("Medidas de la báscula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        // Otra captura del mismo pesaje (misma fecha) reemplaza la anterior en vez de duplicarla.
                        let window = (date.addingTimeInterval(-3600))...(date.addingTimeInterval(3600))
                        let existing = (try? context.fetch(FetchDescriptor<ScaleReading>())) ?? []
                        existing.filter { window.contains($0.date) }.forEach { context.delete($0) }
                        context.insert(ScaleReading(date: date, values: values))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(values.isEmpty)
                }
            }
            .onChange(of: item) { Task { await load() } }
        }
    }

    private func load() async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) else { return }
        image = picked
        reading = true
        let read = await ScaleScreenshotReader.read(picked)
        values = read.values
        // La fecha del informe; si no la trae, la de la captura (suele ser la del pesaje).
        if let tested = read.date {
            date = tested
        } else if let id = item.itemIdentifier,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
                  let created = asset.creationDate {
            date = created
        }
        reading = false
    }
}
