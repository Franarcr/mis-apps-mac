import AppKit

enum Settings {
    /// Cuadrícula de cada pantalla (columnas, filas), guardada por el identificador estable del monitor.
    static var grids: [String: [Int]] {
        get { UserDefaults.standard.dictionary(forKey: "grids") as? [String: [Int]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "grids") }
    }

    /// Separación entre ventanas y con los bordes de la pantalla, en puntos.
    static var gap: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "gap") as? Double ?? 8) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "gap") }
    }

    /// Mover (⌃⌥ + arrastrar) y redimensionar (⌃⌥⇧ + arrastrar) ventanas desde cualquier punto.
    static var dragWithModifiers: Bool {
        get { UserDefaults.standard.object(forKey: "dragWithModifiers") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dragWithModifiers") }
    }

    /// Qué ventana colocan los atajos: la activa o la que está bajo el ratón.
    static var useWindowUnderMouse: Bool {
        get { UserDefaults.standard.object(forKey: "useWindowUnderMouse") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useWindowUnderMouse") }
    }

    /// Atajo que muestra la cuadrícula sobre la pantalla: ⌥⇧L por defecto, en la línea de ⌥⇧V (Portapapeles)
    /// y ⌥⇧N (Puntos). ⌃⌥Espacio no sirve: macOS lo usa para cambiar la fuente de entrada del teclado.
    static var gridShortcut: Shortcut {
        get {
            if let data = UserDefaults.standard.data(forKey: "gridShortcutV2"),
               let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) { return shortcut }
            return Shortcut(keyCode: 37, modifiers: 0x0800 | 0x0200) // ⌥⇧L
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "gridShortcutV2") }
    }

    /// Fondo de escritorio en las vistas previas de las pantallas.
    static var showWallpaper: Bool {
        get { UserDefaults.standard.object(forKey: "showWallpaper") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showWallpaper") }
    }
}

/// Acciones que no son una zona de la cuadrícula.
enum QuickAction: String, CaseIterable, Identifiable {
    case center, restore, nextDisplay, previousDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center: "Centrar"
        case .restore: "Restaurar"
        case .nextDisplay: "Siguiente pantalla"
        case .previousDisplay: "Pantalla anterior"
        }
    }

    var symbol: String {
        switch self {
        case .center: "rectangle.center.inset.filled"
        case .restore: "arrow.uturn.backward"
        case .nextDisplay: "rectangle.righthalf.inset.filled.arrow.right"
        case .previousDisplay: "rectangle.lefthalf.inset.filled.arrow.left"
        }
    }

    var shortcut: Shortcut {
        let ctrlOpt = 0x1000 | 0x0800 // controlKey | optionKey
        switch self {
        case .center: return Shortcut(keyCode: 8, modifiers: ctrlOpt)              // C
        case .restore: return Shortcut(keyCode: 51, modifiers: ctrlOpt)            // ⌫
        case .nextDisplay: return Shortcut(keyCode: 124, modifiers: ctrlOpt | 0x0100) // ⌘→
        case .previousDisplay: return Shortcut(keyCode: 123, modifiers: ctrlOpt | 0x0100) // ⌘←
        }
    }
}

@MainActor
enum Layout {
    /// Aplica la separación: la mitad entre ventanas contiguas y entera en los bordes de la pantalla.
    static func applyGap(_ rect: CGRect, in area: CGRect, gap: CGFloat = Settings.gap) -> CGRect {
        let half = gap / 2, eps: CGFloat = 1
        let left = abs(rect.minX - area.minX) < eps ? gap : half
        let right = abs(rect.maxX - area.maxX) < eps ? gap : half
        let bottom = abs(rect.minY - area.minY) < eps ? gap : half
        let top = abs(rect.maxY - area.maxY) < eps ? gap : half
        return CGRect(x: rect.minX + left, y: rect.minY + bottom,
                      width: rect.width - left - right, height: rect.height - top - bottom)
    }

    /// La ventana a la que se aplican los atajos, según el ajuste "Qué ventana colocar".
    static func targetWindow() -> AXUIElement? {
        if Settings.useWindowUnderMouse {
            let mouse = NSEvent.mouseLocation
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            if let window = WindowControl.window(at: CGPoint(x: mouse.x, y: primaryHeight - mouse.y)) { return window }
        }
        return WindowControl.focusedWindow()
    }

    /// Coloca una ventana ocupando una zona de una pantalla (la separación se añade aquí).
    /// Si está en pantalla completa, primero sale de ella y la coloca al terminar la animación.
    /// Devuelve `true` si hubo que salir de pantalla completa (la colocación llega un momento después).
    @discardableResult
    static func place(_ window: AXUIElement, in rect: CGRect, of screen: NSScreen) -> Bool {
        let frame = applyGap(rect, in: screen.visibleFrame)
        if WindowControl.isFullScreen(window) {
            Log.write("La ventana está en pantalla completa: se sale antes de colocarla")
            WindowControl.exitFullScreen(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                WindowControl.setFrame(frame, of: window)
            }
            return true
        }
        FrameHistory.remember(window)
        WindowControl.setFrame(frame, of: window)
        return false
    }

    /// Aplica una distribución guardada en la pantalla donde está la ventana.
    static func apply(_ layout: SavedLayout, to window: AXUIElement? = nil) {
        guard WindowControl.isTrusted else { return WindowControl.requestAccess() }
        guard let window = window ?? targetWindow(), let current = WindowControl.frame(of: window) else {
            return NSSound.beep()
        }
        let screen = WindowControl.screen(for: current)
        place(window, in: layout.rect(in: screen.visibleFrame), of: screen)
    }

    static func perform(_ action: QuickAction, on window: AXUIElement? = nil) {
        guard WindowControl.isTrusted else { return WindowControl.requestAccess() }
        guard let window = window ?? targetWindow(), let current = WindowControl.frame(of: window) else {
            return NSSound.beep()
        }
        let screen = WindowControl.screen(for: current)
        let vf = screen.visibleFrame

        switch action {
        case .center:
            let size = CGSize(width: min(current.width, vf.width * 0.9), height: min(current.height, vf.height * 0.9))
            FrameHistory.remember(window)
            WindowControl.setFrame(CGRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2,
                                          width: size.width, height: size.height), of: window)
        case .nextDisplay, .previousDisplay:
            let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return NSSound.beep() }
            let target = screens[(index + (action == .nextDisplay ? 1 : screens.count - 1)) % screens.count]
            // Misma posición y tamaño relativos en la otra pantalla.
            let t = target.visibleFrame
            let rx = (current.minX - vf.minX) / vf.width, ry = (current.minY - vf.minY) / vf.height
            let rw = min(current.width / vf.width, 1), rh = min(current.height / vf.height, 1)
            FrameHistory.remember(window)
            WindowControl.setFrame(CGRect(x: t.minX + rx * t.width, y: t.minY + ry * t.height,
                                          width: rw * t.width, height: rh * t.height), of: window)
        case .restore:
            guard let previous = FrameHistory.previous(of: window) else { return NSSound.beep() }
            FrameHistory.remember(window)
            WindowControl.setFrame(previous, of: window)
        }
    }
}
