import SwiftUI

struct WatchTaskDetailView: View {
    var task: ScheduleItem
    @Bindable var store: WatchTrackerStore

    private var currentTask: ScheduleItem {
        store.snapshot.schedule.first(where: { $0.id == task.id })
            ?? store.snapshot.openTasks.first(where: { $0.id == task.id })
            ?? task
    }

    private var isRunning: Bool {
        currentTask.status == .inProgress || (currentTask.start != nil && currentTask.stop == nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(currentTask.task)
                        .font(.title3.weight(.semibold))
                    Text(currentTask.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if let estimate = currentTask.estimateMinutes {
                        Label("\(estimate)m", systemImage: "clock")
                    }
                    if let priority = currentTask.priority {
                        Label("P\(priority)", systemImage: "flag")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Button {
                        Task {
                            if isRunning {
                                await store.pause(currentTask)
                            } else {
                                await store.start(currentTask)
                            }
                        }
                    } label: {
                        Label(isRunning ? "Pause" : "Start", systemImage: isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRunning ? .orange : .green)

                    Button(role: .destructive) {
                        Task { await store.complete(currentTask) }
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }

                if let start = currentTask.start {
                    Text("Started \(start)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let stop = currentTask.stop {
                    Text("Stopped \(stop)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .navigationTitle(isRunning ? "Running" : "Task")
    }
}
