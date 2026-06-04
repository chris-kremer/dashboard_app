import Foundation

struct FreeTimeEntry: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let label: String
    let durationMinutes: Int?
    let time: String?
    let start: String?
    let end: String?
}
