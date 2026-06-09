import SwiftUI

struct WatchRootView: View {
    @Bindable var store: WatchTrackerStore

    var body: some View {
        NavigationStack {
            List {
                if !store.activeTasks.isEmpty {
                    Section("Now") {
                        ForEach(store.activeTasks.prefix(3)) { task in
                            NavigationLink {
                                WatchTaskDetailView(task: task, store: store)
                            } label: {
                                WatchTaskSummaryView(task: task, mode: .active)
                            }
                        }
                    }
                }

                Section("Tasks") {
                    if store.openTasks.isEmpty {
                        ContentUnavailableView("No tasks", systemImage: "checkmark.circle")
                    } else {
                        ForEach(store.openTasks.prefix(8)) { task in
                            NavigationLink {
                                WatchTaskDetailView(task: task, store: store)
                            } label: {
                                WatchTaskSummaryView(task: task, mode: .queued)
                            }
                        }
                    }
                }

                if let next = store.nextBlock {
                    Section("Next") {
                        WatchTaskSummaryView(task: next, mode: .next)
                    }
                }

                Section {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label(store.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing)

                    NavigationLink {
                        WatchSettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }

                if let lastError = store.lastError {
                    Section("Sync") {
                        Text(lastError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Tracker")
            .task {
                if store.lastRefresh == nil {
                    await store.refresh()
                }
            }
            .refreshable {
                await store.refresh()
            }
        }
    }
}

private enum WatchTaskSummaryMode {
    case active
    case queued
    case next
}

private struct WatchTaskSummaryView: View {
    var task: ScheduleItem
    var mode: WatchTaskSummaryMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.task)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if let adjustedPriority = task.adjustedPriority {
                    Text("\(adjustedPriority)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(priorityColor.opacity(0.25), in: Capsule())
                        .foregroundStyle(priorityColor)
                }
            }

            Text(task.category)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let estimate = task.estimateMinutes {
                    Label("\(estimate)m", systemImage: "clock")
                }
                if let start = task.start {
                    Label(start, systemImage: mode == .active ? "play.fill" : "calendar")
                }
                if let stop = task.stop {
                    Text("- \(stop)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var priorityColor: Color {
        switch task.adjustedPriority ?? task.priority ?? 0 {
        case 20...:
            .blue
        case 10..<20:
            .green
        case 5..<10:
            .mint
        case 2..<5:
            .yellow
        case 1:
            .orange
        default:
            .red
        }
    }
}
