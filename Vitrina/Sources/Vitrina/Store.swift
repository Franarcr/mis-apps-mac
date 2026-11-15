import AppKit
import CryptoKit
import Foundation

/// Lo que build.sh anota de cada app que mete dentro de Vitrina.
struct Packed: Decodable {
    let name: String
    let version: String
    let hash: String      // SHA-256 del ejecutable
    let built: Double     // fecha del ejecutable (segundos desde 1970)
    let minOS: String
}

enum Status: Equatable {
    case notInstalled, installed, update, needsNewerOS(String)

    var label: String {
        switch self {
        case .notInstalled: "Sin instalar"
        case .installed: "Instalada"
        case .update: "Versión nueva"
        case .needsNewerOS(let v): "Necesita macOS \(v)"
        }
    }
}

struct Row: Identifiable {
    let info: AppInfo
    let packed: Packed
    var status: Status
    var id: String { info.id }
    var zip: URL { Store.appsFolder.appendingPathComponent("\(info.name).zip") }
    var icon: NSImage {
        NSImage(contentsOf: Store.appsFolder.appendingPathComponent("\(info.name).png"))
            ?? NSWorkspace.shared.icon(for: .application)
    }
}

struct InstallResult: Identifiable {
    let info: AppInfo
    let error: String?
    var id: String { info.id }
}

@MainActor
final class Store: ObservableObject {
    nonisolated static let appsFolder = Bundle.main.resourceURL!.appendingPathComponent("Apps")

    @Published var rows: [Row] = []
    @Published var selected: Set<String> = []
    @Published var installing: String? = nil
    @Published var results: [InstallResult]? = nil

    init() { reload() }

    func reload() {
        let manifest = Self.appsFolder.appendingPathComponent("manifest.json")
        let packed = (try? Data(contentsOf: manifest)).flatMap { try? JSONDecoder().decode([Packed].self, from: $0) } ?? []
        rows = Catalog.apps.compactMap { info in
            guard let p = packed.first(where: { $0.name == info.name }) else { return nil }
            return Row(info: info, packed: p, status: Self.status(of: info, packed: p))
        }
        // De entrada quedan marcadas las que faltan o tienen versión nueva.
        if selected.isEmpty {
            selected = Set(rows.filter { $0.status == .notInstalled || $0.status == .update }.map(\.id))
        }
        selected = selected.filter { id in rows.contains { $0.id == id && $0.canInstall } }
    }

    static func installedURL(_ info: AppInfo) -> URL? {
        let standard = URL(fileURLWithPath: "/Applications/\(info.name).app")
        if FileManager.default.fileExists(atPath: standard.path) { return standard }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: info.bundleID)
    }

    private static func status(of info: AppInfo, packed: Packed) -> Status {
        let parts = packed.minOS.split(separator: ".").compactMap { Int($0) }
        let needed = OperatingSystemVersion(majorVersion: parts.first ?? 14, minorVersion: parts.count > 1 ? parts[1] : 0, patchVersion: 0)
        if !ProcessInfo.processInfo.isOperatingSystemAtLeast(needed) { return .needsNewerOS(packed.minOS) }

        guard let url = installedURL(info), let exe = Bundle(url: url)?.executableURL,
              let data = try? Data(contentsOf: exe) else { return .notInstalled }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if hash == packed.hash { return .installed }
        // Si la instalada es más reciente (por ejemplo, recién compilada en este Mac), no se ofrece la de Vitrina.
        let date = (try? FileManager.default.attributesOfItem(atPath: exe.path)[.modificationDate] as? Date) ?? .distantPast
        return packed.built > date.timeIntervalSince1970 + 1 ? .update : .installed
    }

    // MARK: Instalar

    func installSelected() {
        let chosen = rows.filter { selected.contains($0.id) && $0.canInstall }
        guard !chosen.isEmpty else { return }
        Task {
            var done: [InstallResult] = []
            for row in chosen {
                installing = row.info.name
                let error = await Self.install(row)
                done.append(InstallResult(info: row.info, error: error))
            }
            installing = nil
            selected = []
            reload()
            results = done
        }
    }

    /// Devuelve nil si salió bien, o el motivo del fallo.
    private static func install(_ row: Row) async -> String? {
        let info = row.info
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: info.bundleID)
        let wasRunning = !running.isEmpty
        for app in running { app.terminate() }
        for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        for app in running where !app.isTerminated { app.forceTerminate() }

        let target = URL(fileURLWithPath: "/Applications/\(info.name).app")
        let error: String? = await Task.detached {
            let fm = FileManager.default
            let temp = fm.temporaryDirectory.appendingPathComponent("Vitrina-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: temp) }
            do {
                try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                try run("/usr/bin/ditto", ["-x", "-k", row.zip.path, temp.path])
                let unpacked = temp.appendingPathComponent("\(info.name).app")
                guard fm.fileExists(atPath: unpacked.path) else { return "El paquete está dañado." }
                // Las copia Vitrina misma: así macOS no vuelve a pedir «Abrir igualmente» en cada una.
                try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", unpacked.path])
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try run("/usr/bin/ditto", [unpacked.path, target.path])
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        guard error == nil else { return error }

        // Las de la barra de menú se abren para que aparezca su icono; las demás, solo si estaban abiertas.
        if info.kind == .menuBar || wasRunning {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: target, configuration: config)
        }
        return nil
    }

    func open(_ row: Row) {
        guard let url = Self.installedURL(row.info) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    func reveal(_ row: Row) {
        guard let url = Self.installedURL(row.info) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension Row {
    var canInstall: Bool {
        if case .needsNewerOS = status { return false }
        return true
    }
}

private struct CommandError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func run(_ tool: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let err = Pipe()
    p.standardError = err
    p.standardOutput = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw CommandError(message: text.isEmpty ? "No se pudo copiar." : text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
