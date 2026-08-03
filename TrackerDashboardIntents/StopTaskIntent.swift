import AppIntents
import Foundation

struct StopTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Task"
    static var description = IntentDescription("Writes the current time to the task stop column.")

    @Parameter(title: "Row ID")
    var rowId: String

    init() {}

    init(rowId: String) {
        self.rowId = rowId
    }

    func perform() async throws -> some IntentResult {
        let patch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            delay: nil,
            start: nil,
            stop: Date.trackerTimeFormatter.string(from: Date()),
            status: .inProgress
        )
        try await TaskIntentHelpers.patch(rowId: rowId, patch: patch, kind: .stopTask)
        return .result()
    }
}

#if os(iOS)
extension StopTaskIntent: LiveActivityIntent {}
#endif
