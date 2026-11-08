import AppIntents
import Foundation

// Estas acciones se usan desde los botones de los widgets, la Actividad en vivo, Siri y Atajos.
// Son `LiveActivityIntent`, así que siempre se ejecutan dentro de la app (donde están los datos),
// aunque se toquen en un widget. En la extensión de widgets solo hace falta que existan.

struct StartFastIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Empezar ayuno"
    static var description = IntentDescription("Empieza un ayuno en Vital desde ahora, con la meta de tu plan.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        return .result(dialog: IntentDialog(stringLiteral: await FastingActions.start()))
        #endif
    }
}

struct EndFastIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Terminar ayuno"
    static var description = IntentDescription("Termina el ayuno en curso en Vital.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "")
        #else
        return .result(dialog: IntentDialog(stringLiteral: await FastingActions.end()))
        #endif
    }
}
