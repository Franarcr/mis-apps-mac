import AppKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: DocModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).labelStyle(.iconOnly).help(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Text(model.inspectorTab.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 6)
            Divider()
            Group {
                switch model.inspectorTab {
                case .options: OptionsPane(model: model)
                case .snippets: SnippetsPane(model: model)
                case .files: FilesPane(model: model)
                case .problems: ProblemsPane(model: model)
                case .console: ConsolePane(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(.background)
    }
}

struct OptionsPane: View {
    @ObservedObject var model: DocModel

    var body: some View {
        Form {
            Section("Modo") {
                Picker("Lenguaje", selection: $model.modeChoice) {
                    Text("Según el archivo (\(Lang.from(url: model.fileURL).title))").tag(Lang?.none)
                    ForEach(Lang.allCases) { Text($0.title).tag(Lang?.some($0)) }
                }
                Toggle("Colorear el código", isOn: $model.highlight)
            }
            Section("Vista previa") {
                Picker("Refrescar", selection: $model.refreshMode) {
                    ForEach(RefreshMode.allCases) { Text($0.title).tag($0) }
                }
                if model.refreshMode == .delayed {
                    LabeledContent("Espera") {
                        HStack {
                            Slider(value: $model.delay, in: 0...4, step: 0.25)
                            Text(String(format: "%.2g s", model.delay)).monospacedDigit().frame(width: 36)
                        }
                    }
                }
                if model.refreshMode == .manual {
                    Button("Volver a cargar (⌘R)") { model.render() }
                }
                Picker("Ancho de página", selection: $model.pageWidth) {
                    ForEach(PageWidth.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: model.pageWidth) { UserDefaults.standard.set(model.pageWidth.rawValue, forKey: "anchoPagina") }
                Toggle("Seguir el desplazamiento del editor", isOn: $model.syncScroll)
                LabeledContent("Zoom") {
                    HStack {
                        Slider(value: $model.zoom, in: 0.5...2, step: 0.1)
                        Text("\(Int(model.zoom * 100)) %").monospacedDigit().frame(width: 44)
                    }
                }
            }
            Section("Revisión") {
                Toggle("Revisar mientras escribo", isOn: $model.liveValidation)
            }
        }
        .formStyle(.grouped)
    }
}

struct SnippetsPane: View {
    @ObservedObject var model: DocModel
    @ObservedObject var store = SnippetStore.shared

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items) { s in
                            HStack {
                                Text(s.name)
                                Spacer()
                                Text(s.shortcutLabel).foregroundStyle(.secondary).font(.caption)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.insert(s) }
                            .contextMenu {
                                Button("Insertar") { model.insert(s) }
                                if store.custom.contains(s) {
                                    Button("Eliminar fragmento", role: .destructive) {
                                        store.custom.removeAll { $0.id == s.id }
                                    }
                                }
                            }
                            .help("Doble clic para insertar")
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("Doble clic para insertar").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.showNewSnippet = true } label: { Label("Nuevo", systemImage: "plus") }
            }
            .padding(8)
        }
        .sheet(isPresented: $model.showNewSnippet) { NewSnippetSheet(model: model) }
    }
}

struct NewSnippetSheet: View {
    @ObservedObject var model: DocModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group = "Mis fragmentos"
    @State private var before = ""
    @State private var after = ""
    @State private var replaces = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nuevo fragmento").font(.title3.bold())
            TextField("Nombre", text: $name)
            TextField("Grupo", text: $group)
            Text("Código delante de la selección").font(.caption)
            TextEditor(text: $before).font(.system(.body, design: .monospaced)).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            Text("Código detrás de la selección").font(.caption)
            TextEditor(text: $after).font(.system(.body, design: .monospaced)).frame(height: 60)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            Toggle("Sustituir la selección en vez de envolverla", isOn: $replaces)
            Text("Escribe ${caret} donde quieras que quede el cursor.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    SnippetStore.shared.custom.append(Snippet(name: name, group: group.isEmpty ? "Mis fragmentos" : group,
                                                              before: before, after: after, replacesSelection: replaces))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || (before.isEmpty && after.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let tv = model.textView {
                before = (tv.string as NSString).substring(with: tv.selectedRange())
            }
        }
    }
}

struct FilesPane: View {
    @ObservedObject var model: DocModel

    var body: some View {
        VStack(spacing: 0) {
            if model.linked.isEmpty {
                Text("Aquí aparecen los CSS, JS e imágenes que usa la página. Batido los vigila y recarga la vista previa cuando cambian.\n\nGuarda el documento para que encuentre los archivos de su carpeta.")
                    .font(.callout).foregroundStyle(.secondary).padding()
                Spacer()
            } else {
                List(model.linked) { file in
                    HStack {
                        Image(systemName: file.exists ? "doc" : "questionmark.folder")
                            .foregroundStyle(file.exists ? Color.secondary : Color.orange)
                        VStack(alignment: .leading) {
                            Text(file.url.lastPathComponent)
                            if !file.exists { Text("No se encuentra").font(.caption).foregroundStyle(.orange) }
                        }
                        Spacer()
                        if file.manual { Text("añadido").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .help(file.url.path)
                    .contextMenu {
                        Button("Abrir") { NSWorkspace.shared.open(file.url) }.disabled(!file.exists)
                        Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                            .disabled(!file.exists)
                        if file.manual { Button("Dejar de vigilar") { model.removeLinked(file) } }
                    }
                }
            }
            Divider()
            HStack {
                Text("Clic derecho para abrir").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.addLinkedFiles() } label: { Label("Añadir", systemImage: "plus") }
            }
            .padding(8)
        }
    }
}

struct ProblemsPane: View {
    @ObservedObject var model: DocModel

    var body: some View {
        VStack(spacing: 0) {
            if model.allProblems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.green)
                    Text("Sin problemas").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 40)
                Spacer()
            } else {
                List(model.allProblems) { p in
                    HStack(alignment: .top) {
                        Image(systemName: p.kind == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(p.kind == .error ? .red : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.message).fixedSize(horizontal: false, vertical: true)
                            Text(p.line > 0 ? "\(p.source) · línea \(p.line), col. \(p.column)" : p.source)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if p.line > 0 { model.goTo(line: p.line, column: p.column) } }
                }
            }
            Divider()
            HStack {
                Text("\(model.allProblems.count) problema(s)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Revisar ahora") { model.validateNow() }
            }
            .padding(8)
        }
    }
}

struct ConsolePane: View {
    @ObservedObject var model: DocModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if model.lang == .php && !model.phpOutput.isEmpty {
                            Text("Salida de PHP").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(model.phpOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Divider()
                        }
                        ForEach(model.console) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.kind == "error" ? .red : line.kind == "warn" ? .orange : .primary)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                        if model.console.isEmpty && model.phpOutput.isEmpty {
                            Text("Lo que la página escriba con console.log aparece aquí.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.console.count) {
                    if let last = model.console.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Limpiar") { model.console.removeAll() }
            }
            .padding(8)
        }
    }
}
