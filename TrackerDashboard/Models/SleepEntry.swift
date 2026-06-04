import Foundation

struct SleepEntry: Codable, Equatable {
    let date: String
    let sleepHours: Double?
    let alarmTime: String?
    let oversleptHours: Double?
    let sleepStart: String?
    let plannedWake: String?
    let actualWake: String?
}
