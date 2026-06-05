import SwiftUI

struct TimelineView: View {
    @Environment(SyncController.self) private var sync
    @State private var selectedTask: ScheduleItem?

    private var entries: [TimelineEntry] {
        var result = sync.snapshot.schedule.compactMap(TimelineEntry.schedule)
        if let sleep = sync.snapshot.sleep, let entry = TimelineEntry.sleep(sleep) {
            result.append(entry)
        }
        result.append(contentsOf: (sync.snapshot.freeTime ?? []).compactMap(TimelineEntry.freeTime))
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
            .background(Color(.systemGroupedBackground))
            .sheet(item: $selectedTask) { task in
                EditTaskView(task: task)
            }
        }
    }
}

private struct TimelineScaleView: View {
    let entries: [TimelineEntry]
    let now: Date
    let onSelectTask: (ScheduleItem) -> Void

    private let hourHeight: CGFloat = 58
    private let labelWidth: CGFloat = 52
    private var totalHeight: CGFloat { hourHeight * 24 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            timeLabels
            GeometryReader { proxy in
                let safeWidth = max(proxy.size.width, 1)
                ZStack(alignment: .topLeading) {
                    grid
                    ForEach(layoutEntries(width: safeWidth)) { item in
                        timelineBlock(item.entry)
                            .frame(width: item.width, height: item.height)
                            .offset(x: item.x, y: yOffset(for: item.entry.startMinute))
                    }
                    nowMarker(width: safeWidth)
                        .offset(y: yOffset(for: minuteOfDay(now)))
                }
            }
            .frame(height: totalHeight)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private var timeLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, height: hourHeight, alignment: .topTrailing)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .frame(height: hourHeight)
            }
        }
    }

    private func layoutEntries(width: CGFloat) -> [TimelineLayoutEntry] {
        entries.enumerated().map { index, entry in
            let overlaps = entries.filter { $0.overlaps(entry) }.count
            let column = entries[..<index].filter { $0.overlaps(entry) }.count
            let gap: CGFloat = overlaps > 1 ? 6 : 0
            let availableWidth = max(width - gap * CGFloat(max(overlaps - 1, 0)), 1)
            let blockWidth = max(availableWidth / CGFloat(max(overlaps, 1)), 1)
            return TimelineLayoutEntry(
                entry: entry,
                x: CGFloat(column) * (blockWidth + gap),
                width: blockWidth,
                height: max(10, CGFloat(entry.durationMinutes) / 60 * hourHeight)
            )
        }
    }

    private func yOffset(for minute: Int) -> CGFloat {
        CGFloat(minute) / 60 * hourHeight
    }

    private func nowMarker(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text("now")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.background, in: Capsule())
            Rectangle()
                .fill(.red)
                .frame(width: max(width, 1), height: 2)
        }
        .offset(x: -32, y: -6)
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(entry.color)
                    .frame(width: 7, height: 7)
                Text(entry.timeRange)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
            }
            Text(entry.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
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
            kind: .schedule(task: item.task, category: item.category),
            task: item
        )
    }

    static func sleep(_ item: SleepEntry) -> TimelineEntry? {
        let start = minutes(item.sleepStart) ?? 0
        guard let end = minutes(item.actualWake ?? item.plannedWake ?? item.alarmTime) else { return nil }
        return TimelineEntry(
            id: "sleep:\(item.date)",
            title: "Sleep",
            subtitle: item.sleepHours.map { String(format: "%.1fh", $0) } ?? "",
            startMinute: start,
            endMinute: max(end, start + 30),
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
            kind: .freeTime,
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
        case schedule(task: String, category: String)

        var color: Color {
            switch self {
            case .sleep:
                return .indigo
            case .freeTime:
                return .green
            case let .schedule(task, category):
                let text = "\(task) \(category)".lowercased()
                if text.contains("lecture") || text.contains("tutorial") || text.contains("seminar") {
                    return .blue
                }
                if text.contains("app") || text.contains("project") || text.contains("tech") {
                    return .purple
                }
                if text.contains("reading") || text.contains("book") {
                    return .teal
                }
                if text.contains("sports") {
                    return .orange
                }
                if text.contains("admin") || text.contains("email") {
                    return .red
                }
                return .gray
            }
        }
    }
}
