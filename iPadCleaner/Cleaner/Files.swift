import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct FileEntry: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let created: Date?
    /// Está solo en iCloud (no descargado en el iPad).
    let inCloud: Bool

    var name: String { url.lastPathComponent }

    var kind: FileKind {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .other }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archive }
        if type.conforms(to: .pdf) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet) || type.conforms(to: .text) { return .document }
        return .other
    }
}

enum FileKind: String, CaseIterable, Identifiable {
    case video, image, audio, archive, document, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .video: "Videos"
        case .image: "Imágenes"
        case .audio: "Audio"
        case .archive: "Comprimidos e instaladores"
        case .document: "Documentos"
        case .other: "Otros"
        }
    }
    var icon: String {
        switch self {
        case .video: "film"
        case .image: "photo"
        case .audio: "music.note"
        case .archive: "archivebox"
        case .document: "doc.richtext"
        case .other: "doc"
        }
    }
}

struct DuplicateGroup: Identifiable {
    let id: String
    let files: [FileEntry]
    var size: Int64 { files.first?.size ?? 0 }
    var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
}

/// Archivos de una carpeta elegida en la app Archivos (iCloud Drive, «En mi iPad»…).
/// iPadOS solo deja ver las carpetas que tú eliges.
@MainActor
final class FilesModel: ObservableObject {
    @Published var folder: URL?
    @Published var isScanning = false
    @Published var progressText = ""
    @Published var large: [FileEntry] = []
    @Published var duplicates: [DuplicateGroup] = []
    @Published var selected: Set<URL> = []
    @Published var selectedLarge: Set<URL> = []
    @Published var message: String?
    @Published var lastScan: Date?
    @Published var minLargeMB: Double = 50

    private let bookmarkKey = "carpetaElegida"

    init() {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale), !Self.isInCloud(url) {
                folder = url
                if stale { save(url) }
            }
        }
    }

    /// Solo se aceptan carpetas guardadas en el iPad: borrar en iCloud Drive no libera espacio aquí.
    static func isInCloud(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true { return true }
        return url.path.contains("/Mobile Documents/") || FileManager.default.isUbiquitousItem(at: url)
    }

    func choose(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        if Self.isInCloud(url) {
            if access { url.stopAccessingSecurityScopedResource() }
            message = "Esa carpeta está en iCloud Drive. Elige una dentro de «En mi iPad»: Cleaner solo limpia lo que ocupa espacio en el iPad."
            return
        }
        if access { url.stopAccessingSecurityScopedResource() }
        folder?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        folder = url
        save(url)
        large = []
        duplicates = []
        selected = []
        selectedLarge = []
        lastScan = nil
    }

    private func save(_ url: URL) {
        if let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    func scan() async {
        guard let folder else { return }
        isScanning = true
        message = nil
        progressText = "Buscando archivos…"
        let access = folder.startAccessingSecurityScopedResource()
        let minLarge = Int64(minLargeMB * 1_000_000)
        let result = await Task.detached(priority: .userInitiated) {
            FileScanner.scan(folder, minLarge: minLarge) { text in
                Task { @MainActor in self.progressText = text }
            }
        }.value
        if access { folder.stopAccessingSecurityScopedResource() }
        large = result.large
        duplicates = result.duplicates
        // En duplicados se marca todo menos el más antiguo de cada grupo.
        selected = Set(duplicates.flatMap { $0.files.dropFirst().map(\.url) })
        selectedLarge = []
        if result.count == 0 {
            message = "No encontré archivos guardados en el iPad dentro de esa carpeta."
        }
        lastScan = Date()
        isScanning = false
    }

    func toggle(_ url: URL) {
        if selected.contains(url) { selected.remove(url) } else { selected.insert(url) }
    }

    func toggleLarge(_ url: URL) {
        if selectedLarge.contains(url) { selectedLarge.remove(url) } else { selectedLarge.insert(url) }
    }

    func bytes(of urls: Set<URL>, in entries: [FileEntry]) -> Int64 {
        entries.filter { urls.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    /// Mueve a «Eliminados recientemente» de Archivos. Si iPadOS no lo permite en esa ubicación, no se borra.
    func trash(_ urls: [URL]) {
        guard let folder else { return }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        var moved: [URL] = []
        var failed = 0
        var freed: Int64 = 0
        let all = large + duplicates.flatMap(\.files)
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                moved.append(url)
                freed += all.first { $0.url == url }?.size ?? 0
            } catch {
                failed += 1
            }
        }
        let gone = Set(moved)
        large.removeAll { gone.contains($0.url) }
        duplicates = duplicates.compactMap { g in
            let rest = g.files.filter { !gone.contains($0.url) }
            return rest.count > 1 ? DuplicateGroup(id: g.id, files: rest) : nil
        }
        selected.subtract(gone)
        selectedLarge.subtract(gone)
        var parts: [String] = []
        if !moved.isEmpty { parts.append("\(moved.count) archivo(s), \(Format.bytes(freed)), a «Eliminados recientemente» de Archivos.") }
        if failed > 0 { parts.append("\(failed) no se pudieron mover (iPadOS no deja en esa ubicación); bórralos desde la app Archivos.") }
        message = parts.joined(separator: " ")
    }
}

enum FileScanner {
    struct Result {
        var large: [FileEntry] = []
        var duplicates: [DuplicateGroup] = []
        var count = 0
    }

    static func scan(_ root: URL, minLarge: Int64, progress: @escaping (String) -> Void) -> Result {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .creationDateKey,
                                      .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        var entries: [FileEntry] = []
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return Result()
        }
        for case let url as URL in walker {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            // Lo que está en iCloud no ocupa (o no libera) espacio en el iPad: se ignora.
            let inCloud = v.isUbiquitousItem == true
            if inCloud { continue }
            let size = Int64(v.fileSize ?? v.totalFileAllocatedSize ?? 0)
            entries.append(FileEntry(url: url, size: size, created: v.creationDate, inCloud: inCloud))
            if entries.count % 200 == 0 { progress("Encontrados \(entries.count) archivos…") }
        }

        var out = Result()
        out.count = entries.count
        out.large = entries.filter { $0.size >= minLarge }.sorted { $0.size > $1.size }

        // Duplicados: mismo tamaño → misma huella del contenido. Solo archivos descargados y de más de 100 KB.
        let candidates = Dictionary(grouping: entries.filter { !$0.inCloud && $0.size >= 100_000 }, by: \.size).values.filter { $0.count > 1 }
        let totalCandidates = candidates.reduce(0) { $0 + $1.count }
        var checked = 0
        for sameSize in candidates {
            var byHash: [String: [FileEntry]] = [:]
            for entry in sameSize {
                checked += 1
                if checked % 20 == 0 { progress("Comparando contenido \(checked) de \(totalCandidates)…") }
                if let h = hash(entry.url) { byHash[h, default: []].append(entry) }
            }
            for (h, files) in byHash where files.count > 1 {
                let sorted = files.sorted { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }
                out.duplicates.append(DuplicateGroup(id: h, files: sorted))
            }
        }
        out.duplicates.sort { $0.wasted > $1.wasted }
        return out
    }

    static func hash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = autoreleasepool { try? handle.read(upToCount: 1 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Vistas compartidas

struct FolderBar: View {
    @ObservedObject var model: FilesModel
    let palette: Palette
    @State private var picking = false

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                IconTile(icon: "folder.fill", colors: palette.accentColors, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.folder?.lastPathComponent ?? "Ninguna carpeta elegida")
                        .font(.headline)
                    Text(model.folder == nil
                         ? "Elige una carpeta de «En mi iPad» para revisarla."
                         : (model.lastScan.map { "Revisada a las \($0.formatted(date: .omitted, time: .shortened))" } ?? "Sin revisar todavía"))
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button(model.folder == nil ? "Elegir carpeta" : "Cambiar") { picking = true }
                    .buttonStyle(PillButtonStyle())
                if model.folder != nil {
                    Button(model.isScanning ? "Revisando…" : "Revisar") { Task { await model.scan() } }
                        .buttonStyle(PillButtonStyle(palette: palette))
                        .disabled(model.isScanning)
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.choose(url)
                Task { await model.scan() }
            }
        }
    }
}

struct FileRow: View {
    let entry: FileEntry
    let isOn: Bool
    let palette: Palette
    var relativeTo: URL?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                CheckCircle(isOn: .constant(isOn), colors: palette.accentColors)
                    .allowsHitTesting(false)
                Image(systemName: entry.kind.icon)
                    .frame(width: 24)
                    .foregroundStyle(.white.opacity(0.85))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).lineLimit(1)
                    Text(folderText)
                        .font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer()
                if entry.inCloud {
                    Image(systemName: "icloud").foregroundStyle(.white.opacity(0.6))
                }
                Text(Format.bytes(entry.size))
                    .font(.callout.monospacedDigit())
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var folderText: String {
        let parent = entry.url.deletingLastPathComponent().path
        if let base = relativeTo?.path, parent.hasPrefix(base) {
            let rest = parent.dropFirst(base.count)
            return (relativeTo?.lastPathComponent ?? "") + rest
        }
        return entry.url.deletingLastPathComponent().lastPathComponent
    }
}

struct TrashBar: View {
    let count: Int
    let bytes: Int64
    let action: () -> Void
    @State private var confirming = false

    var body: some View {
        if count > 0 {
            HStack {
                Text("\(count) marcados · \(Format.bytes(bytes))").font(.callout.weight(.semibold))
                Spacer()
                Button("Mover a Eliminados") { confirming = true }
                    .buttonStyle(PillButtonStyle(destructive: true))
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .confirmationDialog("¿Mover \(count) archivo(s) a «Eliminados recientemente»?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Mover \(Format.bytes(bytes))", role: .destructive, action: action)
            } message: {
                Text("Se pueden recuperar desde la app Archivos durante 30 días.")
            }
        }
    }
}

// MARK: - Archivos grandes

struct LargeFilesView: View {
    @ObservedObject var model: FilesModel
    @State private var kind: FileKind?
    private let palette = Palette.largeFiles

    private var shown: [FileEntry] {
        model.large.filter { kind == nil || $0.kind == kind }
    }

    var body: some View {
        ScrollArea {
            VStack(alignment: .leading, spacing: 18) {
                ModuleHeader(
                    title: "Archivos grandes",
                    subtitle: model.message ?? "Los archivos más pesados de la carpeta que elijas. Nada se marca solo: tú decides.",
                    icon: "doc.text.magnifyingglass",
                    palette: palette
                )
                FolderBar(model: model, palette: palette)

                HStack {
                    Text("Mostrar desde")
                    Picker("Tamaño mínimo", selection: $model.minLargeMB) {
                        Text("10 MB").tag(10.0)
                        Text("50 MB").tag(50.0)
                        Text("100 MB").tag(100.0)
                        Text("500 MB").tag(500.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                    .onChange(of: model.minLargeMB) { _, _ in
                        if model.folder != nil { Task { await model.scan() } }
                    }
                }
                .font(.callout)

                if model.isScanning {
                    CenteredMessage(icon: "", title: model.progressText, showsProgress: true).frame(height: 240)
                } else if model.lastScan != nil {
                    let kinds = FileKind.allCases.filter { k in model.large.contains { $0.kind == k } }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            chip(nil, title: "Todos", size: model.large.reduce(0) { $0 + $1.size })
                            ForEach(kinds) { k in
                                chip(k, title: k.title, size: model.large.filter { $0.kind == k }.reduce(0) { $0 + $1.size })
                            }
                        }
                    }
                    if shown.isEmpty {
                        CenteredMessage(icon: "sparkles", title: "Nada tan grande", detail: "No hay archivos de ese tamaño en esta carpeta.")
                            .frame(height: 220)
                    } else {
                        GlassCard(padding: 12) {
                            LazyVStack(spacing: 0) {
                                ForEach(shown) { entry in
                                    FileRow(entry: entry, isOn: model.selectedLarge.contains(entry.url), palette: palette, relativeTo: model.folder) {
                                        model.toggleLarge(entry.url)
                                    }
                                    Divider().overlay(.white.opacity(0.1))
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            let marked = model.large.filter { model.selectedLarge.contains($0.url) }
            TrashBar(count: marked.count, bytes: marked.reduce(0) { $0 + $1.size }) {
                model.trash(marked.map(\.url))
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
    }

    private func chip(_ k: FileKind?, title: String, size: Int64) -> some View {
        Button { kind = k } label: {
            HStack(spacing: 6) {
                if let k { Image(systemName: k.icon) }
                Text("\(title) · \(Format.bytes(size))")
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(kind == k ? AnyShapeStyle(palette.accent) : AnyShapeStyle(.white.opacity(0.12)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Duplicados

struct DuplicatesView: View {
    @ObservedObject var model: FilesModel
    private let palette = Palette.duplicates

    var body: some View {
        ScrollArea {
            VStack(alignment: .leading, spacing: 18) {
                ModuleHeader(
                    title: "Duplicados",
                    subtitle: model.message ?? "Archivos idénticos (compara el contenido, no el nombre). Siempre queda una copia: la más antigua.",
                    icon: "doc.on.doc",
                    palette: palette
                )
                FolderBar(model: model, palette: palette)

                if model.isScanning {
                    CenteredMessage(icon: "", title: model.progressText, showsProgress: true).frame(height: 240)
                } else if model.lastScan != nil {
                    if model.duplicates.isEmpty {
                        CenteredMessage(icon: "sparkles", title: "Sin duplicados", detail: "No hay archivos repetidos en esta carpeta.")
                            .frame(height: 220)
                    } else {
                        Text("\(model.duplicates.count) grupos · se pueden liberar \(Format.bytes(model.duplicates.reduce(0) { $0 + $1.wasted }))")
                            .font(.headline)
                        LazyVStack(spacing: 12) {
                            ForEach(model.duplicates) { group in
                                GlassCard(padding: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(group.files.count) copias de \(Format.bytes(group.size))")
                                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                                        ForEach(group.files) { entry in
                                            let isLastKept = !model.selected.contains(entry.url) &&
                                                group.files.filter { !model.selected.contains($0.url) }.count == 1
                                            FileRow(entry: entry, isOn: model.selected.contains(entry.url), palette: palette, relativeTo: model.folder) {
                                                // Nunca dejar el grupo sin ninguna copia.
                                                if model.selected.contains(entry.url) || !isLastKept {
                                                    let wouldRemain = group.files.filter { !model.selected.contains($0.url) && $0.url != entry.url }.count
                                                    if model.selected.contains(entry.url) || wouldRemain >= 1 { model.toggle(entry.url) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            let marked = model.duplicates.flatMap(\.files).filter { model.selected.contains($0.url) }
            TrashBar(count: marked.count, bytes: marked.reduce(0) { $0 + $1.size }) {
                model.trash(marked.map(\.url))
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
    }
}
