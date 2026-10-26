import AppKit
import SwiftUI

/// Estado de la ventana "Crear comprimido".
final class CreateModel: ObservableObject {
    @Published var items: [URL]
    @Published var name: String
    @Published var format = CreateFormat(rawValue: UserDefaults.standard.string(forKey: "lastFormat") ?? "") ?? .zip {
        didSet { UserDefaults.standard.set(format.rawValue, forKey: "lastFormat") }
    }
    @Published var usePassword = false
    @Published var password = ""
    @Published var confirmation = ""
    @Published var folder: URL

    init(items: [URL]) {
        self.items = items
        let first = items.first
        name = items.count == 1 ? ((first?.lastPathComponent ?? "Archivo") as NSString).deletingPathExtension : "Archivo"
        folder = first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var totalSize: Int64 {
        items.reduce(0) { total, url in
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { return total + Int64(size) }
            let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
            var sum: Int64 = 0
            while let next = walker?.nextObject() as? URL {
                sum += Int64((try? next.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total + sum
        }
    }

    var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Escribe un nombre" }
        if usePassword && format.supportsPassword {
            if password.count < 4 { return "La contraseña debe tener al menos 4 caracteres" }
            if password != confirmation { return "Las contraseñas no coinciden" }
        }
        return nil
    }
}

@MainActor
final class CreateWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [CreateWindowController] = []
    private let model: CreateModel

    static func show(items: [URL]) {
        let controller = CreateWindowController(items: items)
        open.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(items: [URL]) {
        model = CreateModel(items: items)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Crear comprimido"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: CreateView(
            model: model,
            onChooseFolder: { [weak self] in self?.chooseFolder() },
            onCreate: { [weak self] in self?.create() },
            onCancel: { [weak self] in self?.close() }))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.folder
        panel.prompt = "Elegir"
        if panel.runModal() == .OK, let url = panel.url { model.folder = url }
    }

    private func create() {
        let items = model.items
        let format = model.format
        let password = model.usePassword && format.supportsPassword ? model.password : nil
        let target = ArchiveEngine.uniqueURL(in: model.folder, name: model.name.trimmingCharacters(in: .whitespaces),
                                             extension: format.fileExtension)
        close()
        Operation.run("Comprimiendo en \(target.lastPathComponent)", work: { progress in
            try ArchiveEngine.create(from: items, to: target, format: format, password: password, progress: progress)
            return target
        }) { result in
            switch result {
            case .success(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let error): Operation.report(error)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}

private struct CreateView: View {
    @ObservedObject var model: CreateModel
    let onChooseFolder: () -> Void
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Contenido") {
                    Text(model.items.count == 1 ? model.items[0].lastPathComponent : "\(model.items.count) elementos")
                        .lineLimit(1).truncationMode(.middle)
                }
                LabeledContent("Tamaño") {
                    Text(ByteCountFormatter.string(fromByteCount: model.totalSize, countStyle: .file))
                }
            }
            Section {
                TextField("Nombre", text: $model.name)
                Picker("Formato", selection: $model.format) {
                    ForEach(CreateFormat.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Guardar en") {
                    HStack {
                        Text(model.folder.lastPathComponent).lineLimit(1)
                        Button("Cambiar…", action: onChooseFolder)
                    }
                }
            }
            Section {
                Toggle("Proteger con contraseña (AES-256)", isOn: $model.usePassword)
                    .disabled(!model.format.supportsPassword)
                if !model.format.supportsPassword {
                    Text("La contraseña solo está disponible en formato ZIP.").font(.caption).foregroundStyle(.secondary)
                } else if model.usePassword {
                    SecureField("Contraseña", text: $model.password)
                    SecureField("Repite la contraseña", text: $model.confirmation)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if let problem = model.problem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Comprimir", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.problem != nil)
            }
            .padding(14)
        }
        .frame(width: 440)
    }
}
