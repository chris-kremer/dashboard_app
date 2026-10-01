import Foundation

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

