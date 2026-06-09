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
    var fetchedAt: Date

    static var empty: MediaSnapshot {
        MediaSnapshot(status: nil, events: [], fetchedAt: .distantPast)
    }
}
