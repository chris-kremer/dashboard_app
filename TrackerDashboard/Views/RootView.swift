import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }

            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }

            TimelineView()
                .tabItem { Label("Timeline", systemImage: "calendar.day.timeline.left") }

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
