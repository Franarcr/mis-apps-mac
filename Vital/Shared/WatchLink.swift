import Foundation

/// Lo que el iPhone le pasa al reloj y lo que el reloj devuelve al terminar un entreno.
/// Este archivo lo comparten la app del iPhone y la del reloj.

/// El resumen de Salud de hoy, calculado en el iPhone (que tiene todo tu historial para la línea base).
struct WatchSnapshot: Codable {
    var date: Date
    var recovery: Int?          // fijada al despertar
    var live: Int?              // la del momento
    var sleepHours: Double?
    var hrv: Double?
    var hrvBase: Double?
    var restingHR: Double?
    var restingBase: Double?
    var stress: Int?
    var energy: Int?
    var expiry: Date?           // cuándo caduca la instalación
}

struct WatchSet: Codable, Hashable {
    var weight: Double?         // en la unidad elegida (kg o lb)
    var reps: Int
}

struct WatchItem: Codable, Identifiable, Hashable {
    var id: String { exerciseID }
    var exerciseID: String
    var name: String
    var weighted: Bool
    var plan: [WatchSet]        // peso y repeticiones propuestos para cada serie
    var rest: Int               // segundos de descanso
    var note: String            // por qué ese peso
}

struct WatchRoutine: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var items: [WatchItem]
}

struct WatchPayload: Codable {
    var snapshot: WatchSnapshot?
    var routines: [WatchRoutine]
    var unit: String            // "kg" o "lb"
}

/// Una serie hecha en el reloj.
struct WatchDoneSet: Codable {
    var exerciseID: String
    var index: Int
    var weight: Double?         // en la unidad elegida
    var reps: Int
}

struct WatchResult: Codable {
    var session: UUID
    var routineName: String
    var start: Date
    var end: Date
    var unit: String
    var sets: [WatchDoneSet]
}

enum WatchKeys {
    static let payload = "payload"
    static let result = "resultado"
}
