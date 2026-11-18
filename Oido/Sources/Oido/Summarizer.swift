import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Resumen y pendientes con Apple Intelligence, en la Mac. Si no está disponible, se queda sin resumen.
enum Summarizer {
    struct Result { var summary: String?; var actions: [String]; var note: String? }

    static func summarize(_ lines: [Line]) async -> Result {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await Modern.summarize(lines)
        }
        #endif
        return Result(summary: nil, actions: [], note: "El resumen necesita macOS 26 con Apple Intelligence.")
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum Modern {
    static let instructions = """
    Resumes llamadas de trabajo en español. Escribe solo lo que se dijo en la conversación: \
    no inventes nombres, cifras, fechas ni acuerdos. En la transcripción «Yo» es el dueño de la grabación y «Ellos» la otra parte; en tu respuesta di «yo» y «la otra persona».
    """

    static func summarize(_ lines: [Line]) async -> Summarizer.Result {
        switch SystemLanguageModel.default.availability {
        case .available: break
        case .unavailable(let reason):
            let why: String
            switch reason {
            case .appleIntelligenceNotEnabled: why = "Activa Apple Intelligence en Ajustes del Sistema para tener resumen."
            case .modelNotReady: why = "Apple Intelligence todavía se está descargando; vuelve a pedir el resumen más tarde."
            default: why = "Esta Mac no tiene Apple Intelligence, así que la llamada queda sin resumen."
            }
            return .init(summary: nil, actions: [], note: why)
        }

        let text = lines.map { "\($0.speaker == .me ? "Yo" : "Ellos"): \($0.text)" }.joined(separator: "\n")
        do {
            // El modelo admite textos cortos: las llamadas largas se resumen por partes y luego se juntan.
            // Si el filtro de Apple rechaza un tramo, se salta y se resume el resto.
            var parts = chunks(text, size: 6000)
            var skipped = 0
            if parts.count > 1 {
                var notes: [String] = []
                for part in parts {
                    do {
                        let r = try await newSession().respond(to: "Anota en viñetas breves lo importante y lo que alguien se comprometió a hacer en este tramo de la llamada:\n\n\(part)")
                        notes.append(r.content)
                    } catch let error as LanguageModelSession.GenerationError {
                        guard case .guardrailViolation = error else { throw error }
                        skipped += 1
                    }
                }
                guard !notes.isEmpty else {
                    return .init(summary: nil, actions: [], note: "Apple Intelligence no quiso resumir ninguna parte de esta llamada (su filtro de seguridad la marcó). El texto completo está abajo.")
                }
                parts = [notes.joined(separator: "\n")]
            }
            let prompt = """
            Con esta llamada, responde exactamente con este formato:
            RESUMEN:
            (tres a cinco frases)
            PENDIENTES:
            - (cada tarea o compromiso, con quién y cuándo si se dijo; escribe «- Ninguno» si no hay)

            \(parts[0])
            """
            var result: Summarizer.Result
            do {
                result = parse(try await newSession().respond(to: prompt).content)
            } catch let error as LanguageModelSession.GenerationError {
                guard case .guardrailViolation = error else { throw error }
                // Si el resumen final se rechaza pero hay notas por tramos, se muestran las notas.
                guard parts.count == 1, text.count > 6000 else {
                    return .init(summary: nil, actions: [], note: "Apple Intelligence no quiso resumir esta llamada (su filtro de seguridad la marcó). El texto completo está abajo.")
                }
                result = .init(summary: clean(parts[0], removing: ""), actions: [], note: "Son las notas por tramos: Apple Intelligence no quiso juntarlas en un resumen.")
            }
            if skipped > 0 {
                let why = skipped == 1 ? "1 tramo de la llamada quedó" : "\(skipped) tramos de la llamada quedaron"
                result.note = [result.note, "\(why) fuera del resumen porque el filtro de Apple Intelligence los rechazó."].compactMap { $0 }.joined(separator: " ")
            }
            return result
        } catch {
            return .init(summary: nil, actions: [], note: "No se pudo hacer el resumen: \(error.localizedDescription)")
        }
    }

    /// Con el filtro pensado para resumir texto que ya existe: el normal rechaza conversaciones corrientes.
    static func newSession() -> LanguageModelSession {
        LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: instructions)
    }

    static func chunks(_ text: String, size: Int) -> [String] {
        var out: [String] = []
        var current = ""
        for line in text.split(separator: "\n") {
            if current.count + line.count > size, !current.isEmpty { out.append(current); current = "" }
            current += line + "\n"
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func parse(_ text: String) -> Summarizer.Result {
        let upper = text.uppercased()
        guard let r = upper.range(of: "PENDIENTES:") else {
            return .init(summary: clean(text, removing: "RESUMEN:"), actions: [], note: nil)
        }
        let split = text.index(text.startIndex, offsetBy: upper.distance(from: upper.startIndex, to: r.lowerBound))
        let summary = clean(String(text[..<split]), removing: "RESUMEN:")
        let actions = text[split...].split(separator: "\n").dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty && $0.lowercased() != "ninguno" && $0.lowercased() != "ninguno." }
        return .init(summary: summary, actions: actions, note: nil)
    }

    static func clean(_ s: String, removing header: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.uppercased().hasPrefix(header) { t = String(t.dropFirst(header.count)) }
        return t.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
