import AppKit
import SwiftUI

/// Barra de proyectos bajo la foto: el proyecto abierto, sus acciones de lote y la tira de miniaturas.
struct ProjectStrip: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            if model.currentProject != nil {
                strip
            }
        }
        .background(Color(white: 0.09))
        .sheet(isPresented: $model.showingSync) { SyncSheet(model: model) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.projects) { project in
                    Button {
                        model.currentProjectID = project.id
                    } label: {
                        if project.id == model.currentProjectID { Label(project.name, systemImage: "checkmark") }
                        else { Text(project.name) }
                    }
                }
                if !model.projects.isEmpty { Divider() }
                Button("Nuevo proyecto…") { model.newProject() }
                if model.currentProject != nil {
                    Button("Renombrar…") { model.renameProject() }
                    Button("Usar los ajustes de esta foto como base") { model.useCurrentAsProjectBase() }
                        .disabled(model.photo == nil)
                    Button("Cerrar el proyecto") { model.currentProjectID = nil }
                    Divider()
                    Button("Eliminar el proyecto…", role: .destructive) { model.deleteProject() }
                }
            } label: {
                Label(model.currentProject?.name ?? "Proyectos", systemImage: "square.stack.3d.up")
            }
            .fixedSize()

            if let project = model.currentProject {
                Text("\(project.photos.count) fotos").font(.caption).foregroundStyle(.secondary)
                Menu {
                    Button("Fotos…") { model.addPhotosToProject(folders: false) }
                    Button("Carpeta…") { model.addPhotosToProject(folders: true) }
                } label: {
                    Label("Añadir", systemImage: "plus")
                }
                .fixedSize()
                Spacer()
                let count = model.selectedPhotos.count
                if count > 0 {
                    Text(count == 1 ? "1 marcada" : "\(count) marcadas").font(.caption).foregroundStyle(.secondary)
                }
                Button("Todas") { model.selectAllInProject() }
                Button {
                    model.showingSync = true
                } label: { Label("Sincronizar…", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(model.photo == nil || model.selectedPhotos.subtracting([model.photo?.url.path ?? ""]).isEmpty)
                    .help("Lleva los ajustes de la foto abierta a las marcadas (⌘ clic o ⇧ clic para marcar varias)")
                Button {
                    model.autoLightSelected()
                } label: { Label("Automático", systemImage: "wand.and.stars") }
                    .disabled(count == 0 || model.busy != nil)
                    .help("Luz automática en cada foto marcada")
                Button {
                    model.exportSelected()
                } label: { Label("Exportar…", systemImage: "square.and.arrow.up") }
                    .disabled(count == 0 || model.busy != nil)
                    .help("Exporta las marcadas, cada una con sus propios ajustes")
                Button {
                    model.removeSelectedFromProject()
                } label: { Image(systemName: "minus.circle") }
                    .disabled(count == 0)
                    .help("Quitar las marcadas del proyecto (las fotos no se borran)")
            } else {
                Text("Agrupa fotos en un proyecto para editarlas por lotes")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .controlSize(.small)
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 6) {
                    ForEach(model.projectPhotos, id: \.path) { url in
                        Thumb(url: url, image: model.thumbnails[url.path], open: model.photo?.url.path == url.path,
                              marked: model.selectedPhotos.contains(url.path),
                              edited: model.editsRevision >= 0 && EditStore.load(for: url) != nil)
                            .id(url.path)
                            .onTapGesture { model.clickThumbnail(url) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .frame(height: 96)
            .onChange(of: model.photo?.url.path) { path in
                if let path { withAnimation { proxy.scrollTo(path, anchor: .center) } }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async {
                            var isFolder: ObjCBool = false
                            FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
                            if isFolder.boolValue {
                                let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                                model.add(items.filter(EditorModel.isPhoto).sorted { $0.lastPathComponent < $1.lastPathComponent })
                            } else if EditorModel.isPhoto(url) {
                                model.add([url])
                            }
                        }
                    }
                }
                return true
            }
        }
    }
}

/// Una miniatura de la tira.
private struct Thumb: View {
    let url: URL
    let image: CGImage?
    let open: Bool
    let marked: Bool
    let edited: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(white: 0.18)
                }
            }
            .frame(width: 112, height: 76)
            .clipped()
            .overlay(marked && !open ? Color.accentColor.opacity(0.25) : .clear)
            if edited {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9, weight: .bold))
                    .padding(3)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                    .padding(3)
                    .help("Tiene ajustes")
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(open ? Color.white : marked ? Color.accentColor : .clear, lineWidth: open ? 2 : 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help(url.lastPathComponent)
    }
}

/// Elegir qué se sincroniza.
private struct SyncSheet: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sincronizar ajustes").font(.headline)
            let count = model.selectedPhotos.subtracting([model.photo?.url.path ?? ""]).count
            Text("Lleva los ajustes de «\(model.photo?.url.lastPathComponent ?? "")» a \(count == 1 ? "1 foto marcada" : "\(count) fotos marcadas"). Los clics de selección y de agua, los trazos de borrar y el enderezado son de cada foto y no se copian.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(SyncGroup.allCases) { group in
                Toggle(group.rawValue + (group == .sky ? " (experimental)" : ""), isOn: Binding(
                    get: { model.syncGroups.contains(group) },
                    set: { if $0 { model.syncGroups.insert(group) } else { model.syncGroups.remove(group) } }))
            }
            HStack {
                Button("Todo") { model.syncGroups = Set(SyncGroup.allCases) }
                Button("Nada") { model.syncGroups = [] }
                Spacer()
                Button("Cancelar") { model.showingSync = false }.keyboardShortcut(.cancelAction)
                Button("Sincronizar") {
                    model.syncSelected()
                    model.showingSync = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.syncGroups.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
