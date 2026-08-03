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
}

struct TodayView: View {
    @Environment(SyncController.self) private var sync
    @Environment(AppNavigation.self) private var navigation
    @State private var viewModel = TodayViewModel()
    @State private var showingAddTask = false
    @State private var showingCaffeine = false
    @State private var showingFood = false
    @State private var refreshMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let refreshMessage {
                        refreshConfirmation(refreshMessage)
                    }
                    nowNextCards
                    quickActions
                    topTasks
                    loggedToday
                }
                .padding()
            }
            .navigationTitle("")
            .refreshable {
                await refreshToday()
            }
            .sheet(isPresented: $showingAddTask) { AddTaskView() }
            .sheet(isPresented: $showingCaffeine) { LogCaffeineView() }
            .sheet(isPresented: $showingFood) { LogFoodView() }
        }
    }

    private func refreshToday() async {
        await sync.refresh()
        let message = sync.syncState.lastError == nil
            ? "Updated \(Date.now.formatted(date: .omitted, time: .shortened))"
            : "Refresh failed"
        await MainActor.run {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                refreshMessage = message
            }
        }
        try? await Task.sleep(for: .seconds(2))
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.2)) {
                refreshMessage = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.title.bold())
            if let sleepSummary {
                Text(sleepSummary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sleepSummary: String? {
        if let sleep = sync.healthSleep {
            return "Sleep \(String(format: "%.1f", sleep.sleepHours))h\(sleep.actualWake.map { " • woke \($0)" } ?? "") • HealthKit"
        }
        if let sleep = sync.snapshot.sleep, let hours = sleep.sleepHours {
            return "Sleep \(String(format: "%.1f", hours))h\(sleep.actualWake.map { " • woke \($0)" } ?? "")"
        }
        return nil
    }

    private func refreshConfirmation(_ message: String) -> some View {
        Label(message, systemImage: message == "Refresh failed" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(message == "Refresh failed" ? .orange : .green)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var nowNextCards: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 8) {
                let current = viewModel.currentBlocks(in: sync.snapshot, now: context.date)
                currentActivitiesCard(current)

                let next = viewModel.nextBlock(in: sync.snapshot, now: context.date)
                if let next {
                    compactStatusCard(
                        title: "Next",
                        systemImage: "arrow.forward.circle",
                        value: nextActivityText(next),
                        detail: next.category
                    )
                }
            }
        }
    }

    private func activeActivityText(_ item: ScheduleItem) -> String {
        if let stop = item.stop {
            return "\(item.task) until \(stop)"
        }
        if let start = item.start {
            return "\(item.task) since \(start)"
        }
        return item.task
    }

    private func nextActivityText(_ item: ScheduleItem) -> String {
        if let start = item.start ?? item.plannedStart {
            return "\(item.task) \(start)"
        }
        return item.task
    }

    private func currentActivitiesCard(_ items: [ScheduleItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(items.count > 1 ? "Now happening" : "Now", systemImage: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("No active block")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(items.prefix(4)) { item in
                    activeActivityRow(item)
                }
                if items.count > 4 {
                    Text("+ \(items.count - 4) more")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func activeActivityRow(_ item: ScheduleItem) -> some View {
        Button {
            navigation.selectedSection = .tasks
            navigation.selectedTask = item
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(item.stop == nil ? Color.green : Color.blue)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeActivityText(item))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !item.category.isEmpty {
                        Text(item.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func compactStatusCard(title: String, systemImage: String, value: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            quickActionButton(title: "Task", subtitle: "Add to-do", systemImage: "plus.circle.fill", tint: .blue) {
                showingAddTask = true
            }
            quickActionButton(title: "Coffee", subtitle: "Caffeine", systemImage: "cup.and.saucer.fill", tint: .brown) {
                showingCaffeine = true
            }
            quickActionButton(title: "Meal", subtitle: "Food log", systemImage: "fork.knife.circle.fill", tint: .green) {
                showingFood = true
            }
            NavigationLink {
                SleepEditView()
            } label: {
                quickActionLabel(title: "Sleep", subtitle: "Night record", systemImage: "bed.double.fill", tint: .indigo)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func quickActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            quickActionLabel(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func quickActionLabel(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private var topTasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top To-Dos")
                .font(.headline)
            let tasks = Array(viewModel.sortedOpenTasks(in: sync.snapshot).prefix(5))
            if tasks.isEmpty {
                EmptyStateView(title: "No open tasks", systemImage: "checkmark.circle")
            } else {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    TaskRowView(task: task, rank: index + 1, compact: true)
                }
            }
        }
    }

    private var loggedToday: some View {
        DashboardCard {
            Text("Logged Today")
                .font(.headline)
            HStack {
                Label("\(sync.snapshot.caffeine.count)", systemImage: "cup.and.saucer")
                Label("\(sync.snapshot.food.count)", systemImage: "fork.knife")
                if let hours = sync.healthSleep?.sleepHours {
                    Label("\(hours, specifier: "%.1f")h", systemImage: "bed.double")
                } else if let hours = sync.snapshot.sleep?.sleepHours {
                    Label("\(hours, specifier: "%.1f")h", systemImage: "bed.double")
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}
