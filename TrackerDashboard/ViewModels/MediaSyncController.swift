import Foundation
import Observation

@MainActor
@Observable
final class MediaSyncController {
    static let shared = MediaSyncController()

    var snapshot: MediaSnapshot
    var lastError: String?
    var isRefreshing = false

    private let cache: SharedCache
    private let apiClient: MediaAPIClient

    init(cache: SharedCache = .shared, apiClient: MediaAPIClient = .shared) {
        self.cache = cache
        self.apiClient = apiClient
        self.snapshot = cache.loadMediaSnapshot()
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        async let statusResult = result { [self] in try await apiClient.fetchStatus() }
        async let eventsResult = result { [self] in try await apiClient.fetchEvents() }

        let status = await statusResult
        let events = await eventsResult

        var nextSnapshot = snapshot
        var errors: [String] = []

        switch status {
        case .success(let status):
            nextSnapshot.status = status
        case .failure(let error):
            errors.append("status: \(friendlyMessage(for: error))")
        }

        switch events {
        case .success(let response):
            nextSnapshot.events = response.events
        case .failure(let error):
            errors.append("events: \(friendlyMessage(for: error))")
        }

        if errors.count < 2 {
            nextSnapshot.fetchedAt = Date()
            snapshot = nextSnapshot
            try? cache.saveMediaSnapshot(nextSnapshot)
            lastError = errors.isEmpty ? nil : "Tracked free time partly unavailable; showing cached data where needed (\(errors.joined(separator: ", ")))."
        } else if snapshot.fetchedAt == .distantPast {
            lastError = "Tracked free time unavailable right now (\(errors.joined(separator: ", ")))."
        } else {
            lastError = "Tracked free time unavailable right now; showing cached data from \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))."
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
        let totalSeconds = events(on: date).reduce(0) { total, event in
            total + max(event.attentionSeconds, estimatedAttentionSeconds(for: event))
        }
        return Int((Double(totalSeconds) / 60).rounded())
    }

    func trackedFreeTimeEntries(on date: String) -> [FreeTimeEntry] {
        let grouped = Dictionary(grouping: events(on: date), by: \.source)
        return grouped.compactMap { source, events in
            let totalSeconds = events.reduce(0) { total, event in
                total + max(event.attentionSeconds, estimatedAttentionSeconds(for: event))
            }
            guard totalSeconds > 0 else { return nil }
            return FreeTimeEntry(
                id: "media-\(source.rawValue)-\(date)",
                date: date,
                label: source == .youtube ? "YouTube" : "X feed",
                durationMinutes: Int((Double(totalSeconds) / 60).rounded()),
                time: nil,
                start: events.map(\.timestamp).min().map(Date.trackerTimeFormatter.string(from:)),
                end: events.map(\.timestamp).max().map(Date.trackerTimeFormatter.string(from:))
            )
        }
        .sorted { $0.label < $1.label }
    }

    private func estimatedAttentionSeconds(for event: MediaEvent) -> Int {
        switch event.source {
        case .youtube:
            return 0
        case .x:
            return 10
        }
    }
}
