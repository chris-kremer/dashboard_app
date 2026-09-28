import Foundation

// Only ActivityKit's request payload is unavailable in this macOS test runner.
// The transport, storage, settings and models below are the production sources.
struct TaskLiveActivityAttributes {
    struct Suggestion: Codable {
        let rowId: String
        let task: String
        let category: String
        let estimateMinutes: Int?
    }
}

final class RejectNetwork: URLProtocol {
    static var count = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@main
struct LocalTestStoreTests {
    static func check(_ value: Bool, _ message: String) {
        precondition(value, message)
    }

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-test-\(UUID())")
        let store = LocalTestStore(directory: directory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RejectNetwork.self]
        let session = URLSession(configuration: configuration)
        let defaults = UserDefaults(suiteName: "tracker-tests-\(UUID())")!
        let settings = AppSettings(defaults: defaults, sharedDefaults: defaults, existingToken: { nil })
        check(settings.usesLocalTestData, "Fresh install defaults to private test data")
        let ownerDefaults = UserDefaults(suiteName: "tracker-tests-owner-\(UUID())")!
        let owner = AppSettings(defaults: ownerDefaults, sharedDefaults: ownerDefaults, existingToken: { "fake-token" })
        check(!owner.usesLocalTestData, "Configured account is preserved")
        let lockedOwner = AppSettings(defaults: ownerDefaults, sharedDefaults: ownerDefaults, existingToken: { nil })
        check(!lockedOwner.usesLocalTestData, "Temporary Keychain unavailability cannot change mode")
        let api = TrackerAPIClient(session: session, settings: settings, testStore: store)
        let date = Date.trackerDateFormatter.string(from: Date())
        let initial = try await api.fetchSnapshot(date: date)
        check(initial.openTasks.count == 3, "New dataset seeds three fictional tasks")
        let projectAPI = TrackerAPIClient(session: session, settings: settings,
            testStore: LocalTestStore(directory: directory.appendingPathComponent("projects")))
        try await testProjects(api: projectAPI, today: date)
        check(TrackerTime.unionMinutes([60..<120, 90..<150, 150..<180]) == 120, "Overlaps count only once")
        check(TrackerTime.unionMinutes([]) == 0, "Empty union")
        check(TrackerTime.laneAssignments([0..<60, 30..<90, 60..<120]) == [0, 1, 0], "Overlaps have separate lanes; adjacent intervals reuse lanes")
        check(TrackerTime.laneAssignments([60..<120, 0..<60]) == [0, 0], "Lane packing accepts unsorted entries")
        check(TrackerTime.minute("24:00") == 1440 && TrackerTime.minute("24:01") == nil, "Midnight boundary is validated")
        check(TrackerTime.label(195) == "3h 15m", "Workload duration format")
        let overnight = FreeTimeEntry(id: "overnight", date: date, label: "YouTube", durationMinutes: 60, time: nil, start: "23:30", end: "00:30")
        check(TrackerTime.unionMinutes(TrackerTime.freeTimeIntervals([overnight], limit: 600)) == 30, "Cross-midnight free time clips to elapsed day")

        let task = try await api.createTask(CreateTaskRequest(date: date, task: "Test task", category: "personal", priority: 3, estimateMinutes: 20))
        let running = try await api.updateTask(rowNumber: task.rowNumber, patch: TaskPatchRequest(start: "09:00", status: .inProgress, clearsStop: true))
        check(running.start == "09:00" && running.stop == nil, "Task starts")
        let paused = try await api.updateTask(rowNumber: task.rowNumber, patch: TaskPatchRequest(stop: "09:15", status: .inProgress))
        check(paused.stop == "09:15" && paused.actualMinutes == 15 && paused.isOpenDisplayTask, "Pause retains task and elapsed time")
        let cleared = try await api.updateTask(rowNumber: task.rowNumber, patch: TaskPatchRequest(start: "09:20", clearsStop: true))
        check(cleared.stop == nil, "Explicit null clears stop")
        let done = try await api.completeTask(rowNumber: task.rowNumber, source: "test", stop: "09:30")
        check(done.status == .done && done.actualMinutes == 10 && !done.isOpenDisplayTask, "Task completion persists")
        var overlapping = done
        overlapping.start = "09:25"
        overlapping.stop = "09:40"
        var pausedInterval = done
        pausedInterval.status = .inProgress
        pausedInterval.start = "10:00"
        pausedInterval.stop = "10:15"
        var leisure = done
        leisure.category = "Free_time"
        leisure.start = "10:00"
        leisure.stop = "11:00"
        var metrics = initial
        metrics.schedule = [done, overlapping, pausedInterval, leisure]
        let endOfDay = Date.trackerDateFormatter.date(from: date)!.addingTimeInterval(23 * 3600)
        check(metrics.productiveMinutes(now: endOfDay) == 35, "Actual productive intervals union; paused work included; free time excluded")
        check(metrics.finishedTaskCount == 3, "Paused intervals do not count as finished tasks")
        leisure.category = " Media "
        metrics.schedule = [done, overlapping, pausedInterval, leisure]
        check(metrics.productiveMinutes(now: endOfDay) == 35, "Media branding retains legacy free-time accounting")
        var unstarted = done
        unstarted.start = nil
        unstarted.stop = nil
        unstarted.estimateMinutes = 400
        metrics.schedule = [unstarted]
        check(metrics.productiveMinutes(now: endOfDay) == 0, "Estimates never masquerade as productive time")

        _ = try await api.logFood(FoodRequest(date: date, time: "12:00", mealContext: "Lunch", item: "Soup", amount: "1 bowl", location: "Home", notes: "Entry-specific", confidence: "High"))
        _ = try await api.logCaffeine(CaffeineRequest(date: date, label: "Coffee", time: "10:00"))
        _ = try await api.upsertSleep(SleepRequest(date: date, sleepHours: 8, actualWake: "08:00"))
        _ = try await api.upsertSleep(SleepRequest(date: date, sleepHours: 7.5, actualWake: "07:30"))
        let reopened = TrackerAPIClient(session: session, settings: settings, testStore: LocalTestStore(directory: directory))
        let snapshot = try await reopened.fetchSnapshot(date: date)
        check(snapshot.schedule.contains { $0.id == done.id && $0.status == .done }, "Survives store recreation")
        check(snapshot.food.count == 1 && snapshot.caffeine.count == 1 && snapshot.sleep?.sleepHours == 7.5, "Logs and sleep upsert persist")
        check(snapshot.foodSuggestions?.first?.amount == "1 bowl", "Meal autocomplete retains defaults")

        _ = try await api.createTask(CreateTaskRequest(date: date, task: " test TASK ", category: "sports", priority: 1, estimateMinutes: 30))
        _ = try await api.createTask(CreateTaskRequest(date: date, task: "Test task", category: "personal", priority: 3, estimateMinutes: 20))
        let history = try await api.fetchSnapshot()
        let suggestion = history.taskSuggestions?.first { $0.task == "Test task" }
        check(suggestion?.useCount == 3 && suggestion?.priority == 3 && suggestion?.estimateMinutes == 20, "Normalized history uses most common values")
        let otherDate = try await api.fetchSnapshot(date: "2000-01-01")
        check(otherDate.schedule.isEmpty && otherDate.food.isEmpty && otherDate.sleep == nil, "Daily data is date-filtered")
        let pastDate = "2000-01-02"
        let pastTask = try await api.createTask(CreateTaskRequest(date: pastDate, task: "Historical task", category: "personal", priority: 2, estimateMinutes: 15))
        _ = try await api.updateTask(rowNumber: pastTask.rowNumber, patch: TaskPatchRequest(start: "11:00", stop: "11:15", status: .done))
        _ = try await api.logFood(FoodRequest(date: pastDate, time: "12:00", mealContext: "Lunch", item: "Past meal"))
        _ = try await api.logCaffeine(CaffeineRequest(date: pastDate, label: "Tea", time: "09:00"))
        _ = try await api.upsertSleep(SleepRequest(date: pastDate, sleepHours: 8, actualWake: "07:00"))
        let past = try await api.fetchSnapshot(date: pastDate)
        check(past.date == pastDate && past.schedule.count == 1 && past.productiveMinutes() == 15, "Historical timeline returns the requested day's actual task intervals")
        check(past.food.first?.item == "Past meal" && past.caffeine.first?.label == "Tea" && past.sleep?.actualWake == "07:00", "Historical daily logs stay date-scoped")
        let currentAfterHistory = try await api.fetchSnapshot(date: date)
        check(currentAfterHistory.schedule == history.schedule && currentAfterHistory.food == history.food && currentAfterHistory.sleep == history.sleep, "Browsing a past snapshot leaves today's records unchanged")

        async let a = api.createTask(CreateTaskRequest(date: date, task: "Concurrent A", category: "personal"))
        async let b = reopened.createTask(CreateTaskRequest(date: date, task: "Concurrent B", category: "personal"))
        let (first, second) = try await (a, b)
        check(first.rowNumber != second.rowNumber, "Concurrent clients get distinct rows")

        let media = try await api.fetchMediaSessions()
        let nudges = try await api.fetchNudgeHistory()
        check(media.sessions.isEmpty && nudges.records.isEmpty, "Never returns production media or nudges")
        do {
            try await api.registerNudgeDevice(NudgeDeviceRequest(token: "fake-test-token", environment: "production"))
            fatalError("Cloud-only operations must fail locally")
        } catch APIError.httpStatus(503, _) {}
        check(RejectNetwork.count == 0, "Isolated API must never make a network request")

        let independent = TrackerAPIClient(session: session, settings: settings, testStore: LocalTestStore(directory: directory.appendingPathComponent("other-device")))
        let separate = try await independent.fetchSnapshot()
        check(separate.openTasks.count == 3 && separate.food.isEmpty, "Separate install has separate dataset")

        // Existing connected installs must continue to use the remote transport.
        let remote = TrackerAPIClient(session: session, settings: owner, testStore: store)
        do { _ = try await remote.fetchSnapshot(); fatalError("Stub should reject network") } catch {}
        check(RejectNetwork.count == 1, "Connected-account transport remains unchanged")
        print("PASS: isolated transport, persistence, task lifecycle, date filtering, autocomplete, concurrent writes, and account separation")
    }

    static func testProjects(api: TrackerAPIClient, today: String) async throws {
        var catalog = try await api.fetchProjects()
        let project = TrackerProject(name: "Research paper", category: "Work")
        let group = ProjectGroup(projectId: project.id, name: "Introduction")
        let nested = ProjectGroup(projectId: project.id, parentId: group.id, name: "Sources")
        catalog.projects.append(project); catalog.groups = [group, nested]
        catalog = try await api.saveProjects(catalog)
        let yesterday = Date.trackerDateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let tomorrow = Date.trackerDateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        let original = try await api.createTask(CreateTaskRequest(date: yesterday, task: "Project identity test", category: "Work", priority: 4, estimateMinutes: 20))
        catalog = try await api.linkProjectTasks(ProjectLinkRequest(revision: catalog.revision, rows: [ProjectRowReference(original)], projectId: project.id, groupId: nested.id))
        check(catalog.missingTasks(projectId: project.id, on: today).count == 1, "Missing historical task asks for clarification")
        catalog = try await api.resolveProjectTask(ProjectResolutionRequest(revision: catalog.revision, taskId: original.taskId!, action: "keep"))
        check(catalog.activeTasks(projectId: project.id, on: today).count == 1, "Keep restores today, not a second project task")
        check(catalog.schedule.first { $0.rowNumber == original.rowNumber }?.status == .open, "Keep does not rewrite yesterday")
        let current = catalog.activeTasks(projectId: project.id, on: today)[0]
        check(catalog.path(for: current) == "Research paper › Introduction › Sources", "Deep group path preserved on restore")
        _ = try await api.createTask(CreateTaskRequest(date: tomorrow, task: current.task, category: current.category, priority: 4, estimateMinutes: 20, taskId: current.taskId))
        catalog = try await api.fetchProjects()
        check(catalog.activeTasks(projectId: project.id, on: today).count == 1, "Current and future copies count once")
        let currentSummary = ProjectWorkloadSummary(tasks: catalog.activeTasks(projectId: project.id, on: today), today: today)
        check(currentSummary.total == "1 open · ~20m remaining" && currentSummary.upcomingDetail == nil, "Today’s rollover copy is not upcoming work")
        _ = try await api.completeTask(rowNumber: current.rowNumber, source: "test")
        catalog = try await api.fetchProjects()
        check(catalog.nextTask(projectId: project.id, on: today) == nil, "Finished current task no longer drives urgency")
        check(catalog.isComplete(project.id, on: today), "Latest current status overrides historical open copies")
        let separate = try await api.createTask(CreateTaskRequest(date: today, task: current.task, category: "Work", priority: 1, estimateMinutes: 10))
        check(separate.taskId != current.taskId, "Identical names do not merge identities")
        catalog = try await api.linkProjectTasks(ProjectLinkRequest(revision: catalog.revision, rows: [ProjectRowReference(separate)], projectId: project.id, groupId: nil))
        check(!catalog.isComplete(project.id, on: today), "New task reopens completion eligibility")
        var stale = catalog; stale.revision -= 1
        do { _ = try await api.saveProjects(stale); preconditionFailure("Stale save accepted") }
        catch APIError.httpStatus(let status, _) { check(status == 409, "Concurrent edits cannot overwrite metadata") }
        _ = try await api.completeTask(rowNumber: separate.rowNumber, source: "test")
        let future = try await api.createTask(CreateTaskRequest(date: tomorrow, task: "Future project test", category: "Work", priority: 10, estimateMinutes: 15))
        catalog = try await api.fetchProjects()
        catalog = try await api.linkProjectTasks(ProjectLinkRequest(revision: catalog.revision, rows: [ProjectRowReference(future)], projectId: project.id, groupId: nil))
        check(catalog.nextTask(projectId: project.id, on: today) == nil, "Future tasks never drive today’s priority")
        check(!catalog.isComplete(project.id, on: today), "Future work prevents premature closure")
        let futureSummary = ProjectWorkloadSummary(tasks: catalog.activeTasks(projectId: project.id, on: today), today: today)
        check(futureSummary.total == "1 open · ~15m total remaining", "Future-only total is explicitly the whole workload")
        check(futureSummary.upcomingDetail == "Includes ~15m in 1 upcoming task", "Future work is identified with its estimate")
        let mixedSummary = ProjectWorkloadSummary(tasks: [current, future], today: today)
        check(mixedSummary.total == "2 open · ~35m total remaining" && mixedSummary.upcomingDetail == futureSummary.upcomingDetail, "Mixed workload identifies the future portion without adding it twice")
        var unestimatedFuture = future
        unestimatedFuture.estimateMinutes = nil
        check(ProjectWorkloadSummary(tasks: [unestimatedFuture], today: today).upcomingDetail == "Includes 1 upcoming task · not yet estimated", "Unestimated upcoming work remains visible")
        check(ProjectWorkloadSummary(tasks: [future, unestimatedFuture], today: today).upcomingDetail == "Includes ~15m in 2 upcoming tasks · some estimates missing", "Partial upcoming estimates are explicit")
        check(ProjectWorkloadSummary(tasks: [], today: today).upcomingDetail == nil, "Empty workload has no upcoming annotation")
        catalog.projects[0].closed = true
        catalog = try await api.saveProjects(catalog)
        check(catalog.projects[0].closed && !catalog.memberships.isEmpty, "Project closure retains history and membership")
        let standalone = try await api.createTask(CreateTaskRequest(date: today, task: "Standalone checklist", category: "Personal", priority: 1, estimateMinutes: 5))
        catalog = try await api.linkProjectTasks(ProjectLinkRequest(revision: catalog.revision, rows: [ProjectRowReference(standalone)], projectId: nil, groupId: nil))
        let standaloneIndex = catalog.memberships.firstIndex { $0.taskId == standalone.taskId }!
        catalog.memberships[standaloneIndex].checklist = [ProjectChecklistItem(title: "Small step")]
        catalog = try await api.saveProjects(catalog)
        check(catalog.membership(for: standalone)?.checklist?.first?.title == "Small step", "Standalone task checklists persist without requiring projects")
    }
}
