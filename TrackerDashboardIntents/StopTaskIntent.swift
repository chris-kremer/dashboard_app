import AppIntents
import Foundation

struct StopTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Task"
    static var description = IntentDescription("Pauses the task at the current time so it can be resumed later.")

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
