import SwiftUI
import WidgetKit

#if !os(watchOS)
struct TimelineChartWidget: Widget {
    let kind = "TimelineChartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimelineChartProvider()) { entry in
            TimelineChartWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Tracker Timeline")
        .description("Your day at a glance. Overlapping to-dos add their priorities for darker green shading.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TimelineChartWidgetEntry: TimelineEntry {
    let date: Date
    let snapshotDate: String
    let blocks: [TimelineChartEntry]

    static func sample(at date: Date) -> Self {
        let day = Date.trackerDateFormatter.string(from: date)
        let tasks = [
            ScheduleItem(id: "preview-plan", rowNumber: 1, date: day, task: "Plan", category: "Work", priority: 2, start: "09:00", stop: "12:00", status: .done),
            ScheduleItem(id: "preview-focus", rowNumber: 2, date: day, task: "Focus", category: "Work", priority: 3, start: "10:00", stop: "14:00", status: .done)
        ]
        var blocks = tasks.compactMap { TimelineChartEntry.schedule($0, now: date) }
        blocks.append(TimelineChartEntry(id: "preview-sleep", title: "Sleep", subtitle: "", startMinute: 0, endMinute: 420, priorityLevel: 0, kind: .sleep, task: nil))
        blocks.append(TimelineChartEntry(id: "preview-coffee", title: "Coffee", subtitle: "", startMinute: 480, endMinute: 600, priorityLevel: 6, kind: .caffeine, task: nil))
        blocks.append(TimelineChartEntry(id: "preview-free", title: "Media", subtitle: "", startMinute: 1080, endMinute: 1200, priorityLevel: -1, kind: .freeTime, task: nil))
        return Self(date: date, snapshotDate: day, blocks: blocks)
    }
}

struct TimelineChartProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimelineChartWidgetEntry {
        .sample(at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TimelineChartWidgetEntry) -> Void) {
        completion(context.isPreview ? .sample(at: Date()) : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimelineChartWidgetEntry>) -> Void) {
        let now = Date()
        let dates = (0..<12).map { now.addingTimeInterval(Double($0 * 5 * 60)) }
        let entries = entries(at: dates)
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }

    private func entry(at date: Date) -> TimelineChartWidgetEntry { entries(at: [date])[0] }

    private func entries(at dates: [Date]) -> [TimelineChartWidgetEntry] {
        let cache = SharedCache.shared
        let snapshot = cache.loadSnapshot()
        let sleep = cache.loadHealthSleep()
        let media = cache.loadMediaSnapshot()
        return dates.map { date in
            TimelineChartWidgetEntry(date: date,
                snapshotDate: snapshot?.date ?? Date.trackerDateFormatter.string(from: date),
                blocks: snapshot.map { TimelineChartEntry.entries(snapshot: $0, healthSleep: sleep, media: media, now: date) } ?? [])
        }
    }

}

struct TimelineChartWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimelineChartWidgetEntry

    var body: some View {
        TimelineChartWidgetContent(entry: entry, isLarge: family == .systemLarge)
    }
}

struct TimelineChartWidgetContent: View {
    let entry: TimelineChartWidgetEntry
    let isLarge: Bool
    private let labelWidth: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 10 : 5) {
            HStack {
                Label("Timeline", systemImage: "calendar.day.timeline.left")
                    .font(.headline)
                Spacer(minLength: 4)
                Text(dayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if entry.blocks.isEmpty {
                Spacer(minLength: 0)
                Text("Open Tracker to load your timeline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                chart
                Text("Darker green = higher combined priority")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .widgetURL(URL(string: "trackerdashboard://timeline"))
    }

    private var dayLabel: String {
        guard let date = Date.trackerDateFormatter.date(from: entry.snapshotDate) else { return entry.snapshotDate }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var chart: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width - labelWidth)
            let height = max(1, proxy.size.height - 16)
            let rowHeight = height / CGFloat(TimelineLane.allCases.count)
            ZStack(alignment: .topLeading) {
                ForEach(TimelineLane.allCases) { lane in
                    Text(lane.title)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth - 4, height: rowHeight, alignment: .leading)
                        .offset(y: CGFloat(lane.rawValue) * rowHeight)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: width, height: 1)
                        .offset(x: labelWidth, y: CGFloat(lane.rawValue) * rowHeight)
                }
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    let x = labelWidth + CGFloat(hour) / 24 * width
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 1, height: height)
                        .offset(x: x)
                    Text("\(hour)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                        .offset(x: min(max(x - 10, labelWidth), proxy.size.width - 20), y: height + 3)
                }
                ForEach(entry.blocks.filter { $0.lane != .tasks }) { block in
                    bar(title: block.title, color: block.color.opacity(0.65), start: block.startMinute,
                        end: block.endMinute, lane: block.lane, width: width, rowHeight: rowHeight, minimumWidth: block.kind.isPoint ? 2 : 0)
                        .accessibilityLabel("\(block.title), \(block.timeRange)")
                }
                ForEach(TimelineTaskSegment.segments(from: entry.blocks)) { segment in
                    bar(title: segment.title, color: TimelineChartEntry.Kind.schedule(priority: segment.priority).color,
                        start: segment.startMinute, end: segment.endMinute, lane: .tasks, width: width,
                        rowHeight: rowHeight, foreground: segment.priority >= 8 ? .white : .black)
                        .accessibilityLabel("\(segment.title), combined priority \(segment.priority), \(segment.timeRange)")
                }
                if entry.snapshotDate == Date.trackerDateFormatter.string(from: entry.date) {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: entry.date)
                    let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                    Rectangle()
                        .fill(.red)
                        .frame(width: 1.5, height: height)
                        .offset(x: labelWidth + CGFloat(minute) / 1440 * width)
                        .accessibilityLabel("Current time \(entry.date.formatted(date: .omitted, time: .shortened))")
                }
            }
        }
    }

    private func bar(title: String, color: Color, start: Int, end: Int, lane: TimelineLane,
                     width: CGFloat, rowHeight: CGFloat, minimumWidth: CGFloat = 0, foreground: Color = .primary) -> some View {
        let lower = min(max(start, 0), 1440)
        let upper = min(max(end, lower), 1440)
        let barWidth = min(max(minimumWidth, CGFloat(upper - lower) / 1440 * width), width - CGFloat(lower) / 1440 * width)
        return Rectangle()
            .fill(color)
            .overlay(alignment: .leading) {
                if isLarge && barWidth >= 36 {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .padding(.horizontal, 3)
                }
            }
            .frame(width: barWidth, height: max(1, rowHeight - 4))
            .clipped()
            .offset(x: labelWidth + CGFloat(lower) / 1440 * width, y: CGFloat(lane.rawValue) * rowHeight + 2)
    }
}
#endif
