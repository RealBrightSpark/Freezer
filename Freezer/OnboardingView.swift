import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: FreezerStore

    @State private var drawerCount = 3
    @State private var thresholdMonths = 6
    @State private var drafts: [DrawerDraft] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Freezer setup") {
                    Stepper("Number of drawers: \(drawerCount)", value: $drawerCount, in: 1...10)
                        .onChange(of: drawerCount) { _, _ in
                            syncDraftsWithDrawerCount()
                        }
                }

                Section("Drawer defaults") {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Drawer name", text: $draft.name)
                            Picker("Default category", selection: $draft.categoryID) {
                                ForEach(store.categories) { category in
                                    Text(category.name).tag(category.id)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Reminder") {
                    Stepper("Alert after \(thresholdMonths) months", value: $thresholdMonths, in: 1...24)
                }

                Section {
                    Button("Finish setup") {
                        store.completeOnboarding(drawers: drafts, thresholdMonths: thresholdMonths)
                    }
                    .disabled(drafts.isEmpty)
                }
            }
            .navigationTitle("Welcome")
            .freezerScreenStyle()
            .onAppear {
                setupDefaults()
            }
        }
    }

    private func setupDefaults() {
        guard drafts.isEmpty, !store.categories.isEmpty else { return }
        syncDraftsWithDrawerCount()
    }

    private func syncDraftsWithDrawerCount() {
        guard !store.categories.isEmpty else { return }

        var next = drafts
        while next.count < drawerCount {
            let index = next.count
            let fallbackCategory = store.categories[index % store.categories.count]
            next.append(DrawerDraft(name: "Drawer \(index + 1)", categoryID: fallbackCategory.id))
        }

        if next.count > drawerCount {
            next = Array(next.prefix(drawerCount))
        }

        drafts = next
    }
}
