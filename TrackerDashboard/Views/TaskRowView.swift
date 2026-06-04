import SwiftUI

struct TaskRowView: View {
    @Environment(SyncController.self) private var sync
    let task: ScheduleItem
    var rank: Int?
    var compact = false
    @State private var editing = false
    @State private var activeAction: TaskRowAction?

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.task)
                            .font(compact ? .headline : .title3.weight(.semibold))
                        Text([task.category, task.date].filter { !$0.isEmpty }.joined(separator: " • "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
        .sheet(isPresented: $editing) {
            EditTaskView(task: task)
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
                await sync.completeTask(task)
            case .start:
                await sync.startTask(task)
            case .stop:
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
