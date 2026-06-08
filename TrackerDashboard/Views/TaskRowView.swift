import SwiftUI

struct TaskRowView: View {
    @Environment(SyncController.self) private var sync
    let task: ScheduleItem
    var rank: Int?
    var compact = false
    @State private var editing = false
    @State private var activeAction: TaskRowAction?
    @State private var startedAtOverride: Date?
    @State private var stoppedAtOverride: Date?
    @State private var doneFillFraction: Double?

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 15)) { context in
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background {
                    progressBackground(now: context.date)
                }
        }
        .sheet(isPresented: $editing) {
            EditTaskView(task: task)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await sync.snoozeTask(task) }
            } label: {
                Label("2h", systemImage: "clock.arrow.circlepath")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await sync.deleteTask(task) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.task)
                        .font(compact ? .headline : .title3.weight(.semibold))
                    if !task.category.isEmpty {
                        Text(task.category)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                PriorityChip(value: rank, colorValue: task.adjustedPriority)
            }

            HStack(spacing: 8) {
                if let estimate = task.estimateMinutes {
                    Label("\(estimate)m", systemImage: "timer")
                }
                if let priority = task.priority {
                    Label("P\(priority)", systemImage: "flag")
                }
                if let startedAt = taskStartDate() ?? startedAtOverride {
                    Label(elapsedText(since: startedAt, until: stoppedAtOverride ?? task.dateTime(from: task.stop)), systemImage: stoppedAtOverride == nil && task.stop == nil ? "clock" : "pause.circle")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                actionButton(.done)
                startStopButton
                if !compact {
                    Button {
                        editing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit task")
                }
            }
        }
    }

    private var startStopButton: some View {
        let action: TaskRowAction = isRunning ? .stop : .start
        return actionButton(action)
    }

    private func actionButton(_ action: TaskRowAction) -> some View {
        let isActive = activeAction == action
        return Button {
            trigger(action)
        } label: {
            actionLabel(action, isActive: isActive)
            .font(.headline)
            .foregroundStyle(isActive ? .white : action.tint)
            .frame(minWidth: action == .done ? 86 : 44, minHeight: 40)
            .background(isActive ? action.tint : action.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(action.tint.opacity(isActive ? 0 : 0.18), lineWidth: 1)
            }
            .scaleEffect(isActive ? 1.07 : 1)
            .symbolEffect(.bounce, value: activeAction)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.accessibilityLabel)
    }

    @ViewBuilder
    private func actionLabel(_ action: TaskRowAction, isActive: Bool) -> some View {
        let image = isActive ? action.activeSystemImage : action.systemImage
        if action == .done {
            Label("Done", systemImage: image)
        } else {
            Image(systemName: image)
        }
    }

    private func trigger(_ action: TaskRowAction) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
            activeAction = action
        }
        Task {
            switch action {
            case .done:
                await animateDoneFill()
                await sync.completeTask(task)
            case .start:
                await MainActor.run {
                    startedAtOverride = Date()
                    stoppedAtOverride = nil
                }
                await sync.startTask(task)
            case .stop:
                await MainActor.run {
                    stoppedAtOverride = Date()
                }
                await sync.stopTask(task)
            }
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    if activeAction == action {
                        activeAction = nil
                    }
                }
            }
        }
    }

    private func progressBackground(now: Date) -> some View {
        GeometryReader { proxy in
            let progress = progressState(now: now)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
                if let doneFillFraction {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.green.opacity(0.34))
                        .frame(width: proxy.size.width * doneFillFraction)
                        .animation(.easeOut(duration: 0.32), value: doneFillFraction)
                } else if let progress {
                    phaseFill(color: .green, fraction: progress.greenFraction, width: proxy.size.width)
                    phaseFill(color: .yellow, fraction: progress.yellowFraction, width: proxy.size.width)
                    phaseFill(color: .orange, fraction: progress.orangeFraction, width: proxy.size.width)
                    phaseFill(color: .red, fraction: progress.redFraction, width: proxy.size.width)
                }
            }
        }
    }

    private func phaseFill(color: Color, fraction: Double, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.opacity(0.26))
            .frame(width: width * fraction)
            .animation(.linear(duration: 15), value: fraction)
    }

    private func progressState(now: Date) -> (greenFraction: Double, yellowFraction: Double, orangeFraction: Double, redFraction: Double)? {
        guard let estimate = task.estimateMinutes,
              estimate > 0,
              let startedAt = taskStartDate() ?? startedAtOverride
        else {
            return nil
        }

        let effectiveNow = stoppedAtOverride ?? task.dateTime(from: task.stop) ?? now
        let elapsedMinutes = max(0, effectiveNow.timeIntervalSince(startedAt) / 60)
        let ratio = elapsedMinutes / Double(estimate)
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

    private func taskStartDate() -> Date? {
        task.dateTime(from: task.start)
    }

    private func elapsedText(since startedAt: Date, until stoppedAt: Date?) -> String {
        let minutes = max(0, Int((stoppedAt ?? Date()).timeIntervalSince(startedAt) / 60))
        let suffix = stoppedAt == nil ? "elapsed" : "paused"
        if minutes < 60 {
            return "\(minutes)m \(suffix)"
        }
        return "\(minutes / 60)h \(minutes % 60)m \(suffix)"
    }

    private func animateDoneFill() async {
        let current = await MainActor.run {
            progressState(now: Date())?.greenFraction ?? 0
        }
        await MainActor.run {
            doneFillFraction = current
        }
        try? await Task.sleep(for: .milliseconds(40))
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.32)) {
                doneFillFraction = 1
            }
        }
        try? await Task.sleep(for: .milliseconds(360))
    }

    private var isRunning: Bool {
        if startedAtOverride != nil && stoppedAtOverride == nil {
            return true
        }
        return task.start != nil && task.stop == nil
    }
}

private enum TaskRowAction {
    case done
    case start
    case stop

    var systemImage: String {
        switch self {
        case .done: "checkmark"
        case .start: "play.fill"
        case .stop: "stop.fill"
        }
    }

    var activeSystemImage: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .start: "play.circle.fill"
        case .stop: "stop.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .done: .green
        case .start: .orange
        case .stop: .blue
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .done: "Mark task done"
        case .start: "Start task"
        case .stop: "Stop task"
        }
    }
}
