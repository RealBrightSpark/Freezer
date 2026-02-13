import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: FreezerStore

    @State private var editableDrawers: [FreezerDrawer] = []
    @State private var editableCategories: [FreezerCategory] = []
    @State private var newCategoryName = ""

    @State private var newKeyword = ""
    @State private var newMappingCategoryID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Freezer age threshold") {
                    Stepper(
                        "\(store.thresholdMonths) month\(store.thresholdMonths == 1 ? "" : "s")",
                        value: Binding(
                            get: { store.thresholdMonths },
                            set: { store.setThresholdMonths($0) }
                        ),
                        in: 1...24
                    )
                }

                Section("Categories") {
                    ForEach(editableCategories.indices, id: \.self) { index in
                        HStack {
                            TextField("Category name", text: Binding(
                                get: { editableCategories[index].name },
                                set: { editableCategories[index].name = $0 }
                            ))
                            if editableCategories.count > 1 {
                                Button(role: .destructive) {
                                    deleteCategory(editableCategories[index].id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }

                    HStack {
                        TextField("Add category", text: $newCategoryName)
                        Button("Add") {
                            store.addCategory(name: newCategoryName)
                            newCategoryName = ""
                            reloadState()
                        }
                        .disabled(newCategoryName.freezerNormalized.isEmpty)
                    }

                    Button("Save categories") {
                        store.updateCategories(editableCategories)
                        reloadState()
                    }
                }

                Section("Drawers") {
                    ForEach($editableDrawers) { $drawer in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Drawer name", text: $drawer.name)
                            Picker("Default category", selection: $drawer.defaultCategoryID) {
                                ForEach(editableCategories) { category in
                                    Text(category.name).tag(category.id)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button("Save drawer defaults") {
                        store.updateDrawers(editableDrawers)
                    }
                }

                Section("Food mappings") {
                    TextField("Keyword (e.g. spag bol)", text: $newKeyword)

                    Picker("Category", selection: Binding(
                        get: { newMappingCategoryID ?? editableCategories.first?.id },
                        set: { newMappingCategoryID = $0 }
                    )) {
                        ForEach(editableCategories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }

                    Button("Add mapping") {
                        if let categoryID = newMappingCategoryID ?? editableCategories.first?.id {
                            store.addUserMapping(keyword: newKeyword, categoryID: categoryID)
                            newKeyword = ""
                        }
                    }
                    .disabled(newKeyword.freezerNormalized.isEmpty)

                    if store.mappings.isEmpty {
                        Text("No custom mappings yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.mappings) { mapping in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(mapping.keyword)
                                    CategoryBadge(text: store.categoryName(for: mapping.categoryID))
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    store.deleteMapping(id: mapping.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .freezerScreenStyle()
            .onAppear {
                reloadState()
            }
        }
    }

    private func deleteCategory(_ id: UUID) {
        store.deleteCategory(id: id)
        reloadState()
    }

    private func reloadState() {
        editableCategories = store.categories
        editableDrawers = store.drawers

        let validCategoryIDs = Set(editableCategories.map(\.id))
        if let selected = newMappingCategoryID, !validCategoryIDs.contains(selected) {
            newMappingCategoryID = editableCategories.first?.id
        } else if newMappingCategoryID == nil {
            newMappingCategoryID = editableCategories.first?.id
        }
    }
}
