import Foundation

struct CaffeineEntry: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let label: String
    let time: String
}
