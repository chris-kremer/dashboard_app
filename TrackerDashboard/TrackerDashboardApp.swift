import SwiftUI

@main
struct TrackerDashboardApp: App {
    @State private var syncController = SyncController.shared

    init() {
        SyncController.shared.registerBackgroundRefresh()
        SyncController.shared.scheduleBackgroundRefresh()
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
