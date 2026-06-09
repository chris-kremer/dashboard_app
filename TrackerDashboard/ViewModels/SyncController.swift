import Foundation
import Observation
#if os(iOS)
import BackgroundTasks
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
@Observable
final class SyncController {
    static let shared = SyncController()

    var snapshot: TrackerSnapshot
    var healthSleep: HealthSleepEntry?
    var syncState: SyncState
    var isRefreshing = false

    private let cache: SharedCache
    private let apiClient: TrackerAPIClient

    init(cache: SharedCache = .shared, apiClient: TrackerAPIClient = .shared) {
        self.cache = cache
        self.apiClient = apiClient
        self.snapshot = cache.loadSnapshot() ?? .empty
        self.healthSleep = cache.loadHealthSleep()
        self.syncState = cache.loadSyncState()
    }

    func refresh(date: String = Date.trackerDateFormatter.string(from: Date())) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snapshot = try await apiClient.fetchSnapshot(date: date)
            self.snapshot = snapshot
            try cache.saveSnapshot(snapshot)
            await refreshHealthSleep()
            let importedWorkouts = await importHealthWorkouts(date: date)
            if importedWorkouts {
                let updatedSnapshot = try await apiClient.fetchSnapshot(date: date)
                self.snapshot = updatedSnapshot
                try cache.saveSnapshot(updatedSnapshot)
            }
            syncState.lastSuccessfulSync = Date()
            syncState.lastError = nil
            try cache.saveSyncState(syncState)
            reloadWidgets()
            SleepReminderScheduler.update(for: snapshot)
        } catch {
            syncState.lastError = error.localizedDescription
            try? cache.saveSyncState(syncState)
            await refreshHealthSleep()
        }
    }

    func refreshHealthSleep() async {
#if os(iOS)
        do {
            try await HealthKitSleepStore.shared.requestAuthorization()
            if let sleep = try await HealthKitSleepStore.shared.sleep() {
                healthSleep = sleep
                try cache.saveHealthSleep(sleep)
            }
        } catch {
            syncState.lastError = error.localizedDescription
            try? cache.saveSyncState(syncState)
        }
#endif
    }

    func importHealthWorkouts(date: String = Date.trackerDateFormatter.string(from: Date())) async -> Bool {
#if os(iOS)
        do {
            try await HealthKitWorkoutStore.shared.requestAuthorization()
            let targetDate = Date.trackerDateFormatter.date(from: date) ?? Date()
            let workouts = try await HealthKitWorkoutStore.shared.workouts(for: targetDate)
            let existingIds = Set(snapshot.schedule.compactMap { item -> String? in
                item.source == "healthkit-workout" ? item.sourceId : nil
            })
            let missing = workouts.filter { !existingIds.contains($0.id) }
            guard !missing.isEmpty else { return false }

            for workout in missing {
                _ = try await apiClient.createTask(CreateTaskRequest(
                    date: workout.date,
                    task: workout.title,
                    category: "sports",
                    comment: "HealthKit workout",
                    priority: 2,
                    estimateMinutes: 30,
                    start: workout.start,
                    stop: workout.stop,
                    status: .logged,
                    source: "healthkit-workout",
                    sourceId: workout.id,
                    importedAt: ISO8601DateFormatter().string(from: Date())
                ))
            }
            return true
        } catch {
            syncState.lastError = error.localizedDescription
            try? cache.saveSyncState(syncState)
            return false
        }
#else
        return false
#endif
    }

    func createTask(_ request: CreateTaskRequest) async {
        await perform(kind: .createTask, request: request) {
            let item = try await apiClient.createTask(request)
            try cache.upsertTask(item)
            await refresh(date: request.date)
        }
    }

    func updateTask(rowNumber: Int, patch: TaskPatchRequest) async {
        await perform(kind: .updateTask, request: patch) {
            let item = try await apiClient.updateTask(rowNumber: rowNumber, patch: patch)
            try cache.upsertTask(item)
            snapshot = cache.loadSnapshot() ?? snapshot
            reloadWidgets()
        }
    }

    func completeTask(_ task: ScheduleItem, source: String = "ios") async {
        let stopTime = Date.trackerTimeFormatter.string(from: Date())
        var optimistic = task
        optimistic.status = .done
        optimistic.stop = stopTime
        try? cache.upsertTask(optimistic)
        snapshot = cache.loadSnapshot() ?? snapshot
        reloadWidgets()

        await perform(kind: .completeTask, request: CompleteTaskRequest(source: source, stop: stopTime)) {
            _ = try await apiClient.updateTask(rowNumber: task.rowNumber, patch: TaskPatchRequest(
                priority: nil,
                estimateMinutes: nil,
                comment: nil,
                delay: nil,
                start: nil,
                stop: stopTime,
                status: nil
            ))
            let item = try await apiClient.completeTask(rowNumber: task.rowNumber, source: source, stop: stopTime)
            try cache.upsertTask(item)
            snapshot = cache.loadSnapshot() ?? snapshot
            reloadWidgets()
        }
    }

    func startTask(_ task: ScheduleItem) async {
        if task.start != nil && task.stop != nil {
            await continueTaskFromLoggedInterval(task)
            return
        }

        let patch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: nil,
            start: Date.trackerTimeFormatter.string(from: Date()),
            stop: nil,
            status: .inProgress,
            clearsStop: true
        )
        await updateTask(rowNumber: task.rowNumber, patch: patch)
    }

    func stopTask(_ task: ScheduleItem) async {
        let patch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: nil,
            start: nil,
            stop: Date.trackerTimeFormatter.string(from: Date()),
            status: .inProgress
        )
        await updateTask(rowNumber: task.rowNumber, patch: patch)
    }

    func snoozeTask(_ task: ScheduleItem, hours: Int = 2) async {
        let until = ISO8601DateFormatter.tracker.string(from: Date().addingTimeInterval(TimeInterval(hours * 3600)))
        var optimistic = task
        optimistic.delay = until
        optimistic.adjustedPriority = 0
        try? cache.upsertTask(optimistic)
        snapshot = cache.loadSnapshot() ?? snapshot
        reloadWidgets()

        let patch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: until,
            start: nil,
            stop: nil,
            status: nil
        )
        await updateTask(rowNumber: task.rowNumber, patch: patch)
    }

    func deleteTask(_ task: ScheduleItem) async {
        var optimistic = task
        optimistic.status = .cancelled
        try? cache.upsertTask(optimistic)
        snapshot = cache.loadSnapshot() ?? snapshot
        reloadWidgets()

        let patch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: nil,
            start: nil,
            stop: nil,
            status: .cancelled
        )
        await updateTask(rowNumber: task.rowNumber, patch: patch)
    }

    func logCaffeine(_ request: CaffeineRequest) async {
        await perform(kind: .logCaffeine, request: request) {
            _ = try await apiClient.logCaffeine(request)
            await refresh(date: request.date)
        }
    }

    func logFood(_ request: FoodRequest) async {
        await perform(kind: .logFood, request: request) {
            _ = try await apiClient.logFood(request)
            await refresh(date: request.date)
        }
    }

    func upsertSleep(_ request: SleepRequest) async {
        await perform(kind: .upsertSleep, request: request) {
            _ = try await apiClient.upsertSleep(request)
            await refresh(date: request.date)
            SleepReminderScheduler.update(for: snapshot)
        }
    }

    func registerBackgroundRefresh() {
#if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.chriskremer.TrackerDashboard.refresh", using: nil) { task in
            Task { @MainActor in
                await self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
            }
        }
#endif
    }

    func scheduleBackgroundRefresh() {
#if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: "com.chriskremer.TrackerDashboard.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(AppSettings.shared.refreshIntervalMinutes * 60))
        try? BGTaskScheduler.shared.submit(request)
#endif
    }

#if os(iOS)
    private func handleBackgroundRefresh(task: BGAppRefreshTask) async {
        scheduleBackgroundRefresh()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        await refresh()
        task.setTaskCompleted(success: syncState.lastError == nil)
    }
#endif

    private func perform<Request: Encodable>(
        kind: PendingOperation.Kind,
        request: Request,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
        } catch {
            var pending = PendingOperation(kind: kind, payload: (try? TrackerJSON.encoder.encode(request)) ?? Data())
            pending.lastError = error.localizedDescription
            try? cache.appendPendingOperation(pending)
            syncState = cache.loadSyncState()
        }
    }

    private func continueTaskFromLoggedInterval(_ task: ScheduleItem) async {
        let startTime = Date.trackerTimeFormatter.string(from: Date())
        let createRequest = CreateTaskRequest(
            date: task.date,
            task: task.task,
            category: task.category,
            comment: task.comment,
            priority: task.priority,
            estimateMinutes: task.estimateMinutes
        )
        let archivePatch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: nil,
            start: nil,
            stop: nil,
            status: .logged
        )
        let startPatch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: nil,
            start: startTime,
            stop: nil,
            status: .inProgress,
            clearsStop: true
        )

        await perform(kind: .startTask, request: startPatch) {
            var archived = task
            archived.status = .logged
            try cache.upsertTask(archived)

            let created = try await apiClient.createTask(createRequest)
            var optimistic = created
            optimistic.start = startTime
            optimistic.status = .inProgress
            try cache.upsertTask(optimistic)
            snapshot = cache.loadSnapshot() ?? snapshot
            reloadWidgets()

            let archivedServer = try await apiClient.updateTask(rowNumber: task.rowNumber, patch: archivePatch)
            try cache.upsertTask(archivedServer)
            let startedServer = try await apiClient.updateTask(rowNumber: created.rowNumber, patch: startPatch)
            try cache.upsertTask(startedServer)
            snapshot = cache.loadSnapshot() ?? snapshot
            reloadWidgets()
        }
    }

    private func reloadWidgets() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }
}
