import Foundation

struct TrackerSnapshot: Codable, Equatable {
    let serverTime: Date
    let date: String
    var schedule: [ScheduleItem]
    var openTasks: [ScheduleItem]
    var caffeine: [CaffeineEntry]
    var caffeineOptions: [String]?
    var food: [FoodEntry]
    var taskSuggestions: [TaskSuggestion]?
    var foodSuggestions: [FoodSuggestion]?
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
            taskSuggestions: [],
            foodSuggestions: [],
            sleep: nil,
            freeTime: []
        )
    }
}

extension TrackerSnapshot {
    var openEstimateMinutes: Int { todayOpenTasks.reduce(0) { $0 + max(0, $1.estimateMinutes ?? 0) } }

    var finishedTaskCount: Int {
        schedule.filter { $0.date == date && $0.status == .done }.count
    }

    /// Actual intervals only; estimates and overlapping work are never double counted.
    func productiveMinutes(now: Date = Date()) -> Int {
        TrackerTime.unionMinutes(productiveIntervals(now: now))
    }

    func productiveIntervals(now: Date = Date()) -> [Range<Int>] {
        let today = date == Date.trackerDateFormatter.string(from: now)
        let endOfDay = today ? TrackerTime.minute(Date.trackerTimeFormatter.string(from: now)) ?? 0 : 1440
        return schedule.compactMap { item -> Range<Int>? in
            guard item.date == date, !item.isFreeTimeCategory,
                  [.done, .logged, .inProgress].contains(item.status),
                  let start = TrackerTime.minute(item.start),
                  let end = TrackerTime.minute(item.stop) ?? (today && item.status == .inProgress ? endOfDay : nil),
                  min(end, endOfDay) > start else { return nil }
            return start..<min(end, endOfDay)
        }
    }

    var todayOpenTasks: [ScheduleItem] {
        openTasks
            .filter { $0.date == date && $0.isOpenDisplayTask }
            .sorted {
                ($0.adjustedPriority ?? -1, $0.priority ?? -1, $0.task) >
                ($1.adjustedPriority ?? -1, $1.priority ?? -1, $1.task)
            }
    }
}

enum TrackerTime {
    static func freeTimeIntervals(_ entries: [FreeTimeEntry], limit: Int = 1440) -> [Range<Int>] {
        entries.flatMap { entry -> [Range<Int>] in
            guard let start = minute(entry.start ?? entry.time) else { return [] }
            let end = minute(entry.end) ?? (start + max(0, entry.durationMinutes ?? 0))
            if end < start, entry.end != nil {
                var ranges: [Range<Int>] = []
                if start < limit { ranges.append(start..<limit) }
                if min(end, limit) > 0 { ranges.append(0..<min(end, limit)) }
                return ranges
            }
            guard min(end, limit) > start else { return [] }
            return [start..<min(end, limit)]
        }
    }

    /// Greedy interval packing keeps simultaneous entries visible on separate tracks.
    static func laneAssignments(_ intervals: [Range<Int>]) -> [Int] {
        var ends: [Int] = []
        var result = Array(repeating: 0, count: intervals.count)
        for index in intervals.indices.sorted(by: { intervals[$0].lowerBound < intervals[$1].lowerBound }) {
            let interval = intervals[index]
            let lane = ends.firstIndex { $0 <= interval.lowerBound } ?? ends.count
            if lane == ends.count { ends.append(interval.upperBound) } else { ends[lane] = interval.upperBound }
            result[index] = lane
        }
        return result
    }
    static func label(_ minutes: Int) -> String {
        let value = max(0, minutes)
        if value < 60 { return "\(value)m" }
        return value % 60 == 0 ? "\(value / 60)h" : "\(value / 60)h \(value % 60)m"
    }

    static func minute(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0...59).contains(minute), hour < 24 || minute == 0 else { return nil }
        return hour * 60 + minute
    }

    static func unionMinutes(_ intervals: [Range<Int>]) -> Int {
        var merged: [Range<Int>] = []
        for interval in intervals.sorted(by: { $0.lowerBound < $1.lowerBound }) where !interval.isEmpty {
            if let last = merged.last, interval.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, interval.upperBound)
            } else { merged.append(interval) }
        }
        return merged.reduce(0) { $0 + $1.count }
    }
}

extension ScheduleItem {
    var isFreeTimeCategory: Bool {
        let value = category.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
        return value == "x" || value == "break" || ["free time", "social media", "youtube", "twitter", "entertainment", "leisure"].contains { value.contains($0) }
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
