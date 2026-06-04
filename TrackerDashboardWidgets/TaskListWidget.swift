import SwiftUI
import WidgetKit

struct TaskListWidget: Widget {
    let kind = "TaskListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrackerWidgetProvider()) { entry in
            TaskListWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Tracker Tasks")
        .description("Shows open tracker tasks and quick completion buttons.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TaskListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrackerWidgetEntry

    private var limit: Int { family == .systemLarge ? 6 : 3 }

    private var tasks: [ScheduleItem] {
        Array(entry.snapshot.openTasks.sorted { ($0.adjustedPriority ?? -1) > ($1.adjustedPriority ?? -1) }.prefix(limit))
    }

    private var nextBlock: ScheduleItem? {
        entry.snapshot.schedule
            .filter { $0.start != nil }
            .sorted { ($0.start ?? "") < ($1.start ?? "") }
            .first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Open Tasks")
                    .font(.headline)
                Spacer()
                Text("\(entry.snapshot.openTasks.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(tasks) { task in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.task)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(task.category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    startStopButton(for: task)
                    Button(intent: CompleteTaskIntent(rowId: task.id)) {
                        Image(systemName: "checkmark")
                    }
                    .foregroundStyle(.green)
                }
            }
            if family == .systemLarge, let nextBlock {
                Divider()
                Label("\(nextBlock.start ?? "") \(nextBlock.task)", systemImage: "clock")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    @ViewBuilder
    private func startStopButton(for task: ScheduleItem) -> some View {
        if task.start != nil && task.stop == nil {
            Button(intent: StopTaskIntent(rowId: task.id)) {
                Image(systemName: "stop.fill")
            }
            .foregroundStyle(.blue)
        } else {
            Button(intent: StartTaskIntent(rowId: task.id)) {
                Image(systemName: "play.fill")
            }
            .foregroundStyle(.orange)
        }
    }
}
