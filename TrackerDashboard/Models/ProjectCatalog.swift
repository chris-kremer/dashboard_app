import Foundation

struct TrackerProject: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var category: String
    var deadline: String? = nil
    var closed = false
}

struct ProjectGroup: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var projectId: String
    var parentId: String? = nil
    var name: String
}

struct ProjectChecklistItem: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var done = false
}

struct ProjectMembership: Codable, Equatable {
    var taskId: String
    var projectId: String? = nil
    var groupId: String? = nil
    var resolution: String? = nil
    var checklist: [ProjectChecklistItem]? = nil
}

struct ProjectCatalog: Codable, Equatable {
    var revision = 0
    var projects: [TrackerProject] = []
    var groups: [ProjectGroup] = []
    var memberships: [ProjectMembership] = []
    var schedule: [ScheduleItem] = []

    func membership(for task: ScheduleItem) -> ProjectMembership? {
        guard let id = task.taskId else { return nil }
        return memberships.first { $0.taskId == id }
    }

    func ancestors(of groupId: String?) -> [ProjectGroup] {
        var path: [ProjectGroup] = [], seen = Set<String>(), id = groupId
        while let current = id, seen.insert(current).inserted,
              let group = groups.first(where: { $0.id == current }) {
            path.insert(group, at: 0)
            id = group.parentId
        }
        return path
    }

    func path(for task: ScheduleItem) -> String? {
        guard let m = membership(for: task), let p = projects.first(where: { $0.id == m.projectId }) else { return nil }
        return ([p.name] + ancestors(of: m.groupId).map(\.name)).joined(separator: " › ")
    }

    /// Row IDs identify intervals. Stable IDs identify logical tasks. Never merge titles.
    func representatives(on today: String) -> [ScheduleItem] {
        Dictionary(grouping: schedule, by: { $0.taskId ?? $0.id }).values.compactMap { rows in
            let current = rows.filter { $0.date == today }
            if !current.isEmpty { return current.max { $0.rowNumber < $1.rowNumber } }
            let future = rows.filter { $0.date > today }.sorted {
                ($0.date, -$0.rowNumber) < ($1.date, -$1.rowNumber)
            }
            if let first = future.first { return first }
            return rows.max { ($0.date, $0.rowNumber) < ($1.date, $1.rowNumber) }
        }
    }

    func activeTasks(projectId: String?, on today: String) -> [ScheduleItem] {
        representatives(on: today).filter { task in
            let m = membership(for: task)
            return m?.projectId == projectId && task.date >= today && task.isOpenDisplayTask
                && m?.resolution == nil
        }.sorted(by: Self.priorityOrder)
    }

    func nextTask(projectId: String?, on today: String, now: Date = Date()) -> ScheduleItem? {
        activeTasks(projectId: projectId, on: today).first {
            $0.date == today && ($0.delay.flatMap { ISO8601DateFormatter.tracker.date(from: $0) } ?? .distantPast) <= now
        }
    }

    func missingTasks(projectId: String, on today: String) -> [ScheduleItem] {
        representatives(on: today).filter {
            let m = membership(for: $0)
            return m?.projectId == projectId && m?.resolution == nil && $0.date < today && $0.isOpenDisplayTask
        }.sorted(by: Self.priorityOrder)
    }

    func isComplete(_ projectId: String, on today: String) -> Bool {
        let members = memberships.filter { $0.projectId == projectId }
        guard !members.isEmpty else { return false }
        let reps = representatives(on: today)
        return members.allSatisfy { m in
            if m.resolution != nil { return true }
            guard let task = reps.first(where: { $0.taskId == m.taskId }) else { return false }
            return task.status == .done || task.status == .cancelled
        }
    }

    func loggedMinutes(projectId: String, groupId: String? = nil, now: Date = Date()) -> Int {
        let rows = schedule.filter { task in
            guard let m = membership(for: task), m.projectId == projectId else { return false }
            return groupId == nil || ancestors(of: m.groupId).contains { $0.id == groupId }
        }
        let today = Date.trackerDateFormatter.string(from: now)
        return Dictionary(grouping: rows, by: \.date).reduce(0) { total, entry in
            let intervals: [Range<Int>] = entry.value.compactMap { task in
                guard [.done, .logged, .inProgress].contains(task.status),
                      let start = TrackerTime.minute(task.start),
                      let end = TrackerTime.minute(task.stop) ?? (task.date == today && task.status == .inProgress
                          ? TrackerTime.minute(Date.trackerTimeFormatter.string(from: now)) : nil), end > start else { return nil }
                return start..<end
            }
            return total + TrackerTime.unionMinutes(intervals)
        }
    }

    static func priorityOrder(_ a: ScheduleItem, _ b: ScheduleItem) -> Bool {
        if a.date != b.date { return a.date < b.date }
        return (a.adjustedPriority ?? a.priority ?? 0, a.priority ?? 0, a.task) >
            (b.adjustedPriority ?? b.priority ?? 0, b.priority ?? 0, b.task)
    }
}

/// Uses the catalog's active representatives, so rollover copies count once.
struct ProjectWorkloadSummary {
    let tasks: [ScheduleItem]
    let today: String

    var total: String {
        let minutes = tasks.reduce(0) { $0 + ($1.estimateMinutes ?? 0) }
        return "\(tasks.count) open · ~\(TrackerTime.label(minutes)) \(upcoming.isEmpty ? "remaining" : "total remaining")"
    }

    private var upcoming: [ScheduleItem] { tasks.filter { $0.date > today } }

    var upcomingDetail: String? {
        guard !upcoming.isEmpty else { return nil }
        let count = upcoming.count
        let estimates = upcoming.compactMap(\.estimateMinutes)
        let tasksLabel = "\(count) upcoming task\(count == 1 ? "" : "s")"
        guard !estimates.isEmpty else { return "Includes \(tasksLabel) · not yet estimated" }
        let time = TrackerTime.label(estimates.reduce(0, +))
        let incomplete = estimates.count < count ? " · some estimates missing" : ""
        return "Includes ~\(time) in \(tasksLabel)\(incomplete)"
    }
}

struct ProjectRowReference: Codable {
    var rowNumber: Int
    var task: String
    var date: String
    var taskId: String?
    init(_ task: ScheduleItem) {
        rowNumber = task.rowNumber; self.task = task.task; date = task.date; taskId = task.taskId
    }
}

struct ProjectLinkRequest: Codable {
    var revision: Int
    var rows: [ProjectRowReference]
    var projectId: String?
    var groupId: String?
}

struct ProjectResolutionRequest: Codable {
    var revision: Int
    var taskId: String
    var action: String
}
