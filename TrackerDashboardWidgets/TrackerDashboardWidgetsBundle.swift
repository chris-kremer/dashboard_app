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
        TimelineChartWidget()
        LockScreenStatusWidget()
#if os(iOS)
        TaskLiveActivityWidget()
#endif
#endif
    }
}
