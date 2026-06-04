import Foundation
import Observation

@Observable
final class TodayViewModel {
    var now: Date

    init(now: Date = Date()) {
        self.now = now
    }

    func currentBlocks(in snapshot: TrackerSnapshot, now: Date = Date()) -> [ScheduleItem] {
        let minutesNow = minutes(in: now)
        let runningItems = uniqueItems(snapshot.openTasks + snapshot.schedule)
            .filter { $0.start != nil && $0.stop == nil }
            .filter { $0.status != .done && $0.status != .cancelled }
            .sorted { time($0.start ?? "00:00") < time($1.start ?? "00:00") }

        let scheduledItems = snapshot.schedule
            .filter { item in
                guard let start = item.start, let stop = item.stop else { return false }
                return time(start) <= minutesNow && minutesNow <= time(stop)
            }
            .filter { $0.status != .cancelled }
            .sorted { time($0.stop ?? "23:59") < time($1.stop ?? "23:59") }

        return uniqueItems(runningItems + scheduledItems)
    }

    func currentBlock(in snapshot: TrackerSnapshot, now: Date = Date()) -> ScheduleItem? {
        currentBlocks(in: snapshot, now: now).first
    }

    func nextBlock(in snapshot: TrackerSnapshot, now: Date = Date()) -> ScheduleItem? {
        let minutesNow = minutes(in: now)
        return snapshot.schedule
            .filter { $0.start != nil && $0.stop != nil }
            .filter { $0.status != .inProgress }
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
        minutes(in: now)
    }

    private func minutes(in date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func time(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    private func uniqueItems(_ items: [ScheduleItem]) -> [ScheduleItem] {
        var seen = Set<String>()
        return items.filter { item in
            guard !seen.contains(item.id) else { return false }
            seen.insert(item.id)
            return true
        }
    }
}
