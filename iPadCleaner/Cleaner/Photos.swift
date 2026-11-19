import SwiftUI
import Photos

/// Una foto o video con lo que hace falta para mostrarla y decidir.
struct MediaItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let size: Int64
    var date: Date? { asset.creationDate }
}

struct SimilarGroup: Identifiable {
    let id: String
    let items: [MediaItem]
    /// La que se sugiere conservar.
    let keepID: String
}

enum PhotoCategory: String, CaseIterable, Identifiable {
    case similar, screenshots
    var id: String { rawValue }
    var title: String {
        switch self {
        case .similar: "Repetidas y parecidas"
        case .screenshots: "Capturas de pantalla"
        }
    }
    var icon: String {
        switch self {
        case .similar: "square.on.square"
        case .screenshots: "camera.viewfinder"
        }
    }
    var detail: String {
        switch self {
        case .similar: "Fotos iguales o casi iguales. Se conserva la mejor de cada grupo."
        case .screenshots: "Se marcan las de hace más de 30 días."
        }
    }
}

@MainActor
final class PhotosModel: ObservableObject {
    @Published var auth: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var progressText = ""
    @Published var groups: [SimilarGroup] = []
    @Published var screenshots: [MediaItem] = []
    @Published var selected: Set<String> = []
    @Published var lastScan: Date?
    @Published var message: String?
    @Published var freedTotal: Int64 = 0

    var allItems: [MediaItem] {
        groups.flatMap(\.items) + screenshots
    }

    func items(_ category: PhotoCategory) -> [MediaItem] {
        switch category {
        case .similar: groups.flatMap(\.items)
        case .screenshots: screenshots
        }
    }

    func size(_ category: PhotoCategory, selectedOnly: Bool) -> Int64 {
        items(category).filter { !selectedOnly || selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var selectedBytes: Int64 {
        var seen = Set<String>()
        return allItems.filter { selected.contains($0.id) && seen.insert($0.id).inserted }.reduce(0) { $0 + $1.size }
    }

    /// Lo que se sugiere borrar: copias sobrantes y capturas viejas (para la calificación).
    var suggestedBytes: Int64 {
        let extras = groups.flatMap { g in g.items.filter { $0.id != g.keepID } }.reduce(0) { $0 + $1.size }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let oldShots = screenshots.filter { ($0.date ?? .distantPast) < cutoff }.reduce(0) { $0 + $1.size }
        return extras + oldShots
    }

    func requestAccess() async {
        auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func scan() async {
        if auth == .notDetermined { await requestAccess() }
        guard auth == .authorized || auth == .limited else { return }
        isScanning = true
        message = nil
        progress = 0
        progressText = "Leyendo la fototeca…"

        let result = await Task.detached(priority: .userInitiated) {
            PhotoScanner.scan { done, total, text in
                Task { @MainActor in
                    self.progress = total > 0 ? Double(done) / Double(total) : 0
                    self.progressText = text
                }
            }
        }.value

        groups = result.groups
        screenshots = result.screenshots
        // Selección sugerida.
        var sel = Set<String>()
        for g in groups { for item in g.items where item.id != g.keepID { sel.insert(item.id) } }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        for s in screenshots where (s.date ?? .distantPast) < cutoff && !s.asset.isFavorite { sel.insert(s.id) }
        selected = sel
        lastScan = Date()
        isScanning = false
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func setAll(_ category: PhotoCategory, on: Bool) {
        switch category {
        case .similar:
            for g in groups {
                for item in g.items where item.id != g.keepID {
                    if on { selected.insert(item.id) } else { selected.remove(item.id) }
                }
            }
        default:
            for item in items(category) {
                if on { selected.insert(item.id) } else { selected.remove(item.id) }
            }
        }
    }

    /// Mueve lo marcado a «Eliminados recientemente». iPadOS pide confirmación.
    func deleteSelected() async {
        let ids = selected
        let assets = allItems.filter { ids.contains($0.id) }
        var unique: [String: MediaItem] = [:]
        for a in assets { unique[a.id] = a }
        guard !unique.isEmpty else { return }
        let bytes = unique.values.reduce(0) { $0 + $1.size }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(unique.values.map(\.asset) as NSArray)
            }
            groups = groups.compactMap { g in
                let rest = g.items.filter { !ids.contains($0.id) }
                guard rest.count > 1 else { return nil }
                let keep = rest.contains { $0.id == g.keepID } ? g.keepID : rest[0].id
                return SimilarGroup(id: g.id, items: rest, keepID: keep)
            }
            screenshots.removeAll { ids.contains($0.id) }
            selected.subtract(ids)
            freedTotal += bytes
            message = "Listo: \(Format.bytes(bytes)) a «Eliminados recientemente». Para liberar el espacio ya, vacíalo en la app Fotos."
        } catch {
            message = "No se borró nada."
        }
    }
}

/// Recorre la fototeca fuera del hilo principal.
enum PhotoScanner {
    struct Result {
        var groups: [SimilarGroup] = []
        var screenshots: [MediaItem] = []
    }

    static func fileSize(_ asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        // El recurso principal (o el editado si existe) es el que ocupa.
        return resources.reduce(Int64(0)) { sum, r in
            sum + ((r.value(forKey: "fileSize") as? CLong).map(Int64.init) ?? 0)
        }
    }

    static func scan(progress: @escaping (Int, Int, String) -> Void) -> Result {
        var out = Result()
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        // Fotos
        let imageFetch = PHAsset.fetchAssets(with: .image, options: options)
        let total = imageFetch.count
        var assets: [PHAsset] = []
        assets.reserveCapacity(total)
        imageFetch.enumerateObjects { a, _, _ in assets.append(a) }

        let manager = PHImageManager.default()
        let req = PHImageRequestOptions()
        req.isSynchronous = true
        req.deliveryMode = .fastFormat
        req.resizeMode = .fast
        req.isNetworkAccessAllowed = false

        var hashes = [UInt64?](repeating: nil, count: total)
        var sizes = [Int64](repeating: 0, count: total)
        for (i, asset) in assets.enumerated() {
            autoreleasepool {
                sizes[i] = fileSize(asset)
                if asset.mediaSubtypes.contains(.photoScreenshot) {
                    out.screenshots.append(MediaItem(id: asset.localIdentifier, asset: asset, size: sizes[i]))
                }
                manager.requestImage(for: asset, targetSize: CGSize(width: 64, height: 64), contentMode: .aspectFill, options: req) { image, _ in
                    if let cg = image?.cgImage { hashes[i] = dHash(cg) }
                }
            }
            if i % 50 == 0 || i == total - 1 {
                progress(i + 1, total, "Revisando foto \(i + 1) de \(total)…")
            }
        }
        out.screenshots.sort { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        // Grupos: unión de índices parecidos.
        var parent = Array(0..<total)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        // 1) Copias exactas en cualquier fecha: mismo tamaño en píxeles y misma huella.
        var exact: [String: Int] = [:]
        for i in 0..<total {
            guard let h = hashes[i] else { continue }
            let key = "\(assets[i].pixelWidth)x\(assets[i].pixelHeight)-\(h)"
            if let j = exact[key] { union(i, j) } else { exact[key] = i }
        }
        // 2) Parecidas: tomadas con menos de 2 minutos de diferencia y casi la misma imagen (ráfagas).
        for i in 0..<total {
            guard let hi = hashes[i], let di = assets[i].creationDate else { continue }
            var j = i + 1
            while j < total, let dj = assets[j].creationDate, dj.timeIntervalSince(di) <= 120 {
                if let hj = hashes[j], (hi ^ hj).nonzeroBitCount <= 4 { union(i, j) }
                j += 1
            }
        }

        var buckets: [Int: [Int]] = [:]
        for i in 0..<total where hashes[i] != nil { buckets[find(i), default: []].append(i) }
        for (_, members) in buckets where members.count > 1 {
            let items = members.map { MediaItem(id: assets[$0].localIdentifier, asset: assets[$0], size: sizes[$0]) }
            // Conservar: favorita; si no, la de más resolución; si empatan, la más pesada.
            let keep = items.max { a, b in
                if a.asset.isFavorite != b.asset.isFavorite { return !a.asset.isFavorite }
                let pa = a.asset.pixelWidth * a.asset.pixelHeight, pb = b.asset.pixelWidth * b.asset.pixelHeight
                if pa != pb { return pa < pb }
                return a.size < b.size
            }!
            out.groups.append(SimilarGroup(id: keep.id, items: items, keepID: keep.id))
        }
        out.groups.sort { ($0.items.first?.date ?? .distantPast) > ($1.items.first?.date ?? .distantPast) }
        return out
    }

    /// Huella de 64 bits: compara el brillo de cada píxel con el de su derecha en una imagen de 9×8.
    static func dHash(_ image: CGImage) -> UInt64? {
        let w = 9, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hash: UInt64 = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                hash <<= 1
                if pixels[y * w + x] > pixels[y * w + x + 1] { hash |= 1 }
            }
        }
        return hash
    }
}

// MARK: - Vistas

struct Thumbnail: View {
    let asset: PHAsset
    var side: CGFloat = 120
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.08))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: asset.localIdentifier) {
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.isNetworkAccessAllowed = true
            let scale = UIScreen.main.scale
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side * scale, height: side * scale),
                                                  contentMode: .aspectFill, options: opts) { img, _ in
                if let img { self.image = img }
            }
        }
    }
}

struct PhotosView: View {
    @ObservedObject var model: PhotosModel
    @State private var category: PhotoCategory = .similar
    private let palette = Palette.cleanup

    var body: some View {
        ScrollArea {
            VStack(alignment: .leading, spacing: 20) {
                ModuleHeader(
                    title: "Limpiar Fotos",
                    subtitle: model.message ?? "Busca fotos repetidas y capturas viejas. Lo que borres va a «Eliminados recientemente» y se puede recuperar por 30 días.",
                    icon: "photo.on.rectangle.angled",
                    palette: palette
                )

                switch model.auth {
                case .denied, .restricted:
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cleaner no tiene permiso para ver tus fotos.").font(.headline)
                            Text("Actívalo en Ajustes › Apps › Cleaner › Fotos › Acceso completo.")
                                .foregroundStyle(.white.opacity(0.8))
                            Button("Abrir Ajustes") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                            .buttonStyle(PillButtonStyle(palette: palette))
                        }
                    }
                default:
                    if model.isScanning {
                        GlassCard(padding: 24) {
                            VStack(spacing: 12) {
                                ProgressView(value: model.progress).tint(palette.accentStart)
                                Text(model.progressText).font(.callout).foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    } else if model.lastScan == nil {
                        VStack(spacing: 16) {
                            BigCircleButton(title: "Revisar fotos", palette: palette) { Task { await model.scan() } }
                            Text("La primera vez puede tardar unos minutos si tienes muchas fotos.")
                                .font(.callout).foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        results
                    }
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            if model.lastScan != nil && !model.isScanning { deleteBar.padding(.horizontal, 24).padding(.bottom, 12) }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.auth == .limited {
                Text("Solo ves las fotos que compartiste con Cleaner. Para revisar todas: Ajustes › Apps › Cleaner › Fotos › Acceso completo.")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            HStack(spacing: 14) {
                ForEach(PhotoCategory.allCases) { cat in
                    Button { category = cat } label: {
                        GlassCard(padding: 14) {
                            HStack(spacing: 12) {
                                IconTile(icon: cat.icon, colors: palette.accentColors, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.title).font(.callout.weight(.semibold))
                                    Text("\(model.items(cat).count) · \(Format.bytes(model.size(cat, selectedOnly: false)))")
                                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                                }
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(category == cat ? 0.7 : 0), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text(category.detail).font(.callout).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button("Marcar todo") { model.setAll(category, on: true) }
                    .buttonStyle(PillButtonStyle())
                Button("Desmarcar") { model.setAll(category, on: false) }
                    .buttonStyle(PillButtonStyle())
            }

            if model.items(category).isEmpty {
                CenteredMessage(icon: "sparkles", title: "Nada por aquí", detail: "No hay nada que limpiar en esta categoría.")
                    .frame(height: 220)
            } else if category == .similar {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.groups) { group in
                        GlassCard(padding: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let date = group.items.first?.date {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(group.items) { item in
                                            tile(item, keep: item.id == group.keepID)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    ForEach(model.items(category)) { item in tile(item, keep: false) }
                }
            }

        }
    }

    private func tile(_ item: MediaItem, keep: Bool) -> some View {
        let isOn = model.selected.contains(item.id)
        return Button { model.toggle(item.id) } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Thumbnail(asset: item.asset, side: 130)
                        .opacity(isOn ? 0.55 : 1)
                    if isOn {
                        Image(systemName: "trash.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, Color(hex: 0xE0306B))
                            .padding(6)
                    } else if keep {
                        Text("Mejor")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(palette.accent, in: Capsule())
                            .padding(6)
                    }
                    if item.asset.mediaType == .video {
                        Text(durationText(item.asset.duration))
                            .font(.caption2.weight(.semibold))
                            .padding(4)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(6)
                            .frame(width: 130, height: 130, alignment: .bottomLeading)
                    }
                }
                Text(Format.bytes(item.size)).font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var deleteBar: some View {
        if !model.selected.isEmpty {
            HStack(spacing: 14) {
                Text("\(model.selected.count) marcadas · \(Format.bytes(model.selectedBytes))")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Volver a revisar") { Task { await model.scan() } }
                    .buttonStyle(PillButtonStyle())
                Button("Mover a Eliminados") { Task { await model.deleteSelected() } }
                    .buttonStyle(PillButtonStyle(destructive: true))
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
