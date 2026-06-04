import BackgroundTasks
import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class SyncController {
    static let shared = SyncController()

    var snapshot: TrackerSnapshot
    var syncState: SyncState
    var isRefreshing = false

    private let cache: SharedCache
    private let apiClient: TrackerAPIClient

    init(cache: SharedCache = .shared, apiClient: TrackerAPIClient = .shared) {
        self.cache = cache
        self.apiClient = apiClient
        self.snapshot = cache.loadSnapshot() ?? .empty
        self.syncState = cache.loadSyncState()
    }

    func refresh(date: String = Date.trackerDateFormatter.string(from: Date())) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snapshot = try await apiClient.fetchSnapshot(date: date)
            self.snapshot = snapshot
            try cache.saveSnapshot(snapshot)
            syncState.lastSuccessfulSync = Date()
            syncState.lastError = nil
            try cache.saveSyncState(syncState)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            syncState.lastError = error.localizedDescription
            try? cache.saveSyncState(syncState)
        }
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
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func completeTask(_ task: ScheduleItem, source: String = "ios") async {
        var optimistic = task
        optimistic.status = .done
        try? cache.upsertTask(optimistic)
        snapshot = cache.loadSnapshot() ?? snapshot
        WidgetCenter.shared.reloadAllTimelines()

        await perform(kind: .completeTask, request: CompleteTaskRequest(source: source)) {
            let item = try await apiClient.completeTask(rowNumber: task.rowNumber, source: source)
            try cache.upsertTask(item)
            snapshot = cache.loadSnapshot() ?? snapshot
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func startTask(_ task: ScheduleItem) async {
        let startTime = resumedStartTime(for: task) ?? Date.trackerTimeFormatter.string(from: Date())
        let patch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            start: startTime,
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
            start: nil,
            stop: Date.trackerTimeFormatter.string(from: Date()),
            status: .inProgress
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
        }
    }

    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.chriskremer.TrackerDashboard.refresh", using: nil) { task in
            Task { @MainActor in
                await self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.chriskremer.TrackerDashboard.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(AppSettings.shared.refreshIntervalMinutes * 60))
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) async {
        scheduleBackgroundRefresh()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        await refresh()
        task.setTaskCompleted(success: syncState.lastError == nil)
    }

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

    private func resumedStartTime(for task: ScheduleItem) -> String? {
        guard let startedAt = task.dateTime(from: task.start),
              let stoppedAt = task.dateTime(from: task.stop)
        else {
            return nil
        }
        let elapsed = max(0, stoppedAt.timeIntervalSince(startedAt))
        return Date.trackerTimeFormatter.string(from: Date().addingTimeInterval(-elapsed))
    }
}
