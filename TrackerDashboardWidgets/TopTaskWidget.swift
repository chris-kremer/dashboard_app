import SwiftUI
import WidgetKit

struct TopTaskWidget: Widget {
    let kind = "TopTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrackerWidgetProvider()) { entry in
            TopTaskWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Top Task")
        .description("Shows the top open tracker task.")
        .supportedFamilies([.systemSmall])
    }
}

struct TopTaskWidgetView: View {
    let entry: TrackerWidgetEntry

    private var task: ScheduleItem? {
        entry.snapshot.openTasks.sorted { ($0.adjustedPriority ?? -1) > ($1.adjustedPriority ?? -1) }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Top Task", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let task {
                Text(task.task)
                    .font(.headline)
                    .lineLimit(3)
                Spacer()
                HStack {
                    Text(task.adjustedPriority.map { "AP \($0)" } ?? "No AP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(intent: CompleteTaskIntent(rowId: task.id)) {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Spacer()
                Text("No open tasks")
                    .font(.headline)
                Spacer()
            }
        }
        .padding()
    }
}
