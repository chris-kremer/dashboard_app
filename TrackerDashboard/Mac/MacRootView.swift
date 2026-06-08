import SwiftUI

struct MacRootView: View {
    @State private var navigation = AppNavigation()

    var body: some View {
        NavigationSplitView {
            List(TrackerSection.allCases, selection: $navigation.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Tracker")
        } detail: {
            switch navigation.selectedSection {
            case .today:
                TodayView()
            case .tasks:
                TasksView()
            case .timeline:
                TimelineView()
            case .insights:
                InsightsView()
            case .settings:
                SettingsView()
            }
        }
        .environment(navigation)
    }
}
