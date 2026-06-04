import Foundation
import Observation

@Observable
final class TodayViewModel {
    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    func currentBlock(in snapshot: TrackerSnapshot) -> ScheduleItem? {
        snapshot.schedule
            .filter { item in
                guard let start = item.start, let stop = item.stop else { return false }
                return time(start) <= minutesNow && minutesNow <= time(stop)
            }
            .sorted { time($0.stop ?? "23:59") < time($1.stop ?? "23:59") }
            .first
    }

    func nextBlock(in snapshot: TrackerSnapshot) -> ScheduleItem? {
        snapshot.schedule
            .filter { $0.start != nil }
            .filter { time($0.start ?? "00:00") > minutesNow }
            .sorted { time($0.start ?? "00:00") < time($1.start ?? "00:00") }
            .first
    }

    func sortedOpenTasks(in snapshot: TrackerSnapshot) -> [ScheduleItem] {
        snapshot.openTasks.sorted {
            ($0.adjustedPriority ?? -1, $0.priority ?? -1, $0.task) >
            ($1.adjustedPriority ?? -1, $1.priority ?? -1, $1.task)
        }
    }

    private var minutesNow: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func time(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }
}
