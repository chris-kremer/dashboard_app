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

    private var urgentTasks: [ScheduleItem] {
        sync.snapshot.schedule.filter { ($0.adjustedPriority ?? 0) >= 10 }
    }

    private var urgentCompleted: Int {
        urgentTasks.filter { $0.status == .done }.count
    }

    private var urgentCompletionShare: Double {
        guard !urgentTasks.isEmpty else { return 0 }
        return Double(urgentCompleted) / Double(urgentTasks.count)
    }

    private var urgentCompletionPercent: Int {
        Int((urgentCompletionShare * 100).rounded())
    }

    private var actualShare: Double {
        guard plannedMinutes > 0 else { return 0 }
        return min(Double(actualMinutes) / Double(plannedMinutes), 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Insights")
                        .font(.largeTitle.weight(.bold))

                    workloadCard

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        insightCard(
                            title: "Completed",
                            value: "\(completedTasks)",
                            detail: "tasks closed",
                            systemImage: "checkmark.circle.fill",
                            tint: .green
                        )
                        insightCard(
                            title: "Urgent Done",
                            value: "\(urgentCompletionPercent)%",
                            detail: "\(urgentCompleted)/\(urgentTasks.count) top-priority",
                            systemImage: "flame.fill",
                            tint: urgentCompletionTint
                        )
                    }

                    sectionTitle("Logged Today")
                    HStack(spacing: 10) {
                        compactMetric("Coffee", "\(sync.snapshot.caffeine.count)", "cup.and.saucer.fill", .brown)
                        compactMetric("Food", "\(sync.snapshot.food.count)", "fork.knife", .teal)
                        compactMetric("Sleep", sleepValue, "bed.double.fill", .indigo)
                    }

                    if let sleep = sync.snapshot.sleep {
                        sleepCard(sleep)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var workloadCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label("Workload", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(actualMinutes)m / \(plannedMinutes)m")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(workloadHeadline)
                .font(.title2.weight(.bold))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(workloadColor)
                        .frame(width: proxy.size.width * actualShare)
                }
            }
            .frame(height: 12)

            HStack {
                metricPair(title: "Planned", value: minutesLabel(plannedMinutes), tint: .blue)
                Divider()
                metricPair(title: "Actual", value: minutesLabel(actualMinutes), tint: workloadColor)
            }
            .frame(height: 48)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func insightCard(title: String, value: String, detail: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.largeTitle.monospacedDigit().weight(.bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func compactMetric(_ title: String, _ value: String, _ systemImage: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sleepCard(_ sleep: SleepEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Sleep")
            HStack(spacing: 12) {
                metricPair(title: "Duration", value: sleepValue, tint: .indigo)
                Divider()
                metricPair(title: "Wake", value: sleep.actualWake ?? sleep.plannedWake ?? "--:--", tint: .indigo)
                Divider()
                metricPair(title: "Overslept", value: sleep.oversleptHours.map { String(format: "%.1fh", $0) } ?? "-", tint: .orange)
            }
            .frame(height: 48)
            .padding(14)
            .background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func metricPair(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
    }

    private var sleepValue: String {
        sync.snapshot.sleep?.sleepHours.map { String(format: "%.1fh", $0) } ?? "-"
    }

    private var workloadHeadline: String {
        if plannedMinutes == 0 { return "No planned workload yet" }
        if actualMinutes == 0 { return "Planned day is waiting" }
        if actualMinutes >= plannedMinutes { return "Planned work is covered" }
        return "\(minutesLabel(plannedMinutes - actualMinutes)) left against plan"
    }

    private var workloadColor: Color {
        guard plannedMinutes > 0 else { return .secondary }
        let ratio = Double(actualMinutes) / Double(plannedMinutes)
        if ratio >= 1 { return .green }
        if ratio >= 0.6 { return .blue }
        if ratio >= 0.3 { return .orange }
        return .red
    }

    private var urgentCompletionTint: Color {
        guard !urgentTasks.isEmpty else { return .secondary }
        if urgentCompletionShare >= 0.8 { return .green }
        if urgentCompletionShare >= 0.4 { return .orange }
        return .red
    }

    private func minutesLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
