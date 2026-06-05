import SwiftUI

struct MacRootView: View {
    @State private var selection: MacSection? = .today

    var body: some View {
        NavigationSplitView {
            List(MacSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Tracker")
        } detail: {
            switch selection ?? .today {
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
    }
}

private enum MacSection: String, CaseIterable, Identifiable {
    case today
    case tasks
    case timeline
    case insights
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .tasks: "Tasks"
        case .timeline: "Timeline"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .tasks: "checklist"
        case .timeline: "calendar.day.timeline.left"
        case .insights: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}
