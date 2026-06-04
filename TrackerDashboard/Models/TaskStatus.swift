import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case open
    case inProgress = "in_progress"
    case done
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .open: "Open"
        case .inProgress: "In Progress"
        case .done: "Done"
        case .cancelled: "Cancelled"
        }
    }
}
