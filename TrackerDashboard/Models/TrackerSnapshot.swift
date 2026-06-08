import Foundation

struct TrackerSnapshot: Codable, Equatable {
    let serverTime: Date
    let date: String
    var schedule: [ScheduleItem]
    var openTasks: [ScheduleItem]
    var caffeine: [CaffeineEntry]
    var caffeineOptions: [String]?
    var food: [FoodEntry]
    var sleep: SleepEntry?
    var freeTime: [FreeTimeEntry]?

    static var empty: TrackerSnapshot {
        TrackerSnapshot(
            serverTime: Date(),
            date: Date.trackerDateFormatter.string(from: Date()),
            schedule: [],
            openTasks: [],
            caffeine: [],
            caffeineOptions: [],
            food: [],
            sleep: nil,
            freeTime: []
        )
    }
}

extension TrackerSnapshot {
    var todayOpenTasks: [ScheduleItem] {
        openTasks
            .filter { $0.date == date && $0.isOpenDisplayTask }
            .sorted {
                ($0.adjustedPriority ?? -1, $0.priority ?? -1, $0.task) >
                ($1.adjustedPriority ?? -1, $1.priority ?? -1, $1.task)
            }
    }
}

extension Date {
    static let trackerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let trackerTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
