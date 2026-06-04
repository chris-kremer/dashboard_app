import Foundation

struct SyncState: Codable, Equatable {
    var lastSuccessfulSync: Date?
    var lastError: String?
    var pendingOperations: [PendingOperation]

    static let empty = SyncState(lastSuccessfulSync: nil, lastError: nil, pendingOperations: [])
}

struct PendingOperation: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case completeTask
        case startTask
        case stopTask
        case createTask
        case updateTask
        case logCaffeine
        case logFood
        case upsertSleep
    }

    let id: UUID
    let kind: Kind
    let createdAt: Date
    let payload: Data
    var retryCount: Int
    var lastError: String?

    init(kind: Kind, payload: Data, createdAt: Date = Date()) {
        self.id = UUID()
        self.kind = kind
        self.createdAt = createdAt
        self.payload = payload
        self.retryCount = 0
        self.lastError = nil
    }
}
