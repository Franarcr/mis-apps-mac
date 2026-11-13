import SwiftUI

/// Formas de agrupar las redes en la barra lateral.
enum GroupKind: String, CaseIterable, Identifiable {
    case ssid, channel, width, security, generation, vendor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ssid: return "Nombre de red"
        case .channel: return "Canal"
        case .width: return "Ancho de canal"
        case .security: return "Seguridad"
        case .generation: return "Generación"
        case .vendor: return "Fabricante"
        }
    }

    func key(_ n: WiFiNetwork) -> String {
        switch self {
        case .ssid: return n.displayName
        case .channel: return "\(n.channel) · \(n.band.title)"
        case .width: return n.widthLabel
        case .security: return n.security
        case .generation: return n.generationName
        case .vendor: return n.vendor.isEmpty ? "Desconocido" : n.vendor
        }
    }

    /// Orden de los grupos: por nombre, salvo canal y ancho, que van por número.
    func order(_ a: (String, [WiFiNetwork]), _ b: (String, [WiFiNetwork])) -> Bool {
        switch self {
        case .channel:
            let x = a.1[0], y = b.1[0]
            return (x.band, x.channel) < (y.band, y.channel)
        case .width: return a.1[0].width < b.1[0].width
        default: return a.0.localizedCaseInsensitiveCompare(b.0) == .orderedAscending
        }
    }
}

struct GroupFilter: Equatable {
    var kind: GroupKind
    var value: String
    func matches(_ n: WiFiNetwork) -> Bool { kind.key(n) == value }
}

struct SidebarView: View {
    let networks: [WiFiNetwork]
    let currentBSSID: String
    @Binding var filter: GroupFilter?
    @AppStorage("gruposAbiertos") private var openRaw = "ssid"

    private func isOpen(_ k: GroupKind) -> Binding<Bool> {
        Binding(
            get: { openRaw.split(separator: ",").contains(Substring(k.rawValue)) },
            set: { open in
                var set = Set(openRaw.split(separator: ",").map(String.init))
                if open { set.insert(k.rawValue) } else { set.remove(k.rawValue) }
                openRaw = set.sorted().joined(separator: ",")
            })
    }

    var body: some View {
        List {
            Button {
                filter = nil
            } label: {
                HStack {
                    Label("Todas las redes", systemImage: "wifi")
                    Spacer()
                    Text("\(networks.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
            .listRowBackground(filter == nil ? Color.accentColor.opacity(0.18) : Color.clear)

            ForEach(GroupKind.allCases) { kind in
                let groups = Dictionary(grouping: networks, by: kind.key).map { ($0.key, $0.value) }.sorted(by: kind.order)
                Section(isExpanded: isOpen(kind)) {
                    ForEach(groups, id: \.0) { name, items in
                        let selected = filter == GroupFilter(kind: kind, value: name)
                        Button {
                            filter = selected ? nil : GroupFilter(kind: kind, value: name)
                        } label: {
                            HStack(spacing: 6) {
                                if kind == .ssid {
                                    let best = items.max(by: { $0.rssi < $1.rssi })!
                                    RoundedRectangle(cornerRadius: 2).fill(networkColor(best.id)).frame(width: 4, height: 14)
                                }
                                Text(name)
                                    .lineLimit(1)
                                    .italic(kind == .ssid && name == "Red oculta")
                                    .fontWeight(items.contains { $0.bssid == currentBSSID && !currentBSSID.isEmpty } ? .bold : .regular)
                                Spacer()
                                Text("\(items.count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                } header: {
                    HStack {
                        Text(kind.title)
                        Spacer()
                        Text("\(groups.count)").monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// Franja con la red a la que está conectado el Mac.
struct ConnectionStrip: View {
    let connection: Connection?
    let scanning: Bool
    let paused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: paused ? "pause.circle" : "dot.radiowaves.left.and.right")
                .foregroundStyle(paused ? Color.orange : Color.accentColor)
                .symbolEffect(.pulse, isActive: scanning && !paused)
            if let c = connection {
                Text(c.ssid.isEmpty ? "Conectado" : c.ssid).bold().lineLimit(1)
                chip("Canal \(c.channel)")
                chip(c.band.title)
                chip("\(c.width) MHz")
                if c.txRate > 0 { chip("\(Int(c.txRate)) Mbps") }
                chip("\(c.rssi) dBm")
                if !c.phy.isEmpty { chip(c.phy) }
            } else {
                Text(paused ? "Escaneo en pausa" : "Sin conexión Wi-Fi").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .help(connection.map { "Conectado a \($0.ssid) (\($0.bssid))" } ?? "")
    }

    private func chip(_ s: String) -> some View {
        Text(s)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
    }
}
