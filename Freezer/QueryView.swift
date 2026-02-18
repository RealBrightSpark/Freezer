import SwiftUI

struct QueryView: View {
    @EnvironmentObject private var store: FreezerStore

    @State private var query = ""
    @State private var pendingDeleteItem: FreezerItem?

    var body: some View {
        NavigationStack {
            List {
                Section("Search") {
                    TextField("What is in the freezer?", text: $query)
                }

                if !query.freezerNormalized.isEmpty {
                    Section("Summary") {
                        Text("\(results.count) matching item\(results.count == 1 ? "" : "s")")
                        Text(totalSummary)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Results") {
                    if results.isEmpty {
                        Text("No items found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .foregroundStyle(AppTheme.itemText)
                                    HStack(spacing: 8) {
                                        CategoryBadge(text: store.categoryName(for: item.categoryID))
                                        Text(item.quantity.isEmpty ? "No quantity" : item.quantity)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.itemText)
                                        Text(store.drawerName(for: item.drawerID))
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.itemText)
                                    }
                                    Text("Added \(item.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.itemText)
                                }
                                Spacer()
                                if store.canCurrentUserEditContent {
                                    Button("Remove", role: .destructive) {
                                        pendingDeleteItem = item
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundStyle(AppTheme.itemText)
                                }
                            }
                            .listRowBackground(store.expiryState(for: item).rowColor)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .freezerScreenStyle()
            .alert("Remove item?", isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { isPresented in
                    if !isPresented { pendingDeleteItem = nil }
                }
            )) {
                Button("Cancel", role: .cancel) {
                    pendingDeleteItem = nil
                }
                Button("Remove", role: .destructive) {
                    if let item = pendingDeleteItem {
                        store.deleteItem(id: item.id)
                    }
                    pendingDeleteItem = nil
                }
                .disabled(!store.canCurrentUserEditContent)
            } message: {
                if let item = pendingDeleteItem {
                    Text("Remove \(item.name) from \(store.drawerName(for: item.drawerID))?")
                } else {
                    Text("This will remove the item from your freezer list.")
                }
            }
        }
    }

    private var results: [FreezerItem] {
        store.matchingItems(term: query).sorted { $0.dateAdded < $1.dateAdded }
    }

    private var totalSummary: String {
        let quantities = results.map { $0.quantity.freezerNormalized }.filter { !$0.isEmpty }
        if quantities.isEmpty {
            return "No quantity values recorded"
        }
        return quantities.joined(separator: ", ")
    }
}
