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
                taskRow(task)
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

    private func taskRow(_ task: ScheduleItem) -> some View {
        ZStack(alignment: .leading) {
            if let progress = progressState(for: task) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(progress.color.opacity(0.32))
                        .frame(width: proxy.size.width * progress.widthFraction)
                }
            }
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
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .frame(minHeight: 34)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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

    private func progressState(for task: ScheduleItem) -> (widthFraction: Double, color: Color)? {
        guard let estimate = task.estimateMinutes,
              estimate > 0,
              let startedAt = task.dateTime(from: task.start)
        else {
            return nil
        }
        let effectiveNow = task.dateTime(from: task.stop) ?? entry.date
        let ratio = max(0, effectiveNow.timeIntervalSince(startedAt) / 60) / Double(estimate)
        return (min(ratio, 1), progressColor(for: ratio))
    }

    private func progressColor(for ratio: Double) -> Color {
        if ratio <= 1 { return .green }
        if ratio <= 2 { return Color(hue: interpolate(from: 0.33, to: 0.14, progress: ratio - 1), saturation: 0.82, brightness: 0.90) }
        if ratio <= 3 { return Color(hue: interpolate(from: 0.14, to: 0.08, progress: ratio - 2), saturation: 0.88, brightness: 0.94) }
        if ratio <= 4 { return Color(hue: interpolate(from: 0.08, to: 0.00, progress: ratio - 3), saturation: 0.88, brightness: 0.92) }
        return .red
    }

    private func interpolate(from start: Double, to end: Double, progress: Double) -> Double {
        start + ((end - start) * min(max(progress, 0), 1))
    }
}
