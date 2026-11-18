import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Colores de cada sección: un fondo profundo y un acento brillante,
/// al estilo de los módulos de CleanMyMac.
struct Palette {
    let backgroundTop: Color
    let backgroundBottom: Color
    let accentStart: Color
    let accentEnd: Color

    var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var accent: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var accentColors: [Color] { [accentStart, accentEnd] }

    static let status = Palette(backgroundTop: Color(hex: 0x3B1E72), backgroundBottom: Color(hex: 0xB83280), accentStart: Color(hex: 0xFF7EB3), accentEnd: Color(hex: 0xFFB36B))
    static let cleanup = Palette(backgroundTop: Color(hex: 0x0B4F4A), backgroundBottom: Color(hex: 0x1FA27A), accentStart: Color(hex: 0x5EF2C0), accentEnd: Color(hex: 0x2BD3E8))
    static let largeFiles = Palette(backgroundTop: Color(hex: 0x6E2A0E), backgroundBottom: Color(hex: 0xD9822B), accentStart: Color(hex: 0xFFD36E), accentEnd: Color(hex: 0xFF8A3C))
    static let spaceMap = Palette(backgroundTop: Color(hex: 0x102B6B), backgroundBottom: Color(hex: 0x3A64D8), accentStart: Color(hex: 0x7FD3FF), accentEnd: Color(hex: 0x8C7CFF))
    static let duplicates = Palette(backgroundTop: Color(hex: 0x4A1670), backgroundBottom: Color(hex: 0x9B3FD1), accentStart: Color(hex: 0xF3A6FF), accentEnd: Color(hex: 0x9F7BFF))
    static let uninstaller = Palette(backgroundTop: Color(hex: 0x5E0F33), backgroundBottom: Color(hex: 0xD23A5E), accentStart: Color(hex: 0xFFB1BC), accentEnd: Color(hex: 0xFF5E7E))
    static let startup = Palette(backgroundTop: Color(hex: 0x431665), backgroundBottom: Color(hex: 0xE0457B), accentStart: Color(hex: 0xFFC2E2), accentEnd: Color(hex: 0xFF6FA5))
    static let speed = Palette(backgroundTop: Color(hex: 0x06405A), backgroundBottom: Color(hex: 0x12A3B8), accentStart: Color(hex: 0x7DF9E9), accentEnd: Color(hex: 0x3FB8FF))
    static let maintenance = Palette(backgroundTop: Color(hex: 0x1F2163), backgroundBottom: Color(hex: 0x6A4FD8), accentStart: Color(hex: 0xC3B6FF), accentEnd: Color(hex: 0x7C9CFF))

    /// Colores para gráficos de varias porciones (donas, barras).
    static let chartColors: [Color] = [
        Color(hex: 0xFF7EB3), Color(hex: 0x7FD3FF), Color(hex: 0xFFD36E), Color(hex: 0x5EF2C0),
        Color(hex: 0xC3A6FF), Color(hex: 0xFF9A6B), Color(hex: 0x6BE3FF), Color(hex: 0xF3A6FF),
        Color(hex: 0xB8F27C), Color(hex: 0xFFFFFF).opacity(0.55),
    ]
}

// MARK: - Componentes

/// Encabezado grande de cada sección: ícono con brillo, título y subtítulo.
struct ModuleHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let palette: Palette
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 64, height: 64)
                    .shadow(color: palette.accentStart.opacity(0.7), radius: 16)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension ModuleHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, icon: String, palette: Palette) {
        self.init(title: title, subtitle: subtitle, icon: icon, palette: palette) { EmptyView() }
    }
}

/// Tarjeta translúcida tipo vidrio sobre el fondo de color.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
    }
}

/// Anillo de progreso con degradado y texto al centro.
struct RingGauge<Center: View>: View {
    let fraction: Double
    let colors: [Color]
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.001), 1))
                .stroke(
                    AngularGradient(colors: colors + [colors.first ?? .white], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: (colors.first ?? .white).opacity(0.5), radius: 6)
                .animation(.easeOut(duration: 0.6), value: fraction)
            center
        }
    }
}

/// Medidor semicircular, usado en la prueba de velocidad.
struct ArcGauge: View {
    let fraction: Double
    let colors: [Color]
    var lineWidth: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: 0.75 * min(max(fraction, 0.001), 1))
                .stroke(
                    LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .shadow(color: (colors.last ?? .white).opacity(0.6), radius: 8)
                .animation(.easeOut(duration: 0.8), value: fraction)
        }
        .rotationEffect(.degrees(135))
    }
}

/// Barra horizontal con degradado (fracción de 0 a 1).
struct SizeBar: View {
    let fraction: Double
    let colors: [Color]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// Gran botón redondo de acción principal, como el "Escanear" de CleanMyMac.
struct BigCircleButton: View {
    let title: String
    let palette: Palette
    var isEnabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(10)
                .frame(width: 112, height: 112)
                .background(
                    Circle()
                        .fill(palette.accent)
                        .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 2))
                )
                .shadow(color: palette.accentStart.opacity(hovering ? 0.9 : 0.55), radius: hovering ? 26 : 16)
                .scaleEffect(hovering && isEnabled ? 1.05 : 1)
                .animation(.spring(duration: 0.25), value: hovering)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        
    }
}

/// Botón en forma de píldora: con degradado (principal) o translúcido (secundario).
struct PillButtonStyle: ButtonStyle {
    var palette: Palette?
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if destructive {
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF5E7E), Color(hex: 0xE0306B)], startPoint: .leading, endPoint: .trailing))
                } else if let palette {
                    Capsule().fill(palette.accent)
                } else {
                    Capsule().fill(.white.opacity(0.16))
                }
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// Ícono pequeño con fondo de degradado (barra lateral y filas).
struct IconTile: View {
    let icon: String
    let colors: [Color]
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// Casilla redonda de selección.
struct CheckCircle: View {
    @Binding var isOn: Bool
    var colors: [Color] = [.white, .white]

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                if isOn {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            // Sin esto, el círculo vacío solo responde al clic sobre su borde fino.
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Estado vacío o de carga centrado, sobre el fondo de color.
struct CenteredMessage: View {
    let icon: String
    let title: String
    var detail: String?
    var showsProgress = false

    var body: some View {
        VStack(spacing: 14) {
            if showsProgress {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(title)
                .font(.title3.weight(.semibold))
            if let detail {
                Text(detail)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


/// ScrollView vertical con el contenido centrado y un ancho cómodo para el iPad.
struct ScrollArea<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
