import SwiftUI

struct ItemEditorView: View {
    @EnvironmentObject private var store: FreezerStore
    @Environment(\.dismiss) private var dismiss

    @State private var item: FreezerItem

    init(item: FreezerItem) {
        _item = State(initialValue: item)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $item.name)
                    TextField("Quantity", text: $item.quantity)
                    DatePicker("Date added", selection: $item.dateAdded, displayedComponents: .date)
                }

                Section("Placement") {
                    Picker("Category", selection: $item.categoryID) {
                        ForEach(store.categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }

                    Picker("Drawer", selection: $item.drawerID) {
                        ForEach(store.drawers) { drawer in
                            Text(drawer.name).tag(drawer.id)
                        }
                    }
                }
            }
            .navigationTitle("Edit item")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateItem(item)
                        dismiss()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
