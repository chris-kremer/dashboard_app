import Foundation
import Observation

@MainActor
@Observable
final class WatchTrackerStore {
    var snapshot: TrackerSnapshot = .empty
    var isRefreshing = false
    var lastError: String?
    var lastRefresh: Date?

    private let apiClient: TrackerAPIClient

    init(apiClient: TrackerAPIClient = .shared) {
        self.apiClient = apiClient
    }

    var openTasks: [ScheduleItem] {
        snapshot.todayOpenTasks
    }

    var activeTasks: [ScheduleItem] {
        snapshot.schedule
            .filter { $0.status == .inProgress || ($0.start != nil && $0.stop == nil) }
            .sorted { ($0.start ?? "") < ($1.start ?? "") }
    }

    var nextBlock: ScheduleItem? {
        let now = Date()
        return snapshot.schedule
            .filter { item in
                guard let start = item.dateTime(from: item.start) else { return false }
                return start > now && start.timeIntervalSince(now) <= 12 * 60 * 60
            }
            .sorted {
                ($0.dateTime(from: $0.start) ?? .distantFuture) <
                ($1.dateTime(from: $1.start) ?? .distantFuture)
            }
            .first
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let date = Date.trackerDateFormatter.string(from: Date())
            snapshot = try await apiClient.fetchSnapshot(date: date)
            try? SharedCache.shared.saveSnapshot(snapshot)
            lastError = nil
            lastRefresh = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func start(_ task: ScheduleItem) async {
        await patch(task, TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: nil,
            start: Date.trackerTimeFormatter.string(from: Date()),
            stop: nil,
            status: .inProgress,
            clearsStop: true
        ))
    }

    func pause(_ task: ScheduleItem) async {
        await patch(task, TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: nil,
            start: nil,
            stop: Date.trackerTimeFormatter.string(from: Date()),
            status: .inProgress
        ))
    }

    func complete(_ task: ScheduleItem) async {
        let stop = Date.trackerTimeFormatter.string(from: Date())
        optimisticallyUpdate(task) { item in
            item.stop = stop
            item.status = .done
        }

        do {
            _ = try await apiClient.updateTask(rowNumber: task.rowNumber, patch: TaskPatchRequest(
                priority: nil,
                estimateMinutes: nil,
                comment: nil,
                delay: nil,
                start: nil,
                stop: stop,
                status: nil
            ))
            _ = try await apiClient.completeTask(rowNumber: task.rowNumber, source: "watch", stop: stop)
            await refresh()
        } catch {
            lastError = error.localizedDescription
            await refresh()
        }
    }

    private func patch(_ task: ScheduleItem, _ patch: TaskPatchRequest) async {
        optimisticallyUpdate(task) { item in
            if let start = patch.start {
                item.start = start
            }
            if patch.clearsStop {
                item.stop = nil
            } else if let stop = patch.stop {
                item.stop = stop
            }
            if let status = patch.status {
                item.status = status
            }
        }

        do {
            _ = try await apiClient.updateTask(rowNumber: task.rowNumber, patch: patch)
            await refresh()
        } catch {
            lastError = error.localizedDescription
            await refresh()
        }
    }

    private func optimisticallyUpdate(_ task: ScheduleItem, mutate: (inout ScheduleItem) -> Void) {
        if let index = snapshot.schedule.firstIndex(where: { $0.id == task.id }) {
            mutate(&snapshot.schedule[index])
        }
        if let index = snapshot.openTasks.firstIndex(where: { $0.id == task.id }) {
            mutate(&snapshot.openTasks[index])
        }
    }
}
