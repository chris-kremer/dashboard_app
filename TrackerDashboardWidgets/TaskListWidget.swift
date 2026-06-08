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
        Array(entry.snapshot.todayOpenTasks.prefix(limit))
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
                Text("\(entry.snapshot.todayOpenTasks.count)")
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
                    phaseFill(color: .green, fraction: progress.greenFraction, width: proxy.size.width)
                    phaseFill(color: .yellow, fraction: progress.yellowFraction, width: proxy.size.width)
                    phaseFill(color: .orange, fraction: progress.orangeFraction, width: proxy.size.width)
                    phaseFill(color: .red, fraction: progress.redFraction, width: proxy.size.width)
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

    private func phaseFill(color: Color, fraction: Double, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color.opacity(0.32))
            .frame(width: width * fraction)
    }

    private func progressState(for task: ScheduleItem) -> (greenFraction: Double, yellowFraction: Double, orangeFraction: Double, redFraction: Double)? {
        guard let estimate = task.estimateMinutes,
              estimate > 0,
              let startedAt = task.dateTime(from: task.start)
        else {
            return nil
        }
        let effectiveNow = task.dateTime(from: task.stop) ?? entry.date
        let ratio = max(0, effectiveNow.timeIntervalSince(startedAt) / 60) / Double(estimate)
        return (
            phaseFraction(ratio),
            phaseFraction(ratio - 1),
            phaseFraction(ratio - 2),
            phaseFraction(ratio - 3)
        )
    }

    private func phaseFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
