import Foundation

struct HealthSleepEntry: Codable, Equatable {
    var date: String
    var intervals: [HealthSleepInterval]
    var source: String
    var syncedAt: Date

    var sleepHours: Double {
        Double(totalMinutes) / 60
    }

    var totalMinutes: Int {
        intervals.reduce(0) { $0 + max(0, $1.durationMinutes) }
    }

    var sleepStart: String? {
        intervals.sorted { $0.start < $1.start }.first?.startTime
    }

    var actualWake: String? {
        intervals.sorted { $0.end < $1.end }.last?.endTime
    }
}

struct HealthSleepInterval: Codable, Identifiable, Equatable {
    var id: String
    var start: Date
    var end: Date

    var durationMinutes: Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }

    var startTime: String {
        Date.trackerTimeFormatter.string(from: start)
    }

    var endTime: String {
        Date.trackerTimeFormatter.string(from: end)
    }
}
