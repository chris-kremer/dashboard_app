import SwiftUI

struct EditTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncController.self) private var sync
    let task: ScheduleItem

    @State private var priority: Int
    @State private var estimate: Int
    @State private var comment: String
    @State private var projectId = ""
    @State private var groupId = ""
    @State private var checklist: [ProjectChecklistItem] = []
    @State private var checklistTitle = ""
    @State private var saving = false
    @State private var error: String?

    init(task: ScheduleItem) {
        self.task = task
        _priority = State(initialValue: task.priority ?? 3)
        _estimate = State(initialValue: task.estimateMinutes ?? 30)
        _comment = State(initialValue: task.comment ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(task.category.isEmpty ? "Task" : task.category) {
                    Stepper("Priority \(priority)", value: $priority, in: 1...10)
                    Stepper("Estimate \(estimate)m", value: $estimate, in: 5...480, step: 5)
                    TextField("Comment", text: $comment, axis: .vertical)
                }
                if sync.projectsLoaded {
                    ProjectLocationPicker(projectId: $projectId, groupId: $groupId)
                    Group {
                        Section("Checklist") {
                            ForEach($checklist) { $item in
                                Toggle(item.title, isOn: $item.done)
                            }
                            .onDelete { checklist.remove(atOffsets: $0) }
                            HStack {
                                TextField("Small step", text: $checklistTitle)
                                Button("Add") {
                                    checklist.append(ProjectChecklistItem(title: checklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)))
                                    checklistTitle = ""
                                }.disabled(checklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .navigationTitle(task.task)
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
                            delay: nil,
                            start: nil,
                            stop: nil,
                            status: nil
                        )
                        Task {
                            saving = true
                            guard await sync.updateTask(rowNumber: task.rowNumber, patch: patch) else {
                                error = "Could not save task changes. Check sync status before retrying."
                                saving = false; return
                            }
                            let old = sync.projectCatalog.membership(for: task)
                            if !projectId.isEmpty || old != nil || !checklist.isEmpty {
                                if old == nil || (old?.projectId ?? "") != projectId || (old?.groupId ?? "") != groupId {
                                    guard await sync.assignProjectTasks([task], projectId: projectId.isEmpty ? nil : projectId, groupId: groupId.isEmpty ? nil : groupId) else {
                                        error = sync.projectError; saving = false; return
                                    }
                                }
                                var catalog = sync.projectCatalog
                                if let row = catalog.schedule.first(where: { $0.rowNumber == task.rowNumber }),
                                   let index = catalog.memberships.firstIndex(where: { $0.taskId == row.taskId }) {
                                    catalog.memberships[index].checklist = checklist
                                    guard await sync.saveProjects(catalog) else { error = sync.projectError; saving = false; return }
                                }
                            }
                            saving = false
                            dismiss()
                        }
                    }.disabled(saving || sync.projectBusy)
                }
            }
            .onAppear {
                if let membership = sync.projectCatalog.membership(for: task) {
                    projectId = membership.projectId ?? ""; groupId = membership.groupId ?? ""
                    checklist = membership.checklist ?? []
                }
            }
        }
    }
}
