import AppKit

// Modo de prueba: muestra lo apartado en «Barridos» y el correo no deseado, sin mover nada.
//   Barrendero --revisar
let args = CommandLine.arguments
if args.count >= 2, args[1] == "--revisar" {
    Task {
        do {
            let start = Date()
            let found = try await Sweeper.scan(rules: SweepRules.load()) { _ in }
            print("\(found.count) correos para barrer (\(Int(Date().timeIntervalSince(start))) s)")
            let groups = Dictionary(grouping: found, by: \.reason).sorted { $0.value.count > $1.value.count }
            for (reason, items) in groups.prefix(25) {
                print("  \(items.count) · \(reason) · p. ej. «\(items[0].subject.prefix(60))»")
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
        exit(0)
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
