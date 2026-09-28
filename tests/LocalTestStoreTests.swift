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
}
