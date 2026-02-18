import AppIntents
import Foundation

struct FreezerItemEntity: AppEntity, Hashable {
    typealias ID = String

    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Freezer Item")
    }

    static var defaultQuery = FreezerItemEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct FreezerDrawerEntity: AppEntity, Hashable {
    typealias ID = String

    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Freezer Drawer")
    }

    static var defaultQuery = FreezerDrawerEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct FreezerItemEntityQuery: EntityQuery {
    func entities(for identifiers: [FreezerItemEntity.ID]) async throws -> [FreezerItemEntity] {
        let all = allItems()
        let ids = Set(identifiers)
        return all.filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FreezerItemEntity] {
        allItems()
    }

    private func allItems() -> [FreezerItemEntity] {
        let data = FreezerStore.intentSnapshot()
        var seen: Set<String> = []
        var result: [FreezerItemEntity] = []

        for item in data.items.sorted(by: { $0.name < $1.name }) {
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.freezerNormalized
            guard !normalized.isEmpty else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(FreezerItemEntity(id: normalized, name: trimmed))
        }

        return result
    }
}

struct FreezerDrawerEntityQuery: EntityQuery {
    func entities(for identifiers: [FreezerDrawerEntity.ID]) async throws -> [FreezerDrawerEntity] {
        let all = allDrawers()
        let ids = Set(identifiers)
        return all.filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FreezerDrawerEntity] {
        allDrawers()
    }

    private func allDrawers() -> [FreezerDrawerEntity] {
        let data = FreezerStore.intentSnapshot()
        return data.drawers
            .sorted(by: { $0.order < $1.order })
            .map { FreezerDrawerEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

struct RemoveFreezerItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove Freezer Item"
    static var description = IntentDescription("Remove an item from the freezer inventory.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Item",
        requestValueDialog: IntentDialog("Which item should I remove?")
    )
    var item: FreezerItemEntity

    @Parameter(
        title: "Drawer",
        requestValueDialog: IntentDialog("Which drawer is it in?")
    )
    var drawer: FreezerDrawerEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Remove \(\.$item) from \(\.$drawer)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedItem = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDrawer = drawer.name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedItem.isEmpty else {
            return .result(dialog: "Please tell me which item to remove.")
        }
        guard !trimmedDrawer.isEmpty else {
            return .result(dialog: "Please tell me the drawer name.")
        }

        let store = FreezerStore()
        let response = store.removeItemForSiri(itemTerm: trimmedItem, drawerName: trimmedDrawer)
        return .result(dialog: IntentDialog(stringLiteral: response.dialog))
    }
}

struct FreezerShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RemoveFreezerItemIntent(),
            phrases: [
                "Remove \(\.$item) in \(.applicationName)",
                "Remove from \(\.$drawer) in \(.applicationName)",
                "Remove freezer item in \(.applicationName)",
                "In \(.applicationName), remove \(\.$item)",
                "In \(.applicationName), remove from \(\.$drawer)",
                "Use \(.applicationName) to remove freezer item"
            ],
            shortTitle: "Remove Item",
            systemImageName: "trash"
        )
    }
}
