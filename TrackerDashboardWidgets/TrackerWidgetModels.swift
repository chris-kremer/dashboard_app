import Foundation
import WidgetKit

struct TrackerWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TrackerSnapshot
}

struct TrackerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrackerWidgetEntry {
        TrackerWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrackerWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrackerWidgetEntry>) -> Void) {
        let entry = entry()
        let hasRunningTask = entry.snapshot.todayOpenTasks.contains { $0.start != nil && $0.stop == nil }
        let interval = hasRunningTask ? 60 : 1800
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(TimeInterval(interval)))))
    }

    private func entry() -> TrackerWidgetEntry {
        TrackerWidgetEntry(date: Date(), snapshot: SharedCache.shared.loadSnapshot() ?? .empty)
    }
}

extension TrackerSnapshot {
    var todayOpenTasks: [ScheduleItem] {
        openTasks
            .filter { $0.date == date }
            .sorted {
                ($0.adjustedPriority ?? -1, $0.priority ?? -1, $0.task) >
                ($1.adjustedPriority ?? -1, $1.priority ?? -1, $1.task)
            }
    }
}
