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

extension ScheduleItem {
    func dateTime(from timeString: String?) -> Date? {
        guard let timeString,
              let time = Date.trackerTimeFormatter.date(from: timeString)
        else {
            return nil
        }

        let calendar = Calendar(identifier: .gregorian)
        let baseDate = Date.trackerDateFormatter.date(from: date) ?? Date()
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: baseDate
        )
    }
}
