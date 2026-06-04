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
        if let task = TaskIntentHelpers.task(rowId: rowId),
           task.start != nil,
           task.stop != nil {
            try await TaskIntentHelpers.continueTaskFromLoggedInterval(task)
            return .result()
        }

        let patch = TaskPatchRequest(
            priority: nil,
            estimateMinutes: nil,
            comment: nil,
            start: Date.trackerTimeFormatter.string(from: Date()),
            stop: nil,
            status: .inProgress,
            clearsStop: true
        )
        try await TaskIntentHelpers.patch(rowId: rowId, patch: patch, kind: .startTask)
        return .result()
    }
}
