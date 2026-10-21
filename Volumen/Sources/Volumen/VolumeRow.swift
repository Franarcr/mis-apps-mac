import AppKit

/// Fila del menú con el icono y el nombre de la app, el porcentaje y el deslizador de volumen.
@MainActor
final class VolumeRow: NSView {
    private let slider = NSSlider(value: 1, minValue: 0, maxValue: Double(VolumeController.maxVolume), target: nil, action: nil)
    private let percent = NSTextField(labelWithString: "")
    private let onChange: (Float) -> Void

    init(app: AudioApp, volume: Float, onChange: @escaping (Float) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 52))

        let icon = NSImageView(frame: NSRect(x: 16, y: 29, width: 18, height: 18))
        icon.image = app.icon
        let name = NSTextField(labelWithString: app.name)
        name.frame = NSRect(x: 40, y: 29, width: 180, height: 17)
        name.lineBreakMode = .byTruncatingTail
        // Las apps que suenan ahora se ven en negrita.
        name.font = app.isPlaying ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
        percent.frame = NSRect(x: 224, y: 29, width: 60, height: 17)
        percent.alignment = .right
        percent.textColor = .secondaryLabelColor
        percent.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        slider.frame = NSRect(x: 38, y: 6, width: 248, height: 20)
        slider.floatValue = volume
        slider.isContinuous = true
        // Marcas en 0, 50, 100 y 150 %.
        slider.numberOfTickMarks = 4
        slider.target = self
        slider.action = #selector(sliderMoved)

        for view in [icon, name, percent, slider] as [NSView] { addSubview(view) }
        updatePercent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no está implementado") }

    @objc private func sliderMoved() {
        // Cerca del 100 % se queda justo en 100, para volver fácil al volumen normal.
        if abs(slider.floatValue - 1) < 0.04 { slider.floatValue = 1 }
        updatePercent()
        onChange(slider.floatValue)
    }

    private func updatePercent() {
        let value = Int((slider.floatValue * 100).rounded())
        percent.stringValue = value == 0 ? "Silencio" : "\(value) %"
    }
}
