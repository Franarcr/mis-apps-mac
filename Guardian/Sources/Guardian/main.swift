import AppKit
import SwiftUI

// Modos de prueba (solo leen, no cambian nada):
//   Guardian --programas     lista los programas que conviene revisar
//   Guardian --conexiones    resume quién entró por AnyDesk
let args = CommandLine.arguments
if args.count >= 2, args[1] == "--programas" {
    let start = Date()
    let programs = ProgramScanner.scan()
    print("\(programs.count) programas revisados en \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
    let counts = Dictionary(grouping: programs, by: \.verdict).sorted { $0.key < $1.key }
    for (verdict, list) in counts { print("  \(verdict.title): \(list.count)") }
    print("\nPara revisar:")
    for program in programs where program.needsAttention {
        let caps = program.capabilities.map(\.rawValue).sorted().joined(separator: ", ")
        print("  \(program.name) \(program.version) · \(program.verdict.title) · \(program.developer) · [\(caps)]")
    }
    print("\nArrancan solos:")
    for program in programs where program.capabilities.contains(.autostart) {
        print("  \(program.name): \(program.launchItems.map(\.label).joined(separator: ", "))")
    }
    for access in ProgramScanner.systemAccess() { print("\(access.name): \(access.enabled ? "encendido" : "apagado")") }
    exit(0)
}
if args.count >= 2, args[1] == "--conexiones" {
    let connections = AnyDeskWatch.connections().filter(\.incoming)
    let found = AnyDeskWatch.addresses()
    print("Este Mac: \(AnyDeskWatch.ownID() ?? "?") · dirección \(found.own ?? "?") · desatendido: \(AnyDeskWatch.unattendedEnabled() ? "sí" : "no")")
    for (id, list) in Dictionary(grouping: connections, by: \.remoteID) {
        let same = found.byID[id] != nil && found.byID[id] == found.own
        print("  \(id): \(list.count) veces, última \(list.map(\.date).max()!) · \(Set(list.map(\.methodText)).sorted().joined(separator: ", ")) · \(found.byID[id] ?? "?")\(same ? " (misma red)" : "")")
    }
    let sessions = AnyDeskWatch.activeSessions(lastIncoming: connections.last?.remoteID)
    print(sessions.isEmpty ? "Nadie conectado ahora." : "Conectado ahora: \(sessions.map { "\($0.remoteID ?? "?") desde \($0.since)" })")
    exit(0)
}

// Prueba visual: dibuja las dos ventanas en PNG sin mostrarlas.
//   Guardian --captura /carpeta
if args.count >= 3, args[1] == "--captura" {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let state = GuardState()
        state.refreshAnyDesk()
        state.programs = ProgramScanner.scan()
        state.systemAccess = ProgramScanner.systemAccess()
        state.lastScan = Date()
        func save<V: View>(_ view: V, _ name: String, _ size: NSSize) {
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[2]).appendingPathComponent(name))
        }
        save(ConnectionsView(state: state, cut: {}), "conexiones.png", NSSize(width: 760, height: 720))
        save(ProgramsView(state: state), "programas.png", NSSize(width: 820, height: 640))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
