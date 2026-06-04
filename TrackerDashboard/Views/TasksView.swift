import SwiftUI

struct TasksView: View {
    @Environment(SyncController.self) private var sync
    @State private var showingAddTask = false

    private var tasks: [ScheduleItem] {
        sync.snapshot.openTasks.sorted {
            ($0.adjustedPriority ?? -1, $0.priority ?? -1) >
            ($1.adjustedPriority ?? -1, $1.priority ?? -1)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if tasks.isEmpty {
                    EmptyStateView(title: "No open tasks", systemImage: "checkmark.circle")
                } else {
                    ForEach(tasks) { task in
                        TaskRowView(task: task)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddTask = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add task")
                }
            }
            .sheet(isPresented: $showingAddTask) { AddTaskView() }
        }
    }
}
