import AppKit
import SwiftUI

/// Estado de la ventana principal (en una clase porque `@State` necesita las macros de Xcode).
@MainActor
final class AppModel: ObservableObject {
    let store: LayoutStore

    // Ventana que se va a colocar
    struct WindowChoice: Identifiable {
        let id: Int
        let window: AXUIElement
        let label: String
        let icon: NSImage?
    }
    @Published var windows: [WindowChoice] = []
    @Published var selectedWindow: Int? {
        didSet { if let selectedWindow, let choice = windows.first(where: { $0.id == selectedWindow }) { setTarget(choice.window) } }
    }
    /// Mensaje breve bajo las pantallas (lo que acaba de pasar o lo que falta).
    @Published var message: String?
    /// Abierta con el atajo: se oculta tras colocar. Abierta desde el Dock: se queda para seguir colocando.
    var hideAfterPlacing = false
    @Published var showSidebar = UserDefaults.standard.bool(forKey: "showSidebar") {
        didSet { UserDefaults.standard.set(showSidebar, forKey: "showSidebar") }
    }
    @Published var target: AXUIElement?
    @Published var targetName = ""
    @Published var targetIcon: NSImage?
    @Published var targetFrame: CGRect?

    // Ajustes (se guardan al cambiar)
    @Published var grids = Settings.grids { didSet { Settings.grids = grids } }
    @Published var gap = Double(Settings.gap) { didSet { Settings.gap = CGFloat(gap) } }
    @Published var useWindowUnderMouse = Settings.useWindowUnderMouse { didSet { Settings.useWindowUnderMouse = useWindowUnderMouse } }
    @Published var showWallpaper = Settings.showWallpaper { didSet { Settings.showWallpaper = showWallpaper } }
    @Published var dragWithModifiers = Settings.dragWithModifiers {
        didSet { Settings.dragWithModifiers = dragWithModifiers; onDragSettingChanged?() }
    }

    // Grabar una distribución nueva / un atajo
    @Published var recording = false
    @Published var recordingShortcutFor: UUID? { didSet { onShortcutRecordingChanged?() } }
    /// Identificador especial para grabar el atajo de la cuadrícula.
    static let gridRecordingID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    @Published var gridShortcut = Settings.gridShortcut {
        didSet { Settings.gridShortcut = gridShortcut; onGridShortcutChanged?() }
    }
    /// Atajos que no se pudieron activar porque otra app o macOS ya los usa.
    @Published var shortcutProblem: String?
    var onGridShortcutChanged: (() -> Void)?
    @Published var trusted = WindowControl.isTrusted

    /// Selección en curso sobre una pantalla: índice de pantalla y celdas.
    @Published var selection: (screen: Int, c0: Int, r0: Int, c1: Int, r1: Int)?

    var onPlaced: (() -> Void)?
    var onDragSettingChanged: (() -> Void)?
    var onShortcutRecordingChanged: (() -> Void)?

    private var wallpapers: [CGDirectDisplayID: NSImage] = [:]

    init(store: LayoutStore) { self.store = store }

    /// Cuadrícula de una pantalla (6 × 4 si aún no se ha ajustado).
    func grid(for screen: NSScreen) -> (columns: Int, rows: Int) {
        let saved = grids[screen.stableID] ?? []
        return saved.count == 2 ? (saved[0], saved[1]) : (6, 4)
    }

    func columnsBinding(_ screen: NSScreen) -> Binding<Int> {
        Binding(get: { self.grid(for: screen).columns },
                set: { self.grids[screen.stableID] = [$0, self.grid(for: screen).rows] })
    }

    func rowsBinding(_ screen: NSScreen) -> Binding<Int> {
        Binding(get: { self.grid(for: screen).rows },
                set: { self.grids[screen.stableID] = [self.grid(for: screen).columns, $0] })
    }

    /// Vuelve a leer las ventanas abiertas y selecciona `preferred` (o la que ya estaba elegida).
    func refreshWindows(preferred: AXUIElement? = nil) {
        let keep = preferred ?? target
        windows = WindowControl.listWindows().enumerated().map { index, item in
            let title = item.title.isEmpty ? "" : " — \(item.title)"
            return WindowChoice(id: index, window: item.window, label: (item.app.localizedName ?? "App") + title,
                                icon: item.app.icon)
        }
        if let keep, let match = windows.first(where: { CFEqual($0.window, keep) }) {
            selectedWindow = match.id
        } else if let keep {
            setTarget(keep)
            selectedWindow = nil
        } else {
            selectedWindow = windows.first?.id
        }
    }

    func setTarget(_ window: AXUIElement?) {
        target = window
        message = nil
        targetFrame = window.flatMap(WindowControl.frame(of:))
        var pid: pid_t = 0
        if let window { AXUIElementGetPid(window, &pid) }
        let app = pid != 0 ? NSRunningApplication(processIdentifier: pid) : nil
        targetName = app?.localizedName ?? ""
        targetIcon = app?.icon
    }

    func wallpaper(for screen: NSScreen) -> NSImage? {
        guard showWallpaper, let id = screen.displayID else { return nil }
        if let cached = wallpapers[id] { return cached }
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen), let image = NSImage(contentsOf: url) else { return nil }
        wallpapers[id] = image
        return image
    }

    /// Termina un arrastre sobre la cuadrícula: guarda una distribución (modo Grabar) o coloca la ventana.
    func finishSelection(on screen: NSScreen, c0: Int, r0: Int, c1: Int, r1: Int) {
        selection = nil
        let grid = grid(for: screen)
        let layout = SavedLayout(name: "Distribución \(store.layouts.count + 1)", columns: grid.columns, rows: grid.rows,
                                 col0: c0, row0: r0, col1: c1, row1: r1, shortcut: nil)
        if recording {
            recording = false
            store.layouts.append(layout)
            return
        }
        guard let target = readyTarget() else { return }
        if Layout.place(target, in: layout.rect(in: screen.visibleFrame), of: screen) {
            message = "\(targetName) estaba en pantalla completa: saliendo y colocándola…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.targetFrame = WindowControl.frame(of: target)
                self?.message = "\(self?.targetName ?? "") colocada · \(screen.localizedName)"
            }
            return
        }
        placed(target, where: screen.localizedName)
    }

    func apply(_ layout: SavedLayout) {
        guard let target = readyTarget() else { return }
        Layout.apply(layout, to: target)
        placed(target, where: layout.name)
    }

    func perform(_ action: QuickAction) {
        guard let target = readyTarget() else { return }
        Layout.perform(action, on: target)
        placed(target, where: action.title)
    }

    /// La ventana elegida, o `nil` con un mensaje que explica qué falta.
    private func readyTarget() -> AXUIElement? {
        trusted = WindowControl.isTrusted
        guard trusted else {
            message = "Falta el permiso de Accesibilidad: actívalo en Ajustes del Sistema › Privacidad y seguridad › Accesibilidad."
            WindowControl.requestAccess()
            return nil
        }
        guard let target else {
            message = "Elige arriba la ventana que quieres colocar."
            NSSound.beep()
            return nil
        }
        return target
    }

    private func placed(_ target: AXUIElement, where place: String) {
        let before = targetFrame
        targetFrame = WindowControl.frame(of: target)
        if let now = targetFrame, let before, now.equalTo(before) {
            message = "\(targetName) no ha cambiado de tamaño ni de sitio: puede que la app no lo permita. Detalles en ~/Library/Logs/Lazo/lazo.log"
        } else {
            message = "\(targetName) colocada · \(place)"
        }
        if hideAfterPlacing {
            WindowControl.raise(target)
            onPlaced?()
        } else {
            WindowControl.raise(target, activate: false)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Identificador que se mantiene al desconectar y volver a conectar el monitor.
    var stableID: String {
        guard let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return localizedName }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var isPrimary: Bool { self == NSScreen.screens.first }
}

// MARK: - Vista principal

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: LayoutStore

    var body: some View {
        HStack(spacing: 0) {
            if model.showSidebar {
                Sidebar(model: model, store: store)
                    .frame(width: 270)
                Divider()
            }
            VStack(spacing: 0) {
                TargetHeader(model: model)
                Divider()
                ScreensArea(model: model)
                Divider()
                SettingsBar(model: model)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1000, minHeight: 580)
    }
}

private struct TargetHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if !model.trusted {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("Lazo necesita permiso de Accesibilidad para mover ventanas.")
                Spacer()
                Button("Dar permiso…") { WindowControl.requestAccess() }
            } else {
                Text("Ventana a colocar").foregroundStyle(.secondary)
                Picker("Ventana a colocar", selection: $model.selectedWindow) {
                    if model.windows.isEmpty { Text("No hay ventanas abiertas").tag(Int?.none) }
                    ForEach(model.windows) { choice in
                        HStack {
                            if let icon = choice.icon { Image(nsImage: icon) }
                            Text(choice.label)
                        }
                        .tag(Int?.some(choice.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 420)
                .help("Solo aparecen las ventanas del escritorio actual que no estén minimizadas ni ocultas")
                Button {
                    model.refreshWindows()
                } label: { Image(systemName: "arrow.clockwise") }
                .help("Volver a leer las ventanas abiertas")
                Spacer()
                if let frame = model.targetFrame {
                    Text("\(Int(frame.width)) × \(Int(frame.height))").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $model.showSidebar) { Label("Atajos", systemImage: "sidebar.left") }
                .toggleStyle(.button)
                .help("Muestra las zonas guardadas con su atajo de teclado")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: Pantallas

private struct ScreensArea: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        VStack(spacing: 12) {
            GeometryReader { geo in
                let spacing: CGFloat = 24, header: CGFloat = 34
                let ratios = screens.map { $0.frame.width / $0.frame.height }
                let height = min(geo.size.height - header,
                                 (geo.size.width - spacing * CGFloat(screens.count - 1)) / ratios.reduce(0, +))
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                        VStack(spacing: 8) {
                            ScreenHeader(model: model, screen: screen)
                                .frame(height: header - 8)
                            ScreenPreview(model: model, screen: screen, index: index)
                                .frame(width: height * ratios[index], height: height)
                        }
                        .frame(width: height * ratios[index])
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            if model.recording {
                Text("Dibuja la zona que quieres guardar arrastrando sobre la cuadrícula").font(.callout).foregroundStyle(.red)
            } else if let message = model.message {
                Text(message).font(.callout.weight(.medium)).multilineTextAlignment(.center)
            } else {
                Text("Arrastra sobre la cuadrícula de la pantalla donde quieras la ventana")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Nombre del monitor y su cuadrícula (columnas × filas).
private struct ScreenHeader: View {
    @ObservedObject var model: AppModel
    let screen: NSScreen

    var body: some View {
        let grid = model.grid(for: screen)
        HStack(spacing: 6) {
            Image(systemName: screen.localizedName.localizedCaseInsensitiveContains("built") ? "laptopcomputer" : "display")
                .foregroundStyle(.secondary)
            Text(screen.localizedName).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.tail)
            if screen.isPrimary {
                Text("principal").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
            }
            Spacer(minLength: 6)
            Text("\(grid.columns)").monospacedDigit()
            Stepper("Columnas", value: model.columnsBinding(screen), in: 1 ... 12).labelsHidden()
            Text("×").foregroundStyle(.secondary)
            Text("\(grid.rows)").monospacedDigit()
            Stepper("Filas", value: model.rowsBinding(screen), in: 1 ... 8).labelsHidden()
        }
        .controlSize(.small)
        .help("Columnas × filas de la cuadrícula de este monitor")
    }
}

private struct ScreenPreview: View {
    @ObservedObject var model: AppModel
    let screen: NSScreen
    let index: Int

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / screen.frame.width
            let f = screen.frame, vf = screen.visibleFrame
            let visible = CGRect(x: (vf.minX - f.minX) * k, y: (f.maxY - vf.maxY) * k, width: vf.width * k, height: vf.height * k)
            let grid = model.grid(for: screen)
            let cell = CGSize(width: visible.width / CGFloat(grid.columns), height: visible.height / CGFloat(grid.rows))

            ZStack(alignment: .topLeading) {
                // Fondo: el del escritorio o un degradado.
                if let wallpaper = model.wallpaper(for: screen) {
                    Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                } else {
                    LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                }
                // Barra de menú
                Rectangle().fill(.black.opacity(0.35)).frame(height: max(visible.minY, 3))

                Canvas { context, _ in
                    // Cuadrícula
                    for c in 0 ..< grid.columns {
                        for r in 0 ..< grid.rows {
                            let rect = CGRect(x: visible.minX + CGFloat(c) * cell.width, y: visible.minY + CGFloat(r) * cell.height,
                                              width: cell.width, height: cell.height).insetBy(dx: 2, dy: 2)
                            let path = Path(roundedRect: rect, cornerRadius: 4)
                            context.fill(path, with: .color(.white.opacity(0.10)))
                            context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1)
                        }
                    }
                    // Ventana actual
                    if let frame = model.targetFrame, screen.frame.intersects(frame) {
                        let rect = CGRect(x: (frame.minX - f.minX) * k, y: (f.maxY - frame.maxY) * k,
                                          width: frame.width * k, height: frame.height * k)
                        let path = Path(roundedRect: rect, cornerRadius: 5)
                        context.fill(path, with: .color(.white.opacity(0.18)))
                        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                    // Selección
                    if let s = model.selection, s.screen == index {
                        let rect = CGRect(x: visible.minX + CGFloat(min(s.c0, s.c1)) * cell.width,
                                          y: visible.minY + CGFloat(min(s.r0, s.r1)) * cell.height,
                                          width: CGFloat(abs(s.c1 - s.c0) + 1) * cell.width,
                                          height: CGFloat(abs(s.r1 - s.r0) + 1) * cell.height).insetBy(dx: 2, dy: 2)
                        let path = Path(roundedRect: rect, cornerRadius: 6)
                        let tint: Color = model.recording ? .red : .accentColor
                        context.fill(path, with: .color(tint.opacity(0.45)))
                        context.stroke(path, with: .color(tint), lineWidth: 2.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.2)))
            .shadow(radius: 6, y: 3)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let start = cellAt(value.startLocation, visible: visible, cell: cell, grid: grid)
                let now = cellAt(value.location, visible: visible, cell: cell, grid: grid)
                model.selection = (index, start.c, start.r, now.c, now.r)
            }.onEnded { value in
                let start = cellAt(value.startLocation, visible: visible, cell: cell, grid: grid)
                let end = cellAt(value.location, visible: visible, cell: cell, grid: grid)
                model.finishSelection(on: screen, c0: min(start.c, end.c), r0: min(start.r, end.r),
                                      c1: max(start.c, end.c), r1: max(start.r, end.r))
            })
        }
    }

    private func cellAt(_ p: CGPoint, visible: CGRect, cell: CGSize, grid: (columns: Int, rows: Int)) -> (c: Int, r: Int) {
        (min(max(Int((p.x - visible.minX) / cell.width), 0), grid.columns - 1),
         min(max(Int((p.y - visible.minY) / cell.height), 0), grid.rows - 1))
    }
}

// MARK: Barra lateral

private struct Sidebar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: LayoutStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Zonas con atajo").font(.headline)
                Text("Colocan la ventana con una combinación de teclas, sin abrir Lazo.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding([.horizontal, .top], 14)
            HStack {
                Spacer()
                Button {
                    model.recording.toggle()
                } label: {
                    Label(model.recording ? "Grabando…" : "Grabar", systemImage: "record.circle")
                }
                .tint(model.recording ? .red : nil)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Dibuja una zona en la cuadrícula para guardarla como distribución")
            }
            .padding(14)

            if store.layouts.isEmpty {
                Text("No hay zonas guardadas.\n\nPulsa «Grabar» y dibuja una zona.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.layouts) { layout in
                            LayoutRow(model: model, store: store, layout: layout)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Acciones rápidas").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(QuickAction.allCases) { action in
                        Button { model.perform(action) } label: {
                            VStack(spacing: 2) {
                                Image(systemName: action.symbol).font(.title3)
                                Text(action.title).font(.caption)
                                Text(action.shortcut.display).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(14)
        }
        .background(.regularMaterial)
    }
}

private struct LayoutRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: LayoutStore
    let layout: SavedLayout

    private var index: Int? { store.layouts.firstIndex { $0.id == layout.id } }

    var body: some View {
        HStack(spacing: 10) {
            // Miniatura de la zona
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.18))
                GeometryReader { geo in
                    let u = layout.unitRect
                    RoundedRectangle(cornerRadius: 3).fill(Color.accentColor)
                        .frame(width: max(2, u.width * geo.size.width - 3), height: max(2, u.height * geo.size.height - 3))
                        .offset(x: u.minX * geo.size.width + 1.5, y: u.minY * geo.size.height + 1.5)
                }
            }
            .frame(width: 52, height: 33)

            TextField("Nombre", text: Binding(
                get: { layout.name },
                set: { if let i = index { store.layouts[i].name = $0 } }))
                .textFieldStyle(.plain)
                .font(.callout)

            Spacer(minLength: 4)
            Button {
                model.recordingShortcutFor = model.recordingShortcutFor == layout.id ? nil : layout.id
            } label: {
                Text(model.recordingShortcutFor == layout.id ? "Pulsa…" : (layout.shortcut?.display ?? "Atajo"))
                    .font(.caption.monospaced())
                    .frame(minWidth: 52)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(model.recordingShortcutFor == layout.id ? .red : nil)
            .help("Pulsa y escribe la combinación de teclas (Esc cancela, ⌫ la quita)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.apply(layout) }
        .help("Doble clic para aplicarla a la ventana")
        .contextMenu {
            Button("Aplicar") { model.apply(layout) }
            Button("Quitar atajo") { if let i = index { store.layouts[i].shortcut = nil } }
            Divider()
            Button("Eliminar", role: .destructive) { store.layouts.removeAll { $0.id == layout.id } }
        }
    }
}

// MARK: Ajustes

private struct SettingsBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                HStack(spacing: 6) {
                    Text("Separación").fixedSize()
                    Slider(value: $model.gap, in: 0 ... 32, step: 2).frame(width: 120)
                    Text("\(Int(model.gap)) pt").monospacedDigit().frame(width: 40, alignment: .leading)
                }
                Picker("Los atajos colocan", selection: $model.useWindowUnderMouse) {
                    Text("la ventana activa").tag(false)
                    Text("la ventana bajo el ratón").tag(true)
                }
                .fixedSize()
                Spacer(minLength: 0)
            }
            HStack(spacing: 24) {
                Toggle("Arrastrar ventanas con ⌃⌥ (mover) y ⌃⌥⇧ (tamaño)", isOn: $model.dragWithModifiers)
                Toggle("Fondo de escritorio", isOn: $model.showWallpaper)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text("Cuadrícula sobre la ventana bajo el ratón:")
                Button {
                    model.recordingShortcutFor = model.recordingShortcutFor == AppModel.gridRecordingID ? nil : AppModel.gridRecordingID
                } label: {
                    Text(model.recordingShortcutFor == AppModel.gridRecordingID ? "Pulsa el atajo…" : model.gridShortcut.display)
                        .font(.callout.monospaced()).frame(minWidth: 70)
                }
                .tint(model.recordingShortcutFor == AppModel.gridRecordingID ? .red : nil)
                .help("Pulsa y escribe la combinación (con Control, Opción o Comando). Esc cancela.")
                Text("(\(model.gridShortcut.words))").foregroundStyle(.secondary)
                Text("· Abrir Lazo: ⌃⌥⌘Espacio").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if let problem = model.shortcutProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .lineLimit(1)
        .controlSize(.small)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
