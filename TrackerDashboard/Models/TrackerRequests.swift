import Foundation

struct NudgeSettingsRequest: Codable {
    let enabled: Bool
    let initialDelayMinutes: Int
    let repeatIntervalMinutes: Int
}

struct NudgeDeviceRequest: Codable {
    let token: String
    let environment: String
}

struct NudgeCommandRequest: Codable {
    let command: String
    let minutes: Int?
}

struct NudgeAPIResponse: Codable {
    let ok: Bool
}

struct CreateTaskRequest: Codable, Equatable {
    var date: String
    var task: String
    var category: String
    var comment: String?
    var priority: Int?
    var estimateMinutes: Int?
    var start: String? = nil
    var stop: String? = nil
    var status: TaskStatus? = nil
    var source: String? = nil
    var sourceId: String? = nil
    var importedAt: String? = nil
}

struct TaskPatchRequest: Codable, Equatable {
    var priority: Int?
    var estimateMinutes: Int?
    var comment: String?
    var delay: String?
    var start: String?
    var stop: String?
    var status: TaskStatus?
    var clearsStop = false

    enum CodingKeys: String, CodingKey {
        case priority
        case estimateMinutes
        case comment
        case delay
        case start
        case stop
        case status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(estimateMinutes, forKey: .estimateMinutes)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(delay, forKey: .delay)
        try container.encodeIfPresent(start, forKey: .start)
        if clearsStop {
            try container.encodeNil(forKey: .stop)
        } else {
            try container.encodeIfPresent(stop, forKey: .stop)
        }
        try container.encodeIfPresent(status, forKey: .status)
    }
}

struct CompleteTaskRequest: Codable, Equatable {
    var source: String
    var stop: String?
}

struct CaffeineRequest: Codable, Equatable {
    var date: String
    var label: String
    var time: String
}

struct FoodRequest: Codable, Equatable {
    var date: String
    var time: String
    var mealContext: String
    var item: String
    var amount: String?
    var location: String?
    var notes: String?
    var confidence: String?
}

struct SleepRequest: Codable, Equatable {
    var date: String
    var sleepHours: Double?
    var alarmTime: String?
    var oversleptHours: Double?
    var sleepStart: String?
    var plannedWake: String?
    var actualWake: String?
}
