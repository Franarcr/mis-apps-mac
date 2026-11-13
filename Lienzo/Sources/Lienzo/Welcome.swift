import AppKit
import SwiftUI

struct RecentBoard: Identifiable {
    let url: URL
    let name: String
    let folder: String
    let modified: Date?
    let thumbnail: NSImage?
    var id: URL { url }
}

final class RecentsModel: ObservableObject {
    @Published var boards: [RecentBoard] = []

    func reload() {
        let fm = FileManager.default
        boards = NSDocumentController.shared.recentDocumentURLs
            .filter { fm.fileExists(atPath: $0.path) }
            .map { url in
                let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
                return RecentBoard(url: url, name: url.deletingPathExtension().lastPathComponent,
                                   folder: url.deletingLastPathComponent().path
                                       .replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                                   modified: date,
                                   thumbnail: NSImage(contentsOf: Thumbnails.url(for: url)))
            }
    }
}

/// Ventana de inicio con los tableros recientes.
final class WelcomeWindow: NSObject {
    static let shared = WelcomeWindow()
    let model = RecentsModel()
    private var window: NSWindow?

    func show() {
        model.reload()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Tableros recientes"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: WelcomeView(model: model))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }
}

struct WelcomeView: View {
    @ObservedObject var model: RecentsModel
    @State private var search = ""

    private var filtered: [RecentBoard] {
        search.isEmpty ? model.boards : model.boards.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                Spacer().frame(height: 30)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 104, height: 104)
                Text("Lienzo").font(.system(size: 30, weight: .bold))
                Text("Tu pizarra infinita").foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSDocumentController.shared.newDocument(nil)
                } label: {
                    Label("Nuevo tablero", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)
                Button {
                    NSDocumentController.shared.openDocument(nil)
                } label: {
                    Label("Abrir…", systemImage: "folder").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
                Spacer().frame(height: 10)
            }
            .padding(24)
            .frame(width: 250)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Recientes").font(.title2.bold())
                    Spacer()
                    TextField("Buscar", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                .padding(.top, 30)
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.dashed").font(.system(size: 40)).foregroundStyle(.tertiary)
                        Text(model.boards.isEmpty ? "Aún no hay tableros recientes" : "Ningún tablero coincide")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 18) {
                            ForEach(filtered) { b in BoardCard(board: b) }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 900, height: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
    }
}

private struct BoardCard: View {
    let board: RecentBoard
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: NSColor(hex: "F4F4F1")))
                if let t = board.thumbnail {
                    Image(nsImage: t).resizable().aspectRatio(contentMode: .fit).padding(6)
                } else {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 28)).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(hover ? Color.accentColor : Color.black.opacity(0.1), lineWidth: hover ? 2 : 1))
            Text(board.name).font(.headline).lineLimit(1)
            Text(board.modified.map { $0.formatted(.relative(presentation: .named)) } ?? board.folder)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { AppDelegate.open(board.url) }
        .help(board.url.path)
        .contextMenu {
            Button("Abrir") { AppDelegate.open(board.url) }
            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([board.url]) }
        }
    }
}
