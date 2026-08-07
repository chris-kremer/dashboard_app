import Foundation

struct FoodEntry: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let time: String
    let mealContext: String
    let item: String
    let amount: String?
    let location: String?
    let notes: String?
    let confidence: String?
}

struct FoodSuggestion: Codable, Identifiable, Equatable {
    let item: String
    let mealContext: String?
    let amount: String?
    let location: String?
    let confidence: String?
    let useCount: Int
    let lastUsedDate: String

    var id: String { item.lowercased() }
}
