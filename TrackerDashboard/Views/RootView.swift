import SwiftUI

struct RootView: View {
    @State private var navigation = AppNavigation()
    @State private var celebration: RewardCelebration?

    var body: some View {
        TabView(selection: $navigation.selectedSection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(TrackerSection.today)

            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(TrackerSection.tasks)

            TimelineView()
                .tabItem { Label("Timeline", systemImage: "calendar.day.timeline.left") }
                .tag(TrackerSection.timeline)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
                .tag(TrackerSection.insights)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(TrackerSection.settings)
        }
        .environment(navigation)
        .overlay(alignment: .top) {
            if let celebration {
                PositiveReinforcementOverlay(celebration: celebration)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: celebration?.id)
        .onReceive(NotificationCenter.default.publisher(for: .positiveReinforcement)) { notification in
            let source = notification.userInfo?["source"] as? String
            let next = RewardCelebration(source: source)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                celebration = next
            }
            Task {
                try? await Task.sleep(for: .seconds(3.2))
                guard celebration?.id == next.id else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    celebration = nil
                }
            }
        }
#if os(iOS)
        .onAppear {
            openCoverageReviewIfRequested()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCoverageGaps)) { _ in
            openCoverageReviewIfRequested()
        }
#endif
    }

#if os(iOS)
    private func openCoverageReviewIfRequested() {
        guard NudgeNotifications.consumeCoverageReviewRequest() else { return }
        navigation.selectedSection = .insights
        navigation.showingCoverageGaps = true
    }
#endif
}

private struct RewardCelebration: Equatable {
    let id = UUID()
    let source: String?
}

private struct PositiveReinforcementOverlay: View {
    let celebration: RewardCelebration
    @State private var expanded = false

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color.mint : Color.yellow)
                    .frame(width: index.isMultiple(of: 3) ? 8 : 5)
                    .offset(
                        x: expanded ? CGFloat(cos(Double(index) * .pi / 7)) * 118 : 0,
                        y: expanded ? CGFloat(sin(Double(index) * .pi / 7)) * 52 : 10
                    )
                    .opacity(expanded ? 0 : 0.9)
            }

            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(expanded ? 10 : -16))
                    .scaleEffect(expanded ? 1.08 : 0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Good choice.")
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)

                Spacer(minLength: 0)

                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [.green, .mint.opacity(0.9)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .shadow(color: .green.opacity(0.28), radius: 18, y: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) {
                expanded = true
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Good choice. You closed the distraction.")
    }

    private var detail: String {
        switch celebration.source {
        case "youtube": "You closed YouTube and broke the loop."
        case "x": "You closed X and broke the loop."
        default: "You broke the loop and took your attention back."
        }
    }
}
