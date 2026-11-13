import AppKit
import SwiftUI
import Combine

/// Estado compartido entre el lienzo y las barras flotantes.
final class CanvasState: ObservableObject {
    @Published var tool: Tool = .select
    @Published var shapeKind: ShapeKind = .rounded
    @Published var shapeColor = "AFD6FF"
    @Published var noteColor = "FFE98A"
    @Published var penColor = "1F2329"
    @Published var penWidth: CGFloat = 3
    @Published var zoom: CGFloat = 1
    @Published var selectionCount = 0
    @Published var canUndo = false
    @Published var canRedo = false
    weak var canvas: CanvasView?
}

final class BoardWindowController: NSWindowController, NSWindowDelegate {
    convenience init(board: BoardDocument) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 420)
        window.tabbingMode = .preferred
        // El tablero es claro, como el papel: las barras también.
        window.appearance = NSAppearance(named: .aqua)
        window.center()
        self.init(window: window)
        shouldCascadeWindows = true
        window.contentView = BoardContainerView(document: board)
        window.delegate = self
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        (document as? BoardDocument)?.canvas?.endEditing()
        return true
    }
}

/// El lienzo con las barras flotantes encima.
final class BoardContainerView: NSView {
    let canvas: CanvasView

    init(document: BoardDocument) {
        let state = CanvasState()
        canvas = CanvasView(document: document, state: state)
        super.init(frame: NSRect(x: 0, y: 0, width: 1280, height: 820))
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)

        tools = host(ToolbarView(state: state))
        options = host(ToolOptionsView(state: state))
        selectionBar = host(SelectionBar(state: state))
        zoomBar = host(ZoomBar(state: state))
        // Las barras cambian de tamaño según la herramienta y la selección: se recolocan a mano.
        watcher = state.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsLayout = true }
        }
    }

    private var tools: NSView!
    private var options: NSView!
    private var selectionBar: NSView!
    private var zoomBar: NSView!
    private var watcher: AnyCancellable?

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    private func host<V: View>(_ view: V) -> NSView {
        let h = NSHostingView(rootView: view)
        h.sizingOptions = [.intrinsicContentSize]
        addSubview(h)
        return h
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        canvas.frame = bounds
        func size(_ v: NSView) -> CGSize { v.intrinsicContentSize }
        let t = size(tools)
        tools.frame = CGRect(x: 2, y: ((bounds.height - t.height) / 2).rounded(), width: t.width, height: t.height)
        let o = size(options)
        options.frame = CGRect(x: tools.frame.maxX - 6, y: tools.frame.minY, width: o.width, height: o.height)
        let s = size(selectionBar)
        selectionBar.frame = CGRect(x: ((bounds.width - s.width) / 2).rounded(), y: 2, width: s.width, height: s.height)
        let z = size(zoomBar)
        zoomBar.frame = CGRect(x: bounds.width - z.width - 2, y: bounds.height - z.height - 2, width: z.width, height: z.height)
    }
}

// MARK: - Barras flotantes

private struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(10)
    }
}

private struct IconButton: View {
    let symbol: String
    var active = false
    var enabled = true
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
                .foregroundStyle(active ? Color.accentColor : (enabled ? Color.primary : Color.secondary.opacity(0.5)))
                .background(active ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

struct ToolbarView: View {
    @ObservedObject var state: CanvasState

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Tool.allCases) { t in
                IconButton(symbol: t.symbol, active: state.tool == t, help: "\(t.title) (\(t.key.uppercased()))") {
                    state.canvas?.selectTool(t)
                }
            }
            Divider().frame(width: 28).padding(.vertical, 4)
            IconButton(symbol: "arrow.uturn.backward", enabled: state.canUndo, help: "Deshacer (⌘Z)") {
                state.canvas?.undoAction(nil)
            }
            IconButton(symbol: "arrow.uturn.forward", enabled: state.canRedo, help: "Rehacer (⇧⌘Z)") {
                state.canvas?.redoAction(nil)
            }
        }
        .modifier(Panel())
    }
}

struct ToolOptionsView: View {
    @ObservedObject var state: CanvasState

    var body: some View {
        if state.tool == .shape {
            HStack(spacing: 2) {
                ForEach(ShapeKind.allCases) { k in
                    IconButton(symbol: k.symbol, active: state.shapeKind == k, help: k.title) { state.shapeKind = k }
                }
            }
            .modifier(Panel())
        } else if state.tool == .pen {
            HStack(spacing: 6) {
                ForEach(Palette.ink) { sw in
                    Swatch(hex: sw.hex, selected: state.penColor == sw.hex, help: sw.name) { state.penColor = sw.hex }
                }
                Divider().frame(height: 22)
                ForEach([CGFloat(2), 4, 8], id: \.self) { w in
                    Button { state.penWidth = w } label: {
                        Capsule().fill(Color.primary).frame(width: 18, height: w)
                            .frame(width: 28, height: 28)
                            .background(state.penWidth == w ? Color.accentColor.opacity(0.16) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Grosor \(Int(w))")
                }
            }
            .padding(.horizontal, 4)
            .modifier(Panel())
        } else if state.tool == .note {
            HStack(spacing: 6) {
                ForEach(Palette.colors.prefix(8)) { sw in
                    Swatch(hex: sw.hex, selected: state.noteColor == sw.hex, help: sw.name) { state.noteColor = sw.hex }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .modifier(Panel())
        }
    }
}

private struct Swatch: View {
    let hex: String
    var selected = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: NSColor(hex: hex)))
                .overlay(Circle().strokeBorder(.black.opacity(0.18)))
                .frame(width: 20, height: 20)
                .padding(2)
                .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SelectionBar: View {
    @ObservedObject var state: CanvasState

    var body: some View {
        if state.selectionCount > 0 {
            HStack(spacing: 4) {
                ForEach(Palette.colors) { sw in
                    Swatch(hex: sw.hex, help: sw.name) { state.canvas?.applyColor(sw.hex) }
                }
                Divider().frame(height: 22).padding(.horizontal, 2)
                if state.tool == .select, let canvas = state.canvas, canvasHasShape(canvas) {
                    Menu {
                        ForEach(ShapeKind.allCases) { k in
                            Button(k.title) { canvas.setShape(k) }
                        }
                    } label: {
                        Image(systemName: "square.on.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Cambiar figura")
                }
                IconButton(symbol: "textformat.size.smaller", help: "Letra más pequeña") { state.canvas?.changeFontSize(by: 0.85) }
                IconButton(symbol: "textformat.size.larger", help: "Letra más grande") { state.canvas?.changeFontSize(by: 1.18) }
                IconButton(symbol: "square.3.layers.3d.top.filled", help: "Traer al frente (⌘])") { state.canvas?.bringToFront(nil) }
                IconButton(symbol: "square.3.layers.3d.bottom.filled", help: "Enviar al fondo (⌘[)") { state.canvas?.sendToBack(nil) }
                IconButton(symbol: "plus.square.on.square", help: "Duplicar (⌘D)") { state.canvas?.duplicateSelection(nil) }
                IconButton(symbol: "trash", help: "Eliminar (⌫)") { state.canvas?.delete(nil) }
            }
            .padding(.horizontal, 4)
            .modifier(Panel())
        }
    }

    private func canvasHasShape(_ canvas: CanvasView) -> Bool {
        canvas.items.contains { canvas.selection.contains($0.id) && $0.kind == .shape }
    }
}

struct ZoomBar: View {
    @ObservedObject var state: CanvasState

    private var label: String {
        let pct = state.zoom * 100
        return pct < 1 ? "<1 %" : "\(Int(pct.rounded())) %"
    }

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Ajustar a la pantalla (⌘1)") {
                state.canvas?.zoomFit(nil)
            }
            IconButton(symbol: "minus", help: "Alejar (⌘−)") { state.canvas?.zoomOut(nil) }
            Menu {
                ForEach([25, 50, 100, 150, 200, 400], id: \.self) { p in
                    Button("\(p) %") { state.canvas?.setZoom(CGFloat(p) / 100) }
                }
                Divider()
                Button("Ajustar a la pantalla") { state.canvas?.zoomFit(nil) }
            } label: {
                Text(label).monospacedDigit().font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 58)
            .help("Nivel de zoom")
            IconButton(symbol: "plus", help: "Acercar (⌘+)") { state.canvas?.zoomIn(nil) }
        }
        .modifier(Panel())
    }
}

