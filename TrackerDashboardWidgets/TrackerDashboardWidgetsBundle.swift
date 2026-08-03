import WidgetKit
import SwiftUI

@main
struct TrackerDashboardWidgetsBundle: WidgetBundle {
    var body: some Widget {
#if os(watchOS)
        LockScreenStatusWidget()
#else
        TopTaskWidget()
        TaskListWidget()
        LockScreenStatusWidget()
#if os(iOS)
        TaskLiveActivityWidget()
#endif
#endif
    }
}
