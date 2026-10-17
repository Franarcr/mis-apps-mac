import AppKit
import ServiceManagement
import SwiftUI

/// Contenedor de SwiftUI que convierte cualquier clic en un arrastre de la ventana
/// (NSHostingView se queda los clics y `isMovableByWindowBackground` no basta).
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Ventana sin bordes que se arrastra desde cualquier punto y no roba el foco.
final class WidgetPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: content.fittingSize),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = content
    }

    override var canBecomeKey: Bool { false }
}

enum Preferences {
    static var alwaysOnTop: Bool {
        get { UserDefaults.standard.bool(forKey: "alwaysOnTop") }
        set { UserDefaults.standard.set(newValue, forKey: "alwaysOnTop") }
    }

    static var cpuInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: "cpuInMenuBar") }
        set { UserDefaults.standard.set(newValue, forKey: "cpuInMenuBar") }
    }

    static var widgetVisible: Bool {
        get { UserDefaults.standard.object(forKey: "widgetVisible") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "widgetVisible") }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = SystemMonitor()
    private var statusItem: NSStatusItem!
    private var panel: WidgetPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = DraggableHostingView(rootView: WidgetView(monitor: monitor))
        panel = WidgetPanel(content: host)
        applyLevel()
        if !panel.setFrameUsingName("MonitorWidget") {
            // Primera vez: esquina superior derecha de la pantalla principal.
            let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: vf.maxX - panel.frame.width - 20, y: vf.maxY - 20))
        }
        panel.setFrameAutosaveName("MonitorWidget")
        if Preferences.widgetVisible { panel.orderFrontRegardless() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()

        monitor.onTick = { [weak self] in self?.updateStatusItem() }
        monitor.start()
    }

    /// En el escritorio (debajo de las ventanas, como un widget) o siempre encima.
    private func applyLevel() {
        panel.level = Preferences.alwaysOnTop
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if Preferences.cpuInMenuBar {
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: "CPU \(Format.percent(monitor.cpu.last))",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
        } else if button.image == nil {
            button.title = ""
            let icon = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Monitor")
            icon?.isTemplate = true
            button.image = icon
        }
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item(panel.isVisible ? "Ocultar widget" : "Mostrar widget", #selector(toggleWidget)))
        menu.addItem(.separator())
        menu.addItem(item("Mantener encima de las ventanas", #selector(toggleOnTop), on: Preferences.alwaysOnTop))
        menu.addItem(item("Mostrar CPU en la barra de menú", #selector(toggleCPU), on: Preferences.cpuInMenuBar))
        menu.addItem(item("Abrir al iniciar sesión", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(item("Abrir Monitor de Actividad", #selector(openActivityMonitor)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Monitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc private func toggleWidget() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        Preferences.widgetVisible = panel.isVisible
    }

    @objc private func toggleOnTop() {
        Preferences.alwaysOnTop.toggle()
        applyLevel()
    }

    @objc private func toggleCPU() {
        Preferences.cpuInMenuBar.toggle()
        updateStatusItem()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}
