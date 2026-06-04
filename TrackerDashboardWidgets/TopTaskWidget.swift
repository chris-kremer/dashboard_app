import SwiftUI
import WidgetKit
import AppIntents

struct TopTaskWidget: Widget {
    let kind = "TopTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrackerWidgetProvider()) { entry in
            TopTaskWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Top Task")
        .description("Shows the top open tracker task.")
        .supportedFamilies([.systemSmall])
    }
}

struct TopTaskWidgetView: View {
    let entry: TrackerWidgetEntry

    private var task: ScheduleItem? {
        entry.snapshot.openTasks.sorted { ($0.adjustedPriority ?? -1) > ($1.adjustedPriority ?? -1) }.first
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let task {
                progressFill(for: task)
            }
            content
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if let task {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.task)
                    .font(.headline.weight(.semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                if let category = optional(task.category) {
                    Text(category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    widgetButton(systemImage: "play.fill", tint: .orange, intent: StartTaskIntent(rowId: task.id))
                    widgetButton(systemImage: "stop.fill", tint: .blue, intent: StopTaskIntent(rowId: task.id))
                    widgetButton(systemImage: "checkmark", tint: .green, intent: CompleteTaskIntent(rowId: task.id))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("No open tasks")
                    .font(.headline)
                Spacer(minLength: 0)
            }
        }
    }

    private func widgetButton<I: AppIntent>(systemImage: String, tint: Color, intent: I) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func progressFill(for task: ScheduleItem) -> some View {
        GeometryReader { proxy in
            if let progress = progressState(for: task) {
                Rectangle()
                    .fill(progress.color.opacity(0.26))
                    .frame(width: proxy.size.width * progress.widthFraction)
                    .frame(maxHeight: .infinity)
            }
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

    private func optional(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
