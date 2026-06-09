import SwiftUI

@main
struct TrackerDashboardMacApp: App {
    @State private var syncController = SyncController.shared
    @State private var mediaSyncController = MediaSyncController.shared

    init() {
        SleepReminderScheduler.requestAuthorization()
        SleepReminderScheduler.update(for: SyncController.shared.snapshot)
    }

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environment(syncController)
                .environment(mediaSyncController)
                .frame(minWidth: 1040, minHeight: 720)
                .task {
                    await syncController.refresh()
                    await mediaSyncController.refresh()
                }
        }
        .windowResizability(.contentMinSize)
    }
}
