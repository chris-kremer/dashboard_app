import SwiftUI

enum InsightsSection {
    case overview, freeTime, nudges, logs
    var title: String {
        switch self {
        case .overview: "Insights"
        case .freeTime: "Free time"
        case .nudges: "Nudge effectiveness"
        case .logs: "Daily logs"
        }
    }
}

struct InsightsView: View {
    @Environment(SyncController.self) private var sync
    @Environment(MediaSyncController.self) private var mediaSync
    @Environment(AppNavigation.self) private var navigation

    private var adjustedWorkloadMinutes: Int {
        workloadItems.reduce(0) { total, item in
            if isCompletedForInsights(item) {
                return total + completedWorkMinutes(for: item)
            }
            return total + (item.estimateMinutes ?? 0)
        }
    }

    private var actualMinutes: Int {
        workloadItems
            .filter(isCompletedForInsights)
            .reduce(0) { $0 + completedWorkMinutes(for: $1) }
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
        guard adjustedWorkloadMinutes > 0 else { return 0 }
        return min(Double(actualMinutes) / Double(adjustedWorkloadMinutes), 1)
    }

    private var coverageAnalyzer: CoverageGapAnalyzer {
        CoverageGapAnalyzer(
            date: sync.snapshot.date,
            schedule: sync.snapshot.schedule,
            freeTime: trackedFreeTimeEntries,
            healthSleep: sync.healthSleep,
            manualSleep: sync.snapshot.sleep
        )
    }

    private var loggedMinutes: Int {
        coverageAnalyzer.loggedMinutes
    }

    private var coverageGaps: [CoverageGap] {
        coverageAnalyzer.gaps
    }

    private var trackedFreeTimeEntries: [FreeTimeEntry] {
        (sync.snapshot.freeTime ?? []) + mediaSync.trackedFreeTimeEntries(on: sync.snapshot.date)
    }

    private var trackedFreeTimeMinutes: Int {
        let intervals = TrackerTime.freeTimeIntervals(trackedFreeTimeEntries)
        let untimed = trackedFreeTimeEntries.filter { TrackerTime.minute($0.start ?? $0.time) == nil }
            .reduce(0) { $0 + max(0, $1.durationMinutes ?? 0) }
        return TrackerTime.unionMinutes(intervals) + untimed
    }

    private var mediaFreeTimeMinutes: Int {
        mediaSync.trackedFreeTimeMinutes(on: sync.snapshot.date)
    }

    private var todaysMediaEvents: [MediaEvent] {
        mediaSync.events(on: sync.snapshot.date)
    }

    private var selectedMediaSummary: MediaUsageSummary {
        mediaSync.usageSummary(on: sync.snapshot.date)
    }

    private var recentMediaDays: [MediaDailyUsage] {
        mediaSync.dailyUsage(endingOn: sync.snapshot.date)
    }

    private var recentMediaSessions: [CloudMediaSession] {
        mediaSync.recentSessions(through: sync.snapshot.date)
    }

    private var selectedNudgeHistory: [NudgeHistoryEntry] {
        mediaSync.nudgeHistory.filter { $0.date == sync.snapshot.date }
    }

    private var loggedCoverageDenominatorMinutes: Int {
        coverageAnalyzer.coverageEndMinute
    }

    private var loggedCoverageShare: Double {
        min(Double(loggedMinutes) / Double(loggedCoverageDenominatorMinutes), 1)
    }

    private var loggedCoveragePercent: Int {
        Int((loggedCoverageShare * 100).rounded())
    }

    private var workloadItems: [ScheduleItem] {
        sync.snapshot.schedule
            .filter { ($0.adjustedPriority ?? 0) > 2 }
            .filter { $0.status != .cancelled }
            .filter { $0.estimateMinutes != nil }
    }

    private var remainingWorkloadItems: [ScheduleItem] {
        sync.snapshot.todayOpenTasks
            .filter { !isCompletedForInsights($0) }
            .sorted {
                ($0.adjustedPriority ?? -1, $0.priority ?? -1, -($0.estimateMinutes ?? 0), $0.task)
                    > ($1.adjustedPriority ?? -1, $1.priority ?? -1, -($1.estimateMinutes ?? 0), $1.task)
            }
    }

    @State private var history: [String: TrackerSnapshot] = [:]
    @State private var historyError = false
    @State private var selectedHistoryDate: String?
    var section: InsightsSection = .overview

    var body: some View {
        @Bindable var navigation = navigation
        Group {
            if section == .overview {
                NavigationStack {
                    overview
                        .navigationDestination(isPresented: $navigation.showingCoverageGaps) {
                            CoverageGapsDetailView(date: sync.snapshot.date)
                        }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch section {
                        case .freeTime: trackedFreeTimeCard
                        case .nudges:
                            nudgeEffectivenessCard
                            Text("A session ending after a reminder does not necessarily mean the reminder caused it.")
                                .font(.caption).foregroundStyle(.secondary)
                        case .logs:
                            dailyLogs
                            if sync.healthSleep != nil || sync.snapshot.sleep != nil { sleepCard() }
                        case .overview: EmptyView()
                        }
                    }.padding(20)
                }
                .background(TrackerStyle.background)
                .navigationTitle(section.title)
                .trackerInlineNavigationTitle()
                .task { await mediaSync.refresh(date: sync.snapshot.date) }
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TrackerSectionHeader(title: "Insights", detail: sync.snapshot.date)
                HStack(alignment: .top) {
                    metricPair(title: "Productive time", value: TrackerTime.label(sync.snapshot.productiveMinutes()), tint: TrackerStyle.ink)
                    Spacer()
                    NavigationLink {
                        CompletedTasksDetailView(tasks: completedTaskItems)
                    } label: {
                        metricPair(title: "Tasks finished", value: "\(sync.snapshot.finishedTaskCount)", tint: TrackerStyle.ink)
                    }.buttonStyle(.plain)
                }
                .padding(20)
                .background(TrackerStyle.soft, in: RoundedRectangle(cornerRadius: 24))
                productiveTrend
                NavigationLink { WorkloadDetailView(tasks: remainingWorkloadItems) } label: {
                    TrackerDisclosure(title: "Workload", detail: "\(remainingWorkloadItems.count) open tasks · estimated",
                        value: TrackerTime.label(sync.snapshot.openEstimateMinutes))
                }.buttonStyle(.plain)
                NavigationLink { CoverageGapsDetailView(date: sync.snapshot.date) } label: {
                    VStack(spacing: 0) {
                        TrackerDisclosure(title: "Logged coverage",
                            detail: "\(TrackerTime.label(max(0, loggedCoverageDenominatorMinutes - loggedMinutes))) unlogged · \(coverageGaps.count) gaps over 5 min",
                            value: "\(loggedCoveragePercent)%")
                        ProgressView(value: loggedCoverageShare)
                            .tint(TrackerStyle.accent).padding(.horizontal, 17).padding(.bottom, 17)
                    }.background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
                NavigationLink { InsightsView(section: .freeTime) } label: {
                    TrackerDisclosure(title: "Free time", detail: "YouTube, X & recent sessions")
                }.buttonStyle(.plain)
                NavigationLink { InsightsView(section: .logs) } label: {
                    TrackerDisclosure(title: "Daily logs", detail: "Meals, caffeine & sleep")
                }.buttonStyle(.plain)
                if urgentKnownCount > 0 {
                    NavigationLink { UrgentTasksDetailView(completed: urgentCompletedItems, open: urgentOpenItems) } label: {
                        TrackerDisclosure(title: "Priority tasks", detail: "\(urgentCompletedItems.count) of \(urgentKnownCount) AP 10+ finished",
                            value: "\(urgentCompletionPercent)%")
                    }.buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(TrackerStyle.background)
        .navigationTitle("").trackerInlineNavigationTitle()
        .refreshable {
            await sync.refresh()
            await mediaSync.refresh(date: sync.snapshot.date)
            await loadHistory()
        }
        .task(id: sync.snapshot.date) { await loadHistory() }
    }

    private var dailyLogs: some View {
        VStack(spacing: 12) {
            NavigationLink { CaffeineDetailView(entries: sync.snapshot.caffeine) } label: {
                TrackerDisclosure(title: "Caffeine", detail: "Drinks logged", value: "\(sync.snapshot.caffeine.count)")
            }
            NavigationLink { FoodDetailView(entries: sync.snapshot.food) } label: {
                TrackerDisclosure(title: "Meals", detail: "Food entries", value: "\(sync.snapshot.food.count)")
            }
            NavigationLink { SleepDetailView(healthSleep: sync.healthSleep, manualSleep: sync.snapshot.sleep) } label: {
                TrackerDisclosure(title: "Sleep", detail: "Night record & phases", value: sleepValue)
            }
        }.buttonStyle(.plain)
    }

    private var trendDates: [String] {
        let end = Date.trackerDateFormatter.date(from: sync.snapshot.date) ?? Date()
        return (0..<7).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: end).map { Date.trackerDateFormatter.string(from: $0) }
        }
    }

    private func minutesForTrend(_ date: String) -> Int? {
        if date == sync.snapshot.date { return sync.snapshot.productiveMinutes() }
        return history[date]?.productiveMinutes()
    }

    private var productiveTrend: some View {
        let selected = selectedHistoryDate ?? sync.snapshot.date
        let maximum = max(1, trendDates.compactMap(minutesForTrend).max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Productive time").font(.headline)
                Spacer()
                Text("Last 7 days").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(trendDates, id: \.self) { date in
                    let minutes = minutesForTrend(date)
                    Button { selectedHistoryDate = date } label: {
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottom) {
                                Color.clear.frame(height: 80)
                                if let minutes {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(TrackerStyle.accent.opacity(date == selected ? 1 : 0.3))
                                        .frame(height: max(1, CGFloat(minutes) / CGFloat(maximum) * 80))
                                } else {
                                    Text("–").foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: 28)
                            Text(Date.trackerDateFormatter.date(from: date)?.formatted(.dateTime.weekday(.abbreviated)) ?? date)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(date): \(minutes.map(TrackerTime.label) ?? "Unavailable") productive")
                    .accessibilityAddTraits(date == selected ? .isSelected : [])
                }
            }
            Text("\(selected) · \(minutesForTrend(selected).map(TrackerTime.label) ?? "Unavailable")\(selected == Date.trackerDateFormatter.string(from: Date()) ? " so far" : "")")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            if historyError {
                Text("Some history is unavailable. Pull to refresh.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func loadHistory() async {
        historyError = false
        for date in trendDates where date != sync.snapshot.date {
            guard !Task.isCancelled else { return }
            do { history[date] = try await TrackerAPIClient.shared.fetchSnapshot(date: date) }
            catch { historyError = true }
        }
    }

    private var workloadCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label("Workload", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(actualMinutes)m / \(adjustedWorkloadMinutes)m")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(workloadHeadline)
                .font(.title2.weight(.bold))

            WorkloadGauge(
                fraction: actualShare,
                color: workloadColor,
                centerValue: minutesLabel(actualMinutes),
                centerCaption: "of \(minutesLabel(adjustedWorkloadMinutes))"
            )
            .frame(height: 190)

            HStack {
                metricPair(title: "Adjusted", value: minutesLabel(adjustedWorkloadMinutes), tint: .blue)
                Divider()
                metricPair(title: "Actual", value: minutesLabel(actualMinutes), tint: workloadColor)
            }
            .frame(height: 48)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var trackedFreeTimeCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Total tracked free time").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await mediaSync.refresh(date: sync.snapshot.date) } } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Refresh free time")
                }
                Text(minutesLabel(trackedFreeTimeMinutes)).font(.largeTitle.weight(.medium)).monospacedDigit()
                if mediaSync.snapshot.sessions != nil {
                    HStack {
                        metricPair(title: "YouTube", value: minutesLabel(selectedMediaSummary.youtubeMinutes), tint: TrackerStyle.ink)
                        Spacer()
                        metricPair(title: "X", value: minutesLabel(selectedMediaSummary.xMinutes), tint: TrackerStyle.ink)
                    }
                }
            }
            .padding(20)
            .background(TrackerStyle.freeTime.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
            if mediaSync.snapshot.sessions != nil {
                let overlap = max(0, selectedMediaSummary.youtubeMinutes + selectedMediaSummary.xMinutes - selectedMediaSummary.totalMinutes)
                Text("\(minutesLabel(overlap)) media overlap · counted once in the total")
                    .font(.caption).foregroundStyle(.secondary)
                mediaRecentTrend
                if !recentMediaSessions.isEmpty { mediaRecentActivity }
            }
            if trackedFreeTimeEntries.isEmpty {
                Text("No tracked free time for this date.").font(.subheadline).foregroundStyle(.secondary)
            }
            let manualEntries = sync.snapshot.freeTime ?? []
            if !manualEntries.isEmpty {
                Text("Other free-time entries").font(.headline)
                ForEach(manualEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.label).font(.subheadline.weight(.semibold))
                            Text(freeTimeDetail(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(minutesLabel(entry.durationMinutes ?? 0)).font(.subheadline.monospacedDigit())
                    }
                }
            }
            if let error = mediaSync.lastError { Text(error).font(.caption).foregroundStyle(.red) }
            if let status = mediaSync.snapshot.status {
                Text(mediaStatusText(status)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var mediaDailyStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isViewingToday ? "Today" : "Selected Day")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if selectedMediaSummary.longestSessionMinutes > 0 {
                    Label(
                        "Longest \(minutesLabel(selectedMediaSummary.longestSessionMinutes))",
                        systemImage: "timer"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                mediaSourceMetric(
                    title: "YouTube",
                    minutes: selectedMediaSummary.youtubeMinutes,
                    sessions: selectedMediaSummary.youtubeSessions,
                    systemImage: "play.rectangle.fill",
                    tint: .red
                )
                mediaSourceMetric(
                    title: "X",
                    minutes: selectedMediaSummary.xMinutes,
                    sessions: selectedMediaSummary.xSessions,
                    systemImage: "text.bubble.fill",
                    tint: .blue
                )
            }
        }
    }

    private var nudgeEffectivenessCard: some View {
        let selected = selectedNudgeHistory
        let evaluated = selected.filter { !["pending", "superseded"].contains($0.outcome) }
        let helped = evaluated.filter { ["strong", "moderate"].contains($0.outcome) }.count
        let fast = selected.filter { $0.outcome == "strong" }.count
        let ignored = selected.filter { $0.outcome == "ignored" }.count
        let successRate = evaluated.isEmpty ? 0 : Int((Double(helped) / Double(evaluated.count) * 100).rounded())

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Nudge Effectiveness", systemImage: "bell.and.waves.left.and.right.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let best = mediaSync.nudgeSummary?.angles.first, best.successes + best.failures > 0 {
                    Text("Best: \(nudgeAngleLabel(best.angle))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                metricPair(title: "Followed by exit", value: "\(successRate)%", tint: TrackerStyle.accent)
                Divider()
                metricPair(title: "≤30 sec", value: "\(fast)", tint: .mint)
                Divider()
                metricPair(title: "Ignored", value: "\(ignored)", tint: .orange)
            }
            .frame(height: 48)

            if selected.isEmpty {
                Text("No nudges recorded for this date yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider().opacity(0.5)
                Text("Recent Nudges")
                    .font(.subheadline.weight(.bold))

                ForEach(selected.prefix(6)) { nudge in
                    nudgeHistoryRow(nudge)
                }
            }
        }
        .padding(16)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func nudgeHistoryRow(_ nudge: NudgeHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: nudgeOutcomeIcon(nudge.outcome))
                .foregroundStyle(nudgeOutcomeColor(nudge.outcome))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(nudge.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(nudge.generator.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text(nudge.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nudgeContextLine(nudge))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(nudge.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit())
                Text(nudgeOutcomeLabel(nudge))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(nudgeOutcomeColor(nudge.outcome))
            }
        }
    }

    private func nudgeContextLine(_ nudge: NudgeHistoryEntry) -> String {
        var facts = [
            nudge.source == .youtube ? "YouTube" : "X",
            "\(nudge.dailyFreeTimeMinutes)m today",
            nudgeAngleLabel(nudge.angle)
        ]
        if let awake = nudge.context.minutesSinceWake { facts.append("\(awake)m awake") }
        if let task = nudge.context.suggestedTasks.first { facts.append("task: \(task)") }
        return facts.joined(separator: " · ")
    }

    private func nudgeOutcomeLabel(_ nudge: NudgeHistoryEntry) -> String {
        if let seconds = nudge.secondsToClose { return "closed \(seconds)s" }
        return nudge.outcome.capitalized
    }

    private func nudgeOutcomeIcon(_ outcome: String) -> String {
        switch outcome {
        case "strong": "bolt.circle.fill"
        case "moderate": "checkmark.circle.fill"
        case "ignored": "exclamationmark.circle.fill"
        case "late": "clock.fill"
        default: "bell.fill"
        }
    }

    private func nudgeOutcomeColor(_ outcome: String) -> Color {
        switch outcome {
        case "strong": .green
        case "moderate": .mint
        case "ignored": .orange
        case "late": .yellow
        default: .secondary
        }
    }

    private func nudgeAngleLabel(_ angle: String) -> String {
        switch angle {
        case "daily_total": "Daily total"
        case "morning": "Morning"
        case "task": "Task"
        case "content": "Content"
        case "repeat": "Repeat use"
        default: "General"
        }
    }

    private var mediaRecentTrend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 Days")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(minutesLabel(recentMediaAverageMinutes))/day avg")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(recentMediaDays) { day in
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.10))
                                .frame(height: 70)

                            Rectangle()
                                .fill(TrackerStyle.freeTime.opacity(day.date == sync.snapshot.date ? 1 : 0.4))
                                .frame(height: mediaBarHeight(day.totalMinutes))
                            .clipShape(Capsule())
                        }
                        Text(mediaDayLabel(day.date))
                            .font(.caption2.weight(day.date == sync.snapshot.date ? .bold : .regular))
                            .foregroundStyle(day.date == sync.snapshot.date ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(mediaDayAccessibilityLabel(day.date)), YouTube \(day.youtubeMinutes) minutes, X \(day.xMinutes) minutes, unique total \(day.totalMinutes) minutes"
                    )
                }
            }

            HStack(spacing: 14) {
                mediaLegend("Unique total", color: TrackerStyle.freeTime)
                Spacer()
                Text("\(minutesLabel(recentMediaTotalMinutes)) total")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var mediaRecentActivity: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Recent Sessions")
                .font(.subheadline.weight(.bold))

            ForEach(recentMediaSessions) { session in
                HStack(spacing: 10) {
                    Image(systemName: session.source == .youtube ? "play.rectangle.fill" : "text.bubble.fill")
                        .foregroundStyle(session.source == .youtube ? Color.red : Color.blue)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.source == .youtube ? "YouTube" : "X")
                                .font(.subheadline.weight(.semibold))
                            if session.active {
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.green, in: Capsule())
                            }
                        }
                        Text(mediaSessionDetail(session))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(minutesLabel(max(1, Int(ceil(Double(session.durationSeconds) / 60)))))
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(TrackerStyle.ink)
                }
            }
        }
    }

    private func mediaSourceMetric(
        title: String,
        minutes: Int,
        sessions: Int,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(minutesLabel(minutes))
                    .font(.title3.monospacedDigit().weight(.bold))
                Text("\(title) · \(sessions) \(sessions == 1 ? "session" : "sessions")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func mediaLegend(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var recentMediaTotalMinutes: Int {
        recentMediaDays.reduce(0) { $0 + $1.totalMinutes }
    }

    private var recentMediaAverageMinutes: Int {
        guard !recentMediaDays.isEmpty else { return 0 }
        return Int((Double(recentMediaTotalMinutes) / Double(recentMediaDays.count)).rounded())
    }

    private var recentMediaMaximumMinutes: Int {
        max(recentMediaDays.map(\.totalMinutes).max() ?? 0, 1)
    }

    private func mediaBarHeight(_ minutes: Int) -> CGFloat {
        guard minutes > 0 else { return 0 }
        return max(3, CGFloat(minutes) / CGFloat(recentMediaMaximumMinutes) * 70)
    }

    private func mediaDayLabel(_ date: String) -> String {
        guard let value = Date.trackerDateFormatter.date(from: date) else { return "-" }
        return value.formatted(.dateTime.weekday(.narrow))
    }

    private func mediaDayAccessibilityLabel(_ date: String) -> String {
        guard let value = Date.trackerDateFormatter.date(from: date) else { return date }
        return value.formatted(date: .abbreviated, time: .omitted)
    }

    private func mediaSessionDetail(_ session: CloudMediaSession) -> String {
        let day: String
        if session.date == Date.trackerDateFormatter.string(from: Date()) {
            day = "Today"
        } else {
            day = session.startedAt.formatted(.dateTime.weekday(.abbreviated).day())
        }
        let start = session.startedAt.formatted(date: .omitted, time: .shortened)
        let end = session.active ? "now" : session.endedAt.formatted(date: .omitted, time: .shortened)
        return "\(day), \(start)–\(end)"
    }

    private var isViewingToday: Bool {
        sync.snapshot.date == Date.trackerDateFormatter.string(from: Date())
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

    private func sleepCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Sleep")
            HStack(spacing: 12) {
                metricPair(title: "Duration", value: sleepValue, tint: .indigo)
                Divider()
                metricPair(title: "Wake", value: sleepWakeValue, tint: .indigo)
                Divider()
                metricPair(title: "Source", value: sync.healthSleep == nil ? "Manual" : "Health", tint: .indigo)
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
        if let healthSleep = sync.healthSleep {
            return String(format: "%.1fh", healthSleep.sleepHours)
        }
        return sync.snapshot.sleep?.sleepHours.map { String(format: "%.1fh", $0) } ?? "-"
    }

    private var sleepWakeValue: String {
        if let healthSleep = sync.healthSleep {
            return healthSleep.actualWake ?? "--:--"
        }
        return sync.snapshot.sleep?.actualWake ?? sync.snapshot.sleep?.plannedWake ?? "--:--"
    }

    private var workloadHeadline: String {
        if adjustedWorkloadMinutes == 0 { return "No priority workload yet" }
        if actualMinutes == 0 { return "Priority work is waiting" }
        if actualMinutes >= adjustedWorkloadMinutes { return "Priority workload is covered" }
        return "\(minutesLabel(adjustedWorkloadMinutes - actualMinutes)) left on AP 3+ work"
    }

    private var workloadColor: Color {
        guard adjustedWorkloadMinutes > 0 else { return .secondary }
        let ratio = Double(actualMinutes) / Double(adjustedWorkloadMinutes)
        if ratio >= 1 { return .green }
        if ratio >= 0.6 { return .blue }
        if ratio >= 0.3 { return .orange }
        return .red
    }

    private var loggedCoverageColor: Color {
        if loggedCoverageShare >= 0.75 { return .green }
        if loggedCoverageShare >= 0.5 { return .blue }
        if loggedCoverageShare >= 0.25 { return .orange }
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
    }

    private func completedWorkMinutes(for item: ScheduleItem) -> Int {
        item.actualMinutes ?? item.estimateMinutes ?? 0
    }

    private var mergedLoggedIntervals: [LoggedInterval] {
        let intervals = loggedIntervals.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        return intervals.reduce(into: [LoggedInterval]()) { merged, interval in
            guard interval.end > interval.start else { return }
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = LoggedInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
    }

    private var loggedIntervals: [LoggedInterval] {
        var intervals = sync.snapshot.schedule.compactMap(scheduleLoggedInterval)
        intervals.append(contentsOf: trackedFreeTimeEntries.compactMap(freeTimeLoggedInterval))
        if let healthSleep = sync.healthSleep {
            intervals.append(contentsOf: healthSleepLoggedIntervals(healthSleep))
        } else if let sleep = sync.snapshot.sleep {
            intervals.append(contentsOf: sleepLoggedIntervals(sleep))
        }
        return intervals
    }

    private func scheduleLoggedInterval(_ item: ScheduleItem) -> LoggedInterval? {
        guard let start = minutes(item.start) else { return nil }
        let end = minutes(item.stop) ?? runningEndMinute(for: item)
        guard let end else { return nil }
        return LoggedInterval(start: start, end: max(start + 1, end))
    }

    private func freeTimeLoggedInterval(_ item: FreeTimeEntry) -> LoggedInterval? {
        guard let start = minutes(item.start ?? item.time) else { return nil }
        let fallbackEnd = start + max(item.durationMinutes ?? 30, 15)
        let end = minutes(item.end) ?? fallbackEnd
        return LoggedInterval(start: start, end: max(start + 1, end))
    }

    private func sleepLoggedIntervals(_ item: SleepEntry) -> [LoggedInterval] {
        let start = minutes(item.sleepStart) ?? 0
        guard let end = minutes(item.actualWake ?? item.plannedWake ?? item.alarmTime) else { return [] }
        if end >= start {
            return [LoggedInterval(start: start, end: max(start + 1, end))]
        }
        return [
            LoggedInterval(start: start, end: 24 * 60),
            LoggedInterval(start: 0, end: max(1, end))
        ]
    }

    private func healthSleepLoggedIntervals(_ item: HealthSleepEntry) -> [LoggedInterval] {
        item.intervals.flatMap { interval -> [LoggedInterval] in
            let start = minutes(interval.startTime) ?? 0
            let end = minutes(interval.endTime) ?? 0
            if end >= start {
                return [LoggedInterval(start: start, end: end)]
            }
            return [
                LoggedInterval(start: start, end: 24 * 60),
                LoggedInterval(start: 0, end: end)
            ]
        }
    }

    private func runningEndMinute(for item: ScheduleItem) -> Int? {
        guard item.date == Date.trackerDateFormatter.string(from: Date()) else { return nil }
        return minutes(Date.trackerTimeFormatter.string(from: Date()))
    }

    private func minutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int(String($0)) }
        guard parts.count >= 2 else { return nil }
        return min(max(parts[0] * 60 + parts[1], 0), 24 * 60)
    }

    private func freeTimeDetail(_ entry: FreeTimeEntry) -> String {
        if let start = entry.start, let end = entry.end {
            return "\(start)-\(end)"
        }
        return entry.time ?? "Tracked automatically"
    }

    private func mediaStatusText(_ status: MediaStatus) -> String {
        let youtube = status.youtube.latestEventAt?.formatted(date: .abbreviated, time: .shortened) ?? "missing"
        let x = status.x.latestEventAt?.formatted(date: .abbreviated, time: .shortened) ?? "missing"
        return "Latest media exports: YouTube \(youtube), X \(x)"
    }

    private func mediaStatusIsStale(_ status: MediaStatus) -> Bool {
        let latest = [status.youtube.latestEventAt, status.x.latestEventAt].compactMap { $0 }.max()
        guard let latest else { return true }
        return Date().timeIntervalSince(latest) > 24 * 60 * 60
    }
}

private struct LoggedInterval {
    let start: Int
    let end: Int
}

private struct CoverageInterval {
    let start: Int
    let end: Int
    let title: String
}

struct CoverageGap: Identifiable, Hashable {
    let date: String
    let start: Int
    let end: Int
    let previousTitle: String?
    let nextTitle: String?

    var id: String { "\(date):\(start):\(end)" }
    var durationMinutes: Int { max(0, end - start) }
    var startLabel: String { Self.timeLabel(start) }
    var endLabel: String { Self.timeLabel(end) }

    var question: String {
        "What did you do between \(startLabel) and \(endLabel)?"
    }

    var surroundingContext: String {
        switch (previousTitle, nextTitle) {
        case let (previous?, next?):
            return "This was after finishing \(previous) and before beginning \(next)."
        case let (previous?, nil):
            return "This was after finishing \(previous)."
        case let (nil, next?):
            return "This was before beginning \(next)."
        case (nil, nil):
            return "There is no surrounding logged activity."
        }
    }

    private static func timeLabel(_ minute: Int) -> String {
        let bounded = min(max(minute, 0), 24 * 60)
        return String(format: "%02d:%02d", bounded / 60, bounded % 60)
    }
}

struct CoverageGapAnalyzer {
    let date: String
    let schedule: [ScheduleItem]
    let freeTime: [FreeTimeEntry]
    let healthSleep: HealthSleepEntry?
    let manualSleep: SleepEntry?
    var now = Date()

    var coverageEndMinute: Int {
        if date == Date.trackerDateFormatter.string(from: now) {
            return max(Self.minute(Date.trackerTimeFormatter.string(from: now)) ?? 1, 1)
        }
        return 24 * 60
    }

    var loggedMinutes: Int {
        mergedIntervals.reduce(0) { $0 + max(0, $1.end - $1.start) }
    }

    var gaps: [CoverageGap] {
        let intervals = coverageIntervals
            .filter { $0.end > 0 && $0.start < coverageEndMinute }
            .map {
                CoverageInterval(
                    start: max(0, $0.start),
                    end: min(coverageEndMinute, $0.end),
                    title: $0.title
                )
            }
            .filter { $0.end > $0.start }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }

        var result: [CoverageGap] = []
        var cursor = 0
        var previousTitle: String?

        for interval in intervals {
            if interval.end <= cursor { continue }
            if interval.start > cursor {
                if interval.start - cursor > 5 {
                    result.append(CoverageGap(
                        date: date,
                        start: cursor,
                        end: interval.start,
                        previousTitle: previousTitle,
                        nextTitle: interval.title
                    ))
                }
                cursor = interval.start
            }
            if interval.end > cursor {
                cursor = interval.end
                previousTitle = interval.title
            }
            if cursor >= coverageEndMinute { break }
        }

        if coverageEndMinute - cursor > 5 {
            result.append(CoverageGap(
                date: date,
                start: cursor,
                end: coverageEndMinute,
                previousTitle: previousTitle,
                nextTitle: nil
            ))
        }
        return result
    }

    private var mergedIntervals: [CoverageInterval] {
        coverageIntervals
            .map {
                CoverageInterval(
                    start: max(0, min($0.start, coverageEndMinute)),
                    end: max(0, min($0.end, coverageEndMinute)),
                    title: $0.title
                )
            }
            .filter { $0.end > $0.start }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
            .reduce(into: [CoverageInterval]()) { merged, interval in
                if let last = merged.last, interval.start <= last.end {
                    let title = interval.end > last.end ? interval.title : last.title
                    merged[merged.count - 1] = CoverageInterval(
                        start: last.start,
                        end: max(last.end, interval.end),
                        title: title
                    )
                } else {
                    merged.append(interval)
                }
            }
    }

    private var coverageIntervals: [CoverageInterval] {
        var intervals = schedule.flatMap(scheduleIntervals)
        intervals.append(contentsOf: freeTime.flatMap(freeTimeIntervals))
        if let healthSleep {
            intervals.append(contentsOf: healthSleep.intervals.flatMap {
                splitInterval(start: $0.startTime, end: $0.endTime, title: "Sleep")
            })
        } else if let manualSleep {
            let end = manualSleep.actualWake ?? manualSleep.plannedWake ?? manualSleep.alarmTime
            intervals.append(contentsOf: splitInterval(
                start: manualSleep.sleepStart ?? "00:00",
                end: end,
                title: "Sleep"
            ))
        }
        return intervals
    }

    private func scheduleIntervals(_ item: ScheduleItem) -> [CoverageInterval] {
        guard let start = Self.minute(item.start) else { return [] }
        let end = Self.minute(item.stop) ?? runningEnd(for: item)
        guard let end else { return [] }
        if end < start, item.stop != nil {
            return [
                CoverageInterval(start: start, end: 24 * 60, title: item.task),
                CoverageInterval(start: 0, end: max(1, end), title: item.task)
            ]
        }
        return [CoverageInterval(start: start, end: max(start + 1, end), title: item.task)]
    }

    private func freeTimeIntervals(_ item: FreeTimeEntry) -> [CoverageInterval] {
        guard let start = Self.minute(item.start ?? item.time) else { return [] }
        let fallbackEnd = start + max(item.durationMinutes ?? 30, 15)
        let end = Self.minute(item.end) ?? fallbackEnd
        if end < start, item.end != nil {
            return [
                CoverageInterval(start: start, end: 24 * 60, title: item.label),
                CoverageInterval(start: 0, end: max(1, end), title: item.label)
            ]
        }
        return [CoverageInterval(start: start, end: max(start + 1, end), title: item.label)]
    }

    private func runningEnd(for item: ScheduleItem) -> Int? {
        guard item.date == Date.trackerDateFormatter.string(from: now) else { return nil }
        return Self.minute(Date.trackerTimeFormatter.string(from: now))
    }

    private func splitInterval(start: String?, end: String?, title: String) -> [CoverageInterval] {
        guard let start = Self.minute(start), let end = Self.minute(end) else { return [] }
        if end >= start {
            return [CoverageInterval(start: start, end: max(start + 1, end), title: title)]
        }
        return [
            CoverageInterval(start: start, end: 24 * 60, title: title),
            CoverageInterval(start: 0, end: max(1, end), title: title)
        ]
    }

    private static func minute(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int(String($0)) }
        guard parts.count >= 2 else { return nil }
        return min(max(parts[0] * 60 + parts[1], 0), 24 * 60)
    }
}

private struct WorkloadGauge: View {
    let fraction: Double
    let color: Color
    let centerValue: String
    let centerCaption: String

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        ZStack {
            ArcGaugeShape(progress: 1)
                .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 18, lineCap: .round))

            ArcGaugeShape(progress: clampedFraction)
                .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .round))

            VStack(spacing: 4) {
                Text(centerValue)
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                Text(centerCaption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct ArcGaugeShape: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 14
        let size = min(rect.width, rect.height * 1.22) - inset * 2
        let center = CGPoint(x: rect.midX, y: rect.midY + size * 0.08)
        let radius = max(size / 2, 1)
        let start = Angle.degrees(135)
        let end = Angle.degrees(135 + 270 * min(max(progress, 0), 1))

        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}

struct CoverageGapsDetailView: View {
    @Environment(SyncController.self) private var sync
    @Environment(MediaSyncController.self) private var mediaSync
    let date: String
    @State private var selectedGap: CoverageGap?

    private var analyzer: CoverageGapAnalyzer {
        CoverageGapAnalyzer(
            date: date,
            schedule: sync.snapshot.schedule,
            freeTime: (sync.snapshot.freeTime ?? []) + mediaSync.trackedFreeTimeEntries(on: date),
            healthSleep: sync.healthSleep,
            manualSleep: sync.snapshot.sleep
        )
    }

    var body: some View {
        List {
            if analyzer.gaps.isEmpty {
                ContentUnavailableView(
                    "No gaps to review",
                    systemImage: "checkmark.circle",
                    description: Text("Every gap longer than five minutes is covered.")
                )
            } else {
                Section {
                    LabeledContent("Gaps over 5 minutes", value: "\(analyzer.gaps.count)")
                    LabeledContent(
                        "Unlogged time",
                        value: minutesLabel(analyzer.gaps.reduce(0) { $0 + $1.durationMinutes })
                    )
                } header: {
                    Text("Summary")
                }

                Section("Fill the gaps") {
                    ForEach(analyzer.gaps) { gap in
                        Button {
                            selectedGap = gap
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(gap.question)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(gap.surroundingContext)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Label("\(gap.durationMinutes)m unlogged", systemImage: "questionmark.circle")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens a form prefilled with this gap's time")
                    }
                }
            }
        }
        .navigationTitle("Coverage Gaps")
        .trackerInlineNavigationTitle()
        .sheet(item: $selectedGap) { gap in
            LogCoverageGapView(gap: gap)
        }
    }

    private func minutesLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}

private struct LogCoverageGapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncController.self) private var sync
    let gap: CoverageGap

    @State private var taskName = ""
    @State private var category = ""
    @State private var comment = ""
    @State private var priority = 3
    @State private var estimateMinutes: Int
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isSaving = false

    init(gap: CoverageGap) {
        self.gap = gap
        _estimateMinutes = State(initialValue: max(5, gap.durationMinutes))
        _startTime = State(initialValue: Self.date(gap.date, minute: gap.start))
        _endTime = State(initialValue: Self.date(gap.date, minute: gap.end))
    }

    private var loggedDurationMinutes: Int {
        max(0, Calendar.current.dateComponents([.minute], from: startTime, to: endTime).minute ?? 0)
    }

    private var canSave: Bool {
        !taskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && loggedDurationMinutes > 0
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What did you do?") {
                    TextField("Task / activity", text: $taskName)
                    TextField("Category", text: $category)
                    TextField("Comment", text: $comment, axis: .vertical)
                }

                Section("When") {
                    LabeledContent("Date", value: formattedDate)
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Stop", selection: $endTime, displayedComponents: .hourAndMinute)
                    LabeledContent("Logged duration", value: minutesLabel(loggedDurationMinutes))
                    if loggedDurationMinutes <= 0 {
                        Label("Stop must be after start", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Planning details") {
                    Stepper("Priority \(priority)", value: $priority, in: 1...10)
                    Stepper("Estimate \(estimateMinutes)m", value: $estimateMinutes, in: 5...1440, step: 5)
                }

                Section {
                    Text(gap.surroundingContext)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Gap context")
                }
            }
            .navigationTitle("Log Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var formattedDate: String {
        guard let value = Date.trackerDateFormatter.date(from: gap.date) else { return gap.date }
        return value.formatted(date: .abbreviated, time: .omitted)
    }

    private func save() {
        let request = CreateTaskRequest(
            date: gap.date,
            task: taskName.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : comment.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority,
            estimateMinutes: estimateMinutes,
            start: Date.trackerTimeFormatter.string(from: startTime),
            stop: Date.trackerTimeFormatter.string(from: endTime),
            status: .logged,
            source: "ios-gap-fill",
            importedAt: ISO8601DateFormatter().string(from: Date())
        )
        isSaving = true
        Task {
            await sync.createTask(request)
            isSaving = false
            dismiss()
        }
    }

    private func minutesLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private static func date(_ dateString: String, minute: Int) -> Date {
        let base = Date.trackerDateFormatter.date(from: dateString) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: base)
        return Calendar.current.date(byAdding: .minute, value: minute, to: startOfDay) ?? base
    }
}

private struct WorkloadDetailView: View {
    let tasks: [ScheduleItem]

    private var totalMinutes: Int {
        tasks.reduce(0) { $0 + ($1.estimateMinutes ?? 0) }
    }

    var body: some View {
        List {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "All tasks complete",
                    systemImage: "checkmark.circle",
                    description: Text("There are no open tasks for this day.")
                )
            } else {
                Section {
                    LabeledContent("Tasks remaining", value: "\(tasks.count)")
                    LabeledContent("Estimated time", value: minutesLabel(totalMinutes))
                } header: {
                    Text("Summary")
                }

                Section("Still to do") {
                    ForEach(tasks) { task in
                        InsightTaskRow(task: task, tint: .blue)
                    }
                }
            }
        }
        .navigationTitle("Workload")
        .trackerInlineNavigationTitle()
    }

    private func minutesLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
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

    private var total: Int { completed.count + open.count }
    private var estimatedMinutes: Int { open.reduce(0) { $0 + max(0, $1.estimateMinutes ?? 0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if total == 0 {
                    ContentUnavailableView("No priority tasks", systemImage: "checkmark.circle",
                        description: Text("Tasks with adjusted priority 10 or higher appear here."))
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Adjusted priority 10+").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .top) {
                            summaryValue("\(open.count)", caption: "Still open")
                            Spacer()
                            summaryValue("\(completed.count)", caption: "Finished")
                            Spacer()
                            summaryValue(TrackerTime.label(estimatedMinutes), caption: "Est. remaining")
                        }
                        ProgressView(value: Double(completed.count), total: Double(total))
                            .tint(TrackerStyle.accent)
                        Text("\(completed.count) of \(total) finished")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(TrackerStyle.soft, in: RoundedRectangle(cornerRadius: 24))
                    if !open.isEmpty { taskSection("Still to do", tasks: open, finished: false) }
                    if !completed.isEmpty { taskSection("Finished", tasks: completed, finished: true) }
                }
            }
            .padding(20)
        }
        .background(TrackerStyle.background)
        .navigationTitle("Priority tasks")
        .trackerInlineNavigationTitle()
    }

    private func summaryValue(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func taskSection(_ title: String, tasks: [ScheduleItem], finished: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(tasks.count)").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    HStack(alignment: .top, spacing: 10) {
                        if finished {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(TrackerStyle.accent).padding(.top, 2)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(task.task).font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(metadata(task)).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if let priority = task.adjustedPriority {
                            Text("AP \(priority)").font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .foregroundStyle(TrackerStyle.accent)
                                .background(TrackerStyle.soft, in: Capsule())
                                .fixedSize()
                        }
                    }
                    .padding(.vertical, 13)
                    if index < tasks.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func metadata(_ task: ScheduleItem) -> String {
        var values = [task.category].filter { !$0.isEmpty }
        if let priority = task.priority { values.append("P\(priority)") }
        if let estimate = task.estimateMinutes { values.append("Est. \(TrackerTime.label(estimate))") }
        if let start = task.start {
            values.append(task.stop.map { "\(start)–\($0)" } ?? "Started \(start)")
        } else if let stop = task.stop { values.append("Stopped \(stop)") }
        return values.joined(separator: " · ")
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
    let healthSleep: HealthSleepEntry?
    let manualSleep: SleepEntry?

    var body: some View {
        List {
            if let healthSleep {
                Section("HealthKit") {
                    sleepRow("Duration", String(format: "%.1fh", healthSleep.sleepHours), "bed.double.fill")
                    sleepRow("Sleep start", healthSleep.sleepStart ?? "-", "moon.fill")
                    sleepRow("Wake", healthSleep.actualWake ?? "-", "sun.max.fill")
                    sleepRow("Intervals", "\(healthSleep.intervals.count)", "waveform.path.ecg")
                    sleepRow("Synced", healthSleep.syncedAt.formatted(date: .abbreviated, time: .shortened), "heart.text.square.fill")
                }
                if !healthSleep.intervals.isEmpty {
                    Section("HealthKit Intervals") {
                        ForEach(healthSleep.intervals) { interval in
                            sleepRow("\(interval.startTime)-\(interval.endTime)", "\(interval.durationMinutes)m", "clock.fill")
                        }
                    }
                }
            }

            if let sleep = manualSleep {
                Section("Manual Sheet") {
                    sleepRow("Duration", sleep.sleepHours.map { String(format: "%.1fh", $0) } ?? "-", "bed.double.fill")
                    sleepRow("Sleep start", sleep.sleepStart ?? "-", "moon.fill")
                    sleepRow("Alarm", sleep.alarmTime ?? "-", "alarm.fill")
                    sleepRow("Planned wake", sleep.plannedWake ?? "-", "calendar")
                    sleepRow("Actual wake", sleep.actualWake ?? "-", "sun.max.fill")
                    sleepRow("Overslept", sleep.oversleptHours.map { String(format: "%.1fh", $0) } ?? "-", "exclamationmark.triangle.fill")
                }
            }

            if healthSleep == nil && manualSleep == nil {
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
