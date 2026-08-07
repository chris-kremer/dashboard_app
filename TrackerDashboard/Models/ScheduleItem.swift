import Foundation
#if os(iOS)
import ActivityKit
#endif

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

#if os(iOS)
struct TaskLiveActivityAttributes: ActivityAttributes {
    struct RunningTask: Codable, Hashable, Identifiable {
        let rowId: String
        let task: String
        let category: String
        let startedAt: Date
        let estimateMinutes: Int?

        var id: String { rowId }
    }

    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case running
            case suggestions
            case morning
        }

        var phase: Phase
        var rowId: String?
        var task: String
        var category: String
        var startedAt: Date?
        var estimateMinutes: Int?
        var suggestions: [Suggestion]
        var runningTasks: [RunningTask]?
        var greeting: String?
        var morningDate: String?

        var activeTasks: [RunningTask] {
            if let runningTasks, !runningTasks.isEmpty {
                return runningTasks
            }
            guard phase == .running,
                  let rowId,
                  let startedAt
            else {
                return []
            }
            return [RunningTask(
                rowId: rowId,
                task: task,
                category: category,
                startedAt: startedAt,
                estimateMinutes: estimateMinutes
            )]
        }
    }

    struct Suggestion: Codable, Hashable, Identifiable {
        let rowId: String
        let task: String
        let category: String
        let estimateMinutes: Int?

        var id: String { rowId }
    }
}
#endif
