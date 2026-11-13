import AppKit
import SwiftUI

@main
struct BatidoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: BatidoDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1240, height: 780)
        .commands { BatidoCommands() }

        Settings { SettingsView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("Batido"))
    }
}

struct DocModelKey: FocusedValueKey { typealias Value = DocModel }
extension FocusedValues {
    var docModel: DocModel? {
        get { self[DocModelKey.self] }
        set { self[DocModelKey.self] = newValue }
    }
}

struct ContentView: View {
    @Binding var document: BatidoDocument
    let fileURL: URL?
    @StateObject private var model = DocModel()

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                mainArea
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                if model.showInspector {
                    InspectorView(model: model)
                        .frame(minWidth: 250, idealWidth: 290, maxWidth: 440, maxHeight: .infinity)
                }
            }
            StatusBar(model: model)
        }
        .onAppear { model.setup(text: document.text, fileURL: fileURL) }
        .onDisappear { model.close() }
        .onChange(of: fileURL) { model.fileURLChanged(fileURL) }
        .focusedSceneValue(\.docModel, model)
        .toolbar { toolbar }
        .sheet(isPresented: $model.showGoToLine) { GoToLineSheet(model: model) }
    }

    @ViewBuilder private var mainArea: some View {
        let editor = CodeEditor(text: $document.text, model: model)
        let preview = !model.detached && model.showPreview
        if model.showEditor && preview {
            if model.panoramic {
                VSplitView {
                    editor.frame(minHeight: 120)
                    PreviewView(model: model).frame(minHeight: 120)
                }
            } else {
                HSplitView {
                    editor.frame(minWidth: 220)
                    PreviewView(model: model).frame(minWidth: 220)
                }
            }
        } else if preview {
            PreviewView(model: model)
        } else {
            editor
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                Picker("Modo", selection: $model.modeChoice) {
                    Text("Según el archivo").tag(Lang?.none)
                    ForEach(Lang.allCases) { Text($0.title).tag(Lang?.some($0)) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(model.lang.title)
            }
            .help("Lenguaje del documento")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.render() } label: {
                Label("Recargar", systemImage: model.dirtyPreview ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
            }
            .help("Volver a cargar la vista previa (⌘R)")
            Menu {
                ForEach(DocModel.installedBrowsers, id: \.name) { b in
                    Button(b.name) { model.openInBrowser(b.url) }
                }
                Divider()
                Button("Navegador predeterminado") { model.openInBrowser(nil) }
            } label: {
                Label("Navegador", systemImage: "safari")
            }
            .help("Ver en un navegador")
            Menu {
                Picker("Ancho de página", selection: $model.pageWidth) {
                    ForEach(PageWidth.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Ancho de página", systemImage: model.pageWidth.symbol)
            }
            .help("Ancho con el que se dibuja la página")
            Button { model.panoramic.toggle() } label: {
                Label("Disposición", systemImage: model.panoramic ? "rectangle.split.1x2" : "rectangle.split.2x1")
            }
            .help("Cambiar entre lado a lado y arriba-abajo")
            Button { model.toggleDetached() } label: {
                Label("Ventana aparte", systemImage: model.detached ? "macwindow.on.rectangle" : "macwindow.badge.plus")
            }
            .help("Vista previa en una ventana aparte")
            Button { model.showInspector.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Mostrar u ocultar el inspector")
        }
    }
}

struct StatusBar: View {
    @ObservedObject var model: DocModel

    var body: some View {
        HStack(spacing: 14) {
            Text("Línea \(model.line), col. \(model.column)").monospacedDigit()
            Text(model.lang.title)
            Text(model.refreshMode.title)
            if model.dirtyPreview {
                Button("Recargar vista previa") { model.render() }.buttonStyle(.link)
            }
            Spacer()
            let errors = model.allProblems.filter { $0.kind == .error }.count
            let warnings = model.allProblems.count - errors
            Button {
                model.inspectorTab = .problems
                model.showInspector = true
            } label: {
                HStack(spacing: 8) {
                    Label("\(errors)", systemImage: "xmark.octagon").foregroundStyle(errors > 0 ? .red : .secondary)
                    Label("\(warnings)", systemImage: "exclamationmark.triangle").foregroundStyle(warnings > 0 ? .orange : .secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Ver problemas")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

struct GoToLineSheet: View {
    @ObservedObject var model: DocModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ir a la línea").font(.headline)
            TextField("Número de línea", text: $value).onSubmit(go).frame(width: 220)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Ir", action: go).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func go() {
        let parts = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        dismiss()
        if let line = parts.first {
            DispatchQueue.main.async { model.goTo(line: line, column: parts.count > 1 ? parts[1] : 1) }
        }
    }
}

struct BatidoCommands: Commands {
    @FocusedValue(\.docModel) private var model

    var body: some Commands {
        CommandMenu("Código") {
            Button("Ir a la línea…") { model?.showGoToLine = true }
                .keyboardShortcut("l", modifiers: .command)
            Button("Marcar como comentario") { model?.toggleComment() }
                .keyboardShortcut("/", modifiers: .command)
            Divider()
            Button("MAYÚSCULAS") { model?.transformSelection { $0.uppercased() } }
            Button("minúsculas") { model?.transformSelection { $0.lowercased() } }
            Button("Inicial Mayúscula") { model?.transformSelection { $0.capitalized } }
            Divider()
            Button("Revisar página") { model?.validateNow() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Problema siguiente") { model?.jumpToProblem(forward: true) }
                .keyboardShortcut("'", modifiers: .command)
            Button("Problema anterior") { model?.jumpToProblem(forward: false) }
                .keyboardShortcut("'", modifiers: [.command, .shift])
            Divider()
            Menu("Modo") {
                Button("Según el archivo") { model?.modeChoice = nil }
                ForEach(Array(Lang.allCases.enumerated()), id: \.element) { i, lang in
                    Button(lang.title) { model?.modeChoice = lang }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .control)
                }
            }
        }

        CommandMenu("Fragmentos") {
            ForEach(SnippetStore.shared.groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.items) { s in
                        Button(s.name) { model?.insert(s) }.keyboardShortcut(s.shortcut)
                    }
                }
            }
            Divider()
            Button("Nuevo fragmento…") {
                model?.inspectorTab = .snippets
                model?.showInspector = true
                model?.showNewSnippet = true
            }
        }

        CommandMenu("Vista previa") {
            Button("Volver a cargar") { model?.render() }
                .keyboardShortcut("r", modifiers: .command)
            Menu("Ver en el navegador") {
                ForEach(DocModel.installedBrowsers, id: \.name) { b in
                    Button(b.name) { model?.openInBrowser(b.url) }
                }
                Divider()
                Button("Navegador predeterminado") { model?.openInBrowser(nil) }
                    .keyboardShortcut("b", modifiers: [.command, .option])
            }
            Divider()
            Button(model?.detached == true ? "Volver a la ventana principal" : "Vista previa en ventana aparte") {
                model?.toggleDetached()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            Button(model?.panoramic == true ? "Lado a lado" : "Arriba y abajo") { model?.panoramic.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift, .option])
            Button(model?.showEditor == false ? "Mostrar editor" : "Ocultar editor") {
                if let m = model { m.showEditor.toggle(); if !m.showEditor { m.showPreview = true } }
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            Button(model?.showPreview == false ? "Mostrar vista previa" : "Ocultar vista previa") {
                if let m = model { m.showPreview.toggle(); if !m.showPreview { m.showEditor = true } }
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            Button(model?.showInspector == false ? "Mostrar inspector" : "Ocultar inspector") { model?.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Menu("Ancho de página") {
                ForEach(PageWidth.allCases) { w in
                    Button((model?.pageWidth == w ? "✓ " : "") + w.title) { model?.pageWidth = w }
                }
            }
            Divider()
            Button("Acercar") { if let m = model { m.zoom = min(3, m.zoom + 0.1) } }
                .keyboardShortcut("+", modifiers: .command)
            Button("Alejar") { if let m = model { m.zoom = max(0.3, m.zoom - 0.1) } }
                .keyboardShortcut("-", modifiers: .command)
            Button("Tamaño real") { model?.zoom = 1 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Toggle("Seguir el desplazamiento del editor", isOn: Binding(
                get: { model?.syncScroll ?? false }, set: { model?.syncScroll = $0 }))
        }
    }
}

struct SettingsView: View {
    @AppStorage("tamanoLetra") private var fontSize: Double = 13
    @AppStorage("ajustarLineas") private var wrapLines = true
    @AppStorage("refrescoPorOmision") private var refresh = RefreshMode.instant.rawValue
    @AppStorage("esperaPorOmision") private var delay: Double = 0.5
    @AppStorage("rutaPHP") private var phpPath = ""

    var body: some View {
        Form {
            Section("Editor") {
                Stepper("Tamaño de letra: \(Int(fontSize))", value: $fontSize, in: 9...28)
                Toggle("Ajustar líneas largas al ancho", isOn: $wrapLines)
            }
            Section("Documentos nuevos") {
                Picker("Refrescar la vista previa", selection: $refresh) {
                    ForEach(RefreshMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if refresh == RefreshMode.delayed.rawValue {
                    Slider(value: $delay, in: 0...4, step: 0.25) { Text("Espera: \(String(format: "%.2g", delay)) s") }
                }
            }
            Section("PHP") {
                TextField("Ruta a php (vacío = buscar sola)", text: $phpPath)
                if let found = PHPRunner.find(customPath: phpPath) {
                    Label("Se usará \(found.path)", systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    Label("No hay PHP instalado. En Terminal: brew install php", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 8)
    }
}
