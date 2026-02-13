import Foundation
import Combine
import UserNotifications

@MainActor
final class FreezerStore: ObservableObject {
    @Published private(set) var data: FreezerData

    private let saveURL: URL
    private let notificationIdentifier = "freezer.overdue.summary"

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.saveURL = documents.appendingPathComponent("freezer-data.json")

        if let loaded = Self.loadFromDisk(url: saveURL) {
            self.data = loaded
        } else {
            self.data = FreezerData.initial()
            save()
        }
    }

    var categories: [FreezerCategory] {
        data.categories.sorted { $0.name < $1.name }
    }

    var drawers: [FreezerDrawer] {
        data.drawers.sorted { $0.order < $1.order }
    }

    var items: [FreezerItem] {
        data.items.sorted { $0.dateAdded > $1.dateAdded }
    }

    var mappings: [FoodMapping] {
        data.userMappings.sorted { $0.keyword < $1.keyword }
    }

    var onboardingComplete: Bool {
        data.onboardingComplete
    }

    var thresholdMonths: Int {
        data.settings.thresholdMonths
    }

    func completeOnboarding(drawers: [DrawerDraft], thresholdMonths: Int) {
        data.drawers = drawers.enumerated().map { offset, draft in
            FreezerDrawer(
                id: UUID(),
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Drawer \(offset + 1)" : draft.name,
                order: offset,
                defaultCategoryID: draft.categoryID
            )
        }
        data.settings.thresholdMonths = max(1, thresholdMonths)
        data.onboardingComplete = true
        saveAndRefreshNotifications()
    }

    func addItem(name: String, quantity: String, dateAdded: Date, categoryID: UUID?, drawerID: UUID?) {
        guard !name.freezerNormalized.isEmpty else { return }

        let fallbackCategory = categoryID ?? suggestedCategory(for: name)?.id ?? categories.first?.id
        guard let chosenCategoryID = fallbackCategory else { return }

        let fallbackDrawer = drawerID ?? suggestedDrawer(for: chosenCategoryID)?.id ?? drawers.first?.id
        guard let chosenDrawerID = fallbackDrawer else { return }

        let item = FreezerItem(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedName: name.freezerNormalized,
            categoryID: chosenCategoryID,
            drawerID: chosenDrawerID,
            quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            dateAdded: dateAdded
        )

        data.items.append(item)
        saveAndRefreshNotifications()
    }

    func updateItem(_ item: FreezerItem) {
        guard let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.normalizedName = item.name.freezerNormalized
        data.items[index] = updated
        saveAndRefreshNotifications()
    }

    func deleteItem(id: UUID) {
        data.items.removeAll { $0.id == id }
        saveAndRefreshNotifications()
    }

    func setThresholdMonths(_ months: Int) {
        data.settings.thresholdMonths = max(1, months)
        saveAndRefreshNotifications()
    }

    func updateDrawers(_ updatedDrawers: [FreezerDrawer]) {
        data.drawers = updatedDrawers.enumerated().map { index, drawer in
            var copy = drawer
            copy.order = index
            return copy
        }
        save()
    }

    func addUserMapping(keyword: String, categoryID: UUID) {
        let normalized = keyword.freezerNormalized
        guard !normalized.isEmpty else { return }

        if let index = data.userMappings.firstIndex(where: { $0.keyword.freezerNormalized == normalized }) {
            data.userMappings[index].categoryID = categoryID
            data.userMappings[index].keyword = keyword
        } else {
            data.userMappings.append(FoodMapping(id: UUID(), keyword: keyword, categoryID: categoryID))
        }
        save()
    }

    func updateUserMapping(_ mapping: FoodMapping) {
        guard let index = data.userMappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        data.userMappings[index] = mapping
        save()
    }

    func deleteMapping(id: UUID) {
        data.userMappings.removeAll { $0.id == id }
        save()
    }

    func suggestedCategory(for itemName: String) -> FreezerCategory? {
        let normalized = itemName.freezerNormalized
        guard !normalized.isEmpty else { return nil }

        if let mapped = data.userMappings.first(where: { normalized.contains($0.keyword.freezerNormalized) }),
           let category = data.categories.first(where: { $0.id == mapped.categoryID }) {
            return category
        }

        if let builtInName = DefaultFoodData.builtInKeywordMap.first(where: { normalized.contains($0.key) })?.value,
           let category = data.categories.first(where: { $0.name.caseInsensitiveCompare(builtInName) == .orderedSame }) {
            return category
        }

        return data.categories.first
    }

    func suggestedDrawer(for categoryID: UUID) -> FreezerDrawer? {
        drawers.first(where: { $0.defaultCategoryID == categoryID }) ?? drawers.first
    }

    func categoryName(for id: UUID) -> String {
        data.categories.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    func drawerName(for id: UUID) -> String {
        data.drawers.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    func items(for drawerID: UUID) -> [FreezerItem] {
        items.filter { $0.drawerID == drawerID }
    }

    func matchingItems(term: String) -> [FreezerItem] {
        let normalized = term.freezerNormalized
        guard !normalized.isEmpty else { return items }
        return items.filter {
            $0.normalizedName.contains(normalized) ||
            $0.quantity.freezerNormalized.contains(normalized) ||
            categoryName(for: $0.categoryID).freezerNormalized.contains(normalized) ||
            drawerName(for: $0.drawerID).freezerNormalized.contains(normalized)
        }
    }

    func overdueItems(referenceDate: Date = Date()) -> [FreezerItem] {
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -thresholdMonths, to: referenceDate) else {
            return []
        }

        return items.filter { $0.dateAdded < cutoff }
    }

    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func refreshNotifications() {
        let overdueCount = overdueItems().count
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        guard overdueCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Freezer reminder"
        content.body = overdueCount == 1
            ? "1 item has been in the freezer longer than your limit."
            : "\(overdueCount) items have been in the freezer longer than your limit."
        content.sound = .default

        var date = DateComponents()
        date.hour = min(max(0, data.settings.notificationHour), 23)
        date.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    private static func loadFromDisk(url: URL) -> FreezerData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FreezerData.self, from: raw)
    }

    private func saveAndRefreshNotifications() {
        save()
        refreshNotifications()
    }

    private func save() {
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: saveURL, options: [.atomic])
        } catch {
            print("Failed to save freezer data: \(error)")
        }
    }
}

struct DrawerDraft: Identifiable {
    let id: UUID
    var name: String
    var categoryID: UUID

    init(id: UUID = UUID(), name: String, categoryID: UUID) {
        self.id = id
        self.name = name
        self.categoryID = categoryID
    }
}
