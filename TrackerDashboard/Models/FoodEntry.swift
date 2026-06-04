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
