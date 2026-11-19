import Foundation
import AppKit

@MainActor
final class Store: ObservableObject {
    @Published var snap = Snapshot()
    @Published var loading = false
    @Published var loadedOnce = false
    @Published var lastError: String?
    private var timer: Timer?

    init() {
        refresh()
        // La barra de menú se mantiene al día sola.
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let s = Scanner().scan()
            await MainActor.run {
                self.snap = s
                self.loading = false
                self.loadedOnce = true
            }
        }
    }

    var weekUsage: Int? { snap.usage.last?.sevenDay }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Manda a la Papelera (se puede recuperar desde ahí).
    func trash(chat: Chat) {
        let f = URL(fileURLWithPath: chat.path)
        let side = f.deletingPathExtension()
        do {
            try FileManager.default.trashItem(at: f, resultingItemURL: nil)
            if FileManager.default.fileExists(atPath: side.path) {
                try FileManager.default.trashItem(at: side, resultingItemURL: nil)
            }
        } catch { lastError = error.localizedDescription }
        refresh()
    }

    func trash(disk: DiskItem) {
        do { try FileManager.default.trashItem(at: URL(fileURLWithPath: disk.path), resultingItemURL: nil) }
        catch { lastError = error.localizedDescription }
        refresh()
    }

    var claudeIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.anthropic.claudefordesktop" }
    }
}
