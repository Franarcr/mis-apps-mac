import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var welcome: NSWindow?
    private let services = ServiceProvider()
    /// Se abrió para un Servicio del Finder: al terminar, si no hay ventanas, la app se cierra sola.
    private var launchedForService = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        services.onStart = { [weak self] in self?.launchedForService = true }
        services.onFinish = { [weak self] in self?.quitIfIdle() }

        // Si no llega ningún archivo ni Servicio enseguida, se muestra la ventana de bienvenida.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.launchedForService, !NSApp.windows.contains(where: \.isVisible) else { return }
            self.showWelcome()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handle(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcome() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !launchedForService }

    /// Los comprimidos se abren; el resto de archivos y carpetas se comprimen.
    func handle(_ urls: [URL]) {
        let archives = urls.filter(ArchiveEngine.isArchive)
        let others = urls.filter { !ArchiveEngine.isArchive($0) }
        archives.forEach(ArchiveWindowController.show)
        if !others.isEmpty { CreateWindowController.show(items: others) }
        if !urls.isEmpty { welcome?.orderOut(nil) }
    }

    private func quitIfIdle() {
        let visible = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
        if launchedForService, !visible { NSApp.terminate(nil) }
    }

    // MARK: Ventana de bienvenida

    @objc func showWelcome() {
        if welcome == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.title = "Compresor"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WelcomeView(
                onDrop: { [weak self] urls in self?.handle(urls) },
                onOpen: { [weak self] in self?.openArchive() },
                onCompress: { [weak self] in self?.chooseToCompress() }))
            window.center()
            welcome = window
        }
        NSApp.activate(ignoringOtherApps: true)
        welcome?.makeKeyAndOrderFront(nil)
    }

    @objc func openArchive() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.prompt = "Abrir"
        panel.message = "Elige un archivo comprimido"
        if panel.runModal() == .OK { panel.urls.forEach(ArchiveWindowController.show) }
    }

    @objc func chooseToCompress() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Comprimir"
        panel.message = "Elige los archivos o carpetas que quieres comprimir"
        if panel.runModal() == .OK, !panel.urls.isEmpty { CreateWindowController.show(items: panel.urls) }
    }

    // MARK: App predeterminada

    private static let rarAnd7z = ["public.rar-archive", "org.7-zip.7-zip-archive"]
    private static let allArchives = rarAnd7z + ["public.zip-archive", "public.tar-archive", "org.gnu.gnu-zip-archive",
                                                 "org.gnu.gnu-zip-tar-archive", "public.bzip2-archive",
                                                 "public.tar-bzip2-archive", "org.tukaani.xz-archive",
                                                 "org.tukaani.tar-xz-archive", "com.microsoft.cab", "public.cpio-archive"]

    @objc func makeDefaultForRAR() { makeDefault(for: Self.rarAnd7z, label: "RAR y 7z") }
    @objc func makeDefaultForAll() { makeDefault(for: Self.allArchives, label: "todos los comprimidos") }

    /// Hace de Compresor la app que abre estos tipos con doble clic (macOS puede pedir confirmación).
    private func makeDefault(for identifiers: [String], label: String) {
        let app = Bundle.main.bundleURL
        let types = identifiers.compactMap { UTType($0) }
        Task { @MainActor in
            var failed: [String] = []
            for type in types {
                do { try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) }
                catch { failed.append(type.preferredFilenameExtension ?? type.identifier) }
            }
            let alert = NSAlert()
            if failed.isEmpty {
                alert.messageText = "Compresor abrirá \(label)"
                alert.informativeText = "A partir de ahora, al hacer doble clic en esos archivos se abrirán con Compresor."
            } else {
                alert.messageText = "No se pudo cambiar en algunos formatos"
                alert.informativeText = "Formatos sin cambiar: \(failed.joined(separator: ", ")). También puedes hacerlo en el Finder: Obtener información › Abrir con › Cambiar todo."
            }
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: Menú

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            parent.submenu = menu
            main.addItem(parent)
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command,
                  target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            return item
        }
        submenu("Compresor", [
            item("Acerca de Compresor", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Usar Compresor para abrir RAR y 7z", #selector(makeDefaultForRAR), "", target: self),
            item("Usar Compresor para abrir todos los comprimidos", #selector(makeDefaultForAll), "", target: self),
            .separator(),
            item("Ocultar Compresor", #selector(NSApplication.hide(_:)), "h"),
            item("Salir de Compresor", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("Archivo", [
            item("Abrir comprimido…", #selector(openArchive), "o", target: self),
            item("Comprimir archivos…", #selector(chooseToCompress), "n", target: self),
            item("Ventana de bienvenida", #selector(showWelcome), "1", target: self),
            .separator(),
            item("Cerrar", #selector(NSWindow.performClose(_:)), "w"),
        ])
        submenu("Edición", [
            item("Deshacer", Selector(("undo:")), "z"),
            item("Cortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Pegar", #selector(NSText.paste(_:)), "v"),
            item("Seleccionar todo", #selector(NSText.selectAll(_:)), "a"),
        ])
        return main
    }
}

private struct WelcomeView: View {
    let onDrop: ([URL]) -> Void
    let onOpen: () -> Void
    let onCompress: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "archivebox").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Suelta aquí").font(.title2.bold())
                Text("archivos o carpetas para comprimirlos,\no un comprimido para ver su contenido")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(.tertiary))
            .dropDestination(for: URL.self) { urls, _ in
                onDrop(urls)
                return true
            }
            HStack {
                Button("Abrir comprimido…", action: onOpen)
                Button("Comprimir archivos…", action: onCompress)
            }
        }
        .padding(EdgeInsets(top: 34, leading: 20, bottom: 20, trailing: 20))
        .frame(width: 440, height: 300)
    }
}
