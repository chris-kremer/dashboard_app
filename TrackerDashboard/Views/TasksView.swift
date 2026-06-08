import SwiftUI

struct TasksView: View {
    @Environment(SyncController.self) private var sync
    @State private var showingAddTask = false

    private var tasks: [ScheduleItem] {
        sync.snapshot.todayOpenTasks
    }

    var body: some View {
        NavigationStack {
            List {
                if tasks.isEmpty {
                    EmptyStateView(title: "No open tasks", systemImage: "checkmark.circle")
                } else {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRowView(task: task, rank: index + 1)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Tasks")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddTask = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add task")
                }
#else
                ToolbarItem {
                    Button { showingAddTask = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add task")
                }
#endif
            }
            .sheet(isPresented: $showingAddTask) { AddTaskView() }
        }
    }
}
