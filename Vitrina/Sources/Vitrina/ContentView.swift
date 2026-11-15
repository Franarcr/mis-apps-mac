import AppKit
import SwiftUI

enum Filter: String, CaseIterable, Identifiable {
    case all = "Todas", menuBar = "Barra de menú", window = "Con ventana", updates = "Con novedades", installed = "Instaladas"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .menuBar: "menubar.rectangle"
        case .window: "macwindow"
        case .updates: "arrow.triangle.2.circlepath"
        case .installed: "checkmark.circle"
        }
    }
    func matches(_ row: Row) -> Bool {
        switch self {
        case .all: true
        case .menuBar: row.info.kind == .menuBar
        case .window: row.info.kind == .window
        case .updates: row.status == .update
        case .installed: row.status == .installed || row.status == .update
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var filter: Filter = .all
    @State private var search = ""

    private var visible: [Row] {
        store.rows.filter { filter.matches($0) }.filter {
            search.isEmpty || $0.info.name.localizedCaseInsensitiveContains(search)
                || $0.info.summary.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Filter.allCases, selection: Binding(get: { filter }, set: { filter = $0 ?? .all })) { f in
                Label {
                    HStack {
                        Text(f.rawValue)
                        Spacer()
                        let n = store.rows.filter { f.matches($0) }.count
                        if f == .updates && n > 0 { Text("\(n)").foregroundStyle(.orange).font(.caption) }
                    }
                } icon: { Image(systemName: f.symbol) }
                .tag(f)
            }
            .safeAreaInset(edge: .bottom) {
                Text("Mac con chip Apple\nmacOS 14 o posterior")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            VStack(spacing: 0) {
                if store.rows.isEmpty {
                    ContentUnavailableView("No hay apps dentro de Vitrina", systemImage: "shippingbox",
                                           description: Text("Esta copia se armó sin apps. Vuelve a crearla con build.sh."))
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List(visible) { row in AppRow(row: row) }
                        .listStyle(.inset)
                }
                Divider()
                footer
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Buscar")
            .navigationTitle("Vitrina")
            .navigationSubtitle("\(store.rows.count) apps")
        }
        .sheet(item: Binding(get: { store.results.map(ResultsBox.init) }, set: { if $0 == nil { store.results = nil } })) { box in
            ResultsView(results: box.results) { store.results = nil }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let name = store.installing {
                ProgressView().controlSize(.small)
                Text("Instalando \(name)…").foregroundStyle(.secondary)
            } else {
                Text(store.selected.isEmpty ? "Marca las apps que quieras instalar"
                     : store.selected.count == 1 ? "1 seleccionada" : "\(store.selected.count) seleccionadas")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Seleccionar todas") {
                store.selected = Set(visible.filter(\.canInstall).map(\.id))
            }
            .disabled(store.installing != nil)
            Button("Instalar seleccionadas") { store.installSelected() }
                .keyboardShortcut(.defaultAction)
                .disabled(store.selected.isEmpty || store.installing != nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct ResultsBox: Identifiable {
    let results: [InstallResult]
    var id: String { results.map(\.id).joined() }
}

struct AppRow: View {
    @EnvironmentObject private var store: Store
    let row: Row

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { store.selected.contains(row.id) },
                set: { on in if on { store.selected.insert(row.id) } else { store.selected.remove(row.id) } }))
                .labelsHidden()
                .disabled(!row.canInstall || store.installing != nil)
            Image(nsImage: row.icon).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.info.name).font(.headline)
                    Text(row.info.kind == .menuBar ? "barra de menú" : "con ventana")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(row.info.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StatusBadge(status: row.status)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.open(row) }
        .contextMenu {
            Button("Abrir") { store.open(row) }.disabled(Store.installedURL(row.info) == nil)
            Button("Mostrar en el Finder") { store.reveal(row) }.disabled(Store.installedURL(row.info) == nil)
        }
    }
}

struct StatusBadge: View {
    let status: Status
    var body: some View {
        Text(status.label)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch status {
        case .installed: .green
        case .update: .orange
        case .notInstalled: .secondary
        case .needsNewerOS: .red
        }
    }
}

/// Se muestra al terminar: qué se instaló y qué falta hacer en cada app.
struct ResultsView: View {
    let results: [InstallResult]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let failed = results.filter { $0.error != nil }
            Text(failed.isEmpty ? "Listo" : "Terminado con problemas").font(.title2.bold())
            Text(summary).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(failed) { r in
                        Card(title: "No se pudo instalar \(r.info.name)", text: r.error ?? "", tint: .red)
                    }
                    ForEach(results.filter { $0.error == nil && $0.info.setup != nil }) { r in
                        Card(title: r.info.name, text: r.info.setup!.text, tint: .accentColor,
                             button: r.info.setup!.buttonTitle, url: r.info.setup!.settingsURL)
                    }
                }
            }
            .frame(maxHeight: 360)

            HStack {
                Spacer()
                Button("Cerrar", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var summary: String {
        let ok = results.filter { $0.error == nil }.map(\.info.name)
        var s = ok.isEmpty ? "No se instaló ninguna app." : "Instaladas: " + ok.formatted(.list(type: .and)) + "."
        if results.contains(where: { $0.error == nil && $0.info.setup != nil }) {
            s += " Algunas necesitan un paso más:"
        }
        return s
    }
}

private struct Card: View {
    let title: String
    let text: String
    let tint: Color
    var button: String? = nil
    var url: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let button, let url, let link = URL(string: url) {
                Button(button) { NSWorkspace.shared.open(link) }.padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
    }
}
