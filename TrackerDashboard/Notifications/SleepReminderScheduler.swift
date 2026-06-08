import Foundation
import UserNotifications

enum SleepReminderScheduler {
    private static let identifier = "sleep-log-reminder-10"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func update(for snapshot: TrackerSnapshot) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard snapshot.sleep == nil,
              snapshot.date == Date.trackerDateFormatter.string(from: Date()),
              nextTenOClock() != nil
        else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Log sleep"
        content.body = "No sleep has been logged for today yet."
        content.sound = .default

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 10
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    private static func nextTenOClock() -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 10
        components.minute = 0
        guard let ten = Calendar.current.date(from: components), ten > Date() else {
            return nil
        }
        return ten
    }
}
