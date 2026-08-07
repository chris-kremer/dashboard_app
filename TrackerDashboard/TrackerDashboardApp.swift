import SwiftUI
#if os(iOS)
import ActivityKit
import UIKit
import UserNotifications
#endif

@main
struct TrackerDashboardApp: App {
#if os(iOS)
    @UIApplicationDelegateAdaptor(TrackerDashboardAppDelegate.self) private var appDelegate
#endif
    @State private var syncController = SyncController.shared
    @State private var mediaSyncController = MediaSyncController.shared

    init() {
        SleepReminderScheduler.requestAuthorization()
        SleepReminderScheduler.update(for: SyncController.shared.snapshot)
#if os(iOS)
        SyncController.shared.registerBackgroundRefresh()
        SyncController.shared.scheduleBackgroundRefresh()
        NudgeNotifications.configure()
#endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(syncController)
                .environment(mediaSyncController)
                .task {
#if os(iOS)
                    await syncController.refreshHealthSleep()
                    NudgeNotifications.registerForRemoteNotifications()
                    await NudgeNotifications.syncRegistrationAndSettings()
#endif
                    await syncController.refresh()
                    await mediaSyncController.refresh()
                }
        }
    }
}

#if os(iOS)
final class TrackerDashboardAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NudgeNotifications.configure()
        NudgeNotifications.observeLiveActivityPushToStartToken()
        Task {
            do {
                try await HealthKitSleepStore.shared.requestAuthorization()
                try await HealthKitSleepStore.shared.startObservingSleepChanges {
                    await SyncController.shared.refreshHealthSleep()
                }
            } catch {
                // Foreground and scheduled refreshes remain available as a fallback.
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: NudgeNotifications.deviceTokenKey)
        Task {
            await NudgeNotifications.syncRegistrationAndSettings()
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        UserDefaults.standard.set(error.localizedDescription, forKey: NudgeNotifications.registrationErrorKey)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NudgeNotifications.presentRewardIfNeeded(notification.request.content.userInfo)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if NudgeNotifications.isReward(response.notification.request.content.userInfo) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NudgeNotifications.presentRewardIfNeeded(response.notification.request.content.userInfo)
            }
        } else if NudgeNotifications.isCoverageSummary(response.notification.request.content.userInfo) {
            NudgeNotifications.requestCoverageReview()
        }
        completionHandler()
    }
}

enum NudgeNotifications {
    static let deviceTokenKey = "nudgeDeviceToken"
    static let registrationErrorKey = "nudgeRegistrationError"
    static let pendingCoverageReviewKey = "pendingCoverageReview"

    static func configure() {
        UNUserNotificationCenter.current().setNotificationCategories([])
    }

    static func isReward(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["kind"] as? String == "reward"
    }

    static func isCoverageSummary(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["kind"] as? String == "coverage_summary"
    }

    static func requestCoverageReview() {
        UserDefaults.standard.set(true, forKey: pendingCoverageReviewKey)
        NotificationCenter.default.post(name: .showCoverageGaps, object: nil)
    }

    static func consumeCoverageReviewRequest() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingCoverageReviewKey) else { return false }
        UserDefaults.standard.removeObject(forKey: pendingCoverageReviewKey)
        return true
    }

    static func presentRewardIfNeeded(_ userInfo: [AnyHashable: Any]) {
        guard isReward(userInfo) else { return }
        NotificationCenter.default.post(
            name: .positiveReinforcement,
            object: nil,
            userInfo: ["source": userInfo["source"] as? String ?? ""]
        )
    }

    @MainActor
    static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func observeLiveActivityPushToStartToken() {
        guard #available(iOS 17.2, *) else { return }
        Task {
            for await tokenData in Activity<TaskLiveActivityAttributes>.pushToStartTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                do {
                    try await TrackerAPIClient.shared.registerLiveActivityDevice(
                        LiveActivityDeviceRequest(token: token, environment: apnsEnvironment)
                    )
                } catch {
                    UserDefaults.standard.set(error.localizedDescription, forKey: registrationErrorKey)
                }
            }
        }
    }

    static func syncRegistrationAndSettings() async {
        let settings = AppSettings.shared
        do {
            if let token = UserDefaults.standard.string(forKey: deviceTokenKey), !token.isEmpty {
                try await TrackerAPIClient.shared.registerNudgeDevice(NudgeDeviceRequest(
                    token: token,
                    environment: apnsEnvironment
                ))
            }
            try await TrackerAPIClient.shared.updateNudgeSettings(NudgeSettingsRequest(
                enabled: settings.nudgesEnabled,
                initialDelayMinutes: settings.nudgeInitialDelayMinutes,
                repeatIntervalMinutes: settings.nudgeRepeatIntervalMinutes
            ))
            UserDefaults.standard.removeObject(forKey: registrationErrorKey)
        } catch {
            UserDefaults.standard.set(error.localizedDescription, forKey: registrationErrorKey)
        }
    }

    private static var apnsEnvironment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }
}

extension Notification.Name {
    static let positiveReinforcement = Notification.Name("positiveReinforcement")
    static let showCoverageGaps = Notification.Name("showCoverageGaps")
}
#endif
