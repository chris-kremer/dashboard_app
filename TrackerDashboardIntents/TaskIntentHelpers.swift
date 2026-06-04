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
        if let stop = patch.stop {
            task.stop = stop
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
}
