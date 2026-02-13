import SwiftUI

@main
struct FreezerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = FreezerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task {
                    await store.requestNotificationPermission()
                    store.refreshNotifications()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.refreshNotifications()
            }
        }
    }
}
