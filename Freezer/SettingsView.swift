import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: FreezerStore

    @State private var editableDrawers: [FreezerDrawer] = []

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

                Section("Drawers") {
                    ForEach($editableDrawers) { $drawer in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Drawer name", text: $drawer.name)
                            Picker("Default category", selection: $drawer.defaultCategoryID) {
                                ForEach(store.categories) { category in
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
                        get: { newMappingCategoryID ?? store.categories.first?.id },
                        set: { newMappingCategoryID = $0 }
                    )) {
                        ForEach(store.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }

                    Button("Add mapping") {
                        if let categoryID = newMappingCategoryID ?? store.categories.first?.id {
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
                                    Text(store.categoryName(for: mapping.categoryID))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
            .onAppear {
                editableDrawers = store.drawers
                newMappingCategoryID = store.categories.first?.id
            }
        }
    }
}
