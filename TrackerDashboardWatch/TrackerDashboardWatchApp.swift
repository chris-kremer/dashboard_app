import SwiftUI

@main
struct TrackerDashboardWatchApp: App {
    @State private var store = WatchTrackerStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
        }
    }
}
