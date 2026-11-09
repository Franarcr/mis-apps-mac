import Foundation

/// Un correo apartado para la papelera.
struct Candidate: Identifiable, Hashable, Sendable {
    let account: String
    let mailbox: String
    let isJunk: Bool
    let index: Int
    let messageID: String
    let sender: String
    let subject: String
    let received: Date
    /// Regla que lo atrapó («linkedin.com», «Correo no deseado»…).
    let reason: String
    /// Coincide con «Nunca barrer»: se propone devolverlo a la bandeja.
    let isException: Bool
    var id: String { "\(account)|\(mailbox)|\(messageID)" }
}

/// Barrendero trabaja con reglas de Mail: Mail aparta la publicidad en cuanto llega (a la carpeta
/// local «Barridos») y Barrendero, cada semana, muestra lo apartado y el correo no deseado para
/// confirmarlo. Así nunca recorre la bandeja de entrada completa, que en Exchange es lentísima.
/// Solo lee remitente, asunto y fecha, nunca el contenido.
enum Sweeper {
    static let holdingMailbox = "Barridos"
    static let rulePrefix = "Barrendero"

    enum Failure: LocalizedError {
        case script(String)
        var errorDescription: String? {
            switch self {
            case .script(let message):
                message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized")
                    ? "Barrendero no tiene permiso para usar Mail. Actívalo en Configuración del Sistema → Privacidad y seguridad → Automatización."
                    : "Mail respondió con un error: \(message)"
            }
        }
    }

    private static let recordSeparator = "\u{1E}"
    private static let fieldSeparator = "\u{1F}"

    private static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: Reglas de Mail

    /// Rehace las reglas «Barrendero…» de Mail con las reglas actuales.
    static func syncMailRules(_ rules: SweepRules) async throws {
        var lines = [
            "tell application \"Mail\"",
            "if not (exists mailbox \(quote(holdingMailbox))) then make new mailbox with properties {name:\(quote(holdingMailbox))}",
            "repeat with i from (count of rules) to 1 by -1",
            "if name of rule i starts with \(quote(rulePrefix)) then delete rule i",
            "end repeat",
        ]
        func addRule(name: String, all: Bool, conditions: [(String, String)]) {
            lines.append("set r to make new rule with properties {name:\(quote(name)), enabled:true}")
            lines.append("set all conditions must be met of r to \(all)")
            lines.append("tell r")
            for (type, value) in conditions {
                lines.append("make new rule condition at end of rule conditions with properties {rule type:\(type), qualifier:does contain value, expression:\(quote(value))}")
            }
            lines.append("end tell")
            lines.append("set should move message of r to true")
            lines.append("set move message of r to mailbox \(quote(holdingMailbox))")
        }
        if !rules.senders.isEmpty {
            addRule(name: "\(rulePrefix): publicidad y boletines", all: false, conditions: rules.senders.map { ("from header", $0) })
        }
        for (index, rule) in rules.subjectRules.enumerated() {
            addRule(name: "\(rulePrefix): aviso \(index + 1) (\(rule.sender))", all: true,
                    conditions: [("from header", rule.sender), ("subject header", rule.subject)])
        }
        lines.append("end tell")
        lines.append("return \"ok\"")
        _ = try await run(lines.joined(separator: "\n"))
    }

    // MARK: Revisar

    /// Lo apartado en «Barridos» y el correo no deseado de cada cuenta.
    static func scan(rules: SweepRules, progress: @escaping @Sendable (String) -> Void) async throws -> [Candidate] {
        progress("Leyendo «\(holdingMailbox)» y el correo no deseado…")
        let script = """
        on run argv
            set RS to character id 30
            set US to character id 31
            set emptyJunk to (item 1 of argv) is "1"
            set ref0 to current date
            set day of ref0 to 1
            set year of ref0 to 2000
            set month of ref0 to 1
            set time of ref0 to 0
            set out to {}
            tell application "Mail"
                set boxes to {}
                if exists mailbox \(quote(holdingMailbox)) then set end of boxes to {"", \(quote(holdingMailbox)), mailbox \(quote(holdingMailbox)), "0"}
                if emptyJunk then
                    repeat with a in accounts
                        if enabled of a then
                            repeat with mb in mailboxes of a
                                if name of mb is in {"Correo no deseado", "Junk", "Spam", "Correo basura", "Junk Email"} then
                                    set end of boxes to {name of a, name of mb, mb, "1"}
                                end if
                            end repeat
                        end if
                    end repeat
                end if
                repeat with b in boxes
                    set mb to item 3 of b
                    if (count of messages of mb) > 0 then
                        with timeout of 600 seconds
                            set ids to message id of messages of mb
                            set snds to sender of messages of mb
                            set subs to subject of messages of mb
                            set ds to date received of messages of mb
                        end timeout
                        repeat with i from 1 to count of ids
                            set s to item i of subs
                            if s is missing value then set s to ""
                            set f to item i of snds
                            if f is missing value then set f to ""
                            set delta to (item i of ds) - ref0
                            set dd to (delta div 86400) as integer
                            set ss to (delta - dd * 86400) as integer
                            set end of out to (item 1 of b) & US & (item 2 of b) & US & (item 4 of b) & US & (i as text) & US & (item i of ids) & US & f & US & s & US & (dd as text) & US & (ss as text)
                        end repeat
                    end if
                end repeat
            end tell
            set AppleScript's text item delimiters to RS
            return out as text
        end run
        """
        let output = try await run(script, arguments: [rules.emptyJunk ? "1" : "0"])
        guard !output.isEmpty else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let reference = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        return output.components(separatedBy: recordSeparator).compactMap { record in
            let f = record.components(separatedBy: fieldSeparator)
            guard f.count == 9, let index = Int(f[3]), let days = Int(f[7]), let seconds = Int(f[8]) else { return nil }
            let date = calendar.date(byAdding: .day, value: days, to: reference)!.addingTimeInterval(TimeInterval(seconds))
            let junk = f[2] == "1"
            let sender = f[5], subject = f[6]
            let exception = rules.neverSweep.contains { sender.lowercased().contains($0.lowercased()) }
            let reason = junk ? "Correo no deseado (\(f[0]))" : (rules.reason(sender: sender, subject: subject) ?? AppDelegate.address(of: sender))
            return Candidate(account: f[0], mailbox: f[1], isJunk: junk, index: index, messageID: f[4], sender: sender,
                             subject: subject, received: date, reason: exception ? "No barrer: \(AppDelegate.address(of: sender))" : reason,
                             isException: exception)
        }
    }

    // MARK: Barrer y devolver

    /// Mueve a la papelera (`trash`) o devuelve a la bandeja de entrada de su cuenta.
    /// Se recorren de mayor a menor posición confirmando el message id de cada uno.
    static func process(_ items: [Candidate], trash: Bool, progress: @escaping @Sendable (String) -> Void) async throws -> Int {
        var done = 0
        let groups = Dictionary(grouping: items) { "\($0.account)\u{1F}\($0.mailbox)" }
        for (key, group) in groups {
            let parts = key.components(separatedBy: fieldSeparator)
            let sorted = group.sorted { $0.index > $1.index }
            for start in stride(from: 0, to: sorted.count, by: 80) {
                let batch = sorted[start..<min(start + 80, sorted.count)]
                progress(trash ? "Moviendo a la papelera: \(done + batch.count) de \(items.count)…"
                               : "Devolviendo a la bandeja: \(done + batch.count) de \(items.count)…")
                var arguments = [parts[0], parts[1], trash ? "1" : "0"]
                for item in batch { arguments += [String(item.index), item.messageID] }
                let script = """
                on inboxOf(a)
                    tell application "Mail"
                        repeat with n in {"Bandeja de entrada", "INBOX", "Inbox"}
                            if exists mailbox (n as text) of a then return mailbox (n as text) of a
                        end repeat
                    end tell
                    return missing value
                end inboxOf

                on run argv
                    set accName to item 1 of argv
                    set boxName to item 2 of argv
                    set toTrash to (item 3 of argv) is "1"
                    set done to 0
                    tell application "Mail"
                        if accName is "" then
                            set mb to mailbox boxName
                        else
                            set mb to mailbox boxName of account accName
                        end if
                        repeat with i from 4 to (count of argv) by 2
                            set k to (item i of argv) as integer
                            set mid to item (i + 1) of argv
                            set n to count of messages of mb
                            repeat with d in {0, 1, 2, 3, -1, 4, 5, 6, 8, 10}
                                set j to k + d
                                if j ≥ 1 and j ≤ n then
                                    try
                                        set m to message j of mb
                                        if message id of m is mid then
                                            if toTrash then
                                                delete m
                                            else
                                                -- A la bandeja de la cuenta: la del buzón, o la del destinatario.
                                                set target to missing value
                                                if accName is not "" then
                                                    set target to my inboxOf(account accName)
                                                else
                                                    set rcpts to address of to recipients of m
                                                    repeat with a in accounts
                                                        repeat with addr in (email addresses of a)
                                                            if rcpts contains (addr as text) then set target to my inboxOf(a)
                                                        end repeat
                                                        if target is not missing value then exit repeat
                                                    end repeat
                                                    if target is missing value then set target to my inboxOf(item 1 of accounts)
                                                end if
                                                move m to target
                                            end if
                                            set done to done + 1
                                            exit repeat
                                        end if
                                    end try
                                end if
                            end repeat
                        end repeat
                    end tell
                    return done as text
                end run
                """
                done += Int(try await run(script, arguments: arguments)) ?? 0
            }
        }
        return done
    }

    /// Remitente del correo seleccionado en Mail (para agregarlo a las reglas).
    static func selectedSender() async throws -> String? {
        let script = """
        tell application "Mail"
            set sel to selection
            if sel is {} then return ""
            return sender of item 1 of sel
        end tell
        """
        let sender = try await run(script)
        return sender.isEmpty ? nil : sender
    }

    private static func run(_ source: String, arguments: [String] = []) async throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("barrendero-\(UUID().uuidString).applescript")
        try source.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let result: (Int32, String, String) = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [file.path] + arguments
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            let outBox = Buffer(), errBox = Buffer()
            out.fileHandleForReading.readabilityHandler = { outBox.append($0.availableData) }
            err.fileHandleForReading.readabilityHandler = { errBox.append($0.availableData) }
            process.terminationHandler = { process in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                outBox.append(out.fileHandleForReading.readDataToEndOfFile())
                errBox.append(err.fileHandleForReading.readDataToEndOfFile())
                continuation.resume(returning: (process.terminationStatus, outBox.string, errBox.string))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        if result.0 != 0 { throw Failure.script(result.2.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return result.1.trimmingCharacters(in: .newlines)
    }
}

private final class Buffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
