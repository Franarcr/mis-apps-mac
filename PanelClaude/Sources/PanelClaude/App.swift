import SwiftUI

struct PanelClaudeApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("Panel Claude", id: "main") {
            MainView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Actualizar") { store.refresh() }.keyboardShortcut("r")
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            if let u = store.weekUsage {
                Label("\(u) %", systemImage: "gauge.with.dots.needle.67percent")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "gauge.with.dots.needle.67percent")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Barra de menú

struct MenuBarView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = store.snap
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude en este Mac").font(.headline)
            if let u = s.usage.last {
                UsageBar(title: "Límite de 5 horas", value: u.fiveHour)
                UsageBar(title: "Límite semanal", value: u.sevenDay)
                Text("Dato del \(Fmt.date(u.date))").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            row("Chats", "\(s.chats.count) · \(Fmt.bytes(s.totalChatBytes))")
            row("Pesados", "\(s.chats.filter(\.isHeavy).count)")
            row("Conectores", "\(s.connectors.count)")
            row("Plugins", "\(s.plugins.count)")
            row("Habilidades", "\(s.skills.count)")
            row("Espacio total", Fmt.bytes(s.totalDiskBytes))
            if !s.warnings.isEmpty {
                Divider()
                ForEach(s.warnings.filter { $0.level != .info }.prefix(3)) { w in
                    Label(w.text, systemImage: w.level == .alert ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(w.level == .alert ? .red : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            HStack {
                Button("Abrir panel") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(.defaultAction)
                Button(store.loading ? "Leyendo…" : "Actualizar") { store.refresh() }
                    .disabled(store.loading)
                Spacer()
                Button("Salir") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    func row(_ a: String, _ b: String) -> some View {
        HStack { Text(a).foregroundStyle(.secondary); Spacer(); Text(b).monospacedDigit() }
    }
}

struct UsageBar: View {
    let title: String
    let value: Int
    var color: Color { value >= 80 ? .red : value >= 50 ? .orange : .green }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title); Spacer(); Text("\(value) %").monospacedDigit().bold() }
                .font(.callout)
            ProgressView(value: Double(min(value, 100)), total: 100).tint(color)
        }
    }
}
