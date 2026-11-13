import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct AntenaApp: App {
    @StateObject private var scanner = Scanner()

    init() {
        // Modo de herramienta: convierte los CSV del IEEE en la lista de fabricantes que va dentro de la app.
        //   Antena --fabricantes salida.tsv oui.csv mam.csv oui36.csv
        let args = CommandLine.arguments
        if args.count >= 4, args[1] == "--fabricantes" {
            let csvs = args.dropFirst(3).compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            let tsv = Vendors.convert(csvs: csvs)
            try? tsv.write(toFile: args[2], atomically: true, encoding: .utf8)
            print("Fabricantes: \(tsv.split(separator: "\n").count - 1)")
            exit(0)
        }
    }

    var body: some Scene {
        Window("Antena", id: "principal") {
            ContentView(scanner: scanner)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { scanner.start() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Escaneo") {
                Button(scanner.paused ? "Reanudar" : "Pausar") { scanner.paused.toggle() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Escanear ahora") { scanner.scan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Vaciar la lista") { scanner.clear() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                Divider()
                Button("Exportar como CSV…") { exportCSV(scanner) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings { SettingsView() }
    }
}

@MainActor
func exportCSV(_ scanner: Scanner) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH.mm"
    panel.nameFieldStringValue = "Redes Wi-Fi \(f.string(from: Date())).csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    var out = "Nombre,BSSID,Fabricante,Señal (dBm),Ruido (dBm),SNR (dB),Canal,Banda,Ancho (MHz),Frecuencia central (MHz),Seguridad,Generación,Modos,Velocidad máx. (Mbps),Flujos,Clientes,Uso del canal (%),País,802.11r,WPS,Dispositivo,Nota\n"
    for n in scanner.networks.values.sorted(by: { $0.rssi > $1.rssi }) {
        out += [q(n.ssid), n.bssid, q(n.vendor), "\(n.rssi)", "\(n.noise)", "\(n.snr)", "\(n.channel)", n.band.title, "\(n.width)",
                "\(n.centerFrequency)", q(n.security), n.generationName, n.phyModes, "\(Int(n.maxRate.rounded()))", "\(n.streams)",
                n.stations >= 0 ? "\(n.stations)" : "", n.utilization >= 0 ? "\(n.utilization)" : "", n.country,
                n.fastTransition ? "sí" : "no", n.wps ? "sí" : "no", q(n.deviceName), q(scanner.notes[n.id] ?? "")]
            .joined(separator: ",") + "\n"
    }
    try? out.write(to: url, atomically: true, encoding: .utf8)
}

struct SettingsView: View {
    @AppStorage("intervalo") private var interval: Double = 3
    @AppStorage("olvidarTras") private var forget: Double = 120
    @ObservedObject private var vendors = Vendors.shared

    var body: some View {
        Form {
            Section("Escaneo") {
                Picker("Escanear cada", selection: $interval) {
                    ForEach([2.0, 3, 5, 10, 30], id: \.self) { Text("\(Int($0)) segundos").tag($0) }
                }
                Picker("Quitar redes que no se ven desde hace", selection: $forget) {
                    Text("30 segundos").tag(30.0)
                    Text("1 minuto").tag(60.0)
                    Text("2 minutos").tag(120.0)
                    Text("5 minutos").tag(300.0)
                    Text("30 minutos").tag(1800.0)
                    Text("1 hora").tag(3600.0)
                }
            }
            Section("Fabricantes") {
                LabeledContent("Registro del IEEE", value: "\(vendors.count.formatted()) fabricantes")
                LabeledContent("Fecha", value: vendors.date.isEmpty ? "—" : vendors.date)
                HStack {
                    Button("Actualizar desde el IEEE") { vendors.update() }.disabled(vendors.updating)
                    if vendors.updating { ProgressView().controlSize(.small) }
                }
                if !vendors.updateMessage.isEmpty {
                    Text(vendors.updateMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
    }
}
