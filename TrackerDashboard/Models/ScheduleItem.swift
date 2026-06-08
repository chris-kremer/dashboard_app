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
    var plannedStart: String?
    var plannedStop: String?
    var lane: String?
    var source: String?
    var sourceId: String?
    var importedAt: String?

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
        case plannedStart
        case plannedStop
        case lane
        case source
        case sourceId
        case importedAt
    }
}

extension ScheduleItem {
    var isOpenDisplayTask: Bool {
        !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && status != .done
            && status != .cancelled
            && status != .logged
            && (stop == nil || status == .inProgress)
    }

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
