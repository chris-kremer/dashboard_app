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

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $task)
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
}
