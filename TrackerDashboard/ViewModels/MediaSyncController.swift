import Foundation
import Observation

@MainActor
@Observable
final class MediaSyncController {
    static let shared = MediaSyncController()

    var snapshot: MediaSnapshot
    var lastError: String?
    var isRefreshing = false
    var nudgeHistory: [NudgeHistoryEntry] = []
    var nudgeSummary: NudgeHistorySummary?

    private let cache: SharedCache
    private let apiClient: TrackerAPIClient

    init(cache: SharedCache = .shared, apiClient: TrackerAPIClient = .shared) {
        self.cache = cache
        self.apiClient = apiClient
        self.snapshot = cache.loadMediaSnapshot()
    }

    func refresh(date: String = Date.trackerDateFormatter.string(from: Date())) async {
        isRefreshing = true
        defer { isRefreshing = false }

        async let sessionsResult = result { try await self.apiClient.fetchMediaSessions() }
        async let historyResult = result { try await self.apiClient.fetchNudgeHistory() }
        let (sessions, history) = await (sessionsResult, historyResult)

        if case .success(let response) = sessions {
            var nextSnapshot = snapshot
            nextSnapshot.sessions = response.sessions
            nextSnapshot.status = nil
            nextSnapshot.fetchedAt = Date()
            snapshot = nextSnapshot
            try? cache.saveMediaSnapshot(nextSnapshot)
        }
        if case .success(let response) = history {
            nudgeHistory = response.records
            nudgeSummary = response.summary
        }

        if case .failure(let error) = sessions {
            if snapshot.fetchedAt == .distantPast {
                lastError = "Tracked free time unavailable right now (\(friendlyMessage(for: error)))."
            } else {
                lastError = "Tracked free time unavailable right now; showing cached data from \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))."
            }
        } else if case .failure(let error) = history {
            lastError = "Nudge history unavailable right now (\(friendlyMessage(for: error)))."
        } else {
            lastError = nil
        }
    }

    private func result<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return "timed out"
        }
        return error.localizedDescription
    }

    func events(on date: String) -> [MediaEvent] {
        snapshot.events.filter { $0.date == date }
    }

    func trackedFreeTimeMinutes(on date: String) -> Int {
        if snapshot.sessions != nil {
            return displayMinutes(uniqueUsageSeconds(sessions(on: date)))
        }
        return displayMinutes(uniqueUsageSeconds(events: events(on: date)))
    }

    func trackedFreeTimeEntries(on date: String) -> [FreeTimeEntry] {
        if snapshot.sessions != nil {
            let grouped = Dictionary(grouping: sessions(on: date), by: \.source)
            return grouped.compactMap { source, sessions in
                let seconds = uniqueUsageSeconds(sessions)
                guard seconds > 0 else { return nil }
                return FreeTimeEntry(
                    id: "media-\(source.rawValue)-\(date)",
                    date: date,
                    label: source == .youtube ? "YouTube" : "X feed",
                    durationMinutes: Int((Double(seconds) / 60).rounded()),
                    time: nil,
                    start: sessions.map(\.startedAt).min().map(Date.trackerTimeFormatter.string(from:)),
                    end: nil
                )
            }
            .sorted { $0.label < $1.label }
        }
        let grouped = Dictionary(grouping: events(on: date), by: \.source)
        return grouped.compactMap { source, events in
            let totalSeconds = uniqueUsageSeconds(events: events)
            guard totalSeconds > 0 else { return nil }
            return FreeTimeEntry(
                id: "media-\(source.rawValue)-\(date)",
                date: date,
                label: source == .youtube ? "YouTube" : "X feed",
                durationMinutes: Int((Double(totalSeconds) / 60).rounded()),
                time: nil,
                start: events.map(\.timestamp).min().map(Date.trackerTimeFormatter.string(from:)),
                end: nil
            )
        }
        .sorted { $0.label < $1.label }
    }

    func trackedFreeTimeTimelineEntries(on date: String) -> [FreeTimeEntry] {
        if snapshot.sessions != nil {
            return sessions(on: date).map { session in
                FreeTimeEntry(
                    id: "media-\(session.id)",
                    date: date,
                    label: session.source == .youtube ? "YouTube" : "X feed",
                    durationMinutes: max(1, Int(ceil(Double(session.durationSeconds) / 60))),
                    time: nil,
                    start: Date.trackerTimeFormatter.string(from: session.startedAt),
                    end: Date.trackerTimeFormatter.string(from: session.endedAt)
                )
            }
            .sorted { ($0.start ?? "", $0.label) < ($1.start ?? "", $1.label) }
        }
        return Dictionary(grouping: events(on: date), by: \.source)
            .flatMap { source, events in
                usageSessions(for: events).map { session in
                    FreeTimeEntry(
                        id: "media-\(source.rawValue)-\(Int(session.start.timeIntervalSince1970))",
                        date: date,
                        label: source == .youtube ? "YouTube" : "X feed",
                        durationMinutes: max(1, Int(ceil(Double(session.attentionSeconds) / 60))),
                        time: nil,
                        start: Date.trackerTimeFormatter.string(from: session.start),
                        end: Date.trackerTimeFormatter.string(from: session.end)
                    )
                }
            }
            .sorted { ($0.start ?? "", $0.label) < ($1.start ?? "", $1.label) }
    }

    func sessions(on date: String) -> [CloudMediaSession] {
        (snapshot.sessions ?? []).filter { $0.date == date }
    }

    func usageSummary(on date: String) -> MediaUsageSummary {
        let selected = sessions(on: date)
        let youtube = selected.filter { $0.source == .youtube }
        let x = selected.filter { $0.source == .x }
        return MediaUsageSummary(
            youtubeMinutes: displayMinutes(uniqueUsageSeconds(youtube)),
            xMinutes: displayMinutes(uniqueUsageSeconds(x)),
            totalMinutes: displayMinutes(uniqueUsageSeconds(selected)),
            youtubeSessions: youtube.count,
            xSessions: x.count,
            longestSessionMinutes: displayMinutes(selected.map(\.durationSeconds).max() ?? 0)
        )
    }

    func dailyUsage(endingOn date: String, days: Int = 7) -> [MediaDailyUsage] {
        guard days > 0, let endDate = Date.trackerDateFormatter.date(from: date) else {
            return []
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: endDate) else {
                return nil
            }
            let dayKey = Date.trackerDateFormatter.string(from: day)
            let summary = usageSummary(on: dayKey)
            return MediaDailyUsage(
                date: dayKey,
                youtubeMinutes: summary.youtubeMinutes,
                xMinutes: summary.xMinutes,
                totalMinutes: summary.totalMinutes
            )
        }
    }

    func recentSessions(through date: String, limit: Int = 5) -> [CloudMediaSession] {
        guard limit > 0 else { return [] }
        return (snapshot.sessions ?? [])
            .filter { $0.date <= date }
            .sorted { ($0.endedAt, $0.startedAt) > ($1.endedAt, $1.startedAt) }
            .prefix(limit)
            .map { $0 }
    }

    private func usageSessions(for events: [MediaEvent]) -> [MediaUsageSession] {
        let maximumIdleGap: TimeInterval = 5 * 60
        var sessions: [MediaUsageSession] = []

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            let attentionSeconds = max(event.attentionSeconds, estimatedAttentionSeconds(for: event))
            guard attentionSeconds > 0 else { continue }
            let eventEnd = event.timestamp.addingTimeInterval(TimeInterval(attentionSeconds))

            if var current = sessions.last,
               event.timestamp.timeIntervalSince(current.end) <= maximumIdleGap {
                current.end = max(current.end, eventEnd)
                current.attentionSeconds += attentionSeconds
                sessions[sessions.count - 1] = current
            } else {
                sessions.append(MediaUsageSession(
                    start: event.timestamp,
                    end: eventEnd,
                    attentionSeconds: attentionSeconds
                ))
            }
        }
        return sessions
    }

    private func estimatedAttentionSeconds(for event: MediaEvent) -> Int {
        switch event.source {
        case .youtube:
            return 0
        case .x:
            return 10
        }
    }

    private func uniqueUsageSeconds(_ sessions: [CloudMediaSession]) -> Int {
        uniqueUsageSeconds(sessions.map { ($0.startedAt, $0.endedAt) })
    }

    private func uniqueUsageSeconds(events: [MediaEvent]) -> Int {
        let intervals = Dictionary(grouping: events, by: \.source)
            .values
            .flatMap { usageSessions(for: $0) }
            .map { ($0.start, $0.end) }
        return uniqueUsageSeconds(intervals)
    }

    private func uniqueUsageSeconds(_ intervals: [(start: Date, end: Date)]) -> Int {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }

        var merged: [(start: Date, end: Date)] = []
        for interval in sorted {
            guard let previous = merged.last, interval.start <= previous.end else {
                merged.append(interval)
                continue
            }
            merged[merged.count - 1].end = max(previous.end, interval.end)
        }

        return merged.reduce(0) { total, interval in
            total + max(0, Int(interval.end.timeIntervalSince(interval.start)))
        }
    }

    private func displayMinutes(_ seconds: Int) -> Int {
        guard seconds > 0 else { return 0 }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }
}

private struct MediaUsageSession {
    let start: Date
    var end: Date
    var attentionSeconds: Int
}
