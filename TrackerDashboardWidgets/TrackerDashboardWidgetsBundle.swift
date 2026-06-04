import WidgetKit
import SwiftUI

@main
struct TrackerDashboardWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TopTaskWidget()
        TaskListWidget()
        LockScreenStatusWidget()
    }
}
