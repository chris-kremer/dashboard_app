import SwiftUI

struct TasksView: View {
    @Environment(SyncController.self) private var sync
    @Environment(AppNavigation.self) private var navigation
    @State private var showingAddTask = false
    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tasks: [ScheduleItem] {
        let openTasks = sync.snapshot.todayOpenTasks
        let query = trimmedSearchText
        guard !query.isEmpty else { return openTasks }
        return openTasks.filter { task in
            [task.task, task.category, task.comment ?? "", task.lane ?? ""]
                .contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if tasks.isEmpty {
                    EmptyStateView(
                        title: trimmedSearchText.isEmpty
                            ? "No open tasks"
                            : "No matching tasks",
                        systemImage: trimmedSearchText.isEmpty
                            ? "checkmark.circle"
                            : "magnifyingglass"
                    )
                } else {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRowView(task: task, rank: index + 1)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Tasks")
            .searchable(text: $searchText, prompt: "Search tasks")
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
            .sheet(item: selectedTaskBinding) { task in
                EditTaskView(task: task)
            }
        }
    }

    private var selectedTaskBinding: Binding<ScheduleItem?> {
        Binding {
            navigation.selectedTask
        } set: { task in
            navigation.selectedTask = task
        }
    }
}
