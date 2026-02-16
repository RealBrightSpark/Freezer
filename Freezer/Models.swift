import Foundation

enum HouseholdRole: String, Codable, CaseIterable, Identifiable {
    case owner
    case editor
    case viewer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .owner: return "Owner"
        case .editor: return "Editor"
        case .viewer: return "Viewer"
        }
    }
}

struct AppUser: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
}

struct HouseholdMember: Identifiable, Codable, Hashable {
    let id: UUID
    var userID: UUID
    var role: HouseholdRole
    var joinedAt: Date
}

struct Household: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var members: [HouseholdMember]
}

struct FreezerCategory: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}

struct FreezerDrawer: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var order: Int
    var defaultCategoryID: UUID
}

struct FreezerItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var normalizedName: String
    var categoryID: UUID
    var drawerID: UUID
    var quantity: String
    var dateAdded: Date
    var createdByUserID: UUID
    var updatedByUserID: UUID
    var updatedAt: Date

    init(
        id: UUID,
        name: String,
        normalizedName: String,
        categoryID: UUID,
        drawerID: UUID,
        quantity: String,
        dateAdded: Date,
        createdByUserID: UUID,
        updatedByUserID: UUID,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName
        self.categoryID = categoryID
        self.drawerID = drawerID
        self.quantity = quantity
        self.dateAdded = dateAdded
        self.createdByUserID = createdByUserID
        self.updatedByUserID = updatedByUserID
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case normalizedName
        case categoryID
        case drawerID
        case quantity
        case dateAdded
        case createdByUserID
        case updatedByUserID
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        normalizedName = try container.decode(String.self, forKey: .normalizedName)
        categoryID = try container.decode(UUID.self, forKey: .categoryID)
        drawerID = try container.decode(UUID.self, forKey: .drawerID)
        quantity = try container.decode(String.self, forKey: .quantity)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        createdByUserID = try container.decodeIfPresent(UUID.self, forKey: .createdByUserID) ?? UUID()
        updatedByUserID = try container.decodeIfPresent(UUID.self, forKey: .updatedByUserID) ?? createdByUserID
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? dateAdded
    }
}

struct FoodMapping: Identifiable, Codable, Hashable {
    let id: UUID
    var keyword: String
    var categoryID: UUID
}

struct AppSettings: Codable, Hashable {
    var thresholdMonths: Int
    var notificationHour: Int
}

struct FreezerData: Codable {
    var onboardingComplete: Bool
    var users: [AppUser]
    var currentUserID: UUID
    var household: Household
    var categories: [FreezerCategory]
    var drawers: [FreezerDrawer]
    var items: [FreezerItem]
    var userMappings: [FoodMapping]
    var settings: AppSettings

    static func initial() -> FreezerData {
        let now = Date()
        let defaultUser = AppUser(id: UUID(), displayName: "You")
        let defaultMember = HouseholdMember(id: UUID(), userID: defaultUser.id, role: .owner, joinedAt: now)
        let household = Household(id: UUID(), name: "Home Freezer", createdAt: now, members: [defaultMember])
        let categories = DefaultFoodData.initialCategories()

        return FreezerData(
            onboardingComplete: false,
            users: [defaultUser],
            currentUserID: defaultUser.id,
            household: household,
            categories: categories,
            drawers: [],
            items: [],
            userMappings: [],
            settings: AppSettings(thresholdMonths: 6, notificationHour: 9)
        )
    }

    enum CodingKeys: String, CodingKey {
        case onboardingComplete
        case users
        case currentUserID
        case household
        case categories
        case drawers
        case items
        case userMappings
        case settings
    }

    init(
        onboardingComplete: Bool,
        users: [AppUser],
        currentUserID: UUID,
        household: Household,
        categories: [FreezerCategory],
        drawers: [FreezerDrawer],
        items: [FreezerItem],
        userMappings: [FoodMapping],
        settings: AppSettings
    ) {
        self.onboardingComplete = onboardingComplete
        self.users = users
        self.currentUserID = currentUserID
        self.household = household
        self.categories = categories
        self.drawers = drawers
        self.items = items
        self.userMappings = userMappings
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let fallback = FreezerData.initial()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        onboardingComplete = try container.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        categories = try container.decodeIfPresent([FreezerCategory].self, forKey: .categories) ?? fallback.categories
        drawers = try container.decodeIfPresent([FreezerDrawer].self, forKey: .drawers) ?? []
        items = try container.decodeIfPresent([FreezerItem].self, forKey: .items) ?? []
        userMappings = try container.decodeIfPresent([FoodMapping].self, forKey: .userMappings) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings(thresholdMonths: 6, notificationHour: 9)

        users = try container.decodeIfPresent([AppUser].self, forKey: .users) ?? fallback.users
        let decodedCurrentUserID = try container.decodeIfPresent(UUID.self, forKey: .currentUserID) ?? users.first?.id ?? fallback.currentUserID
        let fallbackOwnerID = users.first?.id ?? decodedCurrentUserID
        household = try container.decodeIfPresent(Household.self, forKey: .household) ?? {
            let member = HouseholdMember(id: UUID(), userID: fallbackOwnerID, role: .owner, joinedAt: Date())
            return Household(id: UUID(), name: "Home Freezer", createdAt: Date(), members: [member])
        }()
        currentUserID = decodedCurrentUserID
    }
}

enum DefaultFoodData {
    static let categoryNames = ["Meat", "Fish", "Dairy", "Fruit & Veg", "Ready Meal"]

    static func initialCategories() -> [FreezerCategory] {
        categoryNames.map { FreezerCategory(id: UUID(), name: $0) }
    }

    static let builtInKeywordMap: [String: String] = [
        "chicken": "Meat",
        "beef": "Meat",
        "lamb": "Meat",
        "pork": "Meat",
        "steak": "Meat",
        "mince": "Meat",
        "fish": "Fish",
        "salmon": "Fish",
        "cod": "Fish",
        "tuna": "Fish",
        "prawn": "Fish",
        "milk": "Dairy",
        "cheese": "Dairy",
        "butter": "Dairy",
        "yogurt": "Dairy",
        "yoghurt": "Dairy",
        "cream": "Dairy",
        "broccoli": "Fruit & Veg",
        "carrot": "Fruit & Veg",
        "peas": "Fruit & Veg",
        "spinach": "Fruit & Veg",
        "apple": "Fruit & Veg",
        "berries": "Fruit & Veg",
        "soup": "Ready Meal",
        "spag bol": "Ready Meal",
        "lasagne": "Ready Meal",
        "curry": "Ready Meal",
        "ready meal": "Ready Meal",
        "pizza": "Ready Meal"
    ]
}

extension String {
    var freezerNormalized: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
