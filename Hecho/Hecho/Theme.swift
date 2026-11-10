import SwiftUI

enum Theme {
    /// Verde azulado propio de Hecho.
    static let accent = Color(red: 0.10, green: 0.53, blue: 0.50)
    static let deadline = Color(red: 0.86, green: 0.22, blue: 0.27)
    static let today = Color(red: 0.96, green: 0.62, blue: 0.10)
    static let evening = Color(red: 0.36, green: 0.42, blue: 0.80)
    static let someday = Color(red: 0.66, green: 0.56, blue: 0.40)
    /// Color de las áreas (carpetas), distinto del de los proyectos (círculos verde azulado).
    static let area = Color(red: 0.42, green: 0.40, blue: 0.82)
}

/// Las listas fijas de la barra lateral.
enum SmartList: String, CaseIterable, Hashable {
    case inbox, today, upcoming, anytime, someday, logbook, trash

    var title: String {
        switch self {
        case .inbox: "Entrada"
        case .today: "Hoy"
        case .upcoming: "Próximo"
        case .anytime: "Cuando sea"
        case .someday: "Algún día"
        case .logbook: "Registro"
        case .trash: "Papelera"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray.fill"
        case .today: "sun.max.fill"
        case .upcoming: "calendar"
        case .anytime: "square.stack.fill"
        case .someday: "archivebox.fill"
        case .logbook: "checkmark.seal.fill"
        case .trash: "trash.fill"
        }
    }

    var color: Color {
        switch self {
        case .inbox: Color(red: 0.20, green: 0.55, blue: 0.85)
        case .today: Theme.today
        case .upcoming: Theme.deadline
        case .anytime: Theme.accent
        case .someday: Theme.someday
        case .logbook: Color(red: 0.25, green: 0.65, blue: 0.35)
        case .trash: .gray
        }
    }

    /// Texto que se muestra cuando la lista está vacía.
    var emptyText: String {
        switch self {
        case .inbox: "Anota aquí todo lo que se te ocurra. Luego decides cuándo hacerlo."
        case .today: "Nada para hoy. Elige algo de «Cuando sea» o disfruta el día."
        case .upcoming: "No hay nada programado para los próximos días."
        case .anytime: "Aquí aparece todo lo que puedes hacer ya."
        case .someday: "Guarda aquí las ideas y lo que no tiene prisa."
        case .logbook: "Lo que completes aparecerá aquí."
        case .trash: "La papelera está vacía."
        }
    }

    static let main: [SmartList] = [.inbox, .today, .upcoming, .anytime, .someday]
    static let archive: [SmartList] = [.logbook, .trash]
}

/// Círculo de progreso de un proyecto.
struct ProgressPie: View {
    var progress: Double
    var done: Bool = false
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 1.6)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(color)
            } else {
                PieSlice(fraction: progress)
                    .fill(color)
                    .padding(3)
            }
        }
        .frame(width: 16, height: 16)
    }
}

private struct PieSlice: Shape {
    var fraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard fraction > 0 else { return p }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: rect.width / 2, startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * min(fraction, 1)), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Píldora pequeña con icono y texto (fecha, fecha límite, etiqueta). Al tocarla hace `onTap`; la x hace `onClear`.
struct Chip: View {
    var icon: String?
    var text: String
    var color: Color = .secondary
    var onTap: (() -> Void)?
    var onClear: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            if let onTap {
                Button(action: onTap) { content }.buttonStyle(.borderless)
            } else {
                content
            }
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(color.opacity(0.6))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Quitar")
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var content: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .foregroundStyle(color)
    }
}
