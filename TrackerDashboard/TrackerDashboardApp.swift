import SwiftUI

@main
struct TrackerDashboardApp: App {
    @State private var syncController = SyncController.shared
    @State private var mediaSyncController = MediaSyncController.shared

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
                .environment(mediaSyncController)
                .task {
#if os(iOS)
                    await syncController.refreshHealthSleep()
#endif
                    await syncController.refresh()
                    await mediaSyncController.refresh()
                }
        }
    }
}
