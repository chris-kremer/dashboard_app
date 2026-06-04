import SwiftUI

struct TodayView: View {
    @Environment(SyncController.self) private var sync
    @State private var viewModel = TodayViewModel()
    @State private var showingAddTask = false
    @State private var showingCaffeine = false
    @State private var showingFood = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nowNextCards
                    quickActions
                    topTasks
                    loggedToday
                }
                .padding()
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await sync.refresh() }
                    } label: {
                        Image(systemName: sync.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $showingAddTask) { AddTaskView() }
            .sheet(isPresented: $showingCaffeine) { LogCaffeineView() }
            .sheet(isPresented: $showingFood) { LogFoodView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.title.bold())
            if let sleep = sync.snapshot.sleep, let hours = sleep.sleepHours {
                Text("Sleep \(hours, specifier: "%.1f")h\(sleep.actualWake.map { " • woke \($0)" } ?? "")")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nowNextCards: some View {
        VStack(spacing: 8) {
            let current = viewModel.currentBlock(in: sync.snapshot)
            compactStatusCard(
                title: "Now",
                systemImage: "clock",
                value: current.map { "\($0.task) until \($0.stop ?? "")" } ?? "No active block",
                detail: current?.category
            )

            let next = viewModel.nextBlock(in: sync.snapshot)
            compactStatusCard(
                title: "Next",
                systemImage: "arrow.forward.circle",
                value: next.map { "\($0.task) \($0.start ?? "")" } ?? "No upcoming block",
                detail: next?.category
            )
        }
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
                ForEach(tasks) { task in
                    TaskRowView(task: task, compact: true)
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
                if let hours = sync.snapshot.sleep?.sleepHours {
                    Label("\(hours, specifier: "%.1f")h", systemImage: "bed.double")
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}
