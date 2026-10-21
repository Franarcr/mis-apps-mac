import AppKit
import ApplicationServices

/// Acceso cómodo a los atributos de Accesibilidad de las ventanas de otras apps.
extension AXUIElement {
    func value<T>(_ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var windows: [AXUIElement] { value(kAXWindowsAttribute) ?? [] }

    /// Ventanas normales: sin paneles flotantes, diálogos ni hojas.
    var standardWindows: [AXUIElement] {
        windows.filter { ($0.value(kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole }
    }

    /// Marco en coordenadas de Accesibilidad: origen arriba a la izquierda de la pantalla principal.
    var frame: CGRect? {
        guard let positionValue: AXValue = value(kAXPositionAttribute),
              let sizeValue: AXValue = value(kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    func setFrame(_ frame: CGRect) {
        var position = frame.origin
        var size = frame.size
        // El tamaño se aplica antes y después de mover: si no, una ventana que no cabe
        // en la posición nueva queda recortada al borde de la pantalla.
        if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value) }
        if let value = AXValueCreate(.cgPoint, &position) { AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value) }
        if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value) }
    }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Muestra el aviso de macOS que lleva a Ajustes › Privacidad y seguridad › Accesibilidad.
    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Zona útil de la pantalla (sin barra de menús ni Dock) donde está la mayor parte de `frame`,
    /// en coordenadas de Accesibilidad.
    static func visibleFrame(for frame: CGRect) -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let frames = NSScreen.screens.map { screen in
            let visible = screen.visibleFrame
            return CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
        }
        return frames.max { area($0.intersection(frame)) < area($1.intersection(frame)) }
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}
