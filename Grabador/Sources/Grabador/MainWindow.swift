import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Estado de la app: imagen, unidad y grabación.
@MainActor
final class FlashModel: ObservableObject {
    enum State {
        case idle
        case flashing(FlashProgress)
        case done(FlashResult)
        case failed(String)
    }

    @Published private(set) var image: DiskImage?
    @Published var imageError: String?
    @Published var selectedDrive: Drive?
    @Published var showDrivePicker = false
    /// Estado de vista (sin @State: estas herramientas de compilación no traen sus macros).
    @Published var dropTargeted = false
    @Published var pickerChoice: String?
    @Published private(set) var state: State = .idle
    @Published var verify = UserDefaults.standard.object(forKey: "verificar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(verify, forKey: "verificar") }
    }
    @Published var eject = UserDefaults.standard.object(forKey: "expulsar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(eject, forKey: "expulsar") }
    }

    let driveList = DriveList()
    private var flasher: Flasher?
    private var watch: AnyCancellable?

    init() {
        // Si se quita la unidad elegida, se deselecciona; si solo hay una válida, se elige sola (como Etcher).
        watch = driveList.$drives.sink { [weak self] drives in
            guard let self, !self.isFlashing else { return }
            if let selected = self.selectedDrive, !drives.contains(where: { $0.id == selected.id }) { self.selectedDrive = nil }
            if self.selectedDrive == nil, self.image != nil {
                let usable = drives.filter { self.problem(with: $0) == nil }
                if usable.count == 1 { self.selectedDrive = usable[0] }
            }
        }
    }

    var isFlashing: Bool { if case .flashing = state { return true } else { return false } }
    var canFlash: Bool { image != nil && selectedDrive.map { problem(with: $0) == nil } == true && !isFlashing }

    // MARK: Imagen

    func chooseImage() {
        guard !isFlashing else { return }
        let panel = NSOpenPanel()
        panel.title = "Elige la imagen del sistema"
        panel.message = "Imágenes .img o .iso, o comprimidas en .zip, .gz, .xz o .bz2"
        panel.allowedContentTypes = DiskImage.allExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { selectImage(url) }
    }

    func selectImage(_ url: URL) {
        guard !isFlashing else { return }
        state = .idle
        do {
            image = try DiskImage.open(url)
            imageError = nil
            if let drive = selectedDrive, problem(with: drive) != nil { selectedDrive = nil }
            if selectedDrive == nil {
                let usable = driveList.drives.filter { problem(with: $0) == nil }
                if usable.count == 1 { selectedDrive = usable[0] }
            }
        } catch {
            image = nil
            imageError = error.localizedDescription
        }
    }

    // MARK: Unidad

    /// Por qué no se puede usar una unidad (nil si se puede).
    func problem(with drive: Drive) -> String? {
        if let size = image?.imageSize, size > drive.size { return "Demasiado pequeña para esta imagen" }
        return nil
    }

    /// Avisos que no impiden grabar.
    func warnings(for drive: Drive) -> [String] {
        var list: [String] = []
        if drive.size > 64_000_000_000 { list.append("Unidad grande: comprueba que es la correcta") }
        if drive.virtual { list.append("Imagen de disco (no es una unidad real)") }
        return list
    }

    // MARK: Grabar

    func flash() {
        guard canFlash, let image, let drive = selectedDrive else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "¿Borrar «\(drive.name)» y grabar la imagen?"
        var text = "Se perderá TODO lo que hay en la unidad (\(drive.sizeText)\(drive.bus.isEmpty ? "" : ", \(drive.bus)"))"
        if !drive.volumes.isEmpty { text += ", incluido: \(drive.volumes.joined(separator: ", "))" }
        text += ".\n\nSe grabará «\(image.name)». Esto no se puede deshacer."
        alert.informativeText = text
        alert.addButton(withTitle: "Borrar y grabar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let flasher = Flasher()
        flasher.verify = verify
        flasher.eject = eject
        self.flasher = flasher
        driveList.paused = true
        state = .flashing(FlashProgress())
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: Result<FlashResult, Error> = Result {
                try flasher.run(image: image, target: .drive(drive)) { progress in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isFlashing else { return }
                        self.state = .flashing(progress)
                    }
                }
            }
            DispatchQueue.main.async {
                self.flasher = nil
                self.driveList.paused = false
                self.driveList.refresh()
                switch outcome {
                case .success(let result):
                    self.state = .done(result)
                    NSSound(named: "Glass")?.play()
                case .failure(let error):
                    Log.write("Error: \(error.localizedDescription)")
                    self.state = .failed(error.localizedDescription)
                    NSSound.beep()
                }
                NSApp.requestUserAttention(.informationalRequest)
            }
        }
    }

    func cancel() { flasher?.cancel() }

    /// Tras terminar: volver al principio conservando la imagen (para grabar otra unidad igual).
    func reset(keepImage: Bool) {
        state = .idle
        selectedDrive = nil
        if !keepImage { image = nil }
    }
}

// MARK: - Vista principal

private let accent = Color(red: 0.18, green: 0.80, blue: 0.86)
private let success = Color(red: 0.25, green: 0.85, blue: 0.50)

struct MainView: View {
    @ObservedObject var model: FlashModel
    @ObservedObject var drives: DriveList

    init(model: FlashModel) {
        self.model = model
        self.drives = model.driveList
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill").foregroundStyle(accent)
                Text("Grabador").font(.system(size: 17, weight: .semibold))
            }
            .padding(.top, 14)

            Spacer(minLength: 16)
            HStack(alignment: .top, spacing: 0) {
                imageStep
                connector(active: model.image != nil)
                driveStep
                connector(active: model.selectedDrive != nil)
                flashStep
            }
            .padding(.horizontal, 30)
            Spacer(minLength: 16)

            footer
        }
        .frame(width: 780, height: 440)
        .background(
            LinearGradient(colors: [Color(red: 0.11, green: 0.14, blue: 0.20), Color(red: 0.16, green: 0.20, blue: 0.28)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(model.dropTargeted ? RoundedRectangle(cornerRadius: 12).stroke(accent, lineWidth: 3).padding(6) : nil)
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { model.selectImage(url) } }
            }
            return true
        }
        .sheet(isPresented: $model.showDrivePicker) { DrivePicker(model: model, drives: drives) }
        .foregroundStyle(.white)
    }

    // MARK: Pasos

    private var imageStep: some View {
        StepColumn(number: 1, title: "Imagen", symbol: "doc.badge.plus", done: model.image != nil, enabled: !model.isFlashing) {
            if let image = model.image {
                Text(image.name).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                Text(image.displaySize).font(.caption).foregroundStyle(.white.opacity(0.6))
                if let warning = image.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
                if !model.isFlashing { Button("Cambiar") { model.chooseImage() }.buttonStyle(.link).font(.caption) }
            } else {
                Button("Elegir imagen") { model.chooseImage() }.buttonStyle(PillButton(color: accent))
                Text("o arrástrala aquí").font(.caption).foregroundStyle(.white.opacity(0.5))
                if let error = model.imageError {
                    Text(error).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
        }
    }

    private var driveStep: some View {
        StepColumn(number: 2, title: "Unidad", symbol: model.selectedDrive?.symbol ?? "externaldrive",
                   done: model.selectedDrive != nil, enabled: model.image != nil && !model.isFlashing) {
            if let drive = model.selectedDrive {
                Text(drive.name).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                Text([drive.sizeText, drive.bus].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                ForEach(model.warnings(for: drive), id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                }
                if !model.isFlashing { Button("Cambiar") { model.showDrivePicker = true }.buttonStyle(.link).font(.caption) }
            } else {
                Button("Elegir unidad") { model.showDrivePicker = true }
                    .buttonStyle(PillButton(color: accent)).disabled(model.image == nil)
                Text(drives.drives.isEmpty ? "Conecta un USB o una tarjeta SD" : "\(drives.drives.count) conectada\(drives.drives.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder private var flashStep: some View {
        switch model.state {
        case .idle:
            StepColumn(number: 3, title: "Grabar", symbol: "bolt.fill", done: false, enabled: model.canFlash) {
                Button("¡Grabar!") { model.flash() }
                    .buttonStyle(PillButton(color: accent)).disabled(!model.canFlash)
                Text("Se borrará la unidad").font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        case .flashing(let progress):
            VStack(spacing: 10) {
                ProgressRing(fraction: progress.fraction, color: progress.phase == .verifying ? success : accent)
                    .frame(width: 92, height: 92)
                Text(phaseText(progress.phase)).font(.system(size: 13, weight: .semibold))
                if progress.speed > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(progress.speed), countStyle: .file))/s"
                         + (progress.remaining.map { " · " + remainingText($0) } ?? ""))
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                }
                Button("Cancelar") { model.cancel() }.buttonStyle(.link).font(.caption)
            }
            .frame(width: 200)
        case .done(let result):
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(success)
                Text("¡Listo!").font(.system(size: 17, weight: .bold))
                Text(model.eject ? "Ya puedes quitar la unidad." : "Grabación terminada.")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
                Text("\(ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)) en \(remainingText(result.seconds))"
                     + (result.verified ? " · verificada ✓" : ""))
                    .font(.caption2).foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 12) {
                    Button("Grabar otra unidad") { model.reset(keepImage: true) }.buttonStyle(.link)
                    Button("Empezar de nuevo") { model.reset(keepImage: false) }.buttonStyle(.link)
                }.font(.caption)
            }
            .frame(width: 200)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill").font(.system(size: 56)).foregroundStyle(.red)
                Text("No se pudo grabar").font(.system(size: 15, weight: .bold))
                Text(message).font(.caption).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Volver") { model.reset(keepImage: true) }.buttonStyle(.link).font(.caption)
            }
            .frame(width: 200)
        }
    }

    private func connector(active: Bool) -> some View {
        Rectangle()
            .fill(active ? accent.opacity(0.7) : Color.white.opacity(0.15))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.top, 46)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Toggle("Verificar al terminar", isOn: $model.verify)
            Toggle("Expulsar al terminar", isOn: $model.eject)
            Spacer()
            Text("Solo se muestran unidades externas: el disco del Mac nunca aparece.")
                .foregroundStyle(.white.opacity(0.45))
        }
        .toggleStyle(.checkbox)
        .font(.caption)
        .disabled(model.isFlashing)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }

    private func phaseText(_ phase: FlashProgress.Phase) -> String {
        switch phase {
        case .preparing: return "Preparando…"
        case .writing: return "Grabando…"
        case .verifying: return "Verificando…"
        case .finishing: return "Terminando…"
        }
    }

    private func remainingText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min \(s % 60) s" }
        return "\(s / 3600) h \(s % 3600 / 60) min"
    }
}

/// Una columna de paso: icono redondo, título y contenido.
private struct StepColumn<Content: View>: View {
    let number: Int
    let title: String
    let symbol: String
    let done: Bool
    let enabled: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(done ? accent.opacity(0.22) : Color.white.opacity(0.07)).frame(width: 92, height: 92)
                Circle().stroke(done ? accent : Color.white.opacity(0.2), lineWidth: 2).frame(width: 92, height: 92)
                Image(systemName: symbol).font(.system(size: 36, weight: .light))
                    .foregroundStyle(done ? accent : .white.opacity(enabled ? 0.9 : 0.4))
            }
            Text("\(number) · \(title)".uppercased()).font(.system(size: 11, weight: .bold)).kerning(1)
                .foregroundStyle(.white.opacity(0.5))
            VStack(spacing: 6) { content }
        }
        .frame(width: 200)
        .opacity(enabled || done ? 1 : 0.55)
    }
}

private struct ProgressRing: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
            Circle().trim(from: 0, to: max(0.005, min(fraction, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: fraction)
            Text("\(Int((fraction * 100).rounded(.down)))%").font(.system(size: 20, weight: .bold).monospacedDigit())
        }
    }
}

private struct PillButton: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(Capsule().fill(isEnabled ? color : Color.white.opacity(0.12)))
            .foregroundStyle(isEnabled ? Color.black.opacity(0.85) : Color.white.opacity(0.4))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

// MARK: - Elegir unidad

private struct DrivePicker: View {
    @ObservedObject var model: FlashModel
    @ObservedObject var drives: DriveList
    @Environment(\.dismiss) private var dismiss
    private var choice: String? {
        get { model.pickerChoice }
        nonmutating set { model.pickerChoice = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Elige la unidad").font(.title3.bold())
            Text("Todo lo que contenga se borrará al grabar.").font(.callout).foregroundStyle(.secondary)

            if drives.drives.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "externaldrive.badge.plus").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(drives.loading ? "Buscando unidades…" : "Conecta un USB o mete una tarjeta SD.\nAparecerá aquí sola.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(drives.drives) { drive in row(drive) }
                    }
                }
                .frame(minHeight: 160, maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Elegir") {
                    model.selectedDrive = drives.drives.first { $0.id == choice }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(choice.flatMap { id in drives.drives.first { $0.id == id } }.map { model.problem(with: $0) != nil } ?? true)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear {
            choice = model.selectedDrive?.id
            drives.refresh()
        }
    }

    private func row(_ drive: Drive) -> some View {
        let problem = model.problem(with: drive)
        let selected = choice == drive.id
        return HStack(spacing: 12) {
            Image(systemName: drive.symbol).font(.system(size: 26)).frame(width: 36)
                .foregroundStyle(problem == nil ? accent : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(drive.name).font(.headline)
                Text([drive.sizeText, drive.bus, drive.id].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if !drive.volumes.isEmpty {
                    Text("Contiene: " + drive.volumes.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
                if let problem {
                    Label(problem, systemImage: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                }
                ForEach(model.warnings(for: drive), id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? accent.opacity(0.15) : Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? accent : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .opacity(problem == nil ? 1 : 0.6)
        .onTapGesture(count: 2) {
            guard problem == nil else { return }
            model.selectedDrive = drive
            dismiss()
        }
        .onTapGesture { if problem == nil { choice = drive.id } }
    }
}
