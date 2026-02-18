import SwiftUI
import AppIntents
import UIKit

@main
struct FreezerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(CloudKitSyncAppDelegate.self) private var appDelegate
    @StateObject private var store: FreezerStore

    init() {
        _store = StateObject(
            wrappedValue: FreezerStore(
                repository: AppConfiguration.repository(),
                sharingService: AppConfiguration.sharingService()
            )
        )

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
                .onOpenURL { url in
                    Task {
                        await store.acceptIncomingShareURL(url)
                    }
                }
                .task {
                    await store.requestNotificationPermission()
                    store.refreshNotifications()
                    store.configureCloudSyncIfNeeded()
                    if AppConfiguration.cloudSharingEnabled {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    FreezerShortcutsProvider.updateAppShortcutParameters()
                }
                .onReceive(NotificationCenter.default.publisher(for: .cloudKitRemoteChangeReceived)) { _ in
                    store.reloadFromDiskIfChanged()
                    store.refreshNotifications()
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
