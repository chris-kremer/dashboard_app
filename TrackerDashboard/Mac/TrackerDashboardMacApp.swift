import SwiftUI

@main
struct TrackerDashboardMacApp: App {
    @State private var syncController = SyncController.shared

    init() {
        SleepReminderScheduler.requestAuthorization()
        SleepReminderScheduler.update(for: SyncController.shared.snapshot)
    }

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environment(syncController)
                .frame(minWidth: 1040, minHeight: 720)
                .task {
                    await syncController.refresh()
                }
        }
        .windowResizability(.contentMinSize)
    }
}
