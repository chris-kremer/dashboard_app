import AppIntents
import Foundation
import WidgetKit

enum TaskIntentHelpers {
    static func task(rowId: String, cache: SharedCache = .shared) -> ScheduleItem? {
        cache.loadSnapshot()?.openTasks.first { $0.id == rowId }
    }

    static func complete(rowId: String, source: String) async throws {
        guard var task = task(rowId: rowId) else { return }
        task.status = .done
        try SharedCache.shared.upsertTask(task)
        WidgetCenter.shared.reloadAllTimelines()

        do {
            let updated = try await TrackerAPIClient.shared.completeTask(rowNumber: task.rowNumber, source: source)
            try SharedCache.shared.upsertTask(updated)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            try queue(kind: .completeTask, payload: CompleteTaskRequest(source: source), error: error)
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

        do {
            let updated = try await TrackerAPIClient.shared.updateTask(rowNumber: task.rowNumber, patch: patch)
            try SharedCache.shared.upsertTask(updated)
            WidgetCenter.shared.reloadAllTimelines()
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
            start: nil,
            stop: nil,
            status: .logged
        )
        let startPatch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
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
        } catch {
            try queue(kind: .startTask, payload: startPatch, error: error)
            throw error
        }
    }
}
