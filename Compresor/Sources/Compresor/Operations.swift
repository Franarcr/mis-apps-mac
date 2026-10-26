import AppKit
import SwiftUI

/// Estado del panel de avance (en una clase porque `@State` necesita las macros de Xcode).
final class ProgressModel: ObservableObject {
    @Published var title = ""
    @Published var detail = ""
    @Published var fraction = 0.0
}

/// Ejecuta una operación larga en segundo plano. Si tarda más de medio segundo, muestra un panel
/// con la barra de avance y un botón para cancelar.
@MainActor
enum Operation {
    static func run<T>(_ title: String, work: @escaping @Sendable (Progress) throws -> T,
                       completion: @escaping (Result<T, Error>) -> Void) {
        let progress = Progress()
        let model = ProgressModel()
        model.title = title
        var panel: NSPanel?
        var finished = false

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                model.fraction = progress.fraction
                model.detail = progress.current
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !finished else { return }
            let host = NSHostingView(rootView: ProgressView(model: model) { progress.cancelled = true })
            host.frame.size = host.fittingSize
            let p = NSPanel(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.title = title
            p.isReleasedWhenClosed = false
            p.contentView = host
            p.center()
            p.makeKeyAndOrderFront(nil)
            panel = p
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try work(progress) }
            DispatchQueue.main.async {
                finished = true
                timer.invalidate()
                panel?.orderOut(nil)
                completion(result)
            }
        }
    }

    /// Muestra un error, salvo la cancelación (que no lo es).
    static func report(_ error: Error) {
        if case ArchiveError.cancelled = error { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "No se pudo completar"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Pide la contraseña de un comprimido. `nil` si se cancela.
    static func askPassword(for name: String, wrong: Bool = false) -> String? {
        let alert = NSAlert()
        alert.messageText = wrong ? "Contraseña incorrecta" : "«\(name)» está protegido con contraseña"
        alert.informativeText = "Escribe la contraseña para extraerlo."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Extraer")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Extrae pidiendo la contraseña si hace falta (y otra vez si es incorrecta).
    /// `completion` recibe lo creado, o `nil` si se canceló o falló (el error ya se mostró).
    static func extractAsking(_ archive: URL, password: String?, work: @escaping @Sendable (String?, Progress) throws -> URL,
                              completion: @escaping (URL?, String?) -> Void) {
        run("Extrayendo \(archive.lastPathComponent)", work: { progress in try work(password, progress) }) { result in
            switch result {
            case .success(let url):
                completion(url, password)
            case .failure(ArchiveError.needsPassword), .failure(ArchiveError.wrongPassword):
                let wrong = password != nil
                guard let entered = askPassword(for: archive.lastPathComponent, wrong: wrong) else {
                    completion(nil, password)
                    return
                }
                extractAsking(archive, password: entered, work: work, completion: completion)
            case .failure(let error):
                report(error)
                completion(nil, password)
            }
        }
    }
}

private struct ProgressView: View {
    @ObservedObject var model: ProgressModel
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.title).font(.headline).lineLimit(1)
            SwiftUI.ProgressView(value: model.fraction)
            HStack {
                Text(model.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(Int(model.fraction * 100)) %").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar", action: onCancel).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
