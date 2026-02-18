import SwiftUI
import AppIntents

@main
struct FreezerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = FreezerStore()

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(AppTheme.tint)
                .task {
                    await store.requestNotificationPermission()
                    store.refreshNotifications()
                    FreezerShortcutsProvider.updateAppShortcutParameters()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.reloadFromDiskIfChanged()
                store.refreshNotifications()
                FreezerShortcutsProvider.updateAppShortcutParameters()
            }
        }
    }
}
