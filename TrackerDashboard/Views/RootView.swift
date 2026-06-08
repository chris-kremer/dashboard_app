import SwiftUI

struct RootView: View {
    @State private var navigation = AppNavigation()

    var body: some View {
        TabView(selection: $navigation.selectedSection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(TrackerSection.today)

            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(TrackerSection.tasks)

            TimelineView()
                .tabItem { Label("Timeline", systemImage: "calendar.day.timeline.left") }
                .tag(TrackerSection.timeline)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
                .tag(TrackerSection.insights)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(TrackerSection.settings)
        }
        .environment(navigation)
    }
}
