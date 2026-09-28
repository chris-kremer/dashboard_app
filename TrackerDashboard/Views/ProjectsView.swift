import SwiftUI

struct ProjectsOverviewView: View {
    @Environment(SyncController.self) private var sync
    @State private var creating = false
    @State private var showClosed = false
    private var today: String { Date.trackerDateFormatter.string(from: Date()) }
    private var projects: [TrackerProject] {
        sync.projectCatalog.projects.filter { $0.closed == showClosed }.sorted {
            let left = sync.projectCatalog.nextTask(projectId: $0.id, on: today)
            let right = sync.projectCatalog.nextTask(projectId: $1.id, on: today)
            let a = left?.adjustedPriority ?? left?.priority ?? -1
            let b = right?.adjustedPriority ?? right?.priority ?? -1
            return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a > b
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ProjectSyncStatusView()
                HStack {
                    Text(showClosed ? "Completed projects" : "\(projects.count) projects")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Menu {
                        Button("New project", systemImage: "folder.badge.plus") { creating = true }
                        Button(showClosed ? "Show active projects" : "Show completed projects", systemImage: "archivebox") { showClosed.toggle() }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Project options")
                }
                if sync.projectsLoaded {
                    // Standalone tasks compete in the same ordering, rather than sitting below every project.
                    ForEach(rankedIDs, id: \.self) { id in
                        if id == "__other" {
                            ProjectSummaryCard(project: nil)
                        } else if let project = projects.first(where: { $0.id == id }) {
                            ProjectSummaryCard(project: project)
                        }
                    }
                    if projects.isEmpty && !showClosed {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Give your tasks a home").font(.headline)
                            Text("Create a project, then add tasks directly or organize them into groups. Your existing tasks stay in Other tasks.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Create project", systemImage: "plus") { creating = true }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18).background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                } else if sync.projectError == nil {
                    ProgressView("Loading projects…").padding()
                }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .refreshable { await sync.refreshProjects() }
        .sheet(isPresented: $creating) { ProjectEditorView() }
    }
    private var rankedIDs: [String] {
        var values = projects.map(\.id)
        if !showClosed { values.append("__other") }
        return values.sorted { a, b in
            let x = sync.projectCatalog.nextTask(projectId: a == "__other" ? nil : a, on: today)
            let y = sync.projectCatalog.nextTask(projectId: b == "__other" ? nil : b, on: today)
            let xp = x?.adjustedPriority ?? x?.priority ?? -1, yp = y?.adjustedPriority ?? y?.priority ?? -1
            return xp == yp ? values.firstIndex(of: a)! < values.firstIndex(of: b)! : xp > yp
        }
    }
}

private struct ProjectSyncStatusView: View {
    @Environment(SyncController.self) private var sync
    var body: some View {
        if let error = sync.projectError {
            VStack(alignment: .leading, spacing: 8) {
                Label("Project sync needs attention", systemImage: "exclamationmark.triangle")
                Text(error).font(.caption).textSelection(.enabled)
                Button("Retry") { Task { await sync.refreshProjects() } }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct ProjectWorkloadLabel: View {
    let tasks: [ScheduleItem]
    let today: String

    var body: some View {
        let summary = ProjectWorkloadSummary(tasks: tasks, today: today)
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.total)
            if let upcoming = summary.upcomingDetail {
                Text(upcoming).font(.caption)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private struct ProjectSummaryCard: View {
    @Environment(SyncController.self) private var sync
    var project: TrackerProject?
    private var today: String { Date.trackerDateFormatter.string(from: Date()) }
    private var tasks: [ScheduleItem] { sync.projectCatalog.activeTasks(projectId: project?.id, on: today) }
    private var next: ScheduleItem? { sync.projectCatalog.nextTask(projectId: project?.id, on: today) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                ProjectDetailView(projectId: project?.id)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: project == nil ? "tray.fill" : "folder.fill")
                        .font(.subheadline)
                        .foregroundStyle(TrackerStyle.accent)
                        .frame(width: 32, height: 32)
                        .background(TrackerStyle.soft, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project?.name ?? "Other tasks")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(TrackerStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        ProjectWorkloadLabel(tasks: tasks, today: today)
                            .font(.caption).foregroundStyle(.secondary)
                        if let deadline = project?.deadline { Text("Due \(deadline)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, 9)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let next {
                // The project is the container; the actionable task is visibly
                // nested inside it, not a second competing card heading.
                VStack(alignment: .leading, spacing: 0) {
                    Label(nextTaskLabel(next), systemImage: "arrow.turn.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TrackerStyle.accent)
                        .padding(.horizontal, 4)
                    TaskRowView(task: next, compact: true)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .background(TrackerStyle.background, in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text(tasks.first.map { "Next task \($0.date)" } ?? "No actionable tasks")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let project, !project.closed {
                let missing = sync.projectCatalog.missingTasks(projectId: project.id, on: today)
                if !missing.isEmpty {
                    NavigationLink { ProjectDetailView(projectId: project.id) } label: {
                        Label("\(missing.count) task\(missing.count == 1 ? " needs" : "s need") clarification", systemImage: "questionmark.circle")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func nextTaskLabel(_ task: ScheduleItem) -> String {
        if task.status == .inProgress {
            return task.stop == nil ? "CURRENT TASK" : "PAUSED TASK"
        }
        return "NEXT TASK"
    }
}

struct ProjectDetailView: View {
    @Environment(SyncController.self) private var sync
    var projectId: String?
    @State private var groupId: String?
    @State private var addTask = false
    @State private var editProject = false
    @State private var addGroup = false
    @State private var editGroup = false
    @State private var assign = false
    @State private var missing: ScheduleItem?
    @State private var editingFuture: ScheduleItem?
    @State private var showHistory = false
    @State private var showCloseConfirmation = false
    private var today: String { Date.trackerDateFormatter.string(from: Date()) }
    private var project: TrackerProject? { sync.projectCatalog.projects.first { $0.id == projectId } }
    private var group: ProjectGroup? { sync.projectCatalog.groups.first { $0.id == groupId } }
    private var tasks: [ScheduleItem] { sync.projectCatalog.activeTasks(projectId: projectId, on: today) }
    private var direct: [ScheduleItem] { tasks.filter { sync.projectCatalog.membership(for: $0)?.groupId == groupId } }
    private var children: [ProjectGroup] { sync.projectCatalog.groups.filter { $0.projectId == projectId && $0.parentId == groupId }.sorted { $0.name < $1.name } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ProjectSyncStatusView()
                if groupId != nil {
                    // Menu breadcrumbs stay readable at arbitrary depth and Dynamic Type sizes.
                    Menu {
                        Button(project?.name ?? "Project") { groupId = nil }
                        ForEach(sync.projectCatalog.ancestors(of: groupId)) { ancestor in
                            Button(ancestor.name) { groupId = ancestor.id }
                        }
                    } label: {
                        Label("\(project?.name ?? "Project")\(sync.projectCatalog.ancestors(of: groupId).count > 1 ? " › …" : "") › \(group?.name ?? "Group")", systemImage: "folder")
                    }
                    .font(.subheadline)
                }
                if let project, groupId == nil {
                    ProjectWorkloadLabel(tasks: tasks, today: today)
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let deadline = project.deadline { Label("Due \(deadline)", systemImage: "calendar").font(.caption) }
                    if !project.closed {
                        ForEach(sync.projectCatalog.missingTasks(projectId: project.id, on: today)) { task in
                            Button { missing = task } label: {
                                Label("\(task.task) · wasn’t carried forward", systemImage: "questionmark.circle")
                                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                    .background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if let projectId {
                    Text("\(TrackerTime.label(sync.projectCatalog.loggedMinutes(projectId: projectId, groupId: groupId))) logged")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(children) { child in
                    Button { groupId = child.id } label: {
                        let nested = tasks.filter { task in
                            sync.projectCatalog.ancestors(of: sync.projectCatalog.membership(for: task)?.groupId).contains { $0.id == child.id }
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "folder").foregroundStyle(TrackerStyle.accent)
                                .frame(width: 38, height: 38).background(TrackerStyle.soft, in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(child.name).font(.subheadline.weight(.semibold))
                                ProjectWorkloadLabel(tasks: nested, today: today)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(14).background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
                if direct.contains(where: { $0.date == today }) {
                    Text("Ready today").font(.subheadline.weight(.semibold))
                    ForEach(direct.filter { $0.date == today }) { TaskRowView(task: $0) }
                }
                if direct.contains(where: { $0.date > today }) {
                    Text("Upcoming").font(.subheadline.weight(.semibold))
                    ForEach(direct.filter { $0.date > today }) { task in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.date).font(.caption).foregroundStyle(.secondary)
                            // Future work is editable, not startable before its scheduled day.
                            Button { editingFuture = task } label: {
                                HStack { Text(task.task); Spacer(); Text("\(task.estimateMinutes ?? 0)m").foregroundStyle(.secondary) }
                            }
                        }.padding(12).background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                if direct.isEmpty && children.isEmpty { Text("No open tasks here.").foregroundStyle(.secondary).padding(.vertical) }
                if project?.closed != true {
                    HStack {
                        Button("Add task", systemImage: "plus") { addTask = true }
                        Spacer()
                        if projectId != nil { Button("Move existing tasks", systemImage: "folder.badge.plus") { assign = true } }
                    }.font(.subheadline).padding(.vertical, 8)
                }
                if let project, groupId == nil {
                    DisclosureGroup("History", isExpanded: $showHistory) {
                        let history = sync.projectCatalog.representatives(on: today).filter {
                            sync.projectCatalog.membership(for: $0)?.projectId == project.id &&
                                ($0.status == .done || $0.status == .cancelled || sync.projectCatalog.membership(for: $0)?.resolution != nil)
                        }
                        ForEach(history) { task in
                            HStack {
                                Text(task.task)
                                Spacer()
                                Text(sync.projectCatalog.membership(for: task)?.resolution ?? task.status.rawValue)
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                        if history.isEmpty { Text("No completed tasks yet.").font(.caption).foregroundStyle(.secondary) }
                    }.font(.subheadline)
                }
            }.padding(20)
        }
        .background(TrackerStyle.background)
        .navigationTitle(group?.name ?? project?.name ?? "Other tasks")
        .trackerInlineNavigationTitle()
#if os(iOS)
        .navigationBarBackButtonHidden(groupId != nil)
#endif
        .toolbar {
#if os(iOS)
            if groupId != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { groupId = group?.parentId } label: { Label("Back", systemImage: "chevron.left") }
                        .accessibilityLabel("Back to parent group")
                }
            }
#endif
            ToolbarItem {
                Menu {
                    if project != nil {
                        Button("Edit project", systemImage: "pencil") { editProject = true }
                        if project?.closed == false {
                            Button("New group", systemImage: "folder.badge.plus") { addGroup = true }
                            if group != nil { Button("Edit or move group", systemImage: "folder") { editGroup = true } }
                            Button("Close project", systemImage: "archivebox") { showCloseConfirmation = true }
                        } else {
                            Button("Reopen project", systemImage: "arrow.uturn.backward") { setClosed(false) }
                        }
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .refreshable { await sync.refreshProjects() }
        .sheet(isPresented: $addTask) { AddTaskView(initialProjectId: projectId, initialGroupId: groupId) }
        .sheet(isPresented: $editProject) { ProjectEditorView(project: project) }
        .sheet(isPresented: $addGroup) { ProjectGroupEditorView(projectId: projectId ?? "", initialParentId: groupId) }
        .sheet(isPresented: $editGroup) { ProjectGroupEditorView(projectId: projectId ?? "", group: group) }
        .sheet(isPresented: $assign) { ProjectTaskAssignmentView(projectId: projectId ?? "", groupId: groupId) }
        .sheet(item: $editingFuture) { EditTaskView(task: $0) }
        .confirmationDialog("Close this project?", isPresented: $showCloseConfirmation, titleVisibility: .visible) {
            Button("Close project") { setClosed(true) }
        } message: { Text("Tasks remain in the Sheet and in history. Close the project only when you no longer need to work on them.") }
        .confirmationDialog("This task wasn’t carried forward", isPresented: Binding(get: { missing != nil }, set: { if !$0 { missing = nil } }), titleVisibility: .visible) {
            if let task = missing {
                Button("Keep · bring back to today") { resolve(task, "keep") }
                Button("Mark as done") { resolve(task, "done") }
                Button("Yes, discard it", role: .destructive) { resolve(task, "discarded") }
                Button("Decide later", role: .cancel) { missing = nil }
            }
        } message: { Text("\(missing?.task ?? "This task") was last open on \(missing?.date ?? "a prior day"). Historical rows will stay unchanged.") }
    }
    private func resolve(_ task: ScheduleItem, _ action: String) {
        missing = nil
        Task { await sync.resolveMissingTask(task, action: action) }
    }
    private func setClosed(_ closed: Bool) {
        var catalog = sync.projectCatalog
        guard let index = catalog.projects.firstIndex(where: { $0.id == projectId }) else { return }
        catalog.projects[index].closed = closed
        Task { _ = await sync.saveProjects(catalog) }
    }
}

struct ProjectEditorView: View {
    @Environment(SyncController.self) private var sync
    @Environment(\.dismiss) private var dismiss
    var project: TrackerProject?
    @State private var name = ""
    @State private var category = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $name)
                TextField("Default category", text: $category)
                Toggle("Project deadline", isOn: $hasDeadline)
                if hasDeadline { DatePicker("Finish by", selection: $deadline, displayedComponents: .date) }
                Section { Text("Task priority determines the project’s position. Its deadline is a reminder, not a second priority score.").font(.caption).foregroundStyle(.secondary) }
                ProjectSyncStatusView()
            }
            .navigationTitle(project == nil ? "New project" : "Edit project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var catalog = sync.projectCatalog
                        var value = project ?? TrackerProject(name: name, category: category)
                        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines); value.category = category
                        value.deadline = hasDeadline ? Date.trackerDateFormatter.string(from: deadline) : nil
                        catalog.projects.removeAll { $0.id == value.id }; catalog.projects.append(value)
                        Task { if await sync.saveProjects(catalog) { dismiss() } }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sync.projectBusy || !sync.projectsLoaded)
                }
            }
            .onAppear {
                if let project {
                    name = project.name; category = project.category; hasDeadline = project.deadline != nil
                    deadline = project.deadline.flatMap { Date.trackerDateFormatter.date(from: $0) } ?? Date()
                }
            }
        }
    }
}

private struct ProjectGroupEditorView: View {
    @Environment(SyncController.self) private var sync
    @Environment(\.dismiss) private var dismiss
    var projectId: String
    var group: ProjectGroup? = nil
    var initialParentId: String? = nil
    @State private var name = ""
    @State private var parent = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Group name", text: $name)
                Picker("Inside", selection: $parent) {
                    Text("Project root").tag("")
                    ForEach(sync.projectCatalog.groups.filter { candidate in
                        candidate.projectId == projectId && candidate.id != group?.id &&
                            !sync.projectCatalog.ancestors(of: candidate.id).contains { $0.id == group?.id }
                    }) { candidate in
                        Text(sync.projectCatalog.ancestors(of: candidate.id).map(\.name).joined(separator: " › ")).tag(candidate.id)
                    }
                }
                if group != nil { Text("Moving a group also moves all of its nested groups and tasks.").font(.caption).foregroundStyle(.secondary) }
                ProjectSyncStatusView()
            }
            .navigationTitle(group == nil ? "New group" : "Edit group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var catalog = sync.projectCatalog
                        var value = group ?? ProjectGroup(projectId: projectId, name: name)
                        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines); value.parentId = parent.isEmpty ? nil : parent
                        catalog.groups.removeAll { $0.id == value.id }; catalog.groups.append(value)
                        Task { if await sync.saveProjects(catalog) { dismiss() } }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sync.projectBusy)
                }
            }.onAppear { name = group?.name ?? ""; parent = group?.parentId ?? initialParentId ?? "" }
        }
    }
}

private struct ProjectTaskAssignmentView: View {
    @Environment(SyncController.self) private var sync
    @Environment(\.dismiss) private var dismiss
    var projectId: String
    var groupId: String?
    @State private var selected = Set<String>()
    @State private var query = ""
    private var candidates: [ScheduleItem] {
        let today = Date.trackerDateFormatter.string(from: Date())
        return sync.projectCatalog.representatives(on: today).filter {
            $0.date >= today && $0.isOpenDisplayTask && (query.isEmpty || $0.task.localizedStandardContains(query))
        }.sorted(by: ProjectCatalog.priorityOrder)
    }
    var body: some View {
        NavigationStack {
            List {
                ProjectSyncStatusView()
                ForEach(candidates) { task in
                    Button {
                        if selected.contains(task.id) { selected.remove(task.id) } else { selected.insert(task.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(task.id) ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(task.task)
                                Text(sync.projectCatalog.path(for: task) ?? "Other tasks").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }.searchable(text: $query, prompt: "Find tasks")
            .navigationTitle("Move tasks here")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move \(selected.count)") {
                        let rows = sync.projectCatalog.representatives(on: Date.trackerDateFormatter.string(from: Date())).filter { selected.contains($0.id) }
                        Task { if await sync.assignProjectTasks(rows, projectId: projectId, groupId: groupId) { dismiss() } }
                    }.disabled(selected.isEmpty || selected.count > 100 || sync.projectBusy)
                }
            }
        }
    }
}

struct ProjectLocationPicker: View {
    @Environment(SyncController.self) private var sync
    @Binding var projectId: String
    @Binding var groupId: String
    var body: some View {
        Section("Project") {
            Picker("Project", selection: $projectId) {
                Text("None · Other tasks").tag("")
                ForEach(sync.projectCatalog.projects.filter { !$0.closed }) { Text($0.name).tag($0.id) }
            }
            if !projectId.isEmpty {
                Picker("Group", selection: $groupId) {
                    Text("Project root").tag("")
                    ForEach(sync.projectCatalog.groups.filter { $0.projectId == projectId }) { group in
                        Text(sync.projectCatalog.ancestors(of: group.id).map(\.name).joined(separator: " › ")).tag(group.id)
                    }
                }
            }
        }
        .onChange(of: projectId) { _, value in
            if !sync.projectCatalog.groups.contains(where: { $0.id == groupId && $0.projectId == value }) { groupId = "" }
        }
    }
}
