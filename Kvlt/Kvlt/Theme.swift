import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Colores y letra de cada género.
struct Palette {
    let bg: Color
    let panel: Color
    let accent: Color
    let text: Color
    let dim: Color
    var design: Font.Design = .default

    func title(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: design) }

    static let good = Color(hex: 0x4FB565)
    static let bad = Color(hex: 0xE5484D)
    static let mix = Palette(bg: Color(hex: 0x0F0F14), panel: Color(hex: 0x1D1C27), accent: Color(hex: 0xA78BFA),
                             text: Color(hex: 0xF2F0F7), dim: Color(hex: 0x8E8AA0), design: .rounded)
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.mix }

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

enum Genre: String, CaseIterable, Identifiable, Codable {
    case metal, rockClasico, pop, salsa, merengue, rockEspanol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metal: "Metal"
        case .rockClasico: "Rock clásico"
        case .pop: "Pop"
        case .salsa: "Salsa"
        case .merengue: "Merengue"
        case .rockEspanol: "Rock en español"
        }
    }

    var subtitle: String {
        switch self {
        case .metal: "Black, death y thrash underground"
        case .rockClasico: "De los 60 a los 80"
        case .pop: "De Michael Jackson a Bad Bunny"
        case .salsa: "Nueva York, Puerto Rico, Cuba y Cali"
        case .merengue: "República Dominicana y su gente"
        case .rockEspanol: "Argentina, México, España, Chile, Colombia"
        }
    }

    var icon: String {
        switch self {
        case .metal: "flame.fill"
        case .rockClasico: "guitars.fill"
        case .pop: "star.fill"
        case .salsa: "music.note"
        case .merengue: "sun.max.fill"
        case .rockEspanol: "bolt.fill"
        }
    }

    var palette: Palette {
        switch self {
        case .metal:
            Palette(bg: Color(hex: 0x0A0808), panel: Color(hex: 0x1A1414), accent: Color(hex: 0xB3121F),
                    text: Color(hex: 0xE8E0D4), dim: Color(hex: 0x8C8580), design: .serif)
        case .rockClasico:
            Palette(bg: Color(hex: 0x17110C), panel: Color(hex: 0x2A1F16), accent: Color(hex: 0xE09A2D),
                    text: Color(hex: 0xF3E6CF), dim: Color(hex: 0xA08E74), design: .serif)
        case .pop:
            Palette(bg: Color(hex: 0x170C2B), panel: Color(hex: 0x2A1846), accent: Color(hex: 0xFF4FA3),
                    text: Color(hex: 0xFFFFFF), dim: Color(hex: 0xB3A2D1), design: .rounded)
        case .salsa:
            Palette(bg: Color(hex: 0x260B08), panel: Color(hex: 0x3D1611), accent: Color(hex: 0xFF7A1A),
                    text: Color(hex: 0xFFF1E6), dim: Color(hex: 0xC79A85), design: .rounded)
        case .merengue:
            Palette(bg: Color(hex: 0x052426), panel: Color(hex: 0x0C3A3D), accent: Color(hex: 0xFFD23F),
                    text: Color(hex: 0xF2FFFE), dim: Color(hex: 0x8FBDBA), design: .rounded)
        case .rockEspanol:
            Palette(bg: Color(hex: 0x0D1322), panel: Color(hex: 0x1A2338), accent: Color(hex: 0x34D1BF),
                    text: Color(hex: 0xEEF3FF), dim: Color(hex: 0x8C98B3))
        }
    }

    var topics: [Topic] { Topic.allCases.filter { $0.genre == self } }

    /// Dónde van las preguntas que agrega el jugador.
    var customTopic: Topic { self == .metal ? .tuyas : topics[0] }
}

/// Qué se juega: todo, un género o una escena del metal.
struct Pick: Hashable, Identifiable {
    var genre: Genre?
    var topic: Topic?

    var id: String { key }
    var key: String { topic?.rawValue ?? genre?.rawValue ?? "todas" }
    var title: String {
        if let topic, topic.genre == .metal { return topic.title }
        return genre?.title ?? topic?.genre.title ?? "Todos los géneros"
    }
    var palette: Palette { (topic?.genre ?? genre)?.palette ?? .mix }
}

/// Colores para distinguir a los jugadores.
enum PlayerColor {
    static let all: [Color] = [0xE5484D, 0xF5A524, 0xF7D046, 0x4FB565, 0x2EC4B6, 0x3E8EF7, 0xA78BFA, 0xF472B6].map { Color(hex: $0) }
    static func of(_ i: Int) -> Color { all[((i % all.count) + all.count) % all.count] }
}

struct Avatar: View {
    let name: String
    let color: Int
    var size: CGFloat = 40

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
            .frame(width: size, height: size)
            .background(PlayerColor.of(color), in: Circle())
            .foregroundStyle(.black.opacity(0.75))
    }
}
