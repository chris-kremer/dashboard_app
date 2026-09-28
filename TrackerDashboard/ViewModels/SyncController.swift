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
    var projectCatalog = ProjectCatalog()
    var projectsLoaded = false
    var projectError: String?
    var projectBusy = false
    var projectToClose: TrackerProject?

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
            await refreshProjects()
        } catch {
            syncState.lastError = error.localizedDescription
            try? cache.saveSyncState(syncState)
            await refreshHealthSleep()
        }
    }

    func refreshHealthSleep() async {
        guard !AppSettings.shared.usesLocalTestData else { return }
#if os(iOS)
        do {
            try await HealthKitSleepStore.shared.requestAuthorization()
            if let sleep = try await HealthKitSleepStore.shared.sleep() {
                healthSleep = sleep
                try cache.saveHealthSleep(sleep)
                reloadWidgets()
            }
        } catch {
            syncState.lastError = error.localizedDescription
            try? cache.saveSyncState(syncState)
        }
#endif
    }

    func importHealthWorkouts(date: String = Date.trackerDateFormatter.string(from: Date())) async -> Bool {
        guard !AppSettings.shared.usesLocalTestData else { return false }
#if os(iOS)
        do {
            try await HealthKitWorkoutStore.shared.requestAuthorization()
            let targetDate = Date.trackerDateFormatter.date(from: date) ?? Date()
            let workouts = try await HealthKitWorkoutStore.shared.workouts(for: targetDate)
            let existingIds = Set(snapshot.schedule.compactMap { item -> String? in
                item.source == "healthkit-workout" ? item.sourceId : nil
            })
            let missing = workouts.filter { workout in
                !existingIds.contains(workout.id) && !existingIds.contains(workout.workoutId)
            }
            guard !missing.isEmpty else { return false }

            for workout in missing {
                let segmentNote = workout.segmentCount > 1 ? " segment \(workout.segmentIndex)/\(workout.segmentCount)" : ""
                _ = try await apiClient.createTask(CreateTaskRequest(
                    date: workout.date,
                    task: workout.title,
                    category: "sports",
                    comment: "HealthKit workout\(segmentNote)",
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

    @discardableResult
    func createTask(_ request: CreateTaskRequest, projectId: String? = nil, groupId: String? = nil) async -> Bool {
        var assignmentFailed = false
        let succeeded = await perform(kind: .createTask, request: request) {
            let item = try await apiClient.createTask(request)
            try cache.upsertTask(item)
            if let projectId {
                assignmentFailed = !(await assignProjectTasks([item], projectId: projectId, groupId: groupId))
            }
            await refresh(date: request.date)
        }
        if succeeded {
            postSaveConfirmation(assignmentFailed ? "Task saved in Other tasks. Retry its project assignment."
                : request.source == "ios-gap-fill" || request.status == .logged
                ? "Activity logged"
                : "To-do added")
        }
        return succeeded
    }

    @discardableResult
    func updateTask(rowNumber: Int, patch: TaskPatchRequest) async -> Bool {
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

        let succeeded = await perform(kind: .completeTask, request: CompleteTaskRequest(source: source, stop: stopTime)) {
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
        if succeeded {
            postSaveConfirmation("Task completed")
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
        let stopTime = Date.trackerTimeFormatter.string(from: Date())
        var optimistic = task
        optimistic.stop = stopTime
        optimistic.status = .inProgress
        try? cache.upsertTask(optimistic)
        snapshot = cache.loadSnapshot() ?? snapshot
        reloadWidgets()

        let patch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: nil,
            start: nil,
            stop: stopTime,
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
        let succeeded = await perform(kind: .logCaffeine, request: request) {
            _ = try await apiClient.logCaffeine(request)
            await refresh(date: request.date)
        }
        if succeeded {
            postSaveConfirmation("\(request.label.trimmingCharacters(in: .whitespacesAndNewlines).capitalized) logged")
        }
    }

    func logFood(_ request: FoodRequest) async {
        let succeeded = await perform(kind: .logFood, request: request) {
            _ = try await apiClient.logFood(request)
            await refresh(date: request.date)
        }
        if succeeded {
            postSaveConfirmation("\(request.mealContext) logged")
        }
    }

    func upsertSleep(_ request: SleepRequest) async {
        let succeeded = await perform(kind: .upsertSleep, request: request) {
            _ = try await apiClient.upsertSleep(request)
            await refresh(date: request.date)
            SleepReminderScheduler.update(for: snapshot)
        }
        if succeeded {
            postSaveConfirmation("Sleep saved")
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

    @discardableResult
    private func perform<Request: Encodable>(
        kind: PendingOperation.Kind,
        request: Request,
        operation: () async throws -> Void
    ) async -> Bool {
        do {
            try await operation()
            if projectsLoaded { await refreshProjects() }
            return true
        } catch {
            var pending = PendingOperation(kind: kind, payload: (try? TrackerJSON.encoder.encode(request)) ?? Data())
            pending.lastError = error.localizedDescription
            try? cache.appendPendingOperation(pending)
            syncState = cache.loadSyncState()
            return false
        }
    }

    private func postSaveConfirmation(_ message: String) {
        NotificationCenter.default.post(
            name: .entrySaved,
            object: nil,
            userInfo: ["message": message]
        )
    }

    func refreshProjects() async {
        guard !projectBusy else { return }
        projectBusy = true
        defer { projectBusy = false }
        do {
            acceptProjects(try await apiClient.fetchProjects())
        } catch { projectError = error.localizedDescription }
    }

    private func acceptProjects(_ catalog: ProjectCatalog) {
        let today = Date.trackerDateFormatter.string(from: Date())
        if projectsLoaded {
            projectToClose = catalog.projects.first {
                !$0.closed && catalog.isComplete($0.id, on: today)
                    && !projectCatalog.isComplete($0.id, on: today)
            } ?? projectToClose
        }
        projectCatalog = catalog
        projectsLoaded = true
        projectError = nil
    }

    @discardableResult
    func saveProjects(_ catalog: ProjectCatalog) async -> Bool {
        guard !projectBusy else { return false }
        projectBusy = true
        defer { projectBusy = false }
        do {
            acceptProjects(try await apiClient.saveProjects(catalog))
            return true
        } catch {
            projectError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func assignProjectTasks(_ tasks: [ScheduleItem], projectId: String?, groupId: String?) async -> Bool {
        guard !projectBusy else { return false }
        projectBusy = true
        defer { projectBusy = false }
        do {
            acceptProjects(try await apiClient.linkProjectTasks(ProjectLinkRequest(
                revision: projectCatalog.revision, rows: tasks.map(ProjectRowReference.init), projectId: projectId, groupId: groupId
            )))
            // Include newly stamped identities in task and Live Activity caches.
            for row in projectCatalog.schedule where row.date == snapshot.date {
                try cache.upsertTask(row)
            }
            snapshot = cache.loadSnapshot() ?? snapshot
            return true
        } catch {
            projectError = error.localizedDescription
            return false
        }
    }

    func resolveMissingTask(_ task: ScheduleItem, action: String) async {
        guard !projectBusy, let taskId = task.taskId else { return }
        projectBusy = true
        do {
            acceptProjects(try await apiClient.resolveProjectTask(ProjectResolutionRequest(
                revision: projectCatalog.revision, taskId: taskId, action: action
            )))
            projectBusy = false
            await refresh()
        } catch {
            projectBusy = false
            projectError = error.localizedDescription
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
            estimateMinutes: task.estimateMinutes,
            taskId: task.taskId
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
#if os(iOS)
        Task {
            if let request = await TaskLiveActivityCoordinator.shared.sync(
                with: snapshot,
                healthSleep: healthSleep
            ) {
                do {
                    try await apiClient.startMorningLiveActivity(request)
                    await TaskLiveActivityCoordinator.shared.markMorningShown(date: request.date)
                } catch {
                    // A later HealthKit or foreground refresh can retry the morning start.
                }
            }
        }
#endif
    }
}

extension Notification.Name {
    static let entrySaved = Notification.Name("entrySaved")
}
