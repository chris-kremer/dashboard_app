import SwiftUI
import WidgetKit

struct LockScreenStatusWidget: Widget {
    let kind = "LockScreenStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrackerWidgetProvider()) { entry in
            LockScreenStatusWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Tracker Status")
        .description("Shows open task count or top task on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockScreenStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrackerWidgetEntry

    private var topTask: ScheduleItem? {
        entry.snapshot.openTasks.sorted { ($0.adjustedPriority ?? -1) > ($1.adjustedPriority ?? -1) }.first
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.snapshot.openTasks.count), in: 0...20) {
                Image(systemName: "checklist")
            } currentValueLabel: {
                Text("\(entry.snapshot.openTasks.count)")
            }
            .gaugeStyle(.accessoryCircular)
        default:
            VStack(alignment: .leading) {
                Text(topTask?.task ?? "No open tasks")
                    .font(.headline)
                    .lineLimit(1)
                if let start = entry.snapshot.schedule.first(where: { $0.start != nil })?.start {
                    Text("Next \(start)")
                        .font(.caption)
                } else {
                    Text("\(entry.snapshot.openTasks.count) open")
                        .font(.caption)
                }
            }
        }
    }
}
