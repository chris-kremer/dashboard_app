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

            if !compact, let comment = task.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                actionButton(.start)
                actionButton(.stop)
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
                    startedAtOverride = resumedStartDate() ?? Date()
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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(progress.color.opacity(0.26))
                        .frame(width: proxy.size.width * progress.widthFraction)
                        .animation(.linear(duration: 15), value: progress.widthFraction)
                        .animation(.linear(duration: 15), value: progress.colorStep)
                }
            }
        }
    }

    private func progressState(now: Date) -> (widthFraction: Double, color: Color, colorStep: Int)? {
        guard let estimate = task.estimateMinutes,
              estimate > 0,
              let startedAt = taskStartDate() ?? startedAtOverride
        else {
            return nil
        }

        let effectiveNow = stoppedAtOverride ?? task.dateTime(from: task.stop) ?? now
        let elapsedMinutes = max(0, effectiveNow.timeIntervalSince(startedAt) / 60)
        let ratio = elapsedMinutes / Double(estimate)
        let widthFraction = min(max(ratio, 0), 1)
        let color = progressColor(for: ratio)
        let colorStep = min(Int(ratio * 20), 80)
        return (widthFraction, color, colorStep)
    }

    private func progressColor(for ratio: Double) -> Color {
        if ratio <= 1 {
            return .green
        }
        if ratio <= 2 {
            return Color(hue: interpolate(from: 0.33, to: 0.14, progress: ratio - 1), saturation: 0.82, brightness: 0.90)
        }
        if ratio <= 3 {
            return Color(hue: interpolate(from: 0.14, to: 0.08, progress: ratio - 2), saturation: 0.88, brightness: 0.94)
        }
        if ratio <= 4 {
            return Color(hue: interpolate(from: 0.08, to: 0.00, progress: ratio - 3), saturation: 0.88, brightness: 0.92)
        }
        return .red
    }

    private func interpolate(from start: Double, to end: Double, progress: Double) -> Double {
        start + ((end - start) * min(max(progress, 0), 1))
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

    private func resumedStartDate() -> Date? {
        guard let startedAt = taskStartDate(),
              let stoppedAt = stoppedAtOverride ?? task.dateTime(from: task.stop)
        else {
            return nil
        }
        let elapsed = max(0, stoppedAt.timeIntervalSince(startedAt))
        return Date().addingTimeInterval(-elapsed)
    }

    private func animateDoneFill() async {
        let current = await MainActor.run {
            progressState(now: Date())?.widthFraction ?? 0
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
