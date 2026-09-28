import Foundation

/// A real, persistent sandbox for fresh installs and external beta review.
/// It has no network dependency and never contains an owner's credentials/data.
final class LocalTestStore {
    static let shared = LocalTestStore()
    private let directory: URL

    init(directory: URL? = nil) {
        let manager = FileManager.default
        self.directory = directory ?? (manager.containerURL(
            forSecurityApplicationGroupIdentifier: SharedCache.appGroupIdentifier
        ) ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("IsolatedTestData", isDirectory: true)
    }

    private struct Database: Codable {
        var tasks: [ScheduleItem] = []
        var food: [FoodEntry] = []
        var caffeine: [CaffeineEntry] = []
        var sleep: [SleepEntry] = []
        var nextRow = 2
        var projects: ProjectCatalog? = nil
    }

    func respond(to request: URLRequest) throws -> Data {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("database.json")
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        // App and widget intents may write concurrently in different processes.
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                var database: Database
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    // Corrupt data is an error, never a reason to silently reset it.
                    database = try TrackerJSON.decoder.decode(Database.self, from: Data(contentsOf: coordinatedURL))
                } else {
                    database = Self.seed()
                }
                let response = try Self.handle(request, database: &database)
                try TrackerJSON.encoder.encode(database).write(to: coordinatedURL, options: .atomic)
                return response
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw APIError.invalidResponse }
        return try result.get()
    }

    private static func handle(_ request: URLRequest, database: inout Database) throws -> Data {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try TrackerJSON.decoder.decode(type, from: request.httpBody ?? Data())
        }

        if path == "/projects" || path.hasPrefix("/projects/") {
            var catalog = database.projects ?? ProjectCatalog()
            if method != "GET" {
                let fields = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                guard fields?["revision"] as? Int == catalog.revision else {
                    throw APIError.httpStatus(409, "Projects changed. Refresh and try again.")
                }
                if method == "PUT", path == "/projects" {
                    catalog = try decode(ProjectCatalog.self)
                } else if method == "POST", path == "/projects/link" {
                    let link = try decode(ProjectLinkRequest.self)
                    guard link.projectId == nil || catalog.projects.contains(where: { $0.id == link.projectId && !$0.closed }),
                          link.groupId == nil || catalog.groups.contains(where: { $0.id == link.groupId && $0.projectId == link.projectId }) else {
                        throw APIError.httpStatus(400, "Invalid project destination")
                    }
                    for ref in link.rows {
                        guard let index = database.tasks.firstIndex(where: { $0.rowNumber == ref.rowNumber && $0.task == ref.task && $0.date == ref.date }),
                              ref.taskId == nil || database.tasks[index].taskId == ref.taskId else {
                            throw APIError.httpStatus(409, "Task changed. Refresh before assigning it.")
                        }
                        let id = database.tasks[index].taskId ?? UUID().uuidString
                        database.tasks[index].taskId = id
                        var member = catalog.memberships.first { $0.taskId == id }
                            ?? ProjectMembership(taskId: id, projectId: link.projectId)
                        member.projectId = link.projectId; member.groupId = link.groupId; member.resolution = nil
                        catalog.memberships.removeAll { $0.taskId == id }
                        catalog.memberships.append(member)
                    }
                } else if method == "POST", path == "/projects/resolve" {
                    let resolution = try decode(ProjectResolutionRequest.self)
                    let today = Date.trackerDateFormatter.string(from: Date())
                    guard let index = catalog.memberships.firstIndex(where: { $0.taskId == resolution.taskId }),
                          let last = database.tasks.filter({ $0.taskId == resolution.taskId }).max(by: { ($0.date, $0.rowNumber) < ($1.date, $1.rowNumber) }),
                          last.date < today, last.isOpenDisplayTask else {
                        throw APIError.httpStatus(409, "Task is no longer missing")
                    }
                    if resolution.action == "keep" {
                        let request = CreateTaskRequest(date: today, task: last.task, category: last.category,
                            comment: last.comment, priority: last.priority, estimateMinutes: last.estimateMinutes, taskId: last.taskId)
                        database.tasks.append(makeTask(request, row: database.nextRow)); database.nextRow += 1
                        catalog.memberships[index].resolution = nil
                    } else if ["done", "discarded"].contains(resolution.action) {
                        catalog.memberships[index].resolution = resolution.action
                    } else { throw APIError.httpStatus(400, "Invalid resolution") }
                } else { throw APIError.httpStatus(404, "Unsupported project operation") }
                catalog.revision += 1
                catalog.schedule = []
                database.projects = catalog
            }
            catalog.schedule = database.tasks
            return try TrackerJSON.encoder.encode(catalog)
        }

        if method == "GET", path == "/snapshot" {
            let date = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "date" }?.value
                ?? Date.trackerDateFormatter.string(from: Date())
            let open = database.tasks.filter(\.isOpenDisplayTask).sorted {
                ($0.adjustedPriority ?? 0, $0.priority ?? 0) > ($1.adjustedPriority ?? 0, $1.priority ?? 0)
            }
            return try TrackerJSON.encoder.encode(TrackerSnapshot(
                serverTime: Date(), date: date,
                schedule: database.tasks.filter { $0.date == date }, openTasks: open,
                caffeine: database.caffeine.filter { $0.date == date },
                caffeineOptions: ["Coffee", "Espresso", "Tea", "Energy drink"],
                food: database.food.filter { $0.date == date },
                taskSuggestions: taskSuggestions(database.tasks),
                foodSuggestions: foodSuggestions(database.food),
                sleep: database.sleep.first { $0.date == date }, freeTime: []
            ))
        }
        if method == "POST", path == "/tasks" {
            let task = makeTask(try decode(CreateTaskRequest.self), row: database.nextRow)
            database.nextRow += 1
            database.tasks.append(task)
            return try TrackerJSON.encoder.encode(task)
        }
        let components = path.split(separator: "/")
        if components.count >= 2, components[0] == "tasks", let row = Int(components[1]) {
            guard let index = database.tasks.firstIndex(where: { $0.rowNumber == row }) else {
                throw APIError.httpStatus(404, "Test task not found")
            }
            var task = database.tasks[index]
            if method == "PATCH", components.count == 2 {
                let patch = try decode(TaskPatchRequest.self)
                if let value = patch.priority { task.priority = value; task.adjustedPriority = value }
                if let value = patch.estimateMinutes { task.estimateMinutes = value }
                if let value = patch.comment { task.comment = value }
                if let value = patch.delay { task.delay = value; task.adjustedPriority = 0 }
                if let value = patch.start { task.start = value }
                let fields = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                if fields?["stop"] is NSNull { task.stop = nil }
                if let value = patch.stop { task.stop = value }
                if let value = patch.status { task.status = value }
            } else if method == "POST", components.count == 3, components[2] == "complete" {
                let completion = try decode(CompleteTaskRequest.self)
                task.status = .done
                task.stop = completion.stop ?? Date.trackerTimeFormatter.string(from: Date())
            } else {
                throw APIError.httpStatus(404, "Unsupported test operation")
            }
            if let start = task.dateTime(from: task.start), let stop = task.dateTime(from: task.stop) {
                task.actualMinutes = max(0, Int(stop.timeIntervalSince(start) / 60))
            } else {
                task.actualMinutes = nil
            }
            database.tasks[index] = task
            return try TrackerJSON.encoder.encode(task)
        }
        if method == "POST", path == "/food" {
            let value = try decode(FoodRequest.self)
            let entry = FoodEntry(id: UUID().uuidString, date: value.date, time: value.time,
                                  mealContext: value.mealContext, item: value.item, amount: value.amount,
                                  location: value.location, notes: value.notes, confidence: value.confidence)
            database.food.append(entry)
            return try TrackerJSON.encoder.encode(entry)
        }
        if method == "POST", path == "/caffeine" {
            let value = try decode(CaffeineRequest.self)
            let entry = CaffeineEntry(id: UUID().uuidString, date: value.date, label: value.label, time: value.time)
            database.caffeine.append(entry)
            return try TrackerJSON.encoder.encode(entry)
        }
        if method == "POST", path == "/sleep" {
            let value = try decode(SleepRequest.self)
            let entry = SleepEntry(date: value.date, sleepHours: value.sleepHours, alarmTime: value.alarmTime,
                                   oversleptHours: value.oversleptHours, sleepStart: value.sleepStart,
                                   plannedWake: value.plannedWake, actualWake: value.actualWake)
            database.sleep.removeAll { $0.date == value.date }
            database.sleep.append(entry)
            return try TrackerJSON.encoder.encode(entry)
        }
        if method == "GET", path == "/media/sessions" {
            return try TrackerJSON.encoder.encode(MediaSessionsResponse(sessions: []))
        }
        if method == "GET", path == "/nudge/history" {
            return try TrackerJSON.encoder.encode(NudgeHistoryResponse(records: [], summary: NudgeHistorySummary(
                total: 0, evaluated: 0, strong: 0, moderate: 0, late: 0, ignored: 0,
                successRate: 0, aiCount: 0, angles: []
            )))
        }
        // Explicit failure, not fake success, for cloud-only features.
        throw APIError.httpStatus(503, "This feature requires a connected account and is unavailable with local test data.")
    }

    private static func makeTask(_ value: CreateTaskRequest, row: Int) -> ScheduleItem {
        ScheduleItem(id: "test-\(row)", rowNumber: row, date: value.date, task: value.task,
                     category: value.category, comment: value.comment, priority: value.priority,
                     estimateMinutes: value.estimateMinutes, adjustedPriority: value.priority,
                     start: value.start, stop: value.stop, status: value.status ?? .open,
                     source: value.source, sourceId: value.sourceId, importedAt: value.importedAt,
                     taskId: value.taskId ?? UUID().uuidString)
    }

    private static func seed() -> Database {
        let date = Date.trackerDateFormatter.string(from: Date())
        let requests = [
            CreateTaskRequest(date: date, task: "Plan the day", category: "personal", priority: 3, estimateMinutes: 10),
            CreateTaskRequest(date: date, task: "Read a chapter", category: "personal", priority: 2, estimateMinutes: 20),
            CreateTaskRequest(date: date, task: "Take a walk", category: "sports", priority: 1, estimateMinutes: 30)
        ]
        var database = Database()
        for request in requests {
            database.tasks.append(makeTask(request, row: database.nextRow))
            database.nextRow += 1
        }
        return database
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Values arrive newest-first, so the newest value wins a frequency tie.
    private static func common<T: Hashable>(_ values: [T?]) -> T? {
        let values = values.compactMap { $0 }
        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        let maximum = counts.values.max()
        return values.first { counts[$0] == maximum }
    }

    private static func taskSuggestions(_ tasks: [ScheduleItem]) -> [TaskSuggestion] {
        Dictionary(grouping: tasks.filter { $0.status != .cancelled }, by: { normalized($0.task) }).values.map { group in
            let entries = group.sorted { ($0.date, $0.rowNumber) > ($1.date, $1.rowNumber) }
            return TaskSuggestion(task: entries[0].task, category: common(entries.map(\.category)),
                                  comment: common(entries.map(\.comment)), priority: common(entries.map(\.priority)),
                                  estimateMinutes: common(entries.map(\.estimateMinutes)), useCount: entries.count,
                                  lastUsedDate: entries[0].date)
        }.sorted { $0.task < $1.task }
    }

    private static func foodSuggestions(_ food: [FoodEntry]) -> [FoodSuggestion] {
        Dictionary(grouping: food.enumerated().map { ($0.offset, $0.element) }, by: { normalized($0.1.item) }).values.map { group in
            let entries = group.sorted { ($0.1.date, $0.0) > ($1.1.date, $1.0) }.map(\.1)
            return FoodSuggestion(item: entries[0].item, mealContext: common(entries.map(\.mealContext)),
                                  amount: common(entries.map(\.amount)), location: common(entries.map(\.location)),
                                  confidence: common(entries.map(\.confidence)), useCount: entries.count,
                                  lastUsedDate: entries[0].date)
        }.sorted { $0.item < $1.item }
    }
}
