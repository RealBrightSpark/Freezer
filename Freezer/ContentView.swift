import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: FreezerStore

    var body: some View {
        if store.onboardingComplete {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}
