import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            InventoryView()
                .tabItem {
                    Label("Inventory", systemImage: "archivebox")
                }

            AddItemView()
                .tabItem {
                    Label("Add", systemImage: "plus.circle")
                }

            QueryView()
                .tabItem {
                    Label("Query", systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
