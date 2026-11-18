import SwiftUI

@main
struct CleanerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case status, photos, largeFiles, duplicates, speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Estado"
        case .photos: "Limpiar Fotos"
        case .largeFiles: "Archivos grandes"
        case .duplicates: "Duplicados"
        case .speed: "Velocidad de internet"
        }
    }

    var icon: String {
        switch self {
        case .status: "gauge.with.dots.needle.67percent"
        case .photos: "photo.on.rectangle.angled"
        case .largeFiles: "doc.text.magnifyingglass"
        case .duplicates: "doc.on.doc"
        case .speed: "wifi"
        }
    }

    var palette: Palette {
        switch self {
        case .status: .status
        case .photos: .cleanup
        case .largeFiles: .largeFiles
        case .duplicates: .duplicates
        case .speed: .speed
        }
    }
}

struct RootView: View {
    @State private var section: AppSection? = .status
    @StateObject private var status = StatusModel()
    @StateObject private var photos = PhotosModel()
    @StateObject private var files = FilesModel()
    @StateObject private var speed = SpeedTestModel()

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { item in
                NavigationLink(value: item) {
                    HStack(spacing: 12) {
                        IconTile(icon: item.icon, colors: item.palette.accentColors, size: 30)
                        Text(item.title)
                            .font(.body.weight(.medium))
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Cleaner")
        } detail: {
            let current = section ?? .status
            ZStack {
                current.palette.background.ignoresSafeArea()
                detail(for: current)
                    .foregroundStyle(.white)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .status: StatusView(model: status, photos: photos, go: { self.section = $0 })
        case .photos: PhotosView(model: photos)
        case .largeFiles: LargeFilesView(model: files)
        case .duplicates: DuplicatesView(model: files)
        case .speed: SpeedTestView(model: speed)
        }
    }
}
