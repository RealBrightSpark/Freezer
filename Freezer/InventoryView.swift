import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var store: FreezerStore
    @State private var selectedItem: FreezerItem?
    @State private var showOverdueOnly = false

    var body: some View {
        NavigationStack {
            List {
                if !store.overdueItems().isEmpty {
                    Section("Overdue") {
                        Toggle("Show only overdue items", isOn: $showOverdueOnly)
                    }
                }

                ForEach(store.drawers) { drawer in
                    let drawerItems = visibleItems.filter { $0.drawerID == drawer.id }
                    if !drawerItems.isEmpty {
                        Section {
                            ForEach(drawerItems) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.name)
                                                .foregroundStyle(AppTheme.itemText)
                                            HStack(spacing: 8) {
                                                CategoryBadge(text: store.categoryName(for: item.categoryID))
                                                Text(item.quantity.isEmpty ? "No quantity" : item.quantity)
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.itemText)
                                            }
                                        }
                                        Spacer()
                                        Text(item.dateAdded, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.itemText)
                                    }
                                }
                                .swipeActions {
                                    if store.canCurrentUserEditContent {
                                        Button(role: .destructive) {
                                            store.deleteItem(id: item.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .listRowBackground(store.expiryState(for: item).rowColor)
                            }
                        } header: {
                            Text(drawer.name)
                                .foregroundStyle(.white)
                        }
                    }
                }

                if visibleItems.isEmpty {
                    ContentUnavailableView(
                        "No items found",
                        systemImage: "snowflake",
                        description: Text("Add your first freezer item from the Add tab.")
                    )
                }
            }
            .navigationTitle("Inventory")
            .freezerScreenStyle()
            .sheet(item: $selectedItem) { item in
                ItemEditorView(item: item)
                    .environmentObject(store)
            }
        }
    }

    private var visibleItems: [FreezerItem] {
        if showOverdueOnly {
            return store.overdueItems()
        }
        return store.items
    }
}
