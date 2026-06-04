import SwiftUI

struct InsightsView: View {
    @Environment(SyncController.self) private var sync

    private var plannedMinutes: Int {
        sync.snapshot.schedule.compactMap(\.estimateMinutes).reduce(0, +)
    }

    private var actualMinutes: Int {
        sync.snapshot.schedule.compactMap(\.actualMinutes).reduce(0, +)
    }

    private var completedTasks: Int {
        sync.snapshot.schedule.filter { $0.status == .done }.count
    }

    private var highPriorityOpen: Int {
        sync.snapshot.openTasks.filter { ($0.adjustedPriority ?? 0) >= 5 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    metric("Caffeine", "\(sync.snapshot.caffeine.count)", "cup.and.saucer")
                    metric("Food", "\(sync.snapshot.food.count)", "fork.knife")
                    metric("Planned", "\(plannedMinutes)m", "calendar")
                    metric("Actual", "\(actualMinutes)m", "timer")
                    metric("Completed", "\(completedTasks)", "checkmark.circle")
                    metric("High Priority", "\(highPriorityOpen)", "flame")
                    if let sleep = sync.snapshot.sleep?.sleepHours {
                        metric("Sleep", String(format: "%.1fh", sleep), "bed.double")
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
        }
    }

    private func metric(_ title: String, _ value: String, _ systemImage: String) -> some View {
        DashboardCard {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.largeTitle.weight(.bold))
                .monospacedDigit()
        }
    }
}
