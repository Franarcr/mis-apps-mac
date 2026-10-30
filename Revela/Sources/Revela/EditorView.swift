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
                GeometryReader { geo in
                    let rect = fitted(CGSize(width: image.width, height: image.height), in: geo.size, margin: 24)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .overlay(strokeOverlay(in: rect.size))
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in
                            let point = SelectionPoint(x: tap.location.x / rect.width, y: 1 - tap.location.y / rect.height,
                                                       include: !NSEvent.modifierFlags.contains(.option))
                            if model.selecting { model.adjustments.selection.append(point) }
                            if model.markingWater { model.adjustments.water.append(point) }
                        })
                        .simultaneousGesture(DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard model.erasing else { return }
                                model.currentStroke.append(drag.location)
                            }
                            .onEnded { _ in
                                guard model.erasing else { return }
                                let points = model.currentStroke.map {
                                    SelectionPoint(x: $0.x / rect.width, y: 1 - $0.y / rect.height)
                                }
                                model.currentStroke = []
                                model.addEraseStroke(points)
                            })
                        .position(x: rect.midX, y: rect.midY)
                }
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
                if model.erasing {
                    Text("Pinta sobre lo que quieras borrar")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.red.opacity(0.85), in: Capsule())
                }
                if model.markingWater {
                    Text("Haz clic en el agua (mar, lago, río…) · ⌥ clic para quitar una zona")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.blue.opacity(0.85), in: Capsule())
                }
                if model.selecting {
                    Text("Haz clic en lo que quieras seleccionar · ⌥ clic para quitar una zona")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.85), in: Capsule())
                }
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
                section("Borrar objetos", icon: "eraser") { eraseControls }
                section("Selección con un clic", icon: "hand.point.up.left") { selectionControls }
                section("Cielo", icon: "cloud.sun") { skyControls }
                section("Agua", icon: "water.waves") { waterControls }
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
                    if model.upscaleInstalled {
                        Picker("Tamaño", selection: $model.exportUpscale) {
                            Text("Original").tag(1)
                            Text("×2 con IA").tag(2)
                            Text("×4 con IA").tag(4)
                        }
                        if model.exportUpscale > 1, let photo = model.photo {
                            let w = Int(photo.fullSize.width) * model.exportUpscale, h = Int(photo.fullSize.height) * model.exportUpscale
                            let mp = Double(w * h) / 1_000_000
                            Text("\(w) × \(h)" + String(format: " · %.0f MP", mp) + (mp > UpscaleModel.maxOutputMegapixels ? " · demasiado grande" : ""))
                                .font(.caption).foregroundStyle(mp > UpscaleModel.maxOutputMegapixels ? .orange : .secondary)
                        }
                    } else {
                        Button("Descargar ampliación con IA (67 MB)…") { model.installUpscaleModel() }
                            .help("Modelo Real-ESRGAN (licencia BSD): amplía ×2 o ×4 recuperando detalle.")
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

    /// El trazo que se está pintando (en rojo), en coordenadas de la foto en pantalla.
    private func strokeOverlay(in size: CGSize) -> some View {
        Path { path in
            guard let first = model.currentStroke.first else { return }
            path.move(to: first)
            model.currentStroke.dropFirst().forEach { path.addLine(to: $0) }
        }
        .stroke(Color.red.opacity(0.55), style: StrokeStyle(lineWidth: max(2, size.width * model.brushSize / 100),
                                                             lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
    }

    @ViewBuilder private var eraseControls: some View {
        if model.eraseInstalled {
            HStack {
                Toggle(model.erasing ? "Pintando…" : "Pincel", isOn: $model.erasing)
                    .toggleStyle(.button)
                    .tint(.red)
                if !model.adjustments.erase.isEmpty {
                    Button("Deshacer trazo") { model.undoEraseStroke() }
                    Button("Quitar todo") { model.clearErase() }
                }
            }
            HStack {
                Text("Tamaño")
                Slider(value: $model.brushSize, in: 0.5...12)
                Text(String(format: "%.0f", model.brushSize)).monospacedDigit().frame(width: 24, alignment: .trailing)
            }
            Text("Pinta sobre personas, cables, manchas o cualquier cosa; se rellena con lo que debería haber detrás.")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button("Descargar borrado de objetos (217 MB)…") { model.installEraseModel() }
                Text("Modelo LaMa (licencia Apache 2.0): rellena lo que pintes con lo que debería haber detrás.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var downloadSegmentButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Descargar selección inteligente (94 MB)…") { model.installSegmentModel() }
            Text("Modelo SAM 2.1 de Apple: selecciona cualquier cosa con un clic y encuentra el cielo.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var selectionControls: some View {
        if model.segmentInstalled {
            HStack {
                Toggle(model.selecting ? "Seleccionando…" : "Seleccionar", isOn: $model.selecting)
                    .toggleStyle(.button)
                    .tint(.orange)
                if !model.adjustments.selection.isEmpty {
                    Button("Deshacer clic") { model.undoSelectionClick() }
                    Button("Quitar") { model.clearSelection() }
                }
            }
            if model.adjustments.selection.isEmpty {
                Text("Pulsa «Seleccionar» y haz clic en una persona, el agua, un edificio… para ajustar solo esa zona.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                slider("Exposición", \.selExposure, -100...100)
                slider("Contraste", \.selContrast, -100...100)
                slider("Saturación", \.selSaturation, -100...100)
                slider("Temperatura", \.selTemperature, -100...100)
            }
        } else {
            downloadSegmentButton
        }
    }

    @ViewBuilder private var skyControls: some View {
        if model.segmentInstalled {
            slider("Luz del cielo", \.skyLight, -100...100)
            slider("Realzar cielo", \.skyEnhance, 0...100)
            Text("Cambiar cielo").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 6)], spacing: 6) {
                ForEach([Skies.Sky(id: "", name: "Original")] + Skies.builtIn) { sky in
                    chip(sky.name, selected: (model.adjustments.skyReplacement ?? "") == sky.id) {
                        model.adjustments.skyReplacement = sky.id.isEmpty ? nil : sky.id
                    }
                }
            }
            if let custom = model.adjustments.skyReplacement, !Skies.builtIn.contains(where: { $0.id == custom }) {
                Text("Cielo: \(Skies.name(of: custom))").font(.caption)
            }
            Button("Usar una foto de cielo…") { model.chooseSkyPhoto() }
            if model.adjustments.skyReplacement != nil { slider("Intensidad del cielo", \.skyAmount, 0...100) }
        } else {
            downloadSegmentButton
        }
    }

    @ViewBuilder private var waterControls: some View {
        if model.segmentInstalled {
            HStack {
                Toggle(model.markingWater ? "Marcando…" : "Marcar el agua", isOn: $model.markingWater)
                    .toggleStyle(.button)
                    .tint(.blue)
                if !model.adjustments.water.isEmpty {
                    Button("Deshacer clic") { model.undoWaterClick() }
                    Button("Quitar") { model.clearWater() }
                }
            }
            if model.adjustments.water.isEmpty {
                Text("Pulsa «Marcar el agua» y haz clic en el mar, el lago o el río para que haga juego con el cielo.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                slider("Color del cielo en el agua", \.waterTint, 0...100)
                slider("Reflejo del cielo", \.waterReflection, 0...100)
                slider("Luz del agua", \.waterLight, -100...100)
            }
        } else {
            downloadSegmentButton
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
    }

    /// Rectángulo donde se dibuja la foto, centrada y entera dentro del espacio disponible.
    private func fitted(_ size: CGSize, in area: CGSize, margin: CGFloat) -> CGRect {
        let w = max(area.width - margin * 2, 1), h = max(area.height - margin * 2, 1)
        let s = min(w / size.width, h / size.height)
        let fit = CGSize(width: size.width * s, height: size.height * s)
        return CGRect(x: (area.width - fit.width) / 2, y: (area.height - fit.height) / 2, width: fit.width, height: fit.height)
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
