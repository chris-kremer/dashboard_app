import SwiftUI

enum TimelineLane: Int, CaseIterable, Identifiable {
    case sleep, tasks, life, media, gaps
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .tasks: "Tasks"
        case .life: "Life"
        case .media: "Media"
        case .gaps: "Gaps"
        }
    }
}

struct TimelineTaskSegment: Identifiable {
    let startMinute: Int
    let endMinute: Int
    let entries: [TimelineChartEntry]

    var id: Int { startMinute }
    var priority: Int { entries.reduce(0) { $0 + max(0, $1.priorityLevel) } }
    var title: String { entries.map(\.title).joined(separator: " + ") }
    var timeRange: String { "\(TimelineChartEntry.timeString(startMinute))-\(TimelineChartEntry.timeString(endMinute))" }

    static func segments(from entries: [TimelineChartEntry]) -> [TimelineTaskSegment] {
        let tasks = entries.filter { $0.lane == .tasks && $0.startMinute < $0.endMinute }
        let boundaries = Set(tasks.flatMap {
            [min(max($0.startMinute, 0), 1440), min(max($0.endMinute, 0), 1440)]
        }).sorted()

        // Split at every start/stop so only the overlapping portion adds priorities.
        return zip(boundaries, boundaries.dropFirst()).compactMap { start, end in
            let active = tasks.filter { $0.startMinute < end && $0.endMinute > start }
                .sorted {
                    if $0.priorityLevel != $1.priorityLevel { return $0.priorityLevel > $1.priorityLevel }
                    return $0.id < $1.id
                }
            guard !active.isEmpty else { return nil }
            return TimelineTaskSegment(startMinute: start, endMinute: end, entries: active)
        }
    }
}

struct TimelineChartEntry: Identifiable {
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
    var lane: TimelineLane {
        switch kind {
        case .sleep: .sleep
        case .schedule: .tasks
        case .caffeine, .food: .life
        case .freeTime, .mediaFreeTime: .media
        case .gap: .gaps
        }
    }
    var timeRange: String { "\(Self.timeString(startMinute))-\(Self.timeString(endMinute))" }

    func overlaps(_ other: TimelineChartEntry) -> Bool {
        startMinute < other.endMinute && other.startMinute < endMinute
    }

    static func schedule(_ item: ScheduleItem, now: Date) -> TimelineChartEntry? {
        guard let start = minutes(item.start) else { return nil }
        let fallbackEnd = item.date == Date.trackerDateFormatter.string(from: now) && item.status == .inProgress
            ? (minutes(Date.trackerTimeFormatter.string(from: now)) ?? start)
            : start + max(item.actualMinutes ?? 0, 1)
        let end = minutes(item.stop) ?? fallbackEnd
        return TimelineChartEntry(
            id: item.id,
            title: item.task,
            subtitle: item.category,
            startMinute: start,
            endMinute: min(max(end, start + 1), 24 * 60),
            priorityLevel: item.priority ?? 0,
            kind: item.isFreeTimeCategory ? .freeTime : .schedule(priority: item.priority ?? 0),
            task: item
        )
    }

    static func sleep(_ item: SleepEntry) -> [TimelineChartEntry] {
        let start = minutes(item.sleepStart) ?? 0
        guard let end = minutes(item.actualWake ?? item.plannedWake ?? item.alarmTime) else { return [] }
        if end < start {
            return [
                sleepEntry(item, start: 0, end: max(end, 30), suffix: "early")
            ]
        }
        return [
            sleepEntry(item, start: start, end: max(end, start + 30), suffix: "main")
        ]
    }

    private static func sleepEntry(_ item: SleepEntry, start: Int, end: Int, suffix: String) -> TimelineChartEntry {
        TimelineChartEntry(
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

    static func healthSleep(_ item: HealthSleepEntry) -> [TimelineChartEntry] {
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
                healthSleepEntry(session, start: 0, end: max(end, 30), suffix: "early")
            ]
        }
        return [healthSleepEntry(session, start: start, end: end, suffix: "main")]
    }

    private static func healthSleepEntry(_ interval: HealthSleepInterval, start: Int, end: Int, suffix: String) -> TimelineChartEntry {
        TimelineChartEntry(
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

    static func freeTime(_ item: FreeTimeEntry) -> TimelineChartEntry? {
        let start = minutes(item.start ?? item.time)
        let end = minutes(item.end)
        guard let start else { return nil }
        let fallbackEnd = start + max(item.durationMinutes ?? 30, 15)
        return TimelineChartEntry(
            id: item.id,
            title: item.label,
            subtitle: "Media",
            startMinute: start,
            endMinute: min(max(end ?? fallbackEnd, start + 1), 24 * 60),
            priorityLevel: -1,
            kind: item.id.hasPrefix("media-") ? .mediaFreeTime : .freeTime,
            task: nil
        )
    }

    static func freeTimeSessions(_ items: [FreeTimeEntry]) -> [TimelineChartEntry] {
        items
            .compactMap(freeTime)
            .sorted { ($0.startMinute, $0.endMinute) < ($1.startMinute, $1.endMinute) }
            .reduce(into: [TimelineChartEntry]()) { sessions, entry in
                guard let previous = sessions.last,
                      entry.startMinute - previous.endMinute < 2
                else {
                    sessions.append(entry)
                    return
                }

                sessions[sessions.count - 1] = TimelineChartEntry(
                    id: "\(previous.id)+\(entry.id)",
                    title: combinedFreeTimeTitle(previous.title, entry.title),
                    subtitle: "Media",
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

    static func caffeine(_ item: CaffeineEntry) -> TimelineChartEntry? {
        guard let start = minutes(item.time) else { return nil }
        return TimelineChartEntry(
            id: item.id,
            title: item.label,
            subtitle: "Coffee",
            startMinute: start,
            endMinute: min(start + 1, 24 * 60),
            priorityLevel: 6,
            kind: .caffeine,
            task: nil
        )
    }

    static func food(_ item: FoodEntry) -> TimelineChartEntry? {
        guard let start = minutes(item.time), start < 1440 else { return nil }
        return TimelineChartEntry(id: "food:\(item.id)", title: item.item,
            subtitle: [item.mealContext, item.amount, item.location, item.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
            startMinute: start, endMinute: min(start + 1, 1440), priorityLevel: 0, kind: .food, task: nil)
    }

    private static func minutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int(String($0)) }
        guard parts.count >= 2 else { return nil }
        return min(max(parts[0] * 60 + parts[1], 0), 24 * 60)
    }

    static func timeString(_ minute: Int) -> String {
        String(format: "%02d:%02d", min(minute / 60, 24), minute % 60)
    }

    enum Kind {
        case sleep
        case freeTime
        case mediaFreeTime
        case caffeine
        case food
        case gap
        case schedule(priority: Int)

        var lane: String {
            switch self {
            case .sleep: "Sleep"
            case .freeTime, .mediaFreeTime: "Media"
            case .caffeine, .food: "Life"
            case .gap: "Gaps"
            case .schedule: "Tasks"
            }
        }

        var isPoint: Bool {
            switch self { case .food, .caffeine: true; default: false }
        }

        var isMediaFreeTime: Bool {
            if case .mediaFreeTime = self { return true }
            return false
        }

        var color: Color {
            switch self {
            case .sleep:
                return TrackerStyle.sleep
            case .freeTime:
                return TrackerStyle.freeTime
            case .mediaFreeTime:
                return TrackerStyle.freeTime
            case .caffeine, .food:
                return TrackerStyle.life
            case .gap:
                return .secondary
            case let .schedule(priority):
                let value = Double(max(0, priority))
                let intensity = value / (value + 5)
                return Color(hue: 0.34, saturation: 0.35 + 0.5 * intensity, brightness: 0.93 - 0.65 * intensity)
            }
        }
    }
}

extension TimelineChartEntry {
    static func entries(snapshot: TrackerSnapshot, healthSleep: HealthSleepEntry?, media: MediaSnapshot, now: Date) -> [TimelineChartEntry] {
        let sleep = healthSleep?.date == snapshot.date ? healthSleep : nil
        var result = snapshot.schedule.filter { $0.date == snapshot.date && $0.status != .cancelled }
            .compactMap { schedule($0, now: now) }
        if let sleep { result.append(contentsOf: Self.healthSleep(sleep)) }
        else if let sleep = snapshot.sleep { result.append(contentsOf: Self.sleep(sleep)) }
        let freeTime = (snapshot.freeTime ?? []) + media.trackedFreeTimeTimelineEntries(on: snapshot.date)
        result.append(contentsOf: freeTimeSessions(freeTime))
        result.append(contentsOf: snapshot.caffeine.compactMap(caffeine))
        result.append(contentsOf: snapshot.food.compactMap(food))
        let analyzer = CoverageGapAnalyzer(date: snapshot.date, schedule: snapshot.schedule, freeTime: freeTime,
                                          healthSleep: sleep, manualSleep: snapshot.sleep, now: now)
        result.append(contentsOf: analyzer.gaps.map {
            TimelineChartEntry(id: "gap:\($0.id)", title: "Unlogged time", subtitle: $0.surroundingContext,
                               startMinute: $0.start, endMinute: $0.end, priorityLevel: 0, kind: .gap, task: nil)
        })
        return result.sorted { ($0.startMinute, $0.endMinute, $0.id) < ($1.startMinute, $1.endMinute, $1.id) }
    }
}
