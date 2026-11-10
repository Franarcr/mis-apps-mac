import AppIntents
import Foundation

/// Botón de la casilla en el widget: marca la tarea como hecha.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Completar tarea"
    static var description = IntentDescription("Marca como hecha una tarea de Hoy.")
    static var isDiscoverable = false

    @Parameter(title: "Tarea") var uid: String

    init() {}
    init(uid: String) { self.uid = uid }

    func perform() async throws -> some IntentResult {
        SharedToday.markDone(uid)
        return .result()
    }
}
