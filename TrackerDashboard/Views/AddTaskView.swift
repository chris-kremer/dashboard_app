import SwiftUI

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncController.self) private var sync
    @State private var task = ""
    @State private var category = ""
    @State private var comment = ""
    @State private var priority = 3
    @State private var estimate = 30
    @State private var date = Date()
    @FocusState private var taskFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $task)
                    .focused($taskFieldFocused)
                if !matchingSuggestions.isEmpty {
                    Section("Previous tasks") {
                        ForEach(matchingSuggestions) { suggestion in
                            Button {
                                apply(suggestion)
                            } label: {
                                suggestionRow(suggestion)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                TextField("Category", text: $category)
                TextField("Comment", text: $comment, axis: .vertical)
                Stepper("Priority \(priority)", value: $priority, in: 1...10)
                Stepper("Estimate \(estimate)m", value: $estimate, in: 5...480, step: 5)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Add Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let request = CreateTaskRequest(
                            date: Date.trackerDateFormatter.string(from: date),
                            task: task,
                            category: category,
                            comment: comment.isEmpty ? nil : comment,
                            priority: priority,
                            estimateMinutes: estimate
                        )
                        Task {
                            await sync.createTask(request)
                            dismiss()
                        }
                    }
                    .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var matchingSuggestions: [TaskSuggestion] {
        guard taskFieldFocused else { return [] }
        let query = normalized(task)
        guard !query.isEmpty else { return [] }
        return Array((sync.snapshot.taskSuggestions ?? [])
            .filter { normalized($0.task).contains(query) }
            .sorted {
                let leftPrefix = normalized($0.task).hasPrefix(query)
                let rightPrefix = normalized($1.task).hasPrefix(query)
                if leftPrefix != rightPrefix { return leftPrefix }
                if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
                return $0.lastUsedDate > $1.lastUsedDate
            }
            .prefix(5))
    }

    private func apply(_ suggestion: TaskSuggestion) {
        task = suggestion.task
        if let value = suggestion.category { category = value }
        if let value = suggestion.comment { comment = value }
        if let value = suggestion.priority { priority = min(max(value, 1), 10) }
        if let value = suggestion.estimateMinutes { estimate = min(max(value, 5), 480) }
        taskFieldFocused = false
    }

    private func suggestionRow(_ suggestion: TaskSuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.task)
                    .font(.subheadline.weight(.semibold))
                Text(taskSuggestionDetail(suggestion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text("×\(suggestion.useCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func taskSuggestionDetail(_ suggestion: TaskSuggestion) -> String {
        var parts: [String] = []
        if let category = suggestion.category, !category.isEmpty { parts.append(category) }
        if let priority = suggestion.priority { parts.append("P\(priority)") }
        if let estimate = suggestion.estimateMinutes { parts.append("\(estimate)m") }
        return parts.joined(separator: " · ")
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
