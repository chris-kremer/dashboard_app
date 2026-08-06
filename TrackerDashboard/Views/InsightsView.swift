import SwiftUI

struct InsightsView: View {
    @Environment(SyncController.self) private var sync
    @Environment(MediaSyncController.self) private var mediaSync

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

    private var loggedMinutes: Int {
        mergedLoggedIntervals.reduce(0) { $0 + max(0, min($1.end, loggedCoverageDenominatorMinutes) - $1.start) }
    }

    private var trackedFreeTimeEntries: [FreeTimeEntry] {
        (sync.snapshot.freeTime ?? []) + mediaSync.trackedFreeTimeEntries(on: sync.snapshot.date)
    }

    private var trackedFreeTimeMinutes: Int {
        let sheetMinutes = (sync.snapshot.freeTime ?? []).reduce(0) { $0 + ($1.durationMinutes ?? 0) }
        return sheetMinutes + mediaFreeTimeMinutes
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
        if sync.snapshot.date == Date.trackerDateFormatter.string(from: Date()) {
            return max(minutes(Date.trackerTimeFormatter.string(from: Date())) ?? 1, 1)
        }
        return 24 * 60
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
        workloadItems
            .filter { !isCompletedForInsights($0) }
            .sorted {
                ($0.adjustedPriority ?? -1, $0.priority ?? -1, -($0.estimateMinutes ?? 0), $0.task)
                    > ($1.adjustedPriority ?? -1, $1.priority ?? -1, -($1.estimateMinutes ?? 0), $1.task)
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Insights")
                        .font(.largeTitle.weight(.bold))

                    NavigationLink {
                        WorkloadDetailView(tasks: remainingWorkloadItems)
                    } label: {
                        workloadCard
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows unfinished priority tasks and their estimated durations")

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

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Label("Logged Coverage", systemImage: "record.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(loggedCoveragePercent)%")
                                .font(.title3.monospacedDigit().weight(.bold))
                                .foregroundStyle(loggedCoverageColor)
                        }

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.14))
                                Capsule()
                                    .fill(loggedCoverageColor)
                                    .frame(width: proxy.size.width * loggedCoverageShare)
                            }
                        }
                        .frame(height: 12)

                        HStack {
                            Text("\(minutesLabel(loggedMinutes)) logged")
                            Spacer()
                            Text("\(minutesLabel(max(loggedCoverageDenominatorMinutes - loggedMinutes, 0))) unlogged so far")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                            SleepDetailView(healthSleep: sync.healthSleep, manualSleep: sync.snapshot.sleep)
                        } label: {
                            compactMetric("Sleep", sleepValue, "bed.double.fill", .indigo, showsDisclosure: true)
                        }
                        .buttonStyle(.plain)
                    }

                    if sync.healthSleep != nil || sync.snapshot.sleep != nil {
                        sleepCard()
                    }

                    trackedFreeTimeCard

                    if mediaSync.nudgeSummary != nil || !selectedNudgeHistory.isEmpty {
                        nudgeEffectivenessCard
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Tracked Free Time", systemImage: "play.rectangle.on.rectangle.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if mediaSync.isRefreshing {
                    ProgressView()
                } else {
                    Button {
                        Task { await mediaSync.refresh(date: sync.snapshot.date) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh media free time")
                }
            }

            HStack(spacing: 12) {
                metricPair(title: "Total", value: minutesLabel(trackedFreeTimeMinutes), tint: .purple)
                Divider()
                metricPair(
                    title: "Media total",
                    value: minutesLabel(mediaSync.snapshot.sessions == nil ? mediaFreeTimeMinutes : selectedMediaSummary.totalMinutes),
                    tint: .purple
                )
                Divider()
                metricPair(
                    title: "Sessions",
                    value: "\(mediaSync.snapshot.sessions == nil ? todaysMediaEvents.count : selectedMediaSummary.sessionCount)",
                    tint: .purple
                )
            }
            .frame(height: 48)

            if mediaSync.snapshot.sessions != nil {
                Divider()
                    .opacity(0.5)

                mediaDailyStats
                mediaRecentTrend

                if !recentMediaSessions.isEmpty {
                    mediaRecentActivity
                }
            }

            if trackedFreeTimeEntries.isEmpty {
                Text("No tracked free-time entries for this date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(trackedFreeTimeEntries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.label)
                                    .font(.subheadline.weight(.semibold))
                                Text(freeTimeDetail(entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(minutesLabel(entry.durationMinutes ?? 0))
                                .font(.headline.monospacedDigit().weight(.bold))
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }

            if let status = mediaSync.snapshot.status {
                Text(mediaStatusText(status))
                    .font(.caption)
                    .foregroundStyle(mediaStatusIsStale(status) ? .orange : .secondary)
            } else if let error = mediaSync.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task {
            if mediaSync.snapshot.fetchedAt == .distantPast {
                await mediaSync.refresh(date: sync.snapshot.date)
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
                metricPair(title: "Helped", value: "\(successRate)%", tint: .green)
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

                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.red.opacity(0.8))
                                    .frame(height: mediaBarHeight(day.youtubeMinutes))
                                Rectangle()
                                    .fill(Color.blue.opacity(0.8))
                                    .frame(height: mediaBarHeight(day.xMinutes))
                            }
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
                mediaLegend("YouTube", color: .red)
                mediaLegend("X", color: .blue)
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
                        .foregroundStyle(.purple)
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
            || item.status == .logged
            || item.stop != nil
            || item.actualMinutes != nil
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

private struct WorkloadDetailView: View {
    let tasks: [ScheduleItem]

    private var totalMinutes: Int {
        tasks.reduce(0) { $0 + ($1.estimateMinutes ?? 0) }
    }

    var body: some View {
        List {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "Priority workload complete",
                    systemImage: "checkmark.circle",
                    description: Text("There are no unfinished AP 3+ tasks with estimates.")
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
