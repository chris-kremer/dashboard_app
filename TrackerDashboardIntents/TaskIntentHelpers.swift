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
        _ = await sync(with: snapshot, healthSleep: SharedCache.shared.loadHealthSleep())
    }

    func sync(
        with snapshot: TrackerSnapshot,
        healthSleep: HealthSleepEntry? = nil
    ) async -> MorningLiveActivityRequest? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }

        let activities = Activity<TaskLiveActivityAttributes>.activities
        let activeTasks = snapshot.todayOpenTasks.filter { $0.start != nil }
        if !activeTasks.isEmpty {
            let phase: TaskLiveActivityAttributes.ContentState.Phase = activeTasks.contains { $0.stop == nil }
                ? .running
                : .paused
            let state = activeState(for: activeTasks, phase: phase, morningDate: storedMorningDate)
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
            return nil
        }

        let suggestions = suggestions(from: snapshot)
        let today = Date.trackerDateFormatter.string(from: Date())
        let shouldShowMorning = storedMorningDate != today
            && isCompletedMorningSleep(healthSleep)
            && !suggestions.isEmpty

        if activities.isEmpty {
            guard shouldShowMorning else { return nil }
            let state = morningState(suggestions: suggestions, date: today)
            do {
                _ = try Activity.request(
                    attributes: TaskLiveActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: morningStaleDate()),
                    pushType: nil
                )
                storedMorningDate = today
                return nil
            } catch {
                return MorningLiveActivityRequest(
                    date: today,
                    greeting: state.greeting ?? "Good morning!",
                    staleAt: morningStaleDate() ?? Date().addingTimeInterval(6 * 60 * 60),
                    suggestions: suggestions
                )
            }
        }

        for activity in activities {
            if suggestions.isEmpty {
                let state = suggestionsState(suggestions: [])
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            } else {
                // Keep the activity alive while it offers the next tasks. An ended
                // activity is frozen, so starting a suggestion would otherwise have
                // to create a new activity before the Lock Screen can update.
                let state: TaskLiveActivityAttributes.ContentState
                if shouldShowMorning {
                    state = morningState(suggestions: suggestions, date: today)
                    storedMorningDate = today
                } else {
                    state = suggestionsState(suggestions: suggestions)
                }
                await activity.update(ActivityContent(
                    state: state,
                    staleDate: state.phase == .morning ? morningStaleDate() : nil
                ))
            }
        }
        return nil
    }

    func markMorningShown(date: String) {
        storedMorningDate = date
    }

    private func activeState(
        for tasks: [ScheduleItem],
        phase: TaskLiveActivityAttributes.ContentState.Phase,
        morningDate: String?
    ) -> TaskLiveActivityAttributes.ContentState {
        let liveTasks = tasks.map {
            TaskLiveActivityAttributes.RunningTask(
                rowId: $0.id,
                task: $0.task,
                category: $0.category,
                startedAt: $0.dateTime(from: $0.start) ?? Date(),
                estimateMinutes: $0.estimateMinutes,
                pausedAt: $0.dateTime(from: $0.stop)
            )
        }
        let first = liveTasks[0]
        return TaskLiveActivityAttributes.ContentState(
            phase: phase,
            rowId: first.rowId,
            task: first.task,
            category: first.category,
            startedAt: first.startedAt,
            estimateMinutes: first.estimateMinutes,
            suggestions: [],
            runningTasks: liveTasks,
            greeting: nil,
            morningDate: morningDate
        )
    }

    private func suggestionsState(
        suggestions: [TaskLiveActivityAttributes.Suggestion]
    ) -> TaskLiveActivityAttributes.ContentState {
        TaskLiveActivityAttributes.ContentState(
            phase: .suggestions,
            rowId: nil,
            task: "",
            category: "",
            startedAt: nil,
            estimateMinutes: nil,
            suggestions: suggestions,
            runningTasks: nil,
            greeting: nil,
            morningDate: storedMorningDate
        )
    }

    private func morningState(
        suggestions: [TaskLiveActivityAttributes.Suggestion],
        date: String
    ) -> TaskLiveActivityAttributes.ContentState {
        TaskLiveActivityAttributes.ContentState(
            phase: .morning,
            rowId: nil,
            task: "",
            category: "",
            startedAt: nil,
            estimateMinutes: nil,
            suggestions: suggestions,
            runningTasks: nil,
            greeting: morningGreeting(for: date),
            morningDate: date
        )
    }

    private func isCompletedMorningSleep(_ sleep: HealthSleepEntry?) -> Bool {
        guard let sleep,
              sleep.date == Date.trackerDateFormatter.string(from: Date()),
              sleep.totalMinutes >= 90,
              let wake = sleep.intervals.map(\.end).max()
        else { return false }

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minutesSinceWake = now.timeIntervalSince(wake) / 60
        return hour >= 4
            && hour < 14
            && minutesSinceWake >= 10
            && minutesSinceWake <= 6 * 60
            && calendar.isDate(wake, inSameDayAs: now)
    }

    private func morningGreeting(for date: String) -> String {
        let greetings = [
            "Good morning!",
            "Rise and shine.",
            "Morning — fresh start.",
            "You’re up. Let’s make it count.",
            "Hello, new day.",
            "Morning! One good start is enough."
        ]
        let stableIndex = date.utf8.reduce(0) { ($0 + Int($1)) % greetings.count }
        return greetings[stableIndex]
    }

    private func morningStaleDate() -> Date? {
        Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())
    }

    private var storedMorningDate: String? {
        get {
            UserDefaults(suiteName: SharedCache.appGroupIdentifier)?
                .string(forKey: "morningLiveActivityDate")
        }
        set {
            UserDefaults(suiteName: SharedCache.appGroupIdentifier)?
                .set(newValue, forKey: "morningLiveActivityDate")
        }
    }

    private func suggestions(from snapshot: TrackerSnapshot) -> [TaskLiveActivityAttributes.Suggestion] {
        snapshot.todayOpenTasks
            .filter { $0.start == nil || $0.stop != nil }
            .prefix(3)
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
