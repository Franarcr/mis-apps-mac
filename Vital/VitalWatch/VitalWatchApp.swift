import SwiftUI

@main
struct VitalWatchApp: App {
    @StateObject private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TabView {
                    HealthPage(store: store)
                    RoutinesPage(store: store)
                }
                .tabViewStyle(.verticalPage)
            }
            .onAppear { store.activate() }
        }
    }
}
