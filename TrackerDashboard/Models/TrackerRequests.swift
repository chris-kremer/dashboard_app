import Foundation

struct CreateTaskRequest: Codable, Equatable {
    var date: String
    var task: String
    var category: String
    var comment: String?
    var priority: Int?
    var estimateMinutes: Int?
}

struct TaskPatchRequest: Codable, Equatable {
    var priority: Int?
    var estimateMinutes: Int?
    var comment: String?
    var start: String?
    var stop: String?
    var status: TaskStatus?
}

struct CompleteTaskRequest: Codable, Equatable {
    var source: String
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
