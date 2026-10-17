import AppKit
import SwiftUI

extension NSScreen {
    static var underMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main ?? screens[0]
    }
}

/// Panel tipo Spotlight: recibe el teclado sin activar la app, así el pegado va a la app de antes.
final class HistoryPanel: NSPanel, NSWindowDelegate {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    // Clic fuera del panel → se cierra.
    func windowDidResignKey(_ notification: Notification) { orderOut(nil) }
}

@MainActor
final class HistoryController {
    private let store: ClipStore
    private let panel = HistoryPanel()

    init(store: ClipStore) { self.store = store }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        let view = HistoryView(store: store, model: HistoryModel(),
                               onPaste: { [weak self] in self?.paste($0) },
                               onClose: { [weak self] in self?.hide() })
        panel.contentView = NSHostingView(rootView: view)
        let vf = NSScreen.underMouse.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2 + 60))
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }

    private func paste(_ item: ClipItem) {
        store.copy(item)
        hide()
        Paster.paste()
    }
}

/// Estado del panel (en una clase porque `@State` necesita las macros de Xcode).
final class HistoryModel: ObservableObject {
    @Published var query = ""
    @Published var selected = 0
}

struct HistoryView: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var model: HistoryModel
    let onPaste: (ClipItem) -> Void
    let onClose: () -> Void

    @FocusState private var searchFocused: Bool

    private var query: String { model.query }
    private var selected: Int {
        get { model.selected }
        nonmutating set { model.selected = newValue }
    }

    private var filtered: [ClipItem] {
        let ordered = store.items.filter(\.pinned) + store.items.filter { !$0.pinned }
        guard !query.isEmpty else { return ordered }
        return ordered.filter {
            $0.text.localizedStandardContains(query) || ($0.sourceApp?.localizedStandardContains(query) ?? false)
        }
    }

    private var current: ClipItem? {
        let list = filtered
        return list.indices.contains(selected) ? list[selected] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar en el historial", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .onChange(of: query) { selected = 0 }
                .onSubmit { if let current { onPaste(current) } }
                .onExitCommand(perform: onClose)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { onClose(); return .handled }
                .onKeyPress(keys: [.delete], phases: .down) { press in
                    guard press.modifiers.contains(.command), let current else { return .ignored }
                    store.remove(current)
                    selected = min(selected, max(filtered.count - 1, 0))
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "p123456789"), phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    if press.characters == "p" {
                        if let current { store.togglePin(current) }
                    } else if let n = Int(press.characters), filtered.indices.contains(n - 1) {
                        onPaste(filtered[n - 1])
                    }
                    return .handled
                }
        }
        .padding(14)
    }

    @ViewBuilder
    private var list: some View {
        let items = filtered
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.largeTitle).foregroundStyle(.tertiary)
                Text(query.isEmpty ? "El historial está vacío. Copia algo con ⌘C." : "Sin resultados")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selected) {
                    if let id = current?.id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(_ item: ClipItem, index: Int) -> some View {
        ClipRow(item: item, index: index, selected: index == selected, thumbnail: store.thumbnail(item))
            .id(item.id)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onPaste(item) }
            .onTapGesture { selected = index }
            .contextMenu {
                Button("Pegar") { onPaste(item) }
                Button("Copiar") { store.copy(item); onClose() }
                Button(item.pinned ? "Desfijar" : "Fijar") { store.togglePin(item) }
                Divider()
                Button("Eliminar", role: .destructive) { store.remove(item) }
            }
    }

    private var footer: some View {
        HStack {
            Text("↩ pegar   ⌘1–9 pegar directo   ⌘P fijar   ⌘⌫ eliminar   esc cerrar")
            Spacer()
            Text("\(store.items.filter { !$0.pinned }.count)/\(ClipStore.limit)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selected = min(max(selected + delta, 0), count - 1)
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let thumbnail: NSImage?

    private var preview: String {
        let flat = item.text.prefix(300).replacingOccurrences(of: "\n", with: " ⏎ ")
        return flat.trimmingCharacters(in: .whitespaces)
    }

    private var icon: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: icon).foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, height: 34)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(preview).font(.system(size: 13)).lineLimit(2)
                HStack(spacing: 4) {
                    if item.pinned { Image(systemName: "pin.fill") }
                    if let app = item.sourceApp { Text(app); Text("·") }
                    Text(item.date, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if index < 9 {
                Text("⌘\(index + 1)").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}
