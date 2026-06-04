import SwiftUI

struct TaskRowView: View {
    @Environment(SyncController.self) private var sync
    let task: ScheduleItem
    var rank: Int?
    var compact = false
    @State private var editing = false

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
                    Button {
                        Task { await sync.completeTask(task) }
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    Button {
                        Task { await sync.startTask(task) }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .accessibilityLabel("Start task")
                    Button {
                        Task { await sync.stopTask(task) }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .accessibilityLabel("Stop task")
                    if !compact {
                        Button {
                            editing = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Edit task")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $editing) {
            EditTaskView(task: task)
        }
    }
}
