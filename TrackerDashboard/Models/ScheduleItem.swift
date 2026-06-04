import Foundation

struct ScheduleItem: Codable, Identifiable, Equatable {
    let id: String
    let rowNumber: Int
    var date: String
    var task: String
    var category: String
    var comment: String?
    var priority: Int?
    var estimateMinutes: Int?
    var adjustedPriority: Int?
    var delay: String?
    var actualMinutes: Int?
    var start: String?
    var stop: String?
    var status: TaskStatus

    enum CodingKeys: String, CodingKey {
        case id = "rowId"
        case rowNumber
        case date
        case task
        case category
        case comment
        case priority
        case estimateMinutes
        case adjustedPriority
        case delay
        case actualMinutes
        case start
        case stop
        case status
    }
}
