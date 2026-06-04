import AppIntents
import Foundation

struct StartTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Task"
    static var description = IntentDescription("Writes the current time to the task start column.")

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
            start: Date.trackerTimeFormatter.string(from: Date()),
            stop: nil,
            status: .inProgress
        )
        try await TaskIntentHelpers.patch(rowId: rowId, patch: patch, kind: .startTask)
        return .result()
    }
}
