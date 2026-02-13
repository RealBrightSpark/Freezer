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
                        Section(drawer.name) {
                            ForEach(drawerItems) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(item.name)
                                            Text("\(store.categoryName(for: item.categoryID)) • \(item.quantity.isEmpty ? "No quantity" : item.quantity)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(item.dateAdded, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.deleteItem(id: item.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
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
