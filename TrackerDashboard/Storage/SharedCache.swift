import Foundation

final class SharedCache {
    static let appGroupIdentifier = "group.com.chriskremer.tracker"
    static let shared = SharedCache()

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadSnapshot() -> TrackerSnapshot? {
        load(TrackerSnapshot.self, from: "snapshot.json")
    }

    func saveSnapshot(_ snapshot: TrackerSnapshot) throws {
        try save(snapshot, to: "snapshot.json")
    }

    func loadSyncState() -> SyncState {
        load(SyncState.self, from: "sync-state.json") ?? .empty
    }

    func loadHealthSleep() -> HealthSleepEntry? {
        load(HealthSleepEntry.self, from: "health-sleep.json")
    }

    func saveSyncState(_ state: SyncState) throws {
        try save(state, to: "sync-state.json")
    }

    func saveHealthSleep(_ sleep: HealthSleepEntry) throws {
        try save(sleep, to: "health-sleep.json")
    }

    func upsertTask(_ task: ScheduleItem) throws {
        var snapshot = loadSnapshot() ?? .empty
        snapshot.schedule.removeAll { $0.rowNumber == task.rowNumber }
        snapshot.schedule.append(task)
        snapshot.openTasks.removeAll { $0.rowNumber == task.rowNumber }
        if task.isOpenDisplayTask {
            snapshot.openTasks.append(task)
        }
        snapshot.openTasks.sort { ($0.adjustedPriority ?? -1, $0.priority ?? -1) > ($1.adjustedPriority ?? -1, $1.priority ?? -1) }
        try saveSnapshot(snapshot)
    }

    func appendPendingOperation(_ operation: PendingOperation) throws {
        var state = loadSyncState()
        state.pendingOperations.append(operation)
        state.lastError = operation.lastError
        try saveSyncState(state)
    }

    private func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        guard let url = fileURL(fileName), fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try TrackerJSON.decoder.decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to fileName: String) throws {
        guard let url = fileURL(fileName) else {
            return
        }
        let directoryURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let temporaryURL = directoryURL.appendingPathComponent(".\(fileName).tmp-\(UUID().uuidString)")
        let data = try TrackerJSON.encoder.encode(value)
        try data.write(to: temporaryURL, options: [.atomic])
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: temporaryURL, to: url)
    }

    private func fileURL(_ fileName: String) -> URL? {
        if let appGroupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            return appGroupURL.appendingPathComponent(fileName)
        }

        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportURL
            .appendingPathComponent("TrackerDashboard", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
