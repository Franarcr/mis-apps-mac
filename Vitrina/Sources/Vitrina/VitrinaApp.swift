import AppKit
import SwiftUI

@main
struct VitrinaApp: App {
    @StateObject private var store = Store()
    @NSApplicationDelegateAdaptor private var delegate: Delegate

    var body: some Scene {
        Window("Vitrina", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 680, minHeight: 460)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    if store.installing == nil { store.reload() }
                }
        }
        .defaultSize(width: 760, height: 560)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
