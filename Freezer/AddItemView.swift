import SwiftUI

struct AddItemView: View {
    @EnvironmentObject private var store: FreezerStore

    @State private var name = ""
    @State private var quantity = ""
    @State private var dateAdded = Date()
    @State private var selectedCategoryID: UUID?
    @State private var selectedDrawerID: UUID?

    @State private var didManuallySetCategory = false
    @State private var didManuallySetDrawer = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. chicken)", text: $name)
                        .onChange(of: name) { _, newValue in
                            handleNameChange(newValue)
                        }

                    TextField("Quantity (e.g. 3 pieces)", text: $quantity)

                    DatePicker(selection: $dateAdded, displayedComponents: .date) {
                        Text("Date added")
                            .foregroundStyle(AppTheme.itemText)
                    }
                } header: {
                    Text("Item")
                        .foregroundStyle(.yellow)
                }
                .disabled(!store.canCurrentUserEditContent)

                Section {
                    Picker(selection: Binding(
                        get: { selectedCategoryID ?? store.categories.first?.id },
                        set: { newID in
                            selectedCategoryID = newID
                            didManuallySetCategory = true
                            if let newID {
                                selectedDrawerID = store.suggestedDrawer(for: newID)?.id
                            }
                        }
                    )) {
                        ForEach(store.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    } label: {
                        Text("Category")
                            .foregroundStyle(AppTheme.itemText)
                    }

                    Picker(selection: Binding(
                        get: { selectedDrawerID ?? store.drawers.first?.id },
                        set: { newID in
                            selectedDrawerID = newID
                            didManuallySetDrawer = true
                        }
                    )) {
                        ForEach(store.drawers) { drawer in
                            Text(drawer.name).tag(Optional(drawer.id))
                        }
                    } label: {
                        Text("Drawer")
                            .foregroundStyle(AppTheme.itemText)
                    }
                } header: {
                    Text("Auto assignment")
                        .foregroundStyle(.yellow)
                }
                .disabled(!store.canCurrentUserEditContent)

                Section {
                    Button("Add to freezer") {
                        store.addItem(
                            name: name,
                            quantity: quantity,
                            dateAdded: dateAdded,
                            categoryID: selectedCategoryID,
                            drawerID: selectedDrawerID
                        )
                        resetForm()
                    }
                    .disabled(name.freezerNormalized.isEmpty || store.drawers.isEmpty || !store.canCurrentUserEditContent)
                }
            }
            .navigationTitle("Add item")
            .freezerScreenStyle()
            
            .onAppear {
                bootstrapSelections()
            }
        }
    }

    private func bootstrapSelections() {
        guard selectedCategoryID == nil else { return }
        selectedCategoryID = store.categories.first?.id
        if let categoryID = selectedCategoryID {
            selectedDrawerID = store.suggestedDrawer(for: categoryID)?.id
        }
    }

    private func handleNameChange(_ newName: String) {
        guard !newName.freezerNormalized.isEmpty else { return }

        if !didManuallySetCategory, let category = store.suggestedCategory(for: newName) {
            selectedCategoryID = category.id
            if !didManuallySetDrawer {
                selectedDrawerID = store.suggestedDrawer(for: category.id)?.id
            }
        }
    }

    private func resetForm() {
        name = ""
        quantity = ""
        dateAdded = Date()
        didManuallySetCategory = false
        didManuallySetDrawer = false
        bootstrapSelections()
    }
}
