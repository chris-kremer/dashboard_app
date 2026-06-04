import SwiftUI

struct TimelineView: View {
    @Environment(SyncController.self) private var sync

    private var blocks: [ScheduleItem] {
        sync.snapshot.schedule
            .filter { $0.start != nil || $0.stop != nil }
            .sorted { ($0.start ?? "") < ($1.start ?? "") }
    }

    var body: some View {
        NavigationStack {
            List {
                if blocks.isEmpty {
                    EmptyStateView(title: "No timeline blocks", systemImage: "calendar")
                } else {
                    ForEach(blocks) { block in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .trailing) {
                                Text(block.start ?? "--:--")
                                    .font(.headline.monospacedDigit())
                                Text(block.stop ?? "")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 4)
                                .clipShape(Capsule())
                            VStack(alignment: .leading) {
                                Text(block.task)
                                    .font(.headline)
                                Text(block.category)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Timeline")
        }
    }
}
