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
        .supportedFamilies(Self.supportedFamilies)
    }

    private static var supportedFamilies: [WidgetFamily] {
#if os(macOS)
        [.systemSmall]
#else
        [.accessoryCircular, .accessoryRectangular]
#endif
    }
}

struct LockScreenStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrackerWidgetEntry

    private var completion: (finished: Int, total: Int, percent: Int, fraction: Double) {
        let items = entry.snapshot.schedule.filter { item in
            item.date == entry.snapshot.date
                && !item.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && item.status != .cancelled
        }
        let finished = items.filter(isFinished).count
        let total = items.count
        let fraction = total == 0 ? 0 : Double(finished) / Double(total)
        return (finished, total, Int((fraction * 100).rounded()), fraction)
    }

    private var topTask: ScheduleItem? {
        entry.snapshot.openTasks
            .filter { $0.date == entry.snapshot.date }
            .sorted { ($0.adjustedPriority ?? -1) > ($1.adjustedPriority ?? -1) }
            .first
    }

    var body: some View {
#if os(macOS)
        VStack(alignment: .leading, spacing: 8) {
            Gauge(value: completion.fraction, in: 0...1) {
                Text("Done")
            } currentValueLabel: {
                Text("\(completion.percent)%")
            }
            Text("\(completion.finished)/\(completion.total) tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(topTask?.task ?? "No open tasks")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
        .padding()
#else
        switch family {
        case .accessoryCircular:
            Gauge(value: completion.fraction, in: 0...1) {
                Image(systemName: "chart.pie.fill")
            } currentValueLabel: {
                Text("\(completion.percent)%")
            }
            .gaugeStyle(.accessoryCircular)
        default:
            VStack(alignment: .leading) {
                Text("\(completion.percent)% done")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(completion.finished)/\(completion.total) tasks")
                    .font(.caption)
                Text(topTask?.task ?? "No open tasks")
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
#endif
    }

    private func isFinished(_ item: ScheduleItem) -> Bool {
        item.status == .done
            || item.status == .logged
            || item.stop != nil
            || item.actualMinutes != nil
    }
}
