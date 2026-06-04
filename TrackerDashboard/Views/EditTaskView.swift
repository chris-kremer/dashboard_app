import SwiftUI

struct EditTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncController.self) private var sync
    let task: ScheduleItem

    @State private var priority: Int
    @State private var estimate: Int
    @State private var comment: String

    init(task: ScheduleItem) {
        self.task = task
        _priority = State(initialValue: task.priority ?? 3)
        _estimate = State(initialValue: task.estimateMinutes ?? 30)
        _comment = State(initialValue: task.comment ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(task.task) {
                    Stepper("Priority \(priority)", value: $priority, in: 1...10)
                    Stepper("Estimate \(estimate)m", value: $estimate, in: 5...480, step: 5)
                    TextField("Comment", text: $comment, axis: .vertical)
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let patch = TaskPatchRequest(
                            priority: priority,
                            estimateMinutes: estimate,
                            comment: comment.isEmpty ? nil : comment,
                            start: nil,
                            stop: nil,
                            status: nil
                        )
                        Task {
                            await sync.updateTask(rowNumber: task.rowNumber, patch: patch)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
