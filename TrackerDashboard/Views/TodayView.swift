import SwiftUI

enum TrackerSection: String, CaseIterable, Identifiable {
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

@Observable
final class AppNavigation {
    var selectedSection: TrackerSection = .today
    var selectedTask: ScheduleItem?
    var showingCoverageGaps = false
}

struct TodayView: View {
    @Environment(SyncController.self) private var sync
    @Environment(MediaSyncController.self) private var mediaSync
    @Environment(AppNavigation.self) private var navigation
    @State private var showingAddTask = false
    @State private var showingCaffeine = false
    @State private var showingFood = false
    @State private var showingSleep = false
    @State private var busyTasks = Set<String>()

    private var currentTasks: [ScheduleItem] {
        sync.snapshot.todayOpenTasks.filter {
            guard let start = $0.dateTime(from: $0.start), start <= Date() else { return false }
            return $0.stop == nil || $0.status == .inProgress
        }
            .sorted { ($0.stop == nil ? 0 : 1, $0.start ?? "") < ($1.stop == nil ? 0 : 1, $1.start ?? "") }
    }
    private var upcoming: [ScheduleItem] {
        let currentIDs = Set(currentTasks.map(\.id))
        return Array(sync.snapshot.todayOpenTasks.filter { !currentIDs.contains($0.id) }.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                        if currentTasks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Ready when you are").font(.title2.weight(.semibold))
                                Text("Start a task below, or add something to your day.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(22)
                            .background(TrackerStyle.soft, in: RoundedRectangle(cornerRadius: 26))
                        } else {
                            VStack(spacing: 12) {
                                ForEach(currentTasks) { task in currentTask(task, now: context.date) }
                            }
                        }
                    }
                    daySummary
                    if !upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Up next").font(.headline)
                                Spacer()
                                Button("All tasks") { navigation.selectedSection = .tasks }.font(.caption)
                            }
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, task in
                                TaskRowView(task: task, rank: index + 1, compact: true)
                                if index < upcoming.count - 1 { Divider() }
                            }
                        }
                    }
                    if let error = sync.syncState.lastError {
                        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                    }
                }.padding(20)
            }
            .background(TrackerStyle.background)
            .navigationTitle("").trackerInlineNavigationTitle()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Menu {
                    Button("Task / activity", systemImage: "plus") { showingAddTask = true }
                    Button("Coffee", systemImage: "cup.and.saucer") { showingCaffeine = true }
                    Button("Meal", systemImage: "fork.knife") { showingFood = true }
                    Button("Sleep", systemImage: "bed.double") { showingSleep = true }
                } label: {
                    Label("Add", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20).frame(minHeight: 44)
                        .background(TrackerStyle.surface, in: Capsule())
                }
                .padding(.vertical, 8).frame(maxWidth: .infinity).background(TrackerStyle.background)
            }
            .refreshable { await sync.refresh(); await mediaSync.refresh(date: sync.snapshot.date) }
            .sheet(isPresented: $showingAddTask) { AddTaskView() }
            .sheet(isPresented: $showingCaffeine) { LogCaffeineView() }
            .sheet(isPresented: $showingFood) { LogFoodView() }
            .sheet(isPresented: $showingSleep) { NavigationStack { SleepEditView() } }
        }
    }

    private func currentTask(_ task: ScheduleItem, now: Date) -> some View {
        let isPaused = task.stop != nil
        let elapsed = max(0, Int((task.dateTime(from: task.stop) ?? now).timeIntervalSince(task.dateTime(from: task.start) ?? now)))
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(isPaused ? "PAUSED" : "IN PROGRESS", systemImage: isPaused ? "pause.fill" : "circle.fill")
                            .font(.caption2.weight(.semibold))
                        Text(task.category).font(.caption)
                    }
                    .foregroundStyle(TrackerStyle.accent)
                    Spacer()
                    Button {
                        navigation.selectedTask = task
                        navigation.selectedSection = .tasks
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Edit \(task.task)")
                }
                Text(task.task).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                    .font(.system(.largeTitle, design: .rounded).weight(.regular)).monospacedDigit()
                Spacer()
                if let estimate = task.estimateMinutes {
                    Text("of \(TrackerTime.label(estimate)) estimated").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let estimate = task.estimateMinutes, estimate > 0 {
                ProgressView(value: min(Double(elapsed) / Double(estimate * 60), 1)).tint(TrackerStyle.accent)
            }
            HStack(spacing: 10) {
                Button {
                    perform(task) { if isPaused { await sync.startTask(task) } else { await sync.stopTask(task) } }
                } label: {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity, minHeight: 44).background(TrackerStyle.surface, in: Capsule())
                }
                Button { perform(task) { await sync.completeTask(task) } } label: {
                    Label("Finish task", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 44)
                        .background(TrackerStyle.accent, in: Capsule()).foregroundStyle(TrackerStyle.background)
                }
            }
            .font(.subheadline.weight(.semibold)).buttonStyle(.plain).disabled(busyTasks.contains(task.id))
        }
        .padding(22).background(TrackerStyle.soft, in: RoundedRectangle(cornerRadius: 26))
    }

    private func perform(_ task: ScheduleItem, action: @escaping () async -> Void) {
        guard !busyTasks.contains(task.id) else { return }
        busyTasks.insert(task.id)
        Task { await action(); busyTasks.remove(task.id) }
    }

    private var daySummary: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let analyzer = CoverageGapAnalyzer(date: sync.snapshot.date, schedule: sync.snapshot.schedule,
                freeTime: (sync.snapshot.freeTime ?? []) + mediaSync.trackedFreeTimeEntries(on: sync.snapshot.date),
                healthSleep: sync.healthSleep, manualSleep: sync.snapshot.sleep, now: context.date)
            let total = max(1, analyzer.coverageEndMinute)
            let productive = min(sync.snapshot.productiveMinutes(now: context.date), analyzer.loggedMinutes)
            let gaps = max(0, total - analyzer.loggedMinutes)
            let productiveSet = Set(sync.snapshot.productiveIntervals(now: context.date).flatMap { Array($0) })
            let freeSet = Set(TrackerTime.freeTimeIntervals((sync.snapshot.freeTime ?? []) + mediaSync.trackedFreeTimeEntries(on: sync.snapshot.date), limit: total).flatMap { Array($0) })
            let free = min(max(0, analyzer.loggedMinutes - productive), freeSet.subtracting(productiveSet).count)
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("Your day, so far").font(.headline)
                    Spacer()
                    Text("Since 00:00").font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    dayMetric(TrackerTime.label(productive), "Productive time")
                    Spacer()
                    dayMetric("\(sync.snapshot.finishedTaskCount)", "Tasks finished")
                    Spacer()
                    Button {
                        navigation.selectedSection = .insights
                        navigation.showingCoverageGaps = true
                    } label: { dayMetric("\(Int(Double(analyzer.loggedMinutes) / Double(total) * 100))%", "Logged ›") }
                    .buttonStyle(.plain)
                }
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        Rectangle().fill(TrackerStyle.accent).frame(width: max(0, geometry.size.width - 6) * Double(productive) / Double(total))
                        Rectangle().fill(TrackerStyle.life).frame(width: max(0, geometry.size.width - 6) * Double(max(0, analyzer.loggedMinutes - productive - free)) / Double(total))
                        Rectangle().fill(TrackerStyle.freeTime).frame(width: max(0, geometry.size.width - 6) * Double(free) / Double(total))
                        Rectangle().fill(Color.secondary.opacity(0.18))
                    }.clipShape(Capsule())
                }
                .frame(height: 8)
                .accessibilityLabel("\(TrackerTime.label(productive)) productive, \(TrackerTime.label(gaps)) unlogged")
                HStack {
                    legend("Productive", TrackerStyle.accent)
                    legend("Other & sleep", TrackerStyle.life)
                    legend("Free time", TrackerStyle.freeTime)
                    legend("Unlogged", .secondary.opacity(0.3))
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func dayMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 5, height: 5); Text(title) }
    }
}
