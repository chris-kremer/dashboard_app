import SwiftUI

struct InsightsView: View {
    @Environment(SyncController.self) private var sync

    private var plannedMinutes: Int {
        workloadItems.compactMap(\.estimateMinutes).reduce(0, +)
    }

    private var actualMinutes: Int {
        workloadItems.compactMap(\.actualMinutes).reduce(0, +)
    }

    private var completedTasks: Int {
        completedTaskItems.count
    }

    private var completedTaskItems: [ScheduleItem] {
        sync.snapshot.schedule
            .filter(isCompletedForInsights)
            .sorted { ($0.start ?? "", $0.task) < ($1.start ?? "", $1.task) }
    }

    private var urgentCompletedItems: [ScheduleItem] {
        sync.snapshot.schedule
            .filter { isCompletedForInsights($0) && ($0.adjustedPriority ?? 0) >= 10 }
            .sorted { ($0.adjustedPriority ?? -1, $0.task) > ($1.adjustedPriority ?? -1, $1.task) }
    }

    private var urgentOpenItems: [ScheduleItem] {
        sync.snapshot.todayOpenTasks
            .filter { ($0.adjustedPriority ?? 0) >= 10 }
            .filter { item in !urgentCompletedItems.contains { $0.id == item.id } }
            .sorted { ($0.adjustedPriority ?? -1, $0.task) > ($1.adjustedPriority ?? -1, $1.task) }
    }

    private var urgentKnownCount: Int {
        urgentCompletedItems.count + urgentOpenItems.count
    }

    private var urgentCompletionShare: Double {
        guard urgentKnownCount > 0 else { return 0 }
        return Double(urgentCompletedItems.count) / Double(urgentKnownCount)
    }

    private var urgentCompletionPercent: Int {
        Int((urgentCompletionShare * 100).rounded())
    }

    private var actualShare: Double {
        guard plannedMinutes > 0 else { return 0 }
        return min(Double(actualMinutes) / Double(plannedMinutes), 1)
    }

    private var workloadItems: [ScheduleItem] {
        sync.snapshot.schedule
            .filter { ($0.adjustedPriority ?? 0) > 2 }
            .filter { $0.status != .cancelled }
            .filter { $0.estimateMinutes != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Insights")
                        .font(.largeTitle.weight(.bold))

                    workloadCard

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        NavigationLink {
                            CompletedTasksDetailView(tasks: completedTaskItems)
                        } label: {
                            insightCard(
                                title: "Completed",
                                value: "\(completedTasks)",
                                detail: "items finished",
                                systemImage: "checkmark.circle.fill",
                                tint: .green,
                                showsDisclosure: true
                            )
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            UrgentTasksDetailView(completed: urgentCompletedItems, open: urgentOpenItems)
                        } label: {
                            insightCard(
                                title: "Urgent Done",
                                value: "\(urgentCompletionPercent)%",
                                detail: "\(urgentCompletedItems.count)/\(urgentKnownCount) AP 10+ finished",
                                systemImage: "flame.fill",
                                tint: urgentCompletionTint,
                                showsDisclosure: true
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    sectionTitle("Logged Today")
                    HStack(spacing: 10) {
                        NavigationLink {
                            CaffeineDetailView(entries: sync.snapshot.caffeine)
                        } label: {
                            compactMetric("Coffee", "\(sync.snapshot.caffeine.count)", "cup.and.saucer.fill", .brown, showsDisclosure: true)
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            FoodDetailView(entries: sync.snapshot.food)
                        } label: {
                            compactMetric("Food", "\(sync.snapshot.food.count)", "fork.knife", .teal, showsDisclosure: true)
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            SleepDetailView(sleep: sync.snapshot.sleep)
                        } label: {
                            compactMetric("Sleep", sleepValue, "bed.double.fill", .indigo, showsDisclosure: true)
                        }
                        .buttonStyle(.plain)
                    }

                    if let sleep = sync.snapshot.sleep {
                        sleepCard(sleep)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .background(Color.trackerGroupedBackground)
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

    private func insightCard(title: String, value: String, detail: String, systemImage: String, tint: Color, showsDisclosure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                Spacer()
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
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

    private func compactMetric(_ title: String, _ value: String, _ systemImage: String, _ tint: Color, showsDisclosure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
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
        if plannedMinutes == 0 { return "No priority workload yet" }
        if actualMinutes == 0 { return "Priority work is waiting" }
        if actualMinutes >= plannedMinutes { return "Priority workload is covered" }
        return "\(minutesLabel(plannedMinutes - actualMinutes)) left on AP 3+ work"
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
        guard urgentKnownCount > 0 else { return .secondary }
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

    private func isCompletedForInsights(_ item: ScheduleItem) -> Bool {
        guard !item.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard item.status != .cancelled else {
            return false
        }
        return item.status == .done
            || item.status == .logged
            || item.stop != nil
            || item.actualMinutes != nil
    }
}

private struct CompletedTasksDetailView: View {
    let tasks: [ScheduleItem]

    var body: some View {
        List {
            if tasks.isEmpty {
                ContentUnavailableView("No completed tasks", systemImage: "checkmark.circle")
            } else {
                ForEach(tasks) { task in
                    InsightTaskRow(task: task, tint: .green)
                }
            }
        }
        .navigationTitle("Completed")
        .trackerInlineNavigationTitle()
    }
}

private struct UrgentTasksDetailView: View {
    let completed: [ScheduleItem]
    let open: [ScheduleItem]

    var body: some View {
        List {
            if completed.isEmpty && open.isEmpty {
                ContentUnavailableView("No urgent tasks", systemImage: "flame")
            } else {
                if !completed.isEmpty {
                    Section("Done") {
                        ForEach(completed) { task in
                            InsightTaskRow(task: task, tint: .green)
                        }
                    }
                }
                if !open.isEmpty {
                    Section("Open") {
                        ForEach(open) { task in
                            InsightTaskRow(task: task, tint: .orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("Urgent Done")
        .trackerInlineNavigationTitle()
    }
}

private struct InsightTaskRow: View {
    let task: ScheduleItem
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.task)
                    .font(.headline)
                Spacer()
                if let adjustedPriority = task.adjustedPriority {
                    Text("AP \(adjustedPriority)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint, in: Capsule())
                }
            }
            if !task.category.isEmpty {
                Text(task.category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let estimate = task.estimateMinutes {
                    Label("\(estimate)m", systemImage: "timer")
                }
                if let priority = task.priority {
                    Label("P\(priority)", systemImage: "flag")
                }
                if let start = task.start {
                    Label(start, systemImage: "play.fill")
                }
                if let stop = task.stop {
                    Label(stop, systemImage: "stop.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CaffeineDetailView: View {
    let entries: [CaffeineEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("No coffee logged", systemImage: "cup.and.saucer")
            } else {
                ForEach(entries.sorted { $0.time < $1.time }) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundStyle(.brown)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.label)
                                .font(.headline)
                            Text(entry.time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Coffee")
        .trackerInlineNavigationTitle()
    }
}

private struct FoodDetailView: View {
    let entries: [FoodEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("No food logged", systemImage: "fork.knife")
            } else {
                ForEach(entries.sorted { $0.time < $1.time }) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.item)
                                .font(.headline)
                            Spacer()
                            Text(entry.time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.mealContext)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            if let amount = entry.amount, !amount.isEmpty {
                                Label(amount, systemImage: "scalemass")
                            }
                            if let location = entry.location, !location.isEmpty {
                                Label(location, systemImage: "mappin")
                            }
                            if let confidence = entry.confidence, !confidence.isEmpty {
                                Label(confidence, systemImage: "checkmark.seal")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let notes = entry.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Food")
        .trackerInlineNavigationTitle()
    }
}

private struct SleepDetailView: View {
    let sleep: SleepEntry?

    var body: some View {
        List {
            if let sleep {
                Section("Sleep") {
                    sleepRow("Duration", sleep.sleepHours.map { String(format: "%.1fh", $0) } ?? "-", "bed.double.fill")
                    sleepRow("Sleep start", sleep.sleepStart ?? "-", "moon.fill")
                    sleepRow("Alarm", sleep.alarmTime ?? "-", "alarm.fill")
                    sleepRow("Planned wake", sleep.plannedWake ?? "-", "calendar")
                    sleepRow("Actual wake", sleep.actualWake ?? "-", "sun.max.fill")
                    sleepRow("Overslept", sleep.oversleptHours.map { String(format: "%.1fh", $0) } ?? "-", "exclamationmark.triangle.fill")
                }
            } else {
                ContentUnavailableView("No sleep logged", systemImage: "bed.double")
            }
        }
        .navigationTitle("Sleep")
        .trackerInlineNavigationTitle()
    }

    private func sleepRow(_ title: String, _ value: String, _ systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
