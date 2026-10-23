import AppKit

/// Servicios del Finder (clic derecho › Servicios, o directamente en el menú contextual).
/// Los nombres de los métodos coinciden con NSMessage en Info.plist.
@MainActor
final class ServiceProvider: NSObject {
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

    private func files(_ pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    @objc func compressFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let items = files(pasteboard)
        guard !items.isEmpty else { return }
        onStart?()
        Operation.run("Comprimiendo", work: { progress in
            try ArchiveActions.compress(items, progress: progress)
        }) { [weak self] result in
            switch result {
            case .success(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let error): Operation.report(error)
            }
            self?.onFinish?()
        }
    }

    @objc func compressFilesAs(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let items = files(pasteboard)
        guard !items.isEmpty else { return }
        CreateWindowController.show(items: items)
    }

    @objc func extractHere(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let archives = files(pasteboard).filter(ArchiveEngine.isArchive)
        guard !archives.isEmpty else { return }
        onStart?()
        extractNext(archives, created: [])
    }

    /// Extrae los comprimidos uno tras otro; si uno falla o se cancela, sigue con el siguiente.
    private func extractNext(_ remaining: [URL], created: [URL]) {
        guard let archive = remaining.first else {
            if !created.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(created) }
            onFinish?()
            return
        }
        Operation.extractAsking(archive, password: nil, work: { password, progress in
            try ArchiveActions.extractHere(archive, password: password, progress: progress)
        }) { [weak self] url, _ in
            self?.extractNext(Array(remaining.dropFirst()), created: created + (url.map { [$0] } ?? []))
        }
    }
}
