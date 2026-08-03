import Foundation

struct MediaStatus: Codable, Equatable {
    let ok: Bool
    let youtube: MediaSourceStatus
    let x: MediaSourceStatus
}

struct MediaSourceStatus: Codable, Equatable {
    let exists: Bool
    let path: String?
    let sizeBytes: Int?
    let modifiedAt: Double?
    let exportedAt: Date?
    let recordCount: Int?
    let recommendationRecordCount: Int?
    let exportedRecommendationRecordCount: Int?
    let watchPageMetaRecordCount: Int?
    let exportedWatchPageMetaRecordCount: Int?
    let interactionCount: Int?
    let firstEventAt: Date?
    let latestEventAt: Date?
}

struct MediaEventsResponse: Codable, Equatable {
    let events: [MediaEvent]
}

struct MediaSessionsResponse: Codable, Equatable {
    let sessions: [CloudMediaSession]
}

struct NudgeHistoryResponse: Codable, Equatable {
    let records: [NudgeHistoryEntry]
    let summary: NudgeHistorySummary
}

struct NudgeHistoryEntry: Codable, Identifiable, Equatable {
    let id: String
    let source: MediaSource
    let sentAt: Date
    let sessionStartedAt: Date
    let sessionMinutes: Int
    let dailyFreeTimeMinutes: Int
    let title: String
    let body: String
    let generator: String
    let angle: String
    let escalation: String
    let context: NudgeHistoryContext
    let outcome: String
    let closedAt: Date?
    let secondsToClose: Int?

    var date: String {
        Date.trackerDateFormatter.string(from: sentAt)
    }
}

struct NudgeHistoryContext: Codable, Equatable {
    let contentTitle: String?
    let contentAuthor: String?
    let actualWake: String?
    let minutesSinceWake: Int?
    let completedTaskCount: Int
    let suggestedTasks: [String]
}

struct NudgeHistorySummary: Codable, Equatable {
    let total: Int
    let evaluated: Int
    let strong: Int
    let moderate: Int
    let late: Int
    let ignored: Int
    let successRate: Double
    let aiCount: Int
    let angles: [NudgeAngleSummary]
}

struct NudgeAngleSummary: Codable, Identifiable, Equatable {
    let angle: String
    let successes: Int
    let failures: Int
    let successRate: Double

    var id: String { angle }
}

struct CloudMediaSession: Codable, Identifiable, Equatable {
    let id: String
    let source: MediaSource
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let active: Bool

    var date: String {
        Date.trackerDateFormatter.string(from: startedAt)
    }
}

struct MediaEvent: Codable, Identifiable, Equatable {
    let source: MediaSource
    let type: String
    let timestamp: Date
    let title: String
    let author: String
    let url: String
    let attentionSeconds: Int
    let metadata: MediaEventMetadata

    var id: String {
        "\(source.rawValue):\(metadata.sourceID):\(timestamp.timeIntervalSince1970)"
    }

    var date: String {
        Date.trackerDateFormatter.string(from: timestamp)
    }
}

enum MediaSource: String, Codable, Equatable {
    case youtube
    case x
}

struct MediaEventMetadata: Codable, Equatable {
    let videoId: String?
    let tweetId: String?
    let authorName: String?
    let tab: String?
    let mediaType: String?
    let completed: Bool?
    let maxPositionSeconds: Int?
    let metrics: [String: String]?

    var sourceID: String {
        videoId ?? tweetId ?? "unknown"
    }
}

struct MediaSnapshot: Codable, Equatable {
    var status: MediaStatus?
    var events: [MediaEvent]
    var sessions: [CloudMediaSession]?
    var fetchedAt: Date

    static var empty: MediaSnapshot {
        MediaSnapshot(status: nil, events: [], sessions: [], fetchedAt: .distantPast)
    }
}

struct MediaUsageSummary: Equatable {
    let youtubeMinutes: Int
    let xMinutes: Int
    let totalMinutes: Int
    let youtubeSessions: Int
    let xSessions: Int
    let longestSessionMinutes: Int

    var sessionCount: Int {
        youtubeSessions + xSessions
    }
}

struct MediaDailyUsage: Identifiable, Equatable {
    let date: String
    let youtubeMinutes: Int
    let xMinutes: Int
    let totalMinutes: Int

    var id: String { date }
}
