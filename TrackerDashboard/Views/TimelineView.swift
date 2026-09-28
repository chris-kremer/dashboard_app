import SwiftUI

struct TimelineView: View {
    @Environment(SyncController.self) private var sync
    @Environment(MediaSyncController.self) private var mediaSync
    @State private var selectedTask: ScheduleItem?
    @State private var showingGaps = false
    @State private var selectedDate = Date()
    @State private var historicalSnapshot: TrackerSnapshot?
    @State private var historicalSleep: HealthSleepEntry?
    @State private var loading = false
    @State private var loadError: String?
    @State private var sleepWarning: String?
    @State private var requestID = UUID()

    private var dateKey: String { Date.trackerDateFormatter.string(from: selectedDate) }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var displayedSnapshot: TrackerSnapshot? {
        if isToday, sync.snapshot.date == dateKey { return sync.snapshot }
        return historicalSnapshot?.date == dateKey ? historicalSnapshot : nil
    }
    private var displayedSleep: HealthSleepEntry? {
        if isToday, sync.healthSleep?.date == dateKey { return sync.healthSleep }
        return historicalSleep?.date == dateKey ? historicalSleep : nil
    }

    private func entries(snapshot: TrackerSnapshot, now: Date) -> [TimelineEntry] {
        var result = snapshot.schedule.filter { $0.date == dateKey && $0.status != .cancelled }
            .compactMap { TimelineEntry.schedule($0, now: now) }
        if let sleep = displayedSleep {
            result.append(contentsOf: TimelineEntry.healthSleep(sleep))
        } else if let sleep = snapshot.sleep { result.append(contentsOf: TimelineEntry.sleep(sleep)) }
        let freeTime = (snapshot.freeTime ?? []) + mediaSync.trackedFreeTimeTimelineEntries(on: dateKey)
        result.append(contentsOf: TimelineEntry.freeTimeSessions(freeTime))
        result.append(contentsOf: snapshot.caffeine.compactMap(TimelineEntry.caffeine))
        result.append(contentsOf: snapshot.food.compactMap(TimelineEntry.food))
        let analyzer = CoverageGapAnalyzer(date: dateKey, schedule: snapshot.schedule,
            freeTime: freeTime, healthSleep: displayedSleep, manualSleep: snapshot.sleep, now: now)
        result.append(contentsOf: analyzer.gaps.map {
            TimelineEntry(id: "gap:\($0.id)", title: "Unlogged time", subtitle: $0.surroundingContext,
                startMinute: $0.start, endMinute: $0.end, priorityLevel: 0, kind: .gap, task: nil)
        })
        return result.sorted { ($0.startMinute, $0.endMinute, $0.id) < ($1.startMinute, $1.endMinute, $1.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TrackerSectionHeader(title: "Timeline", detail: isToday ? "Today" : "Past day · view only")
                    dateControls
                    if let loadError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(loadError, systemImage: "exclamationmark.triangle")
                            Button("Retry") { Task { await loadDay() } }
                        }.font(.subheadline)
                    }
                    if loading {
                        ProgressView("Loading day…").frame(maxWidth: .infinity)
                    }
                    if let snapshot = displayedSnapshot {
                        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                            TimelineScaleView(entries: entries(snapshot: snapshot, now: context.date),
                                now: context.date, date: dateKey, allowsEditing: isToday,
                                onSelectTask: { selectedTask = $0 }, onSelectGap: { showingGaps = true })
                        }
                        .id(dateKey)
                    }
                    if let sleepWarning {
                        Label(sleepWarning, systemImage: "bed.double").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = mediaSync.lastError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(TrackerStyle.background)
            .navigationTitle("").trackerInlineNavigationTitle()
            .sheet(item: $selectedTask) { EditTaskView(task: $0) }
            .navigationDestination(isPresented: $showingGaps) { CoverageGapsDetailView(date: dateKey) }
            .refreshable { await loadDay(refreshCurrent: true) }
            .task(id: dateKey) { await loadDay() }
        }
    }

    private var dateControls: some View {
        HStack(spacing: 6) {
            Button { moveDay(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.accessibilityLabel("Previous day")
            DatePicker("Timeline date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact)
                .accessibilityLabel("Timeline date")
            Button { moveDay(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }.disabled(isToday).accessibilityLabel("Next day")
            Spacer(minLength: 0)
            if !isToday {
                Button("Today") { selectedDate = Date() }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }.buttonStyle(.plain)
    }

    private func moveDay(_ offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        selectedDate = min(date, Date())
    }

    @MainActor
    private func loadDay(refreshCurrent: Bool = false) async {
        let key = dateKey
        let date = selectedDate
        let token = UUID()
        requestID = token
        historicalSnapshot = nil
        historicalSleep = nil
        loadError = nil
        sleepWarning = nil
        loading = true
        defer { if requestID == token { loading = false } }

        // Only Today refreshes the shared controller, cache, reminders and widgets.
        // A historical read must never become the app's current snapshot.
        if Calendar.current.isDateInToday(date), sync.snapshot.date == key {
            if refreshCurrent { await sync.refresh() }
        } else {
            do {
                let snapshot = try await TrackerAPIClient.shared.fetchSnapshot(date: key)
                guard !Task.isCancelled, requestID == token, dateKey == key else { return }
                guard snapshot.date == key else { throw TimelineLoadError.wrongDate }
                historicalSnapshot = snapshot
            } catch {
                guard !Task.isCancelled, requestID == token, dateKey == key else { return }
                loadError = "Couldn’t load this day. \(error.localizedDescription)"
                return
            }
        }
#if os(iOS)
        if !AppSettings.shared.usesLocalTestData, !Calendar.current.isDateInToday(date) {
            do {
                let sleep = try await HealthKitSleepStore.shared.sleep(for: date)
                guard !Task.isCancelled, requestID == token, dateKey == key else { return }
                historicalSleep = sleep
            } catch {
                guard !Task.isCancelled, requestID == token, dateKey == key else { return }
                sleepWarning = "Health sleep couldn’t be loaded for this day; showing any manually logged sleep."
            }
        }
#endif
        guard !Task.isCancelled, requestID == token, dateKey == key else { return }
        if refreshCurrent || mediaSync.snapshot.fetchedAt == .distantPast {
            await mediaSync.refresh(date: key)
        }
    }
}

private enum TimelineLoadError: LocalizedError {
    case wrongDate
    var errorDescription: String? { "The server returned a different date. Please retry." }
}

private struct TimelineScaleView: View {
    let entries: [TimelineEntry]
    let now: Date
    let date: String
    let allowsEditing: Bool
    let onSelectTask: (ScheduleItem) -> Void
    let onSelectGap: () -> Void
    @State private var selectedID: String?
    private let lanes = ["Sleep", "Tasks", "Life", "Free", "Gaps"]

    private var selected: TimelineEntry? {
        entries.first { $0.id == selectedID } ?? entries.last { $0.kind.lane != "Gaps" } ?? entries.first
    }
    private var isToday: Bool { date == Date.trackerDateFormatter.string(from: now) }
    private var currentMinute: Int { TrackerTime.minute(Date.trackerTimeFormatter.string(from: now)) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your whole day").font(.headline)
                Spacer()
                Text("00:00–24:00").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text(String(format: "%02d", hour)).font(.caption2).foregroundStyle(.secondary)
                            .position(x: 48 + CGFloat(hour) / 24 * max(0, proxy.size.width - 58), y: 10)
                    }
                }.frame(height: 22)
                ForEach(lanes, id: \.self) { lane in laneView(lane) }
                HStack {
                    Spacer()
                    Text(isToday ? "Now \(Date.trackerTimeFormatter.string(from: now))" : date)
                        .font(.caption).foregroundStyle(TrackerStyle.accent)
                }
            }
            if let entry = selected {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(entry.kind.lane).font(.caption.weight(.semibold)).foregroundStyle(TrackerStyle.accent)
                        Spacer()
                        Button { advance(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("Previous entry")
                        Button { advance(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .accessibilityLabel("Next entry")
                    }.buttonStyle(.plain)
                    Text(entry.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(entry.kind.isPoint ? String(entry.timeRange.prefix(5)) : "\(entry.timeRange) · \(TrackerTime.label(entry.durationMinutes))")
                        .font(.subheadline.monospacedDigit())
                    if !entry.subtitle.isEmpty { Text(entry.subtitle).font(.caption).foregroundStyle(.secondary) }
                    if let task = entry.task {
                        HStack {
                            if let priority = task.priority { Text("Priority \(priority)") }
                            if let estimate = task.estimateMinutes { Text("Est. \(TrackerTime.label(estimate))") }
                            Spacer()
                            if allowsEditing {
                                Button("Edit task") { onSelectTask(task) }.frame(minHeight: 44)
                            }
                        }.font(.caption)
                    } else if entry.kind.lane == "Gaps", allowsEditing {
                        Button("Fill missing log", action: onSelectGap).frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityElement(children: .contain)
                HStack {
                    Text("Tap a lane to inspect entries")
                    Spacer()
                    Text("\((entries.firstIndex { $0.id == entry.id } ?? 0) + 1) / \(entries.count)")
                }.font(.caption2).foregroundStyle(.secondary)
            } else {
                EmptyStateView(title: "No timeline entries", systemImage: "calendar")
            }
        }
    }

    private func laneView(_ lane: String) -> some View {
        let members = entries.filter { $0.kind.lane == lane }
        let tracks = TrackerTime.laneAssignments(members.map { $0.startMinute..<$0.endMinute })
        let trackCount = max(1, (tracks.max() ?? 0) + 1)
        return HStack(spacing: 6) {
            Text(lane).font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)).padding(.vertical, 5)
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Rectangle().fill(Color.secondary.opacity(0.08))
                            .frame(width: 1, height: 34).offset(x: CGFloat(hour) / 24 * max(0, width - 1), y: 5)
                    }
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, entry in
                        entryMark(entry, track: tracks[index], count: trackCount, width: width)
                    }
                    if isToday {
                        Rectangle().fill(TrackerStyle.accent.opacity(0.55))
                            .frame(width: 1, height: 44).offset(x: CGFloat(currentMinute) / 1440 * width)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    let minute = Double(point.x / max(width, 1)) * 1440
                    let track = max(0, min(trackCount - 1, Int((point.y - 8) / (28 / CGFloat(trackCount)))))
                    selectedID = members.enumerated().min { a, b in
                        distance(a.element, minute: minute, track: tracks[a.offset], selectedTrack: track)
                            < distance(b.element, minute: minute, track: tracks[b.offset], selectedTrack: track)
                    }?.element.id
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(lane), \(members.count) entries")
                .accessibilityValue(selected.map { $0.kind.lane == lane ? "\($0.title), \($0.timeRange)" : "" } ?? "")
                .accessibilityAction {
                    selectedID = members.first?.id
                }
                .accessibilityAdjustableAction { direction in
                    guard !members.isEmpty else { return }
                    let index = members.firstIndex { $0.id == selectedID } ?? 0
                    let delta = direction == .increment ? 1 : -1
                    selectedID = members[(index + delta + members.count) % members.count].id
                }
            }.frame(height: 44)
        }
    }

    private func distance(_ entry: TimelineEntry, minute: Double, track: Int, selectedTrack: Int) -> Double {
        max(Double(entry.startMinute) - minute, minute - Double(entry.endMinute), 0)
            + (track == selectedTrack ? 0 : 0.5)
    }

    private func entryMark(_ entry: TimelineEntry, track: Int, count: Int, width: CGFloat) -> some View {
        let x: CGFloat = CGFloat(entry.startMinute) / 1440.0 * width
        let slotHeight: CGFloat = 28.0 / CGFloat(count)
        let naturalWidth: CGFloat = CGFloat(entry.durationMinutes) / 1440.0 * width
        let markWidth: CGFloat = min(max(2.0, naturalWidth), max(0.0, width - x))
        let opacity: Double = selected?.id == entry.id ? 1.0 : 0.65
        return RoundedRectangle(cornerRadius: 3)
            .fill(entry.color.opacity(opacity))
            .frame(width: markWidth, height: max(1.0, slotHeight - 1.0))
            .offset(x: x, y: 8.0 + CGFloat(track) * slotHeight)
    }

    private func advance(_ delta: Int) {
        guard !entries.isEmpty else { return }
        let index = entries.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = entries[(index + delta + entries.count) % entries.count].id
    }
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

    static func schedule(_ item: ScheduleItem, now: Date) -> TimelineEntry? {
        guard let start = minutes(item.start) else { return nil }
        let fallbackEnd = item.date == Date.trackerDateFormatter.string(from: now) && item.status == .inProgress
            ? (minutes(Date.trackerTimeFormatter.string(from: now)) ?? start)
            : start + max(item.actualMinutes ?? 0, 1)
        let end = minutes(item.stop) ?? fallbackEnd
        return TimelineEntry(
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

    static func sleep(_ item: SleepEntry) -> [TimelineEntry] {
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
            endMinute: min(start + 1, 24 * 60),
            priorityLevel: 6,
            kind: .caffeine,
            task: nil
        )
    }

    static func food(_ item: FoodEntry) -> TimelineEntry? {
        guard let start = minutes(item.time), start < 1440 else { return nil }
        return TimelineEntry(id: "food:\(item.id)", title: item.item,
            subtitle: [item.mealContext, item.amount, item.location, item.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
            startMinute: start, endMinute: min(start + 1, 1440), priorityLevel: 0, kind: .food, task: nil)
    }

    private static func minutes(_ value: String?) -> Int? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int(String($0)) }
        guard parts.count >= 2 else { return nil }
        return min(max(parts[0] * 60 + parts[1], 0), 24 * 60)
    }

    private static func timeString(_ minute: Int) -> String {
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
            case .freeTime, .mediaFreeTime: "Free"
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
            case .schedule:
                return TrackerStyle.accent
            }
        }
    }
}
