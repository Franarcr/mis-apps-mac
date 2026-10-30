import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 0) {
            canvas
            Divider()
            sidebar.frame(width: 300)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(white: 0.11))
        .environment(\.colorScheme, .dark)
    }

    // MARK: Foto

    private var canvas: some View {
        ZStack {
            Color(white: 0.07)
            if let image = model.showOriginal ? model.original : model.rendered {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(24)
            } else if model.busy == nil {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 54, weight: .light))
                    Text("Arrastra una foto aquí").font(.title3.weight(.medium))
                    Button("Abrir una foto…") { model.chooseFile() }.buttonStyle(.borderedProminent)
                    Text("JPEG, HEIC, PNG, TIFF y RAW de cámara").font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            VStack {
                toolbar
                Spacer()
                statusBar
            }
            .padding(12)
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor, lineWidth: 3).padding(8)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { model.open(url) } }
            }
            return true
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { model.chooseFile() } label: { Label("Abrir", systemImage: "folder") }
            if model.photo != nil {
                Button { model.showOriginal.toggle() } label: {
                    Label(model.showOriginal ? "Viendo el original" : "Antes", systemImage: "rectangle.split.2x1")
                }
                .tint(model.showOriginal ? .orange : nil)
                Button { model.undo() } label: { Label("Deshacer", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                Button { model.reset() } label: { Label("Restablecer", systemImage: "arrow.counterclockwise") }
                Spacer()
                Button { model.export() } label: { Label("Exportar", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent)
            } else {
                Spacer()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let busy = model.busy {
                ProgressView().controlSize(.small)
                Text(busy)
            } else if let status = model.status {
                Text(status)
            }
            Spacer()
            if let photo = model.photo { Text(photo.url.lastPathComponent).lineLimit(1).truncationMode(.middle) }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.35), in: Capsule())
    }

    // MARK: Ajustes

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Inteligencia artificial", icon: "sparkles") {
                    Toggle("Mejora automática", isOn: $model.adjustments.autoEnhance).toggleStyle(.switch)
                    HStack {
                        Button("Enderezar horizonte") { model.straightenHorizon() }
                        Spacer()
                    }
                    slider("Enderezar", \.straighten, -15...15, format: "%.1f°")
                    slider("Desenfocar fondo", \.backgroundBlur, 0...100)
                    if model.depthInstalled {
                        slider("Desenfoque de lente", \.lensBlur, 0...100)
                    } else {
                        Button("Descargar desenfoque de lente (50 MB)…") { model.installDepthModel() }
                            .help("Modelo Depth Anything V2 de Apple: calcula la distancia de cada punto de la foto.")
                    }
                    slider("Luz del sujeto", \.subjectLight, -100...100)
                    slider("Luz del fondo", \.backgroundLight, -100...100)
                    Text("Usa la IA de macOS, sin internet: detecta personas, animales y objetos principales.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                section("Retrato", icon: "face.smiling") {
                    slider("Suavizar piel", \.skinSmoothing, 0...100)
                    slider("Ojos", \.eyes, 0...100)
                    slider("Dientes", \.teeth, 0...100)
                }
                section("Luz", icon: "sun.max") {
                    slider("Exposición", \.exposure, -3...3, format: "%+.2f")
                    slider("Contraste", \.contrast, -100...100)
                    slider("Luces", \.highlights, -100...100)
                    slider("Sombras", \.shadows, -100...100)
                    slider("Blancos", \.whites, -100...100)
                    slider("Negros", \.blacks, -100...100)
                }
                section("Color", icon: "paintpalette") {
                    slider("Temperatura", \.temperature, -100...100)
                    slider("Tinte", \.tint, -100...100)
                    slider("Intensidad", \.vibrance, -100...100)
                    slider("Saturación", \.saturation, -100...100)
                }
                section("Detalle", icon: "camera.aperture") {
                    slider("Claridad", \.clarity, 0...100)
                    slider("Nitidez", \.sharpness, 0...100)
                    slider("Viñeta", \.vignette, 0...100)
                }
                section("Looks", icon: "camera.filters") { looks }
                section("Exportar", icon: "square.and.arrow.up") {
                    Picker("Formato", selection: $model.exportFormat) {
                        ForEach(Exporter.Format.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if model.exportFormat == .jpeg || model.exportFormat == .heic {
                        HStack {
                            Text("Calidad")
                            Slider(value: $model.exportQuality, in: 0.5...1)
                            Text("\(Int(model.exportQuality * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                    Button("Aplicar estos ajustes a varias fotos…") { model.exportBatch() }
                }
            }
            .padding(16)
            .disabled(model.photo == nil)
            .opacity(model.photo == nil ? 0.5 : 1)
        }
        .font(.callout)
    }

    private var looks: some View {
        VStack(alignment: .leading, spacing: 10) {
            let all = [Looks.Look(id: "", name: "Ninguno")] + Looks.builtIn + model.importedLooks
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 6)], spacing: 6) {
                ForEach(all) { look in
                    let selected = (model.adjustments.look ?? "") == look.id
                    Button {
                        model.adjustments.look = look.id.isEmpty ? nil : look.id
                    } label: {
                        Text(look.name)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.adjustments.look != nil { slider("Intensidad del look", \.lookAmount, 0...100) }
            Button("Importar LUT .cube…") { model.importCube() }
        }
    }

    // MARK: Piezas

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Control deslizante. Doble clic en el nombre lo devuelve a su valor inicial.
    private func slider(_ title: String, _ key: WritableKeyPath<Adjustments, Double>, _ range: ClosedRange<Double>,
                        format: String = "%.0f") -> some View {
        let value = model.adjustments[keyPath: key]
        let neutral = Adjustments.neutral[keyPath: key]
        return VStack(spacing: 2) {
            HStack {
                Text(title).foregroundStyle(value == neutral ? .secondary : .primary)
                    .onTapGesture(count: 2) { model.adjustments[keyPath: key] = neutral }
                    .help("Doble clic para restablecer")
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { model.adjustments[keyPath: key] },
                                  set: { model.adjustments[keyPath: key] = $0 }), in: range)
                .controlSize(.small)
        }
    }
}
