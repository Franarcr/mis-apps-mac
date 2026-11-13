import SwiftUI

enum SecurityFilter: String, CaseIterable, Identifiable {
    case all, open, secured
    var id: String { rawValue }
    var title: String { self == .all ? "Todas" : self == .open ? "Abiertas" : "Protegidas" }
    func matches(_ n: WiFiNetwork) -> Bool {
        switch self {
        case .all: return true
        case .open: return n.security.hasPrefix("Abierta")
        case .secured: return !n.security.hasPrefix("Abierta")
        }
    }
}

enum BandFilter: String, CaseIterable, Identifiable {
    case all, b24, b5, b6
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Todas"
        case .b24: return "2,4 GHz"
        case .b5: return "5 GHz"
        case .b6: return "6 GHz"
        }
    }
    func matches(_ b: Band) -> Bool {
        switch self {
        case .all: return true
        case .b24: return b == .b24
        case .b5: return b == .b5
        case .b6: return b == .b6
        }
    }
}

/// Color fijo para cada red (el mismo en la tabla y en los gráficos).
func networkColor(_ id: String) -> Color {
    var h: UInt64 = 5381
    for u in id.utf8 { h = (h &* 33) &+ UInt64(u) }
    return Color(hue: Double(h % 360) / 360, saturation: 0.62, brightness: 0.88)
}

struct ContentView: View {
    @ObservedObject var scanner: Scanner
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\WiFiNetwork.rssi, order: .reverse)]
    @State private var search = ""
    @AppStorage("filtroBanda") private var bandFilter: BandFilter = .all
    @AppStorage("mostrarDetalles") private var showDetail = true
    @AppStorage("mostrarGraficos") private var showCharts = true
    @AppStorage("mostrarBarraLateral") private var showSidebar = true
    @AppStorage("filtroSeguridad") private var securityFilter: SecurityFilter = .all
    @State private var group: GroupFilter?
    @State private var columns: TableColumnCustomization<WiFiNetwork> = {
        if let data = UserDefaults.standard.data(forKey: "columnas"),
           let c = try? JSONDecoder().decode(TableColumnCustomization<WiFiNetwork>.self, from: data) { return c }
        return TableColumnCustomization<WiFiNetwork>()
    }()

    private var filtered: [WiFiNetwork] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return scanner.networks.values.filter { n in
            bandFilter.matches(n.band) && securityFilter.matches(n) && (group?.matches(n) ?? true) && (q.isEmpty
                || n.ssid.lowercased().contains(q) || n.bssid.lowercased().contains(q)
                || n.vendor.lowercased().contains(q) || n.security.lowercased().contains(q)
                || (scanner.notes[n.id] ?? "").lowercased().contains(q))
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        let rows = filtered
        VStack(spacing: 0) {
            if !scanner.locationAllowed { LocationBanner(scanner: scanner) }
            if let p = scanner.problem {
                Label(p, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(.orange.opacity(0.1))
            }
            HSplitView {
                if showSidebar {
                    SidebarView(networks: Array(scanner.networks.values), currentBSSID: scanner.currentBSSID, filter: $group)
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
                }
                VStack(spacing: 0) {
                    filterBar(shown: rows.count)
                    Divider()
                    VSplitView {
                        HSplitView {
                            table(rows).frame(minWidth: 480, minHeight: 200)
                            if showDetail {
                                DetailView(scanner: scanner, network: selected(rows))
                                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 460)
                            }
                        }
                        .frame(minHeight: 220)
                        if showCharts {
                            ChartsView(networks: rows, selection: selection)
                                .frame(minHeight: 200, idealHeight: 280)
                        }
                    }
                }
            }
            StatusLine(scanner: scanner, shown: rows.count)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Nombre, BSSID, fabricante…")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showSidebar.toggle() } label: { Label("Barra lateral", systemImage: "sidebar.left") }
                    .help("Mostrar u ocultar los grupos")
            }
            ToolbarItem(placement: .navigation) {
                Button { scanner.paused.toggle() } label: {
                    Label(scanner.paused ? "Reanudar" : "Pausar",
                          systemImage: scanner.paused ? "play.fill" : "pause.fill")
                }
                .help(scanner.paused ? "Reanudar el escaneo (⌘P)" : "Pausar el escaneo (⌘P)")
            }
            ToolbarItem(placement: .principal) {
                ConnectionStrip(connection: scanner.connection, scanning: scanner.scanning, paused: scanner.paused)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { exportCSV(scanner) } label: { Label("Exportar", systemImage: "square.and.arrow.up") }
                    .help("Exportar la lista como CSV")
                Button { showCharts.toggle() } label: { Label("Gráficos", systemImage: "chart.xyaxis.line") }
                    .help("Mostrar u ocultar los gráficos")
                Button { showDetail.toggle() } label: { Label("Detalles", systemImage: "sidebar.right") }
                    .help("Mostrar u ocultar los detalles")
            }
        }
        .onChange(of: columns) {
            if let data = try? JSONEncoder().encode(columns) { UserDefaults.standard.set(data, forKey: "columnas") }
        }
    }

    private func filterBar(shown: Int) -> some View {
        HStack(spacing: 12) {
            Picker("Banda", selection: $bandFilter) {
                ForEach(BandFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            Picker("Seguridad", selection: $securityFilter) {
                ForEach(SecurityFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)
            if let g = group {
                HStack(spacing: 4) {
                    Text("\(g.kind.title): \(g.value)").lineLimit(1)
                    Button { group = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .help("Quitar el filtro")
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            Spacer()
            Text("\(shown) de \(scanner.networks.count)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func selected(_ rows: [WiFiNetwork]) -> WiFiNetwork? {
        guard let id = selection.first else { return nil }
        return scanner.networks[id]
    }

    private func table(_ rows: [WiFiNetwork]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            columns1
            columns2
            columns3
            columns4
            columns5
            columns6
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let n = scanner.networks[id] {
                Button("Copiar BSSID") { copy(n.bssid) }
                Button("Copiar nombre") { copy(n.ssid) }
                Button("Filtrar por este nombre") { search = n.ssid }
            }
        }
    }

    @TableColumnBuilder<WiFiNetwork, KeyPathComparator<WiFiNetwork>>
    private var columns1: some TableColumnContent<WiFiNetwork, KeyPathComparator<WiFiNetwork>> {
                TableColumn("Nombre", value: \WiFiNetwork.displayName) { n in
                    NameCell(network: n, connected: !n.bssid.isEmpty && n.bssid == scanner.currentBSSID,
                             note: scanner.notes[n.id] ?? "", stale: Date().timeIntervalSince(n.lastSeen) > scanner.interval * 2.5)
                }
                .width(min: 140, ideal: 190)
                .customizationID("nombre")
                .disabledCustomizationBehavior(.visibility)

                TableColumn("Fabricante", value: \WiFiNetwork.vendor) { n in Text(n.vendor).foregroundStyle(.secondary) }
                    .width(min: 80, ideal: 150).customizationID("fabricante")
                TableColumn("BSSID", value: \WiFiNetwork.bssid) { n in Text(n.bssid).monospaced().font(.callout) }
                    .width(min: 120, ideal: 140).customizationID("bssid")
                TableColumn("Señal", value: \WiFiNetwork.rssi) { n in SignalCell(rssi: n.rssi) }
                    .width(min: 120, ideal: 140).customizationID("senal")
    }

    @TableColumnBuilder<WiFiNetwork, KeyPathComparator<WiFiNetwork>>
    private var columns2: some TableColumnContent<WiFiNetwork, KeyPathComparator<WiFiNetwork>> {
                TableColumn("Ruido", value: \WiFiNetwork.noise) { n in Text(n.noiseLabel).monospacedDigit() }
                    .width(min: 60, ideal: 70).customizationID("ruido").defaultVisibility(.hidden)
                TableColumn("SNR", value: \WiFiNetwork.snr) { n in Text(n.snrLabel).monospacedDigit() }
                    .width(min: 50, ideal: 60).customizationID("snr")
                TableColumn("Canal", value: \WiFiNetwork.channel) { n in Text(n.channelLabel).monospacedDigit() }
                    .width(min: 44, ideal: 54).customizationID("canal")
                TableColumn("Banda", value: \WiFiNetwork.band) { n in Text(n.band.title) }
                    .width(min: 56, ideal: 64).customizationID("banda")
                TableColumn("Ancho", value: \WiFiNetwork.width) { n in Text(n.widthLabel).monospacedDigit() }
                    .width(min: 60, ideal: 70).customizationID("ancho")
    }

    @TableColumnBuilder<WiFiNetwork, KeyPathComparator<WiFiNetwork>>
    private var columns3: some TableColumnContent<WiFiNetwork, KeyPathComparator<WiFiNetwork>> {
                TableColumn("Seguridad", value: \WiFiNetwork.security) { n in SecurityCell(network: n) }
                .width(min: 100, ideal: 150).customizationID("seguridad")
                TableColumn("Generación", value: \WiFiNetwork.generation) { n in Text(n.generationName) }
                    .width(min: 70, ideal: 80).customizationID("generacion")
                TableColumn("Modos", value: \WiFiNetwork.phyModes) { n in Text(n.phyModes) }
                    .width(min: 60, ideal: 90).customizationID("modos")
                TableColumn("Vel. máx.", value: \WiFiNetwork.maxRate) { n in Text(n.maxRateLabel).monospacedDigit() }
                    .width(min: 70, ideal: 85).customizationID("velocidad")
    }

    @TableColumnBuilder<WiFiNetwork, KeyPathComparator<WiFiNetwork>>
    private var columns4: some TableColumnContent<WiFiNetwork, KeyPathComparator<WiFiNetwork>> {
                TableColumn("Flujos", value: \WiFiNetwork.streams) { n in Text(n.streamsLabel).monospacedDigit() }
                    .width(min: 40, ideal: 50).customizationID("flujos").defaultVisibility(.hidden)
                TableColumn("Clientes", value: \WiFiNetwork.stations) { n in Text(n.stationsLabel).monospacedDigit() }
                    .width(min: 50, ideal: 60).customizationID("clientes")
                TableColumn("Uso canal", value: \WiFiNetwork.utilization) { n in UtilizationCell(value: n.utilization) }
                .width(min: 60, ideal: 70).customizationID("uso")
    }

    @TableColumnBuilder<WiFiNetwork, KeyPathComparator<WiFiNetwork>>
    private var columns5: some TableColumnContent<WiFiNetwork, KeyPathComparator<WiFiNetwork>> {
                TableColumn("País", value: \WiFiNetwork.country) { n in Text(n.country) }
                    .width(min: 36, ideal: 44).customizationID("pais").defaultVisibility(.hidden)
                TableColumn("Frec. central", value: \WiFiNetwork.centerFrequency) { n in Text(n.frequencyLabel).monospacedDigit() }
                    .width(min: 80, ideal: 90).customizationID("frecuencia").defaultVisibility(.hidden)
                TableColumn("Dispositivo", value: \WiFiNetwork.deviceName) { n in Text(n.deviceName) }
                    .width(min: 80, ideal: 120).customizationID("dispositivo").defaultVisibility(.hidden)
    }

    @TableColumnBuilder<WiFiNetwork, KeyPathComparator<WiFiNetwork>>
    private var columns6: some TableColumnContent<WiFiNetwork, KeyPathComparator<WiFiNetwork>> {
                TableColumn("Nota", sortUsing: KeyPathComparator(\WiFiNetwork.noteKey)) { n in
                    NoteCell(text: scanner.notes[n.id] ?? "")
                }
                .width(min: 60, ideal: 120).customizationID("nota")
                TableColumn("Visto", value: \WiFiNetwork.lastSeen) { n in
                    Text(n.lastSeen, format: .dateTime.hour().minute().second()).monospacedDigit()
                }
                .width(min: 64, ideal: 70).customizationID("visto").defaultVisibility(.hidden)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

struct SignalCell: View {
    let rssi: Int
    var color: Color { rssi >= -60 ? .green : rssi >= -70 ? .yellow : rssi >= -80 ? .orange : .red }

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: g.size.width * CGFloat(max(0, min(100, 2 * (rssi + 100)))) / 100)
                }
            }
            .frame(width: 44, height: 6)
            Text("\(rssi) dBm").monospacedDigit().frame(width: 58, alignment: .trailing)
            Text("\(max(0, min(100, 2 * (rssi + 100)))) %").monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

struct LocationBanner: View {
    @ObservedObject var scanner: Scanner

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.slash.fill").foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Falta el permiso de Localización").bold()
                Text("Sin él, macOS esconde el nombre y la dirección de las redes. Actívalo para Antena en Ajustes ▸ Privacidad y seguridad ▸ Localización.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir Ajustes") { scanner.openLocationSettings() }
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }
}

struct StatusLine: View {
    @ObservedObject var scanner: Scanner
    let shown: Int

    var body: some View {
        HStack(spacing: 14) {
            if scanner.scanning { ProgressView().controlSize(.mini) }
            Text("Redes: \(scanner.networks.count), mostradas: \(shown)")
            if !scanner.currentSSID.isEmpty { Text("Conectado a «\(scanner.currentSSID)»") }
            if !scanner.interfaceName.isEmpty { Text("Interfaz \(scanner.interfaceName)") }
            Spacer()
            if scanner.paused { Text("Pausado").foregroundStyle(.orange) }
            if let d = scanner.lastScan {
                Text("Último escaneo: \(d.formatted(date: .omitted, time: .standard))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}


struct NoteCell: View {
    let text: String
    var body: some View { Text(text).foregroundStyle(.secondary).lineLimit(1) }
}

struct NameCell: View {
    let network: WiFiNetwork
    let connected: Bool
    let note: String
    let stale: Bool

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(networkColor(network.id)).frame(width: 4, height: 16)
            Text(network.displayName)
                .italic(network.ssid.isEmpty)
                .fontWeight(connected ? .bold : .regular)
                .foregroundStyle(network.ssid.isEmpty ? Color.secondary : Color.primary)
            if connected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Conectado")
            }
            if !note.isEmpty {
                Image(systemName: "note.text").foregroundStyle(.secondary).help(note)
            }
        }
        .opacity(stale ? 0.45 : 1)
    }
}

struct SecurityCell: View {
    let network: WiFiNetwork
    var color: Color {
        if network.security == "Abierta" || network.security == "WEP" { return .red }
        return network.weakCipher ? .orange : .secondary
    }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: network.security.hasPrefix("Abierta") ? "lock.open" : "lock.fill").foregroundStyle(color)
            Text(network.security)
        }
    }
}

struct UtilizationCell: View {
    let value: Int
    var color: Color { value >= 70 ? .red : value >= 50 ? .orange : .primary }
    var body: some View {
        Text(value >= 0 ? "\(value) %" : "—").monospacedDigit().foregroundStyle(color)
    }
}
