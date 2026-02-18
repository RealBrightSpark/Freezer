import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: FreezerStore

    @State private var editableDrawers: [FreezerDrawer] = []
    @State private var editableCategories: [FreezerCategory] = []
    @State private var newCategoryName = ""

    @State private var newKeyword = ""
    @State private var newMappingCategoryID: UUID?

    @State private var householdName = ""
    @State private var selectedCurrentUserID: UUID?
    @State private var newMemberName = ""
    @State private var newMemberRole: HouseholdRole = .editor
    @State private var generatedShareURL: URL?
    @State private var shareErrorMessage = ""
    @State private var isGeneratingShare = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Household name", text: $householdName)
                        .disabled(!store.canCurrentUserManageMembers)

                    Button("Save household name") {
                        store.renameHousehold(householdName)
                        reloadState()
                    }
                    .disabled(!store.canCurrentUserManageMembers || householdName.freezerNormalized.isEmpty)

                    Button("Generate invite link") {
                        Task {
                            await generateShareURL()
                        }
                    }
                    .disabled(!store.canCurrentUserManageMembers || isGeneratingShare)

                    if isGeneratingShare {
                        ProgressView("Generating link...")
                            .foregroundStyle(AppTheme.itemText)
                    }

                    Text("Cloud sharing \(AppConfiguration.cloudSharingEnabled ? "enabled" : "disabled") for this build")
                        .font(.caption)
                        .foregroundStyle(AppTheme.itemText)

                    if let generatedShareURL {
                        ShareLink(item: generatedShareURL) {
                            Label("Share invite link", systemImage: "square.and.arrow.up")
                        }
                        .tint(AppTheme.itemText)
                    }

                    if !shareErrorMessage.isEmpty {
                        Text(shareErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker(selection: Binding(
                        get: { selectedCurrentUserID ?? store.currentUser.id },
                        set: { newID in
                            selectedCurrentUserID = newID
                            store.switchCurrentUser(to: newID)
                            reloadState()
                        }
                    )) {
                        ForEach(store.users) { user in
                            Text(user.displayName).tag(user.id)
                        }
                    } label: {
                        Text("Current user")
                            .foregroundStyle(AppTheme.itemText)
                    }

                    Text("Current role: \(store.members.first(where: { $0.userID == store.currentUser.id })?.role.label ?? "Viewer")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.itemText)

                    HStack {
                        TextField("Add member name", text: $newMemberName)
                        Picker("Role", selection: $newMemberRole) {
                            ForEach(HouseholdRole.allCases) { role in
                                Text(role.label).tag(role)
                            }
                        }
                        .labelsHidden()
                    }
                    .disabled(!store.canCurrentUserManageMembers)

                    Button("Add member") {
                        store.addMember(displayName: newMemberName, role: newMemberRole)
                        newMemberName = ""
                        newMemberRole = .editor
                        reloadState()
                    }
                    .disabled(!store.canCurrentUserManageMembers || newMemberName.freezerNormalized.isEmpty)

                    ForEach(store.members) { member in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(store.userName(for: member.userID))
                                Text(member.role.label)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.itemText)
                            }

                            Spacer()

                            if store.canCurrentUserManageMembers {
                                Picker("Role", selection: Binding(
                                    get: { member.role },
                                    set: { newRole in
                                        store.updateMemberRole(memberID: member.id, role: newRole)
                                        reloadState()
                                    }
                                )) {
                                    ForEach(HouseholdRole.allCases) { role in
                                        Text(role.label).tag(role)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 140)

                                Button(role: .destructive) {
                                    store.removeMember(memberID: member.id)
                                    reloadState()
                                } label: {
                                    Image(systemName: "person.crop.circle.badge.minus")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Collaboration")
                        .foregroundStyle(.yellow)
                }

                Section {
                    Stepper(
                        value: Binding(
                            get: { store.thresholdMonths },
                            set: { store.setThresholdMonths($0) }
                        ),
                        in: 1...24
                    ) {
                        Text("\(store.thresholdMonths) month\(store.thresholdMonths == 1 ? "" : "s")")
                            .foregroundStyle(AppTheme.itemText)
                    }
                } header: {
                    Text("Freezer age threshold")
                        .foregroundStyle(.yellow)
                }
                .disabled(!store.canCurrentUserEditContent)

                Section {
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
                } header: {
                    Text("Categories")
                        .foregroundStyle(.yellow)
                }
                .disabled(!store.canCurrentUserEditContent)

                Section {
                    ForEach($editableDrawers) { $drawer in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Drawer name", text: $drawer.name)
                            Picker(selection: $drawer.defaultCategoryID) {
                                ForEach(editableCategories) { category in
                                    Text(category.name).tag(category.id)
                                }
                            } label: {
                                Text("Default category")
                                    .foregroundStyle(AppTheme.itemText)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button("Save drawer defaults") {
                        store.updateDrawers(editableDrawers)
                    }
                } header: {
                    Text("Drawers")
                        .foregroundStyle(.yellow)
                }
                .disabled(!store.canCurrentUserEditContent)

                Section {
                    TextField("Keyword (e.g. spag bol)", text: $newKeyword)

                    Picker(selection: Binding(
                        get: { newMappingCategoryID ?? editableCategories.first?.id },
                        set: { newMappingCategoryID = $0 }
                    )) {
                        ForEach(editableCategories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    } label: {
                        Text("Category")
                            .foregroundStyle(AppTheme.itemText)
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
                            .foregroundStyle(AppTheme.itemText)
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
                } header: {
                    Text("Food mappings")
                        .foregroundStyle(.yellow)
                }
                .disabled(!store.canCurrentUserEditContent)
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
        householdName = store.householdName
        selectedCurrentUserID = store.currentUser.id

        let validCategoryIDs = Set(editableCategories.map(\.id))
        if let selected = newMappingCategoryID, !validCategoryIDs.contains(selected) {
            newMappingCategoryID = editableCategories.first?.id
        } else if newMappingCategoryID == nil {
            newMappingCategoryID = editableCategories.first?.id
        }
    }

    @MainActor
    private func generateShareURL() async {
        isGeneratingShare = true
        shareErrorMessage = ""
        defer { isGeneratingShare = false }

        do {
            generatedShareURL = try await store.createShareURL()
        } catch {
            generatedShareURL = nil
            shareErrorMessage = error.localizedDescription
        }
    }
}
