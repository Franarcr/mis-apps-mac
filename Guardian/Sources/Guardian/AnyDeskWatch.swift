import Foundation

/// Una línea del registro de conexiones de AnyDesk (~/.anydesk/connection_trace.txt).
struct Connection: Identifiable, Equatable {
    let incoming: Bool
    let date: Date
    /// User, Passwd o Token.
    let method: String
    let remoteID: String
    let line: Int
    var id: Int { line }

    var methodText: String {
        switch method {
        case "User": "Aceptada en pantalla"
        case "Passwd": "Con la contraseña"
        case "Token": "Con un acceso guardado"
        default: method
        }
    }

    var methodExplanation: String {
        switch method {
        case "User": "Alguien frente a este Mac pulsó «Aceptar» en la ventana de AnyDesk."
        case "Passwd": "Entró sin que nadie aceptara, escribiendo la contraseña del acceso desatendido."
        case "Token": "Entró sin que nadie aceptara y sin escribir contraseña: ese equipo marcó «Recordar» la última vez que entró con la contraseña."
        default: ""
        }
    }
}

/// Una sesión de AnyDesk abierta ahora mismo (un proceso «AnyDesk --backend»).
struct ActiveSession: Equatable {
    let pid: Int32
    let since: Date
    /// El equipo que entró (el último que aparece en el registro).
    let remoteID: String?
}

/// Lee lo que AnyDesk deja en ~/.anydesk. Solo lee; nunca cambia su configuración.
enum AnyDeskWatch {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".anydesk")
    static var traceFile: URL { folder.appendingPathComponent("connection_trace.txt") }
    static var logFile: URL { folder.appendingPathComponent("anydesk.trace") }

    static var installed: Bool {
        FileManager.default.fileExists(atPath: folder.path) || FileManager.default.fileExists(atPath: "/Applications/AnyDesk.app")
    }

    static func connections() -> [Connection] {
        guard let text = try? String(contentsOf: traceFile, encoding: .utf8) else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd, HH:mm"
        var result: [Connection] = []
        for (index, raw) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            // «Incoming    2026-10-28, 09:11    Token    1525995368    1525995368»
            let parts = raw.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 5, let date = formatter.date(from: parts[1] + " " + parts[2]) else { continue }
            result.append(Connection(incoming: parts[0] == "Incoming", date: date, method: parts[3], remoteID: parts[4], line: index))
        }
        return result
    }

    /// Sesiones abiertas ahora. AnyDesk abre un proceso «--backend» por cada conexión.
    static func activeSessions(lastIncoming: String?) -> [ActiveSession] {
        let output = Shell.run("/bin/ps", ["-axo", "pid=,lstart=,command="])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        var sessions: [ActiveSession] = []
        for line in output.split(separator: "\n") where line.contains("AnyDesk.app/Contents/MacOS/AnyDesk --backend") {
            // «33754 Tue Nov 10 16:15:40 2026     /Applications/AnyDesk.app/…»
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 6, let pid = Int32(parts[0]) else { continue }
            let since = formatter.date(from: parts[1...5].joined(separator: " ")) ?? Date()
            sessions.append(ActiveSession(pid: pid, since: since, remoteID: lastIncoming))
        }
        return sessions
    }

    /// Todos los procesos de AnyDesk de esta sesión de usuario.
    static func processIDs() -> [Int32] {
        Shell.run("/bin/ps", ["-xo", "pid=,command="]).split(separator: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.contains("AnyDesk.app/Contents/MacOS/AnyDesk") else { return nil }
            return Int32(text.split(separator: " ").first ?? "")
        }
    }

    /// Corta todas las conexiones cerrando AnyDesk. Devuelve cuántos procesos se cerraron.
    @discardableResult
    static func cutAll() -> Int {
        let pids = processIDs()
        for pid in pids { kill(pid, SIGTERM) }
        // Si alguno no se cerró en dos segundos, se fuerza.
        Thread.sleep(forTimeInterval: 2)
        for pid in processIDs() { kill(pid, SIGKILL) }
        return pids.count
    }

    /// El acceso desatendido (entrar sin que nadie acepte) está encendido.
    static func unattendedEnabled() -> Bool {
        let text = ["system.conf", "service.conf", "user.conf"].compactMap {
            try? String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")
        let profile = text.contains("ad.security.permission_profiles._unattended_access.enabled=1")
        let password = text.split(separator: "\n").contains { $0.hasPrefix("ad.anynet.pwd_hash=") && $0.count > "ad.anynet.pwd_hash=".count }
        return profile || password
    }

    static func ownID() -> String? {
        guard let text = try? String(contentsOf: folder.appendingPathComponent("system.conf"), encoding: .utf8) else { return nil }
        return text.split(separator: "\n").first { $0.hasPrefix("ad.anynet.id=") }.map { String($0.dropFirst("ad.anynet.id=".count)) }
    }

    /// Desde qué dirección de internet entró cada equipo, y la de este Mac, según el registro técnico.
    static func addresses() -> (byID: [String: String], own: String?) {
        // El registro técnico puede pasar de 1 MB: se leen solo sus últimos 4 MB.
        guard let handle = try? FileHandle(forReadingFrom: logFile) else { return ([:], nil) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 4_000_000 ? size - 4_000_000 : 0)
        let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        var byID: [String: String] = [:]
        var own: String?
        var current: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if let range = line.range(of: "Client-ID: ") {
                current = line[range.upperBound...].split(separator: " ").first.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            } else if let range = line.range(of: "Logged in from "), let id = current {
                byID[id] = line[range.upperBound...].split(separator: ":").first.map(String.init)
            } else if let range = line.range(of: "External address: ") {
                own = line[range.upperBound...].split(separator: ":").first.map(String.init)
            }
        }
        return (byID, own)
    }

    /// Fecha de cambio del registro, para saber si hay conexiones nuevas sin releerlo entero.
    static func traceStamp() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: traceFile.path))?[.modificationDate] as? Date
    }
}

/// Equipos que la usuaria marcó como suyos o de confianza, con un nombre para reconocerlos.
enum TrustedDevices {
    private static let key = "trustedDevices"

    static var all: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func name(_ id: String) -> String? { all[id] }
    static func isTrusted(_ id: String) -> Bool { all[id] != nil }

    static func trust(_ id: String, name: String) {
        var devices = all
        devices[id] = name.isEmpty ? "Equipo de confianza" : name
        all = devices
    }

    static func forget(_ id: String) {
        var devices = all
        devices[id] = nil
        all = devices
    }

    /// «Mi MacBook (1525995368)» o «equipo desconocido 1525995368».
    static func label(_ id: String) -> String {
        if let name = all[id] { return "\(name) (\(id))" }
        return "equipo desconocido \(id)"
    }
}
