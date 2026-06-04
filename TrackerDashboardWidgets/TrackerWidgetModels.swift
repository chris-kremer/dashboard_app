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
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry()], policy: .after(refreshDate)))
    }

    private func entry() -> TrackerWidgetEntry {
        TrackerWidgetEntry(date: Date(), snapshot: SharedCache.shared.loadSnapshot() ?? .empty)
    }
}
