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
            migrateMultiUserDefaultsIfNeeded()
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

    var householdName: String {
        data.household.name
    }

    var users: [AppUser] {
        data.users.sorted { $0.displayName < $1.displayName }
    }

    var currentUser: AppUser {
        data.users.first(where: { $0.id == data.currentUserID }) ?? data.users[0]
    }

    var members: [HouseholdMember] {
        data.household.members
            .sorted { lhs, rhs in
                if lhs.role == rhs.role {
                    return userName(for: lhs.userID) < userName(for: rhs.userID)
                }
                return roleRank(lhs.role) < roleRank(rhs.role)
            }
    }

    var canCurrentUserEditContent: Bool {
        switch currentRole {
        case .owner, .editor:
            return true
        case .viewer:
            return false
        }
    }

    var canCurrentUserManageMembers: Bool {
        currentRole == .owner
    }

    enum ItemExpiryState {
        case normal
        case expiringSoon
        case expired
    }

    enum SiriRemovalStatus: Sendable {
        case removed
        case notFound
        case ambiguous
        case forbidden
    }

    struct SiriRemovalResponse: Sendable {
        let status: SiriRemovalStatus
        let dialog: String
    }

    private var currentRole: HouseholdRole {
        data.household.members.first(where: { $0.userID == data.currentUserID })?.role ?? .viewer
    }

    func userName(for userID: UUID) -> String {
        data.users.first(where: { $0.id == userID })?.displayName ?? "Unknown"
    }

    func switchCurrentUser(to userID: UUID) {
        guard data.users.contains(where: { $0.id == userID }) else { return }
        data.currentUserID = userID
        save()
    }

    func renameCurrentUser(_ displayName: String) {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = data.users.firstIndex(where: { $0.id == data.currentUserID }) else { return }
        data.users[index].displayName = trimmed
        save()
    }

    func renameHousehold(_ name: String) {
        guard canCurrentUserManageMembers else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.household.name = trimmed
        save()
    }

    func addMember(displayName: String, role: HouseholdRole) {
        guard canCurrentUserManageMembers else { return }

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !data.users.contains(where: { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }

        let user = AppUser(id: UUID(), displayName: trimmed)
        let member = HouseholdMember(id: UUID(), userID: user.id, role: role, joinedAt: Date())
        data.users.append(user)
        data.household.members.append(member)
        save()
    }

    func updateMemberRole(memberID: UUID, role: HouseholdRole) {
        guard canCurrentUserManageMembers else { return }
        guard let index = data.household.members.firstIndex(where: { $0.id == memberID }) else { return }

        let member = data.household.members[index]
        if member.userID == data.currentUserID && role != .owner {
            return
        }

        data.household.members[index].role = role
        ensureAtLeastOneOwner()
        save()
    }

    func removeMember(memberID: UUID) {
        guard canCurrentUserManageMembers else { return }
        guard let index = data.household.members.firstIndex(where: { $0.id == memberID }) else { return }

        let member = data.household.members[index]
        if member.userID == data.currentUserID {
            return
        }

        data.household.members.remove(at: index)

        let stillReferenced = data.household.members.contains(where: { $0.userID == member.userID })
        if !stillReferenced {
            data.users.removeAll { $0.id == member.userID }
        }

        ensureAtLeastOneOwner()
        save()
    }

    func completeOnboarding(drawers: [DrawerDraft], thresholdMonths: Int) {
        guard canCurrentUserEditContent else { return }

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
        guard canCurrentUserEditContent else { return }
        guard !name.freezerNormalized.isEmpty else { return }

        let fallbackCategory = categoryID ?? suggestedCategory(for: name)?.id ?? categories.first?.id
        guard let chosenCategoryID = fallbackCategory else { return }

        let fallbackDrawer = drawerID ?? suggestedDrawer(for: chosenCategoryID)?.id ?? drawers.first?.id
        guard let chosenDrawerID = fallbackDrawer else { return }

        let now = Date()
        let item = FreezerItem(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedName: name.freezerNormalized,
            categoryID: chosenCategoryID,
            drawerID: chosenDrawerID,
            quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
            dateAdded: dateAdded,
            createdByUserID: data.currentUserID,
            updatedByUserID: data.currentUserID,
            updatedAt: now
        )

        data.items.append(item)
        saveAndRefreshNotifications()
    }

    func updateItem(_ item: FreezerItem) {
        guard canCurrentUserEditContent else { return }
        guard let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }

        var updated = item
        updated.normalizedName = item.name.freezerNormalized
        updated.updatedByUserID = data.currentUserID
        updated.updatedAt = Date()
        data.items[index] = updated
        saveAndRefreshNotifications()
    }

    func deleteItem(id: UUID) {
        guard canCurrentUserEditContent else { return }
        data.items.removeAll { $0.id == id }
        saveAndRefreshNotifications()
    }

    func setThresholdMonths(_ months: Int) {
        guard canCurrentUserEditContent else { return }
        data.settings.thresholdMonths = max(1, months)
        saveAndRefreshNotifications()
    }

    func updateDrawers(_ updatedDrawers: [FreezerDrawer]) {
        guard canCurrentUserEditContent else { return }

        data.drawers = updatedDrawers.enumerated().map { index, drawer in
            var copy = drawer
            copy.order = index
            return copy
        }
        save()
    }

    func addUserMapping(keyword: String, categoryID: UUID) {
        guard canCurrentUserEditContent else { return }

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

    func addCategory(name: String) {
        guard canCurrentUserEditContent else { return }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !data.categories.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }

        data.categories.append(FreezerCategory(id: UUID(), name: trimmed))
        save()
    }

    func updateCategories(_ categories: [FreezerCategory]) {
        guard canCurrentUserEditContent else { return }

        let cleaned = categories
            .map {
                FreezerCategory(
                    id: $0.id,
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.name.isEmpty }

        guard !cleaned.isEmpty else { return }

        var unique: [FreezerCategory] = []
        for category in cleaned {
            if !unique.contains(where: { $0.name.caseInsensitiveCompare(category.name) == .orderedSame }) {
                unique.append(category)
            }
        }

        guard !unique.isEmpty else { return }
        data.categories = unique

        let validCategoryIDs = Set(unique.map(\.id))
        let fallbackCategoryID = unique[0].id

        for index in data.drawers.indices where !validCategoryIDs.contains(data.drawers[index].defaultCategoryID) {
            data.drawers[index].defaultCategoryID = fallbackCategoryID
        }

        for index in data.items.indices where !validCategoryIDs.contains(data.items[index].categoryID) {
            data.items[index].categoryID = fallbackCategoryID
        }

        for index in data.userMappings.indices where !validCategoryIDs.contains(data.userMappings[index].categoryID) {
            data.userMappings[index].categoryID = fallbackCategoryID
        }

        save()
    }

    func deleteCategory(id: UUID) {
        guard canCurrentUserEditContent else { return }
        guard data.categories.count > 1 else { return }
        guard data.categories.contains(where: { $0.id == id }) else { return }
        guard let fallbackCategory = data.categories.first(where: { $0.id != id }) else { return }

        data.categories.removeAll { $0.id == id }

        for index in data.drawers.indices where data.drawers[index].defaultCategoryID == id {
            data.drawers[index].defaultCategoryID = fallbackCategory.id
        }

        for index in data.items.indices where data.items[index].categoryID == id {
            data.items[index].categoryID = fallbackCategory.id
        }

        for index in data.userMappings.indices where data.userMappings[index].categoryID == id {
            data.userMappings[index].categoryID = fallbackCategory.id
        }

        save()
    }

    func updateUserMapping(_ mapping: FoodMapping) {
        guard canCurrentUserEditContent else { return }
        guard let index = data.userMappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        data.userMappings[index] = mapping
        save()
    }

    func deleteMapping(id: UUID) {
        guard canCurrentUserEditContent else { return }
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

    func removeItemForSiri(itemTerm: String, drawerName requestedDrawerName: String?) -> SiriRemovalResponse {
        guard canCurrentUserEditContent else {
            return SiriRemovalResponse(
                status: .forbidden,
                dialog: "You do not have permission to remove freezer items."
            )
        }

        let trimmedTerm = itemTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTerm = trimmedTerm.freezerNormalized
        guard !normalizedTerm.isEmpty else {
            return SiriRemovalResponse(
                status: .notFound,
                dialog: "I could not find that item in your freezer."
            )
        }

        var matches = items.filter { item in
            item.normalizedName == normalizedTerm ||
            item.normalizedName.contains(normalizedTerm) ||
            normalizedTerm.contains(item.normalizedName)
        }

        if let requestedDrawerName, !requestedDrawerName.freezerNormalized.isEmpty {
            let normalizedDrawer = requestedDrawerName.freezerNormalized
            matches = matches.filter { self.drawerName(for: $0.drawerID).freezerNormalized == normalizedDrawer }
        }

        matches = matches.sorted { $0.dateAdded < $1.dateAdded }

        guard !matches.isEmpty else {
            return SiriRemovalResponse(
                status: .notFound,
                dialog: "I could not find \(trimmedTerm) in your freezer."
            )
        }

        if matches.count > 1 {
            let drawers = Array(Set(matches.map { drawerName(for: $0.drawerID) })).sorted()
            let drawerList = drawers.joined(separator: ", ")
            return SiriRemovalResponse(
                status: .ambiguous,
                dialog: "I found \(trimmedTerm) in \(drawerList). Please repeat with the drawer name."
            )
        }

        guard let item = matches.first else {
            return SiriRemovalResponse(
                status: .notFound,
                dialog: "I could not find \(trimmedTerm) in your freezer."
            )
        }

        let drawer = drawerName(for: item.drawerID)
        deleteItem(id: item.id)

        return SiriRemovalResponse(
            status: .removed,
            dialog: "\(item.name) removed from \(drawer)."
        )
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

    func expiryState(for item: FreezerItem, referenceDate: Date = Date()) -> ItemExpiryState {
        guard let expiryDate = Calendar.current.date(byAdding: .month, value: thresholdMonths, to: item.dateAdded),
              let warningStart = Calendar.current.date(byAdding: .month, value: -1, to: expiryDate) else {
            return .normal
        }

        if referenceDate >= expiryDate {
            return .expired
        }

        if referenceDate >= warningStart {
            return .expiringSoon
        }

        return .normal
    }

    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func reloadFromDiskIfChanged() {
        guard let loaded = Self.loadFromDisk(url: saveURL) else { return }
        data = loaded
        migrateMultiUserDefaultsIfNeeded()
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

    private nonisolated static func loadFromDisk(url: URL) -> FreezerData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FreezerData.self, from: raw)
    }

    nonisolated static func intentSnapshot() -> FreezerData {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = documents.appendingPathComponent("freezer-data.json")
        return loadFromDisk(url: url) ?? FreezerData.initial()
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

    private func roleRank(_ role: HouseholdRole) -> Int {
        switch role {
        case .owner: return 0
        case .editor: return 1
        case .viewer: return 2
        }
    }

    private func ensureAtLeastOneOwner() {
        if data.household.members.contains(where: { $0.role == .owner }) {
            return
        }

        if let firstIndex = data.household.members.indices.first {
            data.household.members[firstIndex].role = .owner
        }
    }

    private func migrateMultiUserDefaultsIfNeeded() {
        if data.users.isEmpty {
            let user = AppUser(id: UUID(), displayName: "You")
            data.users = [user]
            data.currentUserID = user.id
        }

        if !data.users.contains(where: { $0.id == data.currentUserID }) {
            data.currentUserID = data.users[0].id
        }

        if data.household.members.isEmpty {
            data.household.members = [
                HouseholdMember(id: UUID(), userID: data.currentUserID, role: .owner, joinedAt: Date())
            ]
        }

        if !data.household.members.contains(where: { $0.userID == data.currentUserID }) {
            data.household.members.append(
                HouseholdMember(id: UUID(), userID: data.currentUserID, role: .owner, joinedAt: Date())
            )
        }

        ensureAtLeastOneOwner()

        for index in data.items.indices {
            if !data.users.contains(where: { $0.id == data.items[index].createdByUserID }) {
                data.items[index].createdByUserID = data.currentUserID
            }
            if !data.users.contains(where: { $0.id == data.items[index].updatedByUserID }) {
                data.items[index].updatedByUserID = data.currentUserID
            }
        }

        save()
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
