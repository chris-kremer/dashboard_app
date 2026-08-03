import AppIntents
import Foundation
import WidgetKit
#if os(iOS)
import ActivityKit
#endif

enum TaskIntentHelpers {
    static func task(rowId: String, cache: SharedCache = .shared) -> ScheduleItem? {
        cache.loadSnapshot()?.openTasks.first { $0.id == rowId }
    }

    static func complete(rowId: String, source: String) async throws {
        guard var task = task(rowId: rowId) else { return }
        let stopTime = Date.trackerTimeFormatter.string(from: Date())
        task.status = .done
        task.stop = stopTime
        try SharedCache.shared.upsertTask(task)
        WidgetCenter.shared.reloadAllTimelines()
#if os(iOS)
        await TaskLiveActivityCoordinator.shared.syncFromCache()
#endif

        do {
            _ = try await TrackerAPIClient.shared.updateTask(rowNumber: task.rowNumber, patch: TaskPatchRequest(
                priority: nil,
                estimateMinutes: nil,
                comment: nil,
                delay: nil,
                start: nil,
                stop: stopTime,
                status: nil
            ))
            let updated = try await TrackerAPIClient.shared.completeTask(rowNumber: task.rowNumber, source: source, stop: stopTime)
            try SharedCache.shared.upsertTask(updated)
            WidgetCenter.shared.reloadAllTimelines()
#if os(iOS)
            await TaskLiveActivityCoordinator.shared.syncFromCache()
#endif
        } catch {
            try queue(kind: .completeTask, payload: CompleteTaskRequest(source: source, stop: stopTime), error: error)
            throw error
        }
    }

    static func patch(rowId: String, patch: TaskPatchRequest, kind: PendingOperation.Kind) async throws {
        guard var task = task(rowId: rowId) else { return }
        if let start = patch.start {
            task.start = start
            task.status = patch.status ?? .inProgress
        }
        if patch.clearsStop {
            task.stop = nil
        }
        if let stop = patch.stop {
            task.stop = stop
            task.status = patch.status ?? task.status
        }
        try SharedCache.shared.upsertTask(task)
        WidgetCenter.shared.reloadAllTimelines()
#if os(iOS)
        await TaskLiveActivityCoordinator.shared.syncFromCache()
#endif

        do {
            let updated = try await TrackerAPIClient.shared.updateTask(rowNumber: task.rowNumber, patch: patch)
            try SharedCache.shared.upsertTask(updated)
            WidgetCenter.shared.reloadAllTimelines()
#if os(iOS)
            await TaskLiveActivityCoordinator.shared.syncFromCache()
#endif
        } catch {
            try queue(kind: kind, payload: patch, error: error)
            throw error
        }
    }

    private static func queue<T: Encodable>(kind: PendingOperation.Kind, payload: T, error: Error) throws {
        var operation = PendingOperation(kind: kind, payload: try TrackerJSON.encoder.encode(payload))
        operation.lastError = error.localizedDescription
        try SharedCache.shared.appendPendingOperation(operation)
    }

    static func continueTaskFromLoggedInterval(_ task: ScheduleItem) async throws {
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

        var archived = task
        archived.status = .logged
        try SharedCache.shared.upsertTask(archived)
        WidgetCenter.shared.reloadAllTimelines()

        do {
            let created = try await TrackerAPIClient.shared.createTask(createRequest)
            let archivedServer = try await TrackerAPIClient.shared.updateTask(rowNumber: task.rowNumber, patch: archivePatch)
            let startedServer = try await TrackerAPIClient.shared.updateTask(rowNumber: created.rowNumber, patch: startPatch)
            try SharedCache.shared.upsertTask(archivedServer)
            try SharedCache.shared.upsertTask(startedServer)
            WidgetCenter.shared.reloadAllTimelines()
#if os(iOS)
            await TaskLiveActivityCoordinator.shared.syncFromCache()
#endif
        } catch {
            try queue(kind: .startTask, payload: startPatch, error: error)
            throw error
        }
    }
}

#if os(iOS)
actor TaskLiveActivityCoordinator {
    static let shared = TaskLiveActivityCoordinator()

    func syncFromCache() async {
        guard let snapshot = SharedCache.shared.loadSnapshot() else { return }
        await sync(with: snapshot)
    }

    func sync(with snapshot: TrackerSnapshot) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let activities = Activity<TaskLiveActivityAttributes>.activities
        let runningTasks = snapshot.todayOpenTasks.filter { $0.start != nil && $0.stop == nil }
        if !runningTasks.isEmpty {
            let state = runningState(for: runningTasks)
            let content = ActivityContent(state: state, staleDate: nil)

            if let activity = activities.first {
                await activity.update(content)
                for extraActivity in activities.dropFirst() {
                    await extraActivity.end(nil, dismissalPolicy: .immediate)
                }
            } else {
                do {
                    _ = try Activity.request(
                        attributes: TaskLiveActivityAttributes(),
                        content: content,
                        pushType: nil
                    )
                } catch {
                    // The task remains safely logged even if Live Activities are unavailable.
                }
            }
            return
        }

        guard !activities.isEmpty else { return }
        let suggestions = suggestions(from: snapshot)
        let state = TaskLiveActivityAttributes.ContentState(
            phase: .suggestions,
            rowId: nil,
            task: "",
            category: "",
            startedAt: nil,
            estimateMinutes: nil,
            suggestions: suggestions,
            runningTasks: nil
        )
        let content = ActivityContent(state: state, staleDate: nil)

        for activity in activities {
            if suggestions.isEmpty {
                await activity.end(content, dismissalPolicy: .immediate)
            } else {
                await activity.end(
                    content,
                    dismissalPolicy: .after(Date().addingTimeInterval(15 * 60))
                )
            }
        }
    }

    private func runningState(for tasks: [ScheduleItem]) -> TaskLiveActivityAttributes.ContentState {
        let liveTasks = tasks.map {
            TaskLiveActivityAttributes.RunningTask(
                rowId: $0.id,
                task: $0.task,
                category: $0.category,
                startedAt: $0.dateTime(from: $0.start) ?? Date(),
                estimateMinutes: $0.estimateMinutes
            )
        }
        let first = liveTasks[0]
        return TaskLiveActivityAttributes.ContentState(
            phase: .running,
            rowId: first.rowId,
            task: first.task,
            category: first.category,
            startedAt: first.startedAt,
            estimateMinutes: first.estimateMinutes,
            suggestions: [],
            runningTasks: liveTasks
        )
    }

    private func suggestions(from snapshot: TrackerSnapshot) -> [TaskLiveActivityAttributes.Suggestion] {
        snapshot.todayOpenTasks
            .filter { $0.start == nil || $0.stop != nil }
            .prefix(2)
            .map {
                TaskLiveActivityAttributes.Suggestion(
                    rowId: $0.id,
                    task: $0.task,
                    category: $0.category,
                    estimateMinutes: $0.estimateMinutes
                )
            }
    }
}
#endif
