import SwiftUI

struct DetailView: View {
    @ObservedObject var scanner: Scanner
    let network: WiFiNetwork?

    var body: some View {
        if let n = network {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(n)
                    let warnings = scanner.warnings(for: n)
                    if !warnings.isEmpty {
                        box("Avisos") {
                            ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                                Label(w.text, systemImage: w.level >= 2 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(w.level >= 2 ? .red : .orange)
                                    .font(.callout)
                            }
                        }
                    }
                    box("Señal") {
                        row("Intensidad", "\(n.rssi) dBm")
                        row("Ruido", n.noise != 0 ? n.noiseLabel : "Sin medir")
                        row("Señal/ruido (SNR)", n.snrLabel)
                        row("Calidad", "\(n.quality) %")
                    }
                    box("Canal") {
                        row("Canal", "\(n.channel)")
                        row("Banda", n.band.title)
                        row("Ancho", n.widthLabel)
                        row("Canal central", n.centerChannel == n.centerChannel.rounded() ? "\(Int(n.centerChannel))" : String(format: "%.1f", n.centerChannel))
                        row("Frecuencia central", "\(n.centerFrequency) MHz")
                        if n.utilization >= 0 { row("Ocupación del canal", "\(n.utilization) %") }
                        if n.stations >= 0 { row("Clientes conectados", "\(n.stations)") }
                    }
                    box("Red") {
                        row("Seguridad", n.security)
                        row("Generación", n.generationName)
                        row("Modos", n.phyModes)
                        row("Velocidad máxima", n.maxRateLabel)
                        row("Flujos espaciales", "\(n.streams)")
                        if !n.basicRates.isEmpty { row("Velocidades básicas", n.basicRates + " Mbps") }
                        if n.minRate > 0 { row("Velocidad mínima", InfoElements.rate(n.minRate) + " Mbps") }
                        row("Intervalo de baliza", "\(n.beaconInterval) TU")
                        row("Roaming rápido (802.11r)", n.fastTransition ? "Sí" : "No")
                        row("WPS", n.wps ? "Sí" : "No")
                        if !n.htProtection.isEmpty { row("Protección HT", n.htProtection) }
                        if !n.country.isEmpty { row("País", n.country) }
                        if !n.deviceName.isEmpty { row("Dispositivo", n.deviceName) }
                        if n.adHoc { row("Tipo", "Ad hoc") }
                        row("Visto por primera vez", n.firstSeen.formatted(date: .omitted, time: .standard))
                        row("Visto por última vez", n.lastSeen.formatted(date: .omitted, time: .standard))
                    }
                    box("Nota") {
                        TextField("Escribe una nota para esta red", text: Binding(
                            get: { scanner.notes[n.id] ?? "" },
                            set: { scanner.notes[n.id] = $0.isEmpty ? nil : $0 }), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                    }
                    if !n.elements.isEmpty {
                        box("Elementos de información (\(n.elements.count))") {
                            ForEach(n.elements) { e in
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text(e.name).font(.callout)
                                        Spacer()
                                        Text(e.ext.map { "255/\($0)" } ?? "\(e.number)")
                                            .font(.caption.monospaced()).foregroundStyle(.tertiary)
                                    }
                                    if !e.summary.isEmpty {
                                        Text(e.summary).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(.background)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "wifi").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text("Elige una red para ver sus detalles").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
    }

    private func header(_ n: WiFiNetwork) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8).fill(networkColor(n.id).gradient)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "wifi").foregroundStyle(.white).font(.title3.bold()))
            VStack(alignment: .leading, spacing: 2) {
                Text(n.displayName).font(.title3.bold()).textSelection(.enabled)
                Text(n.bssid).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                if !n.vendor.isEmpty { Text(n.vendor).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    private func box<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
            VStack(alignment: .leading, spacing: 5) { content() }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(v).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
    }
}
