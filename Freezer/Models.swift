import Foundation

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
    var categories: [FreezerCategory]
    var drawers: [FreezerDrawer]
    var items: [FreezerItem]
    var userMappings: [FoodMapping]
    var settings: AppSettings

    static func initial() -> FreezerData {
        let categories = DefaultFoodData.initialCategories()
        return FreezerData(
            onboardingComplete: false,
            categories: categories,
            drawers: [],
            items: [],
            userMappings: [],
            settings: AppSettings(thresholdMonths: 6, notificationHour: 9)
        )
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
