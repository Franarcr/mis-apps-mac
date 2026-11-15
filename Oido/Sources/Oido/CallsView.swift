import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Ventana con el archivo de llamadas: lista a la izquierda, la llamada elegida a la derecha.
struct CallsView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var recorder = Recorder.shared
    @State private var selection: String?
    @State private var search = ""

    private var visible: [Call] {
        guard !search.isEmpty else { return store.calls }
        return store.calls.filter { call in
            call.title.localizedCaseInsensitiveContains(search) || call.app.localizedCaseInsensitiveContains(search)
                || (call.summary ?? "").localizedCaseInsensitiveContains(search)
                || call.lines.contains { $0.text.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.calls) { call in CallRow(call: call).tag(call.id) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 260)
            .overlay {
                if store.calls.isEmpty {
                    ContentUnavailableView("Sin llamadas todavía", systemImage: "ear",
                                           description: Text("Cuando empiece una llamada en WhatsApp, Teams o Meet, Oído te preguntará si la graba."))
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        } detail: {
            if let id = selection, let call = store.call(id) {
                CallDetail(call: call, search: search).id(id)
            } else {
                ContentUnavailableView("Elige una llamada", systemImage: "waveform")
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Buscar en las llamadas")
        .onAppear { if selection == nil { selection = store.calls.first?.id } }
        .onChange(of: store.calls.first?.id) { _, new in if selection == nil { selection = new } }
    }

    private var groups: [(title: String, calls: [Call])] {
        let cal = Calendar.current
        var out: [(String, [Call])] = []
        for call in visible {
            let title: String
            if cal.isDateInToday(call.start) { title = "Hoy" }
            else if cal.isDateInYesterday(call.start) { title = "Ayer" }
            else { title = call.start.formatted(.dateTime.month(.wide).year()).capitalized }
            if out.last?.0 == title { out[out.count - 1].1.append(call) } else { out.append((title, [call])) }
        }
        return out
    }
}

struct CallRow: View {
    let call: Call
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(call.title).font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                Text(call.start.formatted(date: .omitted, time: .shortened))
                Text("·")
                Text(call.status == .recording ? "grabando" : call.durationText)
                Spacer()
                switch call.status {
                case .recording: Image(systemName: "record.circle").foregroundStyle(.red)
                case .transcribing: ProgressView().controlSize(.mini)
                case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                case .ready: EmptyView()
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: Detalle

struct CallDetail: View {
    let call: Call
    let search: String
    @StateObject private var player = Player()
    @State private var title = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusBox
                        if let summary = call.summary, !summary.isEmpty { summaryBox(summary) }
                        if !call.lines.isEmpty { transcript }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: player.currentLine(in: call.lines)) { _, line in
                    if player.isPlaying, let line { withAnimation { proxy.scrollTo(line, anchor: .center) } }
                }
            }
        }
        .onAppear {
            title = call.title
            player.load(call)
        }
        .onDisappear { player.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Título", text: $title)
                    .textFieldStyle(.plain).font(.title2.bold())
                    .onSubmit { Store.shared.update(call.id) { $0.title = title } }
                Spacer()
                Menu {
                    Button("Copiar texto") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(call.plainText, forType: .string)
                    }
                    Button("Exportar texto…") { export() }
                    Button("Mostrar audio en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([call.folder]) }
                    if call.status != .recording && call.status != .transcribing {
                        Button("Transcribir de nuevo") { Store.shared.process(call.id) }
                    }
                    Divider()
                    Button("Mover a la Papelera", role: .destructive) { player.stop(); Store.shared.delete(call.id) }
                        .disabled(call.status == .recording)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            Text("\(call.app) · \(call.start.formatted(date: .complete, time: .shortened))")
                .font(.callout).foregroundStyle(.secondary)
            if player.ready {
                HStack(spacing: 10) {
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    Text(Call.clock(player.time)).monospacedDigit().font(.caption)
                    Slider(value: Binding(get: { player.time }, set: { player.seek($0) }), in: 0...max(player.duration, 1))
                    Text(Call.clock(player.duration)).monospacedDigit().font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder private var statusBox: some View {
        switch call.status {
        case .recording:
            Label("Grabando…", systemImage: "record.circle").foregroundStyle(.red)
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Pasando la llamada a texto. La primera vez puede tardar porque macOS descarga el español.")
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Note(text: call.error ?? "No se pudo transcribir.", tint: .orange)
        case .ready:
            if let note = call.summaryNote { Note(text: note, tint: .secondary) }
        }
    }

    private func summaryBox(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Resumen", systemImage: "sparkles").font(.headline)
            Text(summary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if !call.actions.isEmpty {
                Text("Pendientes").font(.subheadline.bold()).padding(.top, 4)
                ForEach(call.actions, id: \.self) { action in
                    Label { Text(action).textSelection(.enabled) } icon: { Image(systemName: "circle") }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conversación").font(.headline)
            ForEach(call.lines, id: \.self) { line in
                LineView(line: line, search: search, current: player.isPlaying && player.currentLine(in: call.lines) == line)
                    .id(line)
                    .onTapGesture { player.seek(line.start); player.play() }
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(call.title).txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? call.plainText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct LineView: View {
    let line: Line
    let search: String
    let current: Bool

    var body: some View {
        let me = line.speaker == .me
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(me ? "Yo" : "Ellos").font(.caption.bold()).foregroundStyle(me ? Color.blue : .orange)
                Text(Call.clock(line.start)).font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
            }
            .frame(width: 44, alignment: .trailing)
            Text(highlighted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background((me ? Color.blue : Color.orange).opacity(current ? 0.22 : 0.08),
                            in: RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var highlighted: AttributedString {
        var s = AttributedString(line.text)
        if !search.isEmpty, let r = s.range(of: search, options: .caseInsensitive) {
            s[r].backgroundColor = .yellow.opacity(0.5)
        }
        return s
    }
}

struct Note: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: Reproductor

@MainActor
final class Player: ObservableObject {
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var ready = false
    private var audio: AVAudioPlayer?
    private var timer: Timer?

    func load(_ call: Call) {
        let fm = FileManager.default
        guard call.status != .recording,
              let url = [call.mixURL, call.micURL, call.appURL].first(where: { fm.fileExists(atPath: $0.path) }),
              let audio = try? AVAudioPlayer(contentsOf: url) else { return }
        audio.prepareToPlay()
        self.audio = audio
        duration = audio.duration
        ready = true
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        guard let audio else { return }
        audio.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let audio = self.audio else { return }
                self.time = audio.currentTime
                if !audio.isPlaying { self.isPlaying = false; self.timer?.invalidate() }
            }
        }
    }

    func pause() { audio?.pause(); isPlaying = false; timer?.invalidate() }
    func stop() { pause(); audio = nil }

    func seek(_ t: Double) {
        audio?.currentTime = t
        time = t
    }

    func currentLine(in lines: [Line]) -> Line? {
        lines.last { $0.start <= time + 0.3 }
    }
}
