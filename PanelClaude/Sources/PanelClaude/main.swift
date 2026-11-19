import Foundation

// Modo sin ventana para el artefacto:  PanelClaude --json <archivo>
// Escribe la foto completa en JSON y termina.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--json") {
    let snap = Scanner().scan()
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try! enc.encode(snap)
    if i + 1 < args.count {
        try! data.write(to: URL(fileURLWithPath: args[i + 1]))
    } else {
        FileHandle.standardOutput.write(data)
    }
    exit(0)
}

PanelClaudeApp.main()
