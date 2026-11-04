import Foundation
import SwiftData

/// Nutrientes por 100 g (o 100 ml en bebidas). Sodio en mg; el resto en g y kcal.
struct Nutrients: Codable, Hashable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var saturated: Double? = nil
    var trans: Double? = nil
    var fiber: Double? = nil
    var sugar: Double? = nil
    var sodium: Double? = nil

    func scaled(_ grams: Double) -> Nutrients {
        let f = grams / 100
        return Nutrients(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f,
                         saturated: saturated.map { $0 * f }, trans: trans.map { $0 * f }, fiber: fiber.map { $0 * f },
                         sugar: sugar.map { $0 * f }, sodium: sodium.map { $0 * f })
    }

    static func + (a: Nutrients, b: Nutrients) -> Nutrients {
        func add(_ x: Double?, _ y: Double?) -> Double? { x == nil && y == nil ? nil : (x ?? 0) + (y ?? 0) }
        return Nutrients(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat,
                         saturated: add(a.saturated, b.saturated), trans: add(a.trans, b.trans), fiber: add(a.fiber, b.fiber),
                         sugar: add(a.sugar, b.sugar), sodium: add(a.sodium, b.sodium))
    }
}

/// Una porción con nombre («1 taza», «1 tajada»…) y sus gramos.
struct Portion: Codable, Hashable {
    let name: String
    let grams: Double
}

/// Un alimento o producto que se puede registrar.
struct Food: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var brand: String? = nil
    var per100: Nutrients
    var portions: [Portion]
    var isDrink = false
    /// Lista de ingredientes (de la etiqueta), para el análisis de azúcares, sodio y aditivos.
    var ingredients: String? = nil
    /// Aditivos que trae Open Food Facts («en:e102»…), además de los que se lean en los ingredientes.
    var additives: [String] = []
    var barcode: String? = nil
    var source: String = "tico"     // tico, código, etiqueta, propio
}

/// Comidas típicas de Costa Rica con valores aproximados por 100 g (referencias de la Tabla de Composición
/// de Alimentos de Centroamérica del INCAP y del USDA, ajustadas a la preparación casera usual).
/// Son orientativos: la cantidad de aceite, sal o azúcar cambia mucho de una casa a otra.
enum TicoFoods {
    private static func f(_ name: String, _ kcal: Double, _ p: Double, _ c: Double, _ fat: Double, sat: Double? = nil,
                          fib: Double? = nil, sug: Double? = nil, na: Double? = nil, drink: Bool = false,
                          _ portions: [(String, Double)]) -> Food {
        Food(id: "tico-" + name.folding(options: .diacriticInsensitive, locale: nil).lowercased().replacingOccurrences(of: " ", with: "-"),
             name: name, per100: Nutrients(kcal: kcal, protein: p, carbs: c, fat: fat, saturated: sat, fiber: fib, sugar: sug, sodium: na),
             portions: portions.map { Portion(name: $0.0, grams: $0.1) }, isDrink: drink)
    }

    static let all: [Food] = [
        // Desayuno y acompañamientos
        f("Gallo pinto", 160, 6, 26, 4, sat: 0.6, fib: 5, sug: 1, na: 280, [("1 taza", 170), ("½ taza", 85)]),
        f("Arroz blanco", 145, 2.7, 28, 2, sat: 0.3, fib: 0.4, na: 200, [("1 taza", 160), ("½ taza", 80)]),
        f("Arroz integral", 123, 2.7, 25.6, 1, fib: 1.6, na: 150, [("1 taza", 195)]),
        f("Frijoles negros cocidos", 130, 8.5, 23, 0.5, fib: 8.5, sug: 0.3, na: 240, [("1 taza", 170), ("½ taza", 85)]),
        f("Frijoles molidos", 140, 7, 20, 3.5, sat: 0.8, fib: 7, na: 380, [("2 cucharadas", 40)]),
        f("Natilla", 190, 3, 4, 18, sat: 11, sug: 4, na: 50, [("1 cucharada", 15)]),
        f("Huevo frito", 196, 13.6, 0.8, 15, sat: 4.3, na: 210, [("1 unidad", 46)]),
        f("Huevo revuelto", 150, 10, 1.6, 11, sat: 3.3, na: 150, [("2 huevos", 100)]),
        f("Huevo cocido", 155, 12.6, 1.1, 10.6, sat: 3.3, na: 124, [("1 unidad", 50)]),
        f("Plátano maduro frito", 250, 1.5, 38, 11, sat: 2, fib: 2.3, sug: 20, na: 5, [("1 tajada", 40), ("½ plátano", 90)]),
        f("Plátano maduro cocido", 120, 1.3, 31, 0.4, fib: 2.3, sug: 15, na: 4, [("1 unidad", 180)]),
        f("Patacones", 280, 1.5, 40, 13, sat: 2, fib: 2.5, na: 250, [("1 unidad", 40)]),
        f("Tortilla de maíz", 220, 5.7, 45, 2.9, sat: 0.4, fib: 6, na: 45, [("1 unidad", 30)]),
        f("Tortilla de harina", 310, 8, 50, 8, sat: 3, fib: 2, sug: 2, na: 600, [("1 unidad", 45)]),
        f("Pan cuadrado blanco", 265, 9, 49, 3.2, sat: 0.7, fib: 2.7, sug: 5, na: 490, [("1 rebanada", 25)]),
        f("Pan casero (bollito)", 290, 8, 52, 5, sat: 1.5, fib: 2, sug: 6, na: 450, [("1 unidad", 50)]),
        f("Queso Turrialba", 280, 20, 3, 21, sat: 13, na: 600, [("1 tajada", 30)]),
        f("Queso palmito", 300, 22, 2, 23, sat: 14, na: 500, [("1 tajada", 30)]),
        f("Avena cocida con agua", 70, 2.5, 12, 1.4, sat: 0.3, fib: 1.7, na: 5, [("1 taza", 240)]),
        f("Avena en hojuelas (cruda)", 389, 17, 66, 7, sat: 1.2, fib: 10.6, sug: 1, na: 2, [("½ taza", 40)]),
        f("Arepa tica", 330, 6, 50, 12, sat: 4, fib: 1.5, sug: 18, na: 300, [("1 unidad", 80)]),
        // Carnes y proteínas
        f("Pechuga de pollo a la plancha", 165, 31, 0, 3.6, sat: 1, na: 250, [("1 filete", 120)]),
        f("Pollo frito", 280, 24, 8, 17, sat: 4.5, na: 450, [("1 pieza", 120)]),
        f("Carne en salsa", 180, 20, 4, 9, sat: 3.5, sug: 2, na: 400, [("1 porción", 120)]),
        f("Bistec encebollado", 215, 26, 3, 11, sat: 4.5, na: 350, [("1 bistec", 120)]),
        f("Carne molida de res", 250, 26, 0, 15, sat: 6, na: 75, [("1 porción", 100)]),
        f("Chuleta de cerdo", 230, 27, 0, 13, sat: 4.5, na: 300, [("1 chuleta", 130)]),
        f("Chicharrón", 450, 25, 0, 39, sat: 14, na: 700, [("1 porción", 60)]),
        f("Pescado frito", 230, 22, 6, 13, sat: 3, na: 350, [("1 filete", 130)]),
        f("Pescado a la plancha", 130, 26, 0, 2.7, sat: 0.9, na: 150, [("1 filete", 130)]),
        f("Atún en agua", 116, 26, 0, 1, sat: 0.3, na: 340, [("1 lata escurrida", 120)]),
        f("Jamón de pavo", 110, 17, 3, 3, sat: 1, sug: 1, na: 1000, [("1 tajada", 20)]),
        f("Salchichón", 300, 12, 3, 27, sat: 10, na: 1100, [("1 tajada", 20)]),
        f("Proteína whey", 400, 80, 8, 6, sat: 3, sug: 4, na: 200, [("1 scoop", 30)]),
        // Platos
        f("Casado (plato completo)", 165, 8, 22, 5.5, sat: 1.6, fib: 4, sug: 4, na: 300, [("1 plato", 550)]),
        f("Arroz con pollo", 165, 9, 22, 4.5, sat: 1.2, fib: 1, na: 380, [("1 plato", 300)]),
        f("Olla de carne", 70, 6, 7, 2, sat: 0.7, fib: 1.5, na: 280, [("1 plato", 450)]),
        f("Sopa negra", 90, 5, 12, 2.5, sat: 0.7, fib: 4, na: 300, [("1 plato", 350)]),
        f("Chifrijo", 230, 11, 18, 13, sat: 4, fib: 5, na: 550, [("1 plato", 300)]),
        f("Picadillo de papa", 110, 4, 15, 4, sat: 1.2, fib: 1.8, na: 300, [("1 porción", 120)]),
        f("Picadillo de chayote", 60, 2, 6, 3, sat: 0.8, fib: 1.7, na: 250, [("1 porción", 120)]),
        f("Tamal de cerdo", 190, 6, 20, 10, sat: 3.5, fib: 2, na: 400, [("1 unidad", 250)]),
        f("Empanada de carne", 300, 9, 30, 16, sat: 4, fib: 1.5, na: 450, [("1 unidad", 120)]),
        f("Pasta cocida", 158, 5.8, 31, 0.9, fib: 1.8, na: 5, [("1 taza", 140)]),
        f("Pasta con pollo en salsa blanca", 160, 9.5, 17, 6, sat: 3, fib: 1, sug: 1.5, na: 260, [("1 plato", 400)]),
        f("Pasta con carne en salsa roja", 150, 8, 19, 4.5, sat: 1.6, fib: 1.5, sug: 3, na: 280, [("1 plato", 400)]),
        // Verduras, raíces y frutas
        f("Ensalada verde", 20, 1, 4, 0.2, fib: 1.5, sug: 2, na: 10, [("1 porción", 80)]),
        f("Ensalada de repollo", 25, 1.2, 5.5, 0.1, fib: 2.3, sug: 3, na: 20, [("1 porción", 80)]),
        f("Yuca cocida", 160, 1.4, 38, 0.3, fib: 1.8, sug: 1.7, na: 14, [("1 porción", 150)]),
        f("Papa cocida", 87, 1.9, 20, 0.1, fib: 1.8, sug: 0.9, na: 5, [("1 unidad", 150)]),
        f("Camote cocido", 86, 1.6, 20, 0.1, fib: 3, sug: 4.2, na: 36, [("1 porción", 150)]),
        f("Aguacate", 160, 2, 8.5, 14.7, sat: 2.1, fib: 6.7, sug: 0.7, na: 7, [("½ unidad", 100), ("1 tajada", 30)]),
        f("Papaya", 43, 0.5, 11, 0.3, fib: 1.7, sug: 7.8, na: 8, [("1 taza", 140)]),
        f("Piña", 50, 0.5, 13, 0.1, fib: 1.4, sug: 10, na: 1, [("1 taza", 165)]),
        f("Mango", 60, 0.8, 15, 0.4, fib: 1.6, sug: 14, na: 1, [("1 unidad", 200)]),
        f("Banano", 89, 1.1, 23, 0.3, fib: 2.6, sug: 12, na: 1, [("1 unidad", 120)]),
        f("Sandía", 30, 0.6, 7.6, 0.2, fib: 0.4, sug: 6.2, na: 1, [("1 taza", 150)]),
        f("Naranja", 47, 0.9, 12, 0.1, fib: 2.4, sug: 9, na: 0, [("1 unidad", 130)]),
        // Bebidas (por 100 ml)
        f("Café negro", 2, 0.3, 0, 0, sug: 0, na: 5, drink: true, [("1 taza", 240)]),
        f("Café con azúcar", 15, 0.3, 3.5, 0, sug: 3.4, na: 5, drink: true, [("1 taza", 240)]),
        f("Café con leche", 40, 2, 4.5, 1.6, sat: 1, sug: 4.5, na: 25, drink: true, [("1 taza", 240)]),
        f("Leche entera", 61, 3.2, 4.8, 3.3, sat: 1.9, sug: 4.8, na: 43, drink: true, [("1 vaso", 250)]),
        f("Fresco natural con azúcar", 45, 0.2, 11, 0, sug: 10.5, na: 2, drink: true, [("1 vaso", 250)]),
        f("Coca-Cola", 42, 0, 10.6, 0, sug: 10.6, na: 10, drink: true, [("1 lata", 355), ("1 botella", 600)]),
        f("Cerveza Imperial", 41, 0.4, 3.3, 0, sug: 0, na: 4, drink: true, [("1 lata", 350)]),
        f("Yogurt natural", 61, 3.5, 4.7, 3.3, sat: 2.1, sug: 4.7, na: 46, [("1 vaso", 200)]),
        // Grasas y salsas
        f("Salsa Lizano", 60, 0.5, 14, 0.2, sug: 10, na: 2300, [("1 cucharadita", 5), ("1 cucharada", 15)]),
        f("Mayonesa", 680, 1, 0.6, 75, sat: 11, sug: 0.6, na: 630, [("1 cucharada", 15)]),
        f("Mantequilla", 717, 0.9, 0.1, 81, sat: 51, na: 640, [("1 cucharadita", 5)]),
        f("Aceite vegetal", 884, 0, 0, 100, sat: 14, [("1 cucharada", 14)]),
        f("Mantequilla de maní", 588, 25, 20, 50, sat: 10, fib: 6, sug: 9, na: 430, [("1 cucharada", 16)]),
        f("Galletas María", 430, 7, 74, 11, sat: 5, fib: 2, sug: 22, na: 360, [("1 galleta", 6), ("1 paquete", 30)]),
    ]
}

/// Lo que comiste: un alimento, cuánto y en qué comida del día.
@Model
final class FoodEntry {
    var date: Date
    var meal: String          // `Meal.rawValue`
    var foodJSON: String      // el `Food` completo, para recalcular y volver a registrarlo
    var grams: Double

    init(date: Date, meal: Meal, food: Food, grams: Double) {
        self.date = date
        self.meal = meal.rawValue
        foodJSON = String(data: (try? JSONEncoder().encode(food)) ?? Data(), encoding: .utf8) ?? "{}"
        self.grams = grams
    }

    var food: Food? { try? JSONDecoder().decode(Food.self, from: Data(foodJSON.utf8)) }
    var nutrients: Nutrients { food?.per100.scaled(grams) ?? Nutrients() }
}

/// Productos escaneados o leídos de etiquetas, para no tener que escanearlos otra vez.
@Model
final class SavedFood {
    var id: String
    var foodJSON: String
    var lastUsed: Date

    init(food: Food) {
        id = food.id
        foodJSON = String(data: (try? JSONEncoder().encode(food)) ?? Data(), encoding: .utf8) ?? "{}"
        lastUsed = .now
    }

    var food: Food? { try? JSONDecoder().decode(Food.self, from: Data(foodJSON.utf8)) }
}

enum Meal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String {
        switch self {
        case .breakfast: "Desayuno"
        case .lunch: "Almuerzo"
        case .dinner: "Cena"
        case .snack: "Meriendas"
        }
    }
    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }
    /// La comida que toca según la hora.
    static var now: Meal {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 10 ? .breakfast : h < 15 ? .lunch : h < 18 ? .snack : .dinner
    }
}
