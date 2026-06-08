import SwiftUI

@main
struct TrackerDashboardApp: App {
    @State private var syncController = SyncController.shared

    init() {
        SleepReminderScheduler.requestAuthorization()
        SleepReminderScheduler.update(for: SyncController.shared.snapshot)
#if os(iOS)
        SyncController.shared.registerBackgroundRefresh()
        SyncController.shared.scheduleBackgroundRefresh()
#endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(syncController)
                .task {
                    await syncController.refresh()
                }
        }
    }
}
