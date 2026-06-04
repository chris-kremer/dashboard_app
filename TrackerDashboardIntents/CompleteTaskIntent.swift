import AppIntents
import Foundation

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Marks a tracker task done in the central Google Sheet.")

    @Parameter(title: "Row ID")
    var rowId: String

    init() {}

    init(rowId: String) {
        self.rowId = rowId
    }

    func perform() async throws -> some IntentResult {
        try await TaskIntentHelpers.complete(rowId: rowId, source: "widget")
        return .result()
    }
}
