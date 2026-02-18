import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: FreezerStore

    var body: some View {
        Group {
            if store.onboardingComplete {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .alert(item: $store.collaborationAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
