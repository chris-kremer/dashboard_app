import SwiftUI
import WidgetKit
#if os(iOS)
import ActivityKit
import AppIntents
#endif

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
#elseif os(watchOS)
        [.accessoryCircular, .accessoryRectangular, .accessoryInline]
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
        entry.snapshot.todayOpenTasks.first
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
        case .accessoryInline:
            Text("\(completion.percent)% done")
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

#if os(iOS)
struct TaskLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskLiveActivityAttributes.self) { context in
            TaskLiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.86))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.phase == .running ? "timer" : "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.mint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.activeTasks.count == 1,
                       let task = context.state.activeTasks.first {
                        Text(task.startedAt, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if context.state.activeTasks.count > 1 {
                        Text("\(context.state.activeTasks.count) live")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(islandTitle(for: context.state))
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TaskLiveActivityIslandBottomView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .running ? "timer" : "checkmark")
                    .foregroundStyle(.mint)
            } compactTrailing: {
                if context.state.activeTasks.count == 1,
                   let task = context.state.activeTasks.first {
                    Text(task.startedAt, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .frame(width: 42)
                } else if context.state.activeTasks.count > 1 {
                    Text("\(context.state.activeTasks.count)")
                        .font(.caption.weight(.bold))
                } else {
                    Text("Next")
                        .font(.caption2.weight(.semibold))
                }
            } minimal: {
                Image(systemName: context.state.phase == .running ? "timer" : "checkmark")
                    .foregroundStyle(.mint)
            }
            .keylineTint(.mint)
        }
    }

    private func islandTitle(for state: TaskLiveActivityAttributes.ContentState) -> String {
        if state.activeTasks.count > 1 {
            return "\(state.activeTasks.count) tasks running"
        }
        return state.activeTasks.first?.task ?? "Choose what’s next"
    }
}

private struct TaskLiveActivityLockScreenView: View {
    let state: TaskLiveActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.phase == .running {
                runningView
            } else {
                suggestionsView
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }

    private var runningView: some View {
        Group {
            if state.activeTasks.count == 1,
               let task = state.activeTasks.first {
                singleTaskView(task)
            } else {
                multipleTasksView
            }
        }
    }

    private func singleTaskView(_ task: TaskLiveActivityAttributes.RunningTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.task)
                        .font(.headline)
                        .lineLimit(2)
                    Text(task.category.isEmpty ? "Uncategorized" : task.category)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.mint)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button(intent: CompleteTaskIntent(rowId: task.rowId)) {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(.mint)
                .accessibilityLabel("Finish \(task.task)")
            }

            TaskLiveProgressView(task: task)
        }
    }

    private var multipleTasksView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(state.activeTasks.count) tasks running", systemImage: "timer")
                .font(.headline)
                .foregroundStyle(.mint)

            ForEach(state.activeTasks.prefix(3)) { task in
                TaskLiveCompactTaskRow(task: task)
            }

            if state.activeTasks.count > 3 {
                Text("+ \(state.activeTasks.count - 3) more running")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Done. Pick what’s next", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.mint)

            if state.suggestions.isEmpty {
                Text("Nothing else is queued for today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.suggestions.prefix(2)) { suggestion in
                    Button(intent: StartTaskIntent(rowId: suggestion.rowId)) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.task)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(suggestionDetail(suggestion))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func suggestionDetail(_ suggestion: TaskLiveActivityAttributes.Suggestion) -> String {
        let category = suggestion.category.isEmpty ? "Uncategorized" : suggestion.category
        guard let estimate = suggestion.estimateMinutes else { return category }
        return "\(category) · \(estimate) min"
    }
}

private struct TaskLiveProgressView: View {
    let task: TaskLiveActivityAttributes.RunningTask

    var body: some View {
        VStack(spacing: 6) {
            if let estimate = task.estimateMinutes,
               estimate > 0 {
                ProgressView(
                    timerInterval: task.startedAt...task.startedAt.addingTimeInterval(TimeInterval(estimate * 60)),
                    countsDown: false
                )
                .tint(.mint)
            } else {
                ProgressView(value: 0)
                    .tint(.mint)
            }

            HStack {
                Text(task.startedAt, style: .timer)
                    .monospacedDigit()
                Spacer()
                if let estimate = task.estimateMinutes {
                    Text("Estimate \(estimate) min")
                } else {
                    Text("No estimate")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }
}

private struct TaskLiveCompactTaskRow: View {
    let task: TaskLiveActivityAttributes.RunningTask

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.task)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(task.category.isEmpty ? "Uncategorized" : task.category)
                        Text("·")
                        Text(task.startedAt, style: .timer)
                            .monospacedDigit()
                        if let estimate = task.estimateMinutes {
                            Text("/ \(estimate)m")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 2)

                Button(intent: CompleteTaskIntent(rowId: task.rowId)) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(.mint)
                .accessibilityLabel("Finish \(task.task)")
            }

            if let estimate = task.estimateMinutes, estimate > 0 {
                ProgressView(
                    timerInterval: task.startedAt...task.startedAt.addingTimeInterval(TimeInterval(estimate * 60)),
                    countsDown: false
                )
                .tint(.mint)
            }
        }
    }
}

private struct TaskLiveActivityIslandBottomView: View {
    let state: TaskLiveActivityAttributes.ContentState

    var body: some View {
        if state.phase == .running {
            VStack(spacing: 7) {
                ForEach(state.activeTasks.prefix(2)) { task in
                    if state.activeTasks.count == 1 {
                        HStack(spacing: 12) {
                            TaskLiveProgressView(task: task)
                            Button(intent: CompleteTaskIntent(rowId: task.rowId)) {
                                Image(systemName: "checkmark")
                                    .font(.headline.weight(.bold))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.circle)
                            .tint(.mint)
                        }
                    } else {
                        TaskLiveCompactTaskRow(task: task)
                    }
                }
            }
        } else {
            HStack(spacing: 12) {
                ForEach(state.suggestions.prefix(2)) { suggestion in
                    Button(intent: StartTaskIntent(rowId: suggestion.rowId)) {
                        Label(suggestion.task, systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(.mint)
                }
            }
        }
    }
}
#endif
