import SwiftUI

struct TimelineView: View {
    @Environment(SyncController.self) private var sync
    @Environment(MediaSyncController.self) private var mediaSync
    @State private var selectedTask: ScheduleItem?

    private var entries: [TimelineEntry] {
        var result = sync.snapshot.schedule.compactMap(TimelineEntry.schedule)
        if let sleep = sync.healthSleep {
            result.append(contentsOf: TimelineEntry.healthSleep(sleep))
        } else if let sleep = sync.snapshot.sleep {
            result.append(contentsOf: TimelineEntry.sleep(sleep))
        }
        let freeTimeEntries = (sync.snapshot.freeTime ?? []) + mediaSync.trackedFreeTimeTimelineEntries(on: sync.snapshot.date)
        result.append(contentsOf: TimelineEntry.freeTimeSessions(freeTimeEntries))
        result.append(contentsOf: sync.snapshot.caffeine.compactMap(TimelineEntry.caffeine))
        return result.sorted { $0.startMinute < $1.startMinute }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Timeline")
                        .font(.largeTitle.weight(.bold))

                    if entries.isEmpty {
                        EmptyStateView(title: "No timeline blocks", systemImage: "calendar")
                            .padding(.top, 40)
                    } else {
                        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                            TimelineScaleView(entries: entries, now: context.date) { task in
                                selectedTask = task
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .background(Color.trackerGroupedBackground)
            .sheet(item: $selectedTask) { task in
                EditTaskView(task: task)
            }
            .task {
                if mediaSync.snapshot.fetchedAt == .distantPast {
                    await mediaSync.refresh(date: sync.snapshot.date)
                }
            }
        }
    }
}

private struct TimelineScaleView: View {
    let entries: [TimelineEntry]
    let now: Date
    let onSelectTask: (ScheduleItem) -> Void
    @State private var zoom: CGFloat = 1

    private let rowHeight: CGFloat = 72
    private let axisWidth: CGFloat = 34
    private let baseChartWidth: CGFloat = 1680
    private var chartWidth: CGFloat { baseChartWidth * zoom }
    private var chartHeight: CGFloat { rowHeight * 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            zoomControls
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        priorityLabels
                        ZStack(alignment: .topLeading) {
                            grid
                            ForEach(layoutEntries(width: chartWidth)) { item in
                                timelineBlock(item.entry)
                                    .frame(width: item.width, height: item.height)
                                    .offset(x: item.x, y: yOffset(for: item.entry.priorityLevel))
                            }
                            nowMarker(height: chartHeight)
                                .offset(x: xOffset(for: minuteOfDay(now), width: chartWidth))
                        }
                        .frame(width: chartWidth, height: chartHeight)
                    }
                    xAxis
                        .padding(.leading, axisWidth + 10)
                }
                .padding(.bottom, 6)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Text("0-24h")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                zoom = max(0.55, zoom - 0.15)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoom <= 0.55)
            Button {
                zoom = min(1.65, zoom + 0.15)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoom >= 1.65)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func timelineBlock(_ entry: TimelineEntry) -> some View {
        if let task = entry.task {
            Button {
                onSelectTask(task)
            } label: {
                TimelineBlockView(entry: entry)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(task.task)")
        } else {
            TimelineBlockView(entry: entry)
        }
    }

    private var priorityLabels: some View {
        VStack(spacing: 0) {
            ForEach([6, 5, 4, 3, 2, 1, 0, -1], id: \.self) { priority in
                Text(priority == 6 ? "" : "\(priority)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: axisWidth, height: rowHeight, alignment: .center)
            }
        }
    }

    private var grid: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .frame(height: rowHeight)
                }
            }
            HStack(spacing: 0) {
                ForEach(0...24, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 1, height: chartHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var xAxis: some View {
        HStack(spacing: 0) {
            ForEach([0, 4, 8, 12, 16, 20, 24], id: \.self) { hour in
                Text("\(hour)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: hour == 0 ? .leading : hour == 24 ? .trailing : .center)
            }
        }
        .frame(width: chartWidth)
    }

    private func layoutEntries(width: CGFloat) -> [TimelineLayoutEntry] {
        entries.map { entry in
            return TimelineLayoutEntry(
                entry: entry,
                x: xOffset(for: entry.startMinute, width: width),
                width: max(8, CGFloat(entry.durationMinutes) / CGFloat(24 * 60) * width),
                height: rowHeight * 0.92
            )
        }
    }

    private func yOffset(for priority: Int) -> CGFloat {
        let clamped = min(max(priority, -1), 6)
        return CGFloat(6 - clamped) * rowHeight + rowHeight * 0.04
    }

    private func xOffset(for minute: Int, width: CGFloat) -> CGFloat {
        CGFloat(min(max(minute, 0), 24 * 60)) / CGFloat(24 * 60) * width
    }

    private func nowMarker(height: CGFloat) -> some View {
        VStack(spacing: 3) {
            Text("now")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.background, in: Capsule())
            Rectangle()
                .fill(.red)
                .frame(width: 2, height: height)
        }
        .offset(x: -1, y: -18)
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

private struct TimelineBlockView: View {
    let entry: TimelineEntry

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.height < 18 {
                compactBlock
            } else {
                fullBlock
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
        }
    }

    private var compactBlock: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(entry.color.opacity(0.55))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(entry.color)
                    .frame(width: 4)
            }
    }

    private var fullBlock: some View {
#if os(macOS)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(entry.color)
                .frame(width: 7, height: 7)
            Text(entry.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(entry.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(entry.color)
                .frame(width: 4)
        }
#else
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(entry.color)
                    .frame(width: 7, height: 7)
                Text(entry.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(entry.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(entry.color)
                .frame(width: 4)
        }
#endif
    }
}

private struct TimelineLayoutEntry: Identifiable {
    let entry: TimelineEntry
    let x: CGFloat
    let width: CGFloat
    let height: CGFloat

    var id: String { entry.id }
}

private struct TimelineEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let startMinute: Int
    let endMinute: Int
    let priorityLevel: Int
    let kind: Kind
    let task: ScheduleItem?

    var durationMinutes: Int { max(1, endMinute - startMinute) }
    var color: Color { kind.color }
    var timeRange: String { "\(Self.timeString(startMinute))-\(Self.timeString(endMinute))" }

    func overlaps(_ other: TimelineEntry) -> Bool {
        startMinute < other.endMinute && other.startMinute < endMinute
    }

    static func schedule(_ item: ScheduleItem) -> TimelineEntry? {
        guard let start = minutes(item.start) else { return nil }
        let fallbackEnd = item.estimateMinutes.map { start + $0 } ?? start + max(item.actualMinutes ?? 30, 30)
        let end = minutes(item.stop) ?? fallbackEnd
        return TimelineEntry(
            id: item.id,
            title: item.task,
            subtitle: item.category,
            startMinute: start,
            endMinute: min(max(end, start + 1), 24 * 60),
            priorityLevel: item.priority ?? 0,
            kind: .schedule(priority: item.priority ?? 0),
            task: item
        )
    }

    static func sleep(_ item: SleepEntry) -> [TimelineEntry] {
        let start = minutes(item.sleepStart) ?? 0
        guard let end = minutes(item.actualWake ?? item.plannedWake ?? item.alarmTime) else { return [] }
        if end < start {
            return [
                sleepEntry(item, start: start, end: 24 * 60, suffix: "late"),
                sleepEntry(item, start: 0, end: max(end, 30), suffix: "early")
            ]
        }
        return [
            sleepEntry(item, start: start, end: max(end, start + 30), suffix: "main")
        ]
    }

    private static func sleepEntry(_ item: SleepEntry, start: Int, end: Int, suffix: String) -> TimelineEntry {
        TimelineEntry(
            id: "sleep:\(item.date):\(suffix)",
            title: "Sleep",
            subtitle: item.sleepHours.map { String(format: "%.1fh", $0) } ?? "",
            startMinute: start,
            endMinute: min(max(end, start + 1), 24 * 60),
            priorityLevel: 0,
            kind: .sleep,
            task: nil
        )
    }

    static func healthSleep(_ item: HealthSleepEntry) -> [TimelineEntry] {
        guard let firstStart = item.intervals.map(\.start).min(),
              let lastEnd = item.intervals.map(\.end).max(),
              lastEnd > firstStart
        else { return [] }

        let session = HealthSleepInterval(
            id: item.date,
            start: firstStart,
            end: lastEnd
        )
        let start = minutes(session.startTime) ?? 0
        let end = minutes(session.endTime) ?? start + max(session.durationMinutes, 30)

        if !Calendar.current.isDate(firstStart, inSameDayAs: lastEnd) || end < start {
            return [
                healthSleepEntry(session, start: start, end: 24 * 60, suffix: "late"),
                healthSleepEntry(session, start: 0, end: max(end, 30), suffix: "early")
            ]
        }
        return [healthSleepEntry(session, start: start, end: end, suffix: "main")]
    }

    private static func healthSleepEntry(_ interval: HealthSleepInterval, start: Int, end: Int, suffix: String) -> TimelineEntry {
        TimelineEntry(
            id: "health-sleep:\(interval.id):\(suffix)",
            title: "Sleep",
            subtitle: "HealthKit",
            startMinute: start,
            endMinute: min(max(end, start + 1), 24 * 60),
            priorityLevel: 0,
            kind: .sleep,
            task: nil
        )
    }

    static func freeTime(_ item: FreeTimeEntry) -> TimelineEntry? {
        let start = minutes(item.start ?? item.time)
        let end = minutes(item.end)
        guard let start else { return nil }
        let fallbackEnd = start + max(item.durationMinutes ?? 30, 15)
        return TimelineEntry(
            id: item.id,
            title: item.label,
            subtitle: "Free time",
            startMinute: start,
            endMinute: min(max(end ?? fallbackEnd, start + 1), 24 * 60),
            priorityLevel: -1,
            kind: item.id.hasPrefix("media-") ? .mediaFreeTime : .freeTime,
            task: nil
        )
    }

    static func freeTimeSessions(_ items: [FreeTimeEntry]) -> [TimelineEntry] {
        items
            .compactMap(freeTime)
            .sorted { ($0.startMinute, $0.endMinute) < ($1.startMinute, $1.endMinute) }
            .reduce(into: [TimelineEntry]()) { sessions, entry in
                guard let previous = sessions.last,
                      entry.startMinute - previous.endMinute < 2
                else {
                    sessions.append(entry)
                    return
                }

                sessions[sessions.count - 1] = TimelineEntry(
                    id: "\(previous.id)+\(entry.id)",
                    title: combinedFreeTimeTitle(previous.title, entry.title),
                    subtitle: "Free time",
                    startMinute: min(previous.startMinute, entry.startMinute),
                    endMinute: max(previous.endMinute, entry.endMinute),
                    priorityLevel: -1,
                    kind: previous.kind.isMediaFreeTime || entry.kind.isMediaFreeTime ? .mediaFreeTime : .freeTime,
                    task: nil
                )
            }
    }

    private static func combinedFreeTimeTitle(_ first: String, _ second: String) -> String {
        var labels: [String] = []
        for label in [first, second].flatMap({ $0.components(separatedBy: " + ") }) where !labels.contains(label) {
            labels.append(label)
        }
        return labels.joined(separator: " + ")
    }

    static func caffeine(_ item: CaffeineEntry) -> TimelineEntry? {
        guard let start = minutes(item.time) else { return nil }
        return TimelineEntry(
            id: item.id,
            title: item.label,
            subtitle: "Coffee",
            startMinute: start,
            endMinute: min(start + 120, 24 * 60),
            priorityLevel: 6,
            kind: .caffeine,
            task: nil
        )
    }

    private static func minutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int(String($0)) }
        guard parts.count >= 2 else { return nil }
        return min(max(parts[0] * 60 + parts[1], 0), 24 * 60)
    }

    private static func timeString(_ minute: Int) -> String {
        String(format: "%02d:%02d", min(minute / 60, 23), minute % 60)
    }

    enum Kind {
        case sleep
        case freeTime
        case mediaFreeTime
        case caffeine
        case schedule(priority: Int)

        var isMediaFreeTime: Bool {
            if case .mediaFreeTime = self { return true }
            return false
        }

        var color: Color {
            switch self {
            case .sleep:
                return .blue
            case .freeTime:
                return .red
            case .mediaFreeTime:
                return .red
            case .caffeine:
                return .gray
            case let .schedule(priority):
                switch priority {
                case 5...:
                    return .trackerDarkGreen
                case 4:
                    return .green
                case 3:
                    return Color(red: 0.55, green: 0.82, blue: 0.35)
                case 2:
                    return .yellow
                case 1:
                    return .orange
                default:
                    return .white
                }
            }
        }
    }
}
