import AppKit
import Security

/// Qué tan confiable es la firma de un programa, de mejor a peor.
enum Verdict: Int, Comparable {
    case apple, appStore, notarized, own, identified, adHoc, broken, unsigned

    static func < (a: Verdict, b: Verdict) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .apple: "De Apple"
        case .appStore: "De la App Store"
        case .notarized: "Desarrollador verificado"
        case .own: "Hecha por ti"
        case .identified: "Sin revisión de Apple"
        case .adHoc: "Sin firma de desarrollador"
        case .broken: "Firma rota"
        case .unsigned: "Sin firma"
        }
    }

    var explanation: String {
        switch self {
        case .apple: "Viene con macOS o es de Apple."
        case .appStore: "Descargada de la App Store: Apple la revisó antes de publicarla."
        case .notarized: "El desarrollador está identificado y Apple revisó esta versión en busca de software malicioso."
        case .own: "Una de tus propias apps, firmada en este Mac con tu firma local."
        case .identified: "El desarrollador está identificado, pero Apple no revisó esta versión. Suele pasar con programas viejos."
        case .adHoc: "No dice quién la hizo. Puede ser normal en herramientas caseras, pero conviene saber de dónde salió."
        case .broken: "El programa fue modificado después de firmarse. Puede estar dañado o alterado: no lo abras hasta revisarlo."
        case .unsigned: "No tiene ninguna firma: no se sabe quién la hizo ni si fue alterada."
        }
    }

    /// Verde, azul, ámbar o rojo.
    var color: NSColor {
        switch self {
        case .apple, .appStore, .notarized: .systemGreen
        case .own: .systemBlue
        case .identified, .adHoc: .systemOrange
        case .broken, .unsigned: .systemRed
        }
    }

    var needsReview: Bool { self >= .identified && self != .own }
}

/// Un permiso declarado por el programa (lo que puede pedir, no si ya se lo diste).
enum Capability: String, CaseIterable {
    case camera = "Cámara"
    case microphone = "Micrófono"
    case automation = "Controlar otras apps"
    case remote = "Acceso remoto"
    case autostart = "Arranca solo"

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .microphone: "mic"
        case .automation: "gearshape.2"
        case .remote: "desktopcomputer.and.arrow.down"
        case .autostart: "power"
        }
    }

    var explanation: String {
        switch self {
        case .camera: "Puede pedir permiso para usar la cámara."
        case .microphone: "Puede pedir permiso para usar el micrófono."
        case .automation: "Puede pedir permiso para manejar otras apps (Mail, Finder…)."
        case .remote: "Permite que otra persona vea y maneje este Mac desde lejos."
        case .autostart: "Tiene algo que se pone en marcha solo al encender o al iniciar sesión."
        }
    }
}

struct Program: Identifiable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let verdict: Verdict
    /// Quién firmó, p. ej. «AnyDesk Software GmbH».
    let developer: String
    let capabilities: Set<Capability>
    let running: Bool
    /// Elementos que arrancan solos asociados a este programa.
    let launchItems: [LaunchItem]

    var id: String { url.path }
    var needsAttention: Bool { verdict.needsReview || capabilities.contains(.remote) }
}

/// Un archivo de /Library/LaunchAgents, /Library/LaunchDaemons o ~/Library/LaunchAgents.
struct LaunchItem: Identifiable {
    let file: URL
    let label: String
    let program: String
    /// Agente (al iniciar sesión) o servicio del sistema (al encender, con permisos de administrador).
    let isDaemon: Bool
    var id: String { file.path }
    var kind: String { isDaemon ? "Servicio del sistema (al encender)" : "Al iniciar sesión" }
}

/// Un acceso de macOS que permite entrar a este Mac desde otro equipo.
struct SystemAccess: Identifiable {
    let name: String
    let enabled: Bool
    let explanation: String
    let settingsURL: String
    var id: String { name }
}

enum ProgramScanner {
    /// Pistas en el identificador para reconocer programas de acceso remoto.
    static let remoteMarkers = [
        "anydesk", "teamviewer", "rustdesk", "chromeremotedesktop", "splashtop", "logmein", "realvnc",
        "screenconnect", "connectwise", "supremo", "nomachine", "parsec", "jumpdesktop", "remotix",
        "dwservice", "zoho.assist", "getscreen", "bomgar", "beyondtrust", "gotoassist", "ultraviewer",
        "ammyy", "aeroadmin", "remotepc", "islonline", "showmypc", "airdroid",
    ]

    /// Nombres de las firmas locales de ../crear-firma.sh.
    static let ownIdentities = ["Fran Firma Local", "MacCleaner Local"]

    static func isRemoteTool(bundleID: String, name: String) -> Bool {
        let text = (bundleID + " " + name).lowercased().replacingOccurrences(of: " ", with: "")
        return remoteMarkers.contains { text.contains($0) }
    }

    static func scan() -> [Program] {
        let launchItems = scanLaunchItems()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path })
        var urls: [URL] = []
        let fm = FileManager.default
        let folders = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Applications/Utilities"),
                       fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                if item.pathExtension == "app" {
                    urls.append(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          item.lastPathComponent != "Utilities",
                          let inner = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                    // Carpetas como «Adobe Acrobat DC» o «Microsoft Office» guardan sus apps dentro.
                    urls += inner.filter { $0.pathExtension == "app" }
                }
            }
        }
        var programs = urls.map { inspect($0, launchItems: launchItems, running: running) }
        programs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return programs
    }

    static func inspect(_ url: URL, launchItems: [LaunchItem], running: Set<String>) -> Program {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let bundleID = bundle?.bundleIdentifier ?? ""
        let version = (info["CFBundleShortVersionString"] as? String) ?? ""
        let signature = Signature.read(url)

        var caps = Set<Capability>()
        let ent = signature.entitlements
        if ent["com.apple.security.device.camera"] as? Bool == true || info["NSCameraUsageDescription"] != nil { caps.insert(.camera) }
        if ent["com.apple.security.device.audio-input"] as? Bool == true || ent["com.apple.security.device.microphone"] as? Bool == true
            || info["NSMicrophoneUsageDescription"] != nil { caps.insert(.microphone) }
        if ent["com.apple.security.automation.apple-events"] as? Bool == true || info["NSAppleEventsUsageDescription"] != nil { caps.insert(.automation) }
        if isRemoteTool(bundleID: bundleID, name: name) { caps.insert(.remote) }

        let appPath = url.standardizedFileURL.path
        let vendor = bundleID.split(separator: ".").prefix(2).joined(separator: ".").lowercased()
        let mine = launchItems.filter { item in
            if item.program.hasPrefix(appPath + "/") { return true }
            // p. ej. com.google.keystone.agent es de Google Chrome (com.google.Chrome).
            return vendor.count > 6 && item.label.lowercased().hasPrefix(vendor + ".") && bundleID.lowercased().hasPrefix(vendor)
                && !vendor.hasPrefix("com.apple")
        }
        if !mine.isEmpty { caps.insert(.autostart) }

        return Program(url: url, name: name, bundleID: bundleID, version: version, verdict: signature.verdict,
                       developer: signature.developer, capabilities: caps, running: running.contains(appPath), launchItems: mine)
    }

    static func scanLaunchItems() -> [LaunchItem] {
        let fm = FileManager.default
        let folders: [(String, Bool)] = [
            ("/Library/LaunchDaemons", true), ("/Library/LaunchAgents", false),
            (fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path, false),
        ]
        var items: [LaunchItem] = []
        for (folder, daemon) in folders {
            guard let files = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(file)
                guard let plist = NSDictionary(contentsOf: url) as? [String: Any] else { continue }
                let label = (plist["Label"] as? String) ?? file.replacingOccurrences(of: ".plist", with: "")
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first ?? (plist["BundleProgram"] as? String) ?? ""
                items.append(LaunchItem(file: url, label: label, program: program, isDaemon: daemon))
            }
        }
        return items.sorted { $0.label < $1.label }
    }

    /// Compartir pantalla, Gestión remota y Sesión remota (SSH) de macOS.
    static func systemAccess() -> [SystemAccess] {
        let output = Shell.run("/bin/launchctl", ["print-disabled", "system"])
        func state(_ label: String) -> Bool {
            // «"com.apple.screensharing" => enabled». Si no aparece, está apagado (lo normal).
            guard let line = output.split(separator: "\n").first(where: { $0.contains("\"\(label)\"") }) else { return false }
            return line.contains("enabled") || line.contains("false")
        }
        let sharing = "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
        return [
            SystemAccess(name: "Compartir pantalla", enabled: state("com.apple.screensharing"),
                         explanation: "Otro Mac de tu red puede ver y manejar esta pantalla con la app Compartir Pantalla, si conoce un usuario y contraseña de este Mac.",
                         settingsURL: sharing),
            SystemAccess(name: "Sesión remota (SSH)", enabled: state("com.openssh.sshd"),
                         explanation: "Permite entrar a este Mac escribiendo comandos desde otro equipo, con usuario y contraseña.",
                         settingsURL: sharing),
        ]
    }
}

/// Lo que dice la firma de un programa, leído con el marco Security (sin abrirlo ni ejecutarlo).
struct Signature {
    var verdict: Verdict = .unsigned
    var developer = ""
    var entitlements: [String: Any] = [:]

    static func read(_ url: URL) -> Signature {
        var result = Signature()
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else { return result }

        var cfInfo: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation), &cfInfo)
        let info = (cfInfo as? [String: Any]) ?? [:]
        if info[kSecCodeInfoIdentifier as String] == nil { return result }  // sin firma
        result.entitlements = (info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]) ?? [:]
        if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first,
           let summary = SecCertificateCopySubjectSummary(leaf) as String? {
            result.developer = cleanDeveloper(summary)
        }

        // Comprobar la firma sin repasar todos los recursos: es rápido incluso con apps enormes.
        let quick = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
        guard SecStaticCodeCheckValidity(code, quick, nil) == errSecSuccess else {
            result.verdict = .broken
            return result
        }
        func meets(_ text: String) -> Bool {
            var requirement: SecRequirement?
            guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
            return SecStaticCodeCheckValidity(code, quick, requirement) == errSecSuccess
        }
        if meets("anchor apple") {
            result.verdict = .apple
            result.developer = "Apple"
        } else if meets("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9]") {
            result.verdict = .appStore
        } else if meets("notarized") {
            result.verdict = .notarized
        } else if meets("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]") {
            result.verdict = .identified
        } else if ProgramScanner.ownIdentities.contains(where: { result.developer.contains($0) }) {
            result.verdict = .own
            result.developer = "Tu firma local"
        } else {
            result.verdict = .adHoc
        }
        return result
    }

    /// «Developer ID Application: AnyDesk Software GmbH (KHRWM533LU)» → «AnyDesk Software GmbH».
    static func cleanDeveloper(_ summary: String) -> String {
        var text = summary
        for prefix in ["Developer ID Application: ", "Apple Mac OS Application Signing", "Apple Development: ", "Mac Developer: "] {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        if let paren = text.range(of: " (", options: .backwards), text.hasSuffix(")") { text = String(text[..<paren.lowerBound]) }
        return text.isEmpty ? "App Store" : text
    }
}

enum Shell {
    /// Ejecuta un programa del sistema y devuelve lo que escribe.
    static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
