import SwiftUI

/// Calificación de un producto con los criterios de la skill «etiqueta»: semáforo por nutriente (agencia de
/// alimentos del Reino Unido, por 100 g o 100 ml), azúcares disfrazados, sodio oculto, grasas trans, aditivos de
/// cuidado y ultraprocesado. Solo describe el producto: no sugiere alternativas.
struct LabelAnalysis {
    enum Light: Int, Comparable {
        case green, yellow, red
        static func < (a: Light, b: Light) -> Bool { a.rawValue < b.rawValue }
        var color: Color { [Color.green, .yellow, .red][rawValue] }
        var word: String { ["Bajo", "Medio", "Alto"][rawValue] }
    }

    enum Rating: Int {
        case green, yellow, orange, red
        var color: Color { [Color.green, .yellow, .orange, .red][rawValue] }
        var title: String { ["Verde", "Amarillo", "Naranja", "Rojo"][rawValue] }
        var verdict: String {
            ["Buen perfil nutricional", "Perfil intermedio", "Perfil poco saludable", "Perfil muy poco saludable"][rawValue]
        }
    }

    struct Found: Identifiable {
        var id: String { name }
        let name: String
        let position: Int?        // posición en la lista de ingredientes (1 = el primero)
        let note: String?
    }

    var lights: [(name: String, value: Double, unit: String, light: Light)] = []
    var hiddenSugars: [Found] = []
    var sweeteners: [Found] = []
    var sodiumSources: [Found] = []
    var fatAlerts: [Found] = []
    var cautions: [Found] = []
    var ultraProcessed = false
    var positives: [String] = []
    var score = 0
    var rating: Rating = .green
    var hasIngredients = false

    // MARK: Cálculo

    static func analyze(_ food: Food) -> LabelAnalysis {
        var a = LabelAnalysis()
        let n = food.per100
        let drink = food.isDrink

        func light(_ v: Double, _ low: Double, _ high: Double) -> Light { v <= low ? .green : v <= high ? .yellow : .red }
        if let s = n.sugar { a.lights.append(("Azúcares", s, "g", drink ? light(s, 2.5, 11.25) : light(s, 5, 22.5))) }
        a.lights.append(("Grasa total", n.fat, "g", drink ? light(n.fat, 1.5, 8.75) : light(n.fat, 3, 17.5)))
        if let s = n.saturated { a.lights.append(("Grasa saturada", s, "g", drink ? light(s, 0.75, 2.5) : light(s, 1.5, 5))) }
        if let s = n.sodium { a.lights.append(("Sodio", s, "mg", drink ? light(s, 120, 300) : light(s, 120, 600))) }
        for l in a.lights { a.score += l.light == .red ? 3 : l.light == .yellow ? 1 : 0 }

        // Ingredientes, en orden.
        let items = ingredientList(food.ingredients ?? "")
        a.hasIngredients = !items.isEmpty
        func find(_ catalog: [(String, [String], String?)]) -> [Found] {
            catalog.compactMap { name, patterns, note in
                guard let index = items.firstIndex(where: { item in patterns.contains { has(item, $0) } }) else { return nil }
                return Found(name: name, position: index + 1, note: note)
            }
        }
        a.hiddenSugars = find(sugarNames)
        a.sweeteners = find(sweetenerNames)
        a.sodiumSources = find(sodiumNames)
        a.fatAlerts = find(fatNames)
        // Aditivos: por nombre en los ingredientes o por código E de Open Food Facts.
        let codes = Set(food.additives.map { $0.replacingOccurrences(of: "en:", with: "").lowercased() })
        a.cautions = cautionNames.compactMap { name, patterns, eCodes, note in
            if let index = items.firstIndex(where: { item in patterns.contains { has(item, $0) } || eCodes.contains { has(item, $0) } }) {
                return Found(name: name, position: index + 1, note: note)
            }
            return eCodes.contains(where: codes.contains) ? Found(name: name, position: nil, note: note) : nil
        }

        if a.hiddenSugars.count >= 3 { a.score += 2 }
        if items.prefix(3).contains(where: { item in sugarNames.flatMap(\.1).contains { has(item, $0) } }) { a.score += 2 }
        let trans = (n.trans ?? 0) > 0 || a.fatAlerts.contains { $0.name.contains("hidrogenad") }
        if trans { a.score += 4 }
        a.score += min(3, a.cautions.filter { $0.note?.hasPrefix("!") ?? false }.count)

        let industrial = ["jarabe", "aislad", "hidrolizad", "saborizante", "sabor artificial", "aroma", "emulsificante",
                          "emulsionante", "maltodextrina", "glutamato", "colorante", "estabilizante", "espesante", "edulcorante"]
        a.ultraProcessed = items.count > 5 && items.filter { item in industrial.contains { item.contains($0) } }.count >= 2
        if a.ultraProcessed { a.score += 1 }

        if (n.fiber ?? 0) >= 6 { a.score -= 1; a.positives.append("Buena fibra: \(fmt(n.fiber!)) g por 100") }
        if !drink && n.protein >= 10 { a.score -= 1; a.positives.append("Buena proteína: \(fmt(n.protein)) g por 100") }
        if !items.isEmpty && items.count <= 5 && a.cautions.isEmpty && !a.ultraProcessed {
            a.score -= 1; a.positives.append("Lista corta de ingredientes reconocibles")
        }
        a.score = max(0, a.score)
        a.rating = trans || a.score >= 10 ? .red : a.score >= 6 ? .orange : a.score >= 3 ? .yellow : .green
        return a
    }

    /// Palabras cortas («sal», «miel», «bha») se buscan como palabra entera, para no confundir «sal» con «salsa».
    static func has(_ item: String, _ pattern: String) -> Bool {
        guard pattern.count <= 4 else { return item.contains(pattern) }
        return item.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0 == pattern }
    }

    /// Separa la lista por comas, sin partir lo que va entre paréntesis.
    static func ingredientList(_ text: String) -> [String] {
        var text = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
        if let r = text.range(of: "ingredientes") { text = String(text[r.upperBound...]) }
        var items: [String] = [], current = "", depth = 0
        for ch in text {
            if ch == "(" || ch == "[" { depth += 1 } else if ch == ")" || ch == "]" { depth = max(0, depth - 1) }
            if (ch == "," || ch == ";" || ch == ".") && depth == 0 {
                items.append(current); current = ""
            } else { current.append(ch) }
        }
        items.append(current)
        return items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }.filter { !$0.isEmpty }
    }

    static func fmt(_ v: Double) -> String { v < 10 ? String(format: "%.1f", v) : "\(Int(v.rounded()))" }

    // MARK: Listas (sin tildes, en minúscula)

    private static let sugarNames: [(String, [String], String?)] = [
        ("Azúcar", ["azucar"], nil), ("Sacarosa", ["sacarosa"], nil), ("Glucosa", ["glucosa"], nil),
        ("Fructosa", ["fructosa"], nil), ("Dextrosa", ["dextrosa"], nil), ("Maltosa", ["maltosa"], nil),
        ("Jarabe de maíz", ["jarabe de maiz", "jmaf", "hfcs"], nil), ("Jarabe", ["jarabe", "sirope"], nil),
        ("Melaza", ["melaza"], nil), ("Miel", ["miel"], nil), ("Tapa de dulce / panela", ["tapa de dulce", "panela", "piloncillo", "rapadura"], nil),
        ("Néctar de agave", ["agave"], nil), ("Azúcar de coco", ["azucar de coco"], nil),
        ("Maltodextrina", ["maltodextrina"], nil), ("Dextrina", ["dextrina"], nil), ("Extracto de malta", ["extracto de malta", "malta de cebada"], nil),
        ("Concentrado de jugo de fruta", ["concentrado de jugo", "jugo concentrado", "pure de fruta concentrado"], nil),
    ]

    private static let sweetenerNames: [(String, [String], String?)] = [
        ("Sucralosa", ["sucralosa", "e955"], nil),
        ("Aspartamo", ["aspartam", "e951"], "Clasificado por la IARC como «posiblemente cancerígeno» (2B); la ingesta diaria aceptable se mantiene."),
        ("Acesulfame K", ["acesulfam", "e950"], nil), ("Sacarina", ["sacarina", "e954"], nil), ("Ciclamato", ["ciclamato", "e952"], nil),
        ("Stevia", ["stevia", "esteviol", "e960"], nil), ("Eritritol", ["eritritol", "e968"], nil),
        ("Sorbitol", ["sorbitol", "e420"], "Puede causar molestias digestivas."), ("Maltitol", ["maltitol", "e965"], "Puede causar molestias digestivas."),
        ("Xilitol", ["xilitol", "e967"], nil),
    ]

    private static let sodiumNames: [(String, [String], String?)] = [
        ("Sal", ["sal", "cloruro de sodio"], nil), ("Glutamato monosódico", ["glutamato", "e621"], "Suma sodio y suele indicar un producto muy procesado."),
        ("Inosinato / guanilato", ["inosinato", "guanilato", "e631", "e627"], nil), ("Bicarbonato de sodio", ["bicarbonato de sodio"], nil),
        ("Benzoato de sodio", ["benzoato de sodio", "e211"], nil), ("Nitrito / nitrato de sodio", ["nitrito de sodio", "nitrato de sodio", "e250", "e251"], nil),
        ("Fosfatos de sodio", ["fosfato de sodio", "fosfatos de sodio", "pirofosfato", "tripolifosfato"], nil),
        ("Citrato de sodio", ["citrato de sodio"], nil), ("Caseinato de sodio", ["caseinato de sodio"], nil),
        ("Salsa de soya", ["salsa de soya", "salsa de soja"], nil), ("Extracto de levadura", ["extracto de levadura"], nil),
        ("Proteína vegetal hidrolizada", ["proteina vegetal hidrolizada"], nil), ("Consomé / sazonador", ["consome", "caldo en polvo", "sazonador"], nil),
    ]

    private static let fatNames: [(String, [String], String?)] = [
        ("Aceite parcialmente hidrogenado", ["parcialmente hidrogenad"], "Contiene grasas trans aunque la tabla diga 0 g."),
        ("Aceite de palma / palmiste", ["palma", "palmiste"], "Alto en grasa saturada."),
        ("Manteca vegetal", ["manteca vegetal"], "Alta en grasa saturada."),
    ]

    /// Una nota que empieza con «!» suma un punto (colorantes artificiales y conservantes de cuidado).
    private static let cautionNames: [(String, [String], [String], String?)] = [
        ("Tartrazina", ["tartrazina", "amarillo 5", "amarillo no. 5"], ["e102"], "!Colorante asociado a hiperactividad en niños."),
        ("Amarillo ocaso", ["amarillo ocaso", "amarillo 6", "amarillo no. 6"], ["e110"], "!Colorante asociado a hiperactividad en niños."),
        ("Rojo allura", ["rojo allura", "rojo 40", "rojo no. 40"], ["e129"], "!Colorante asociado a hiperactividad en niños."),
        ("Azorrubina", ["azorrubina", "carmoisina"], ["e122"], "!Colorante asociado a hiperactividad en niños."),
        ("Ponceau 4R", ["ponceau"], ["e124"], "!Colorante asociado a hiperactividad en niños."),
        ("Dióxido de titanio", ["dioxido de titanio"], ["e171"], "!Prohibido como aditivo en la UE desde 2022."),
        ("Nitritos / nitratos", ["nitrito", "nitrato"], ["e249", "e250", "e251", "e252"], "!Conservante de carnes procesadas (la OMS las clasifica como cancerígenas, grupo 1)."),
        ("BHA", ["butilhidroxianisol", "bha"], ["e320"], "!Conservante antioxidante de cuidado."),
        ("BHT", ["butilhidroxitolueno", "bht"], ["e321"], "!Conservante antioxidante de cuidado."),
        ("TBHQ", ["tbhq", "terbutilhidroquinona"], ["e319"], "!Conservante antioxidante de cuidado."),
        ("Sulfitos", ["sulfito", "metabisulfito"], ["e220", "e221", "e222", "e223", "e224", "e225", "e226", "e227", "e228"], "Problema para asmáticos."),
        ("Benzoato de sodio", ["benzoato"], ["e211"], "Con vitamina C puede formar benceno."),
        ("Carragenina", ["carragen"], ["e407"], "Hay debate sobre inflamación intestinal (en estudio)."),
        ("Carboximetilcelulosa", ["carboximetilcelulosa"], ["e466"], "Efecto sobre la microbiota en estudio."),
        ("Polisorbato 80", ["polisorbato"], ["e433"], "Efecto sobre la microbiota en estudio."),
        ("Cafeína", ["cafeina"], [], nil),
    ]
}

// MARK: - Vista del análisis

struct LabelAnalysisView: View {
    let food: Food
    let analysis: LabelAnalysis

    init(food: Food) {
        self.food = food
        analysis = LabelAnalysis.analyze(food)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(analysis.rating.color).frame(width: 14, height: 14)
                Text("\(analysis.rating.title.uppercased()) · \(analysis.rating.verdict)").font(.headline)
                Spacer()
                Text("puntaje \(analysis.score)").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(analysis.lights, id: \.name) { l in
                HStack {
                    Circle().fill(l.light.color).frame(width: 9, height: 9)
                    Text(l.name)
                    Spacer()
                    Text("\(LabelAnalysis.fmt(l.value)) \(l.unit) · \(l.light.word)").foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.callout)
            }
            Text("Por 100 \(food.isDrink ? "ml" : "g")").font(.caption2).foregroundStyle(.secondary)

            if let sugar = food.per100.sugar, sugar > 0 {
                section("Azúcar") {
                    Text("\(LabelAnalysis.fmt(sugar)) g por 100 = \(LabelAnalysis.fmt(sugar / 4)) cucharaditas")
                    found(analysis.hiddenSugars, empty: analysis.hasIngredients ? "Sin azúcares añadidos en los ingredientes." : nil)
                    if analysis.hiddenSugars.count >= 3 {
                        Text("⚠️ \(analysis.hiddenSugars.count) tipos de azúcar: repartirlo hace que ninguno quede de primero; sumados podrían ser el ingrediente principal.")
                            .foregroundStyle(.orange)
                    }
                    if !analysis.sweeteners.isEmpty { Text("Edulcorantes:").bold(); found(analysis.sweeteners, empty: nil) }
                }
            }
            if let sodium = food.per100.sodium, sodium > 0 {
                section("Sodio") {
                    Text("\(Int(sodium.rounded())) mg por 100 = \(LabelAnalysis.fmt(sodium * 2.5 / 1000)) g de sal")
                    found(analysis.sodiumSources, empty: nil)
                }
            }
            if !analysis.fatAlerts.isEmpty { section("Grasas") { found(analysis.fatAlerts, empty: nil) } }
            if !analysis.cautions.isEmpty || analysis.ultraProcessed {
                section("Otros ingredientes de cuidado") {
                    found(analysis.cautions, empty: nil)
                    if analysis.ultraProcessed { Text("Producto ultraprocesado: lista larga con varios ingredientes industriales.") }
                }
            }
            if !analysis.positives.isEmpty {
                section("Lo positivo") { ForEach(analysis.positives, id: \.self) { Text("• \($0)") } }
            }
            if !analysis.hasIngredients && food.source != "tico" {
                Text("Sin lista de ingredientes: el análisis de azúcares disfrazados y aditivos no es completo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Análisis orientativo basado en la etiqueta; no sustituye la consulta con un nutricionista o médico, sobre todo si tenés diabetes, hipertensión u otra condición.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            content().font(.callout)
        }
    }

    @ViewBuilder private func found(_ list: [LabelAnalysis.Found], empty: String?) -> some View {
        if list.isEmpty, let empty {
            Text(empty).foregroundStyle(.secondary)
        }
        ForEach(list) { f in
            VStack(alignment: .leading, spacing: 1) {
                Text("• \(f.name)\(f.position.map { " (\($0).º ingrediente)" } ?? "")")
                if let note = f.note { Text(note.hasPrefix("!") ? String(note.dropFirst()) : note).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
