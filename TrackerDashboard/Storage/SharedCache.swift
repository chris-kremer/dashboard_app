import Foundation

final class SharedCache {
    static let appGroupIdentifier = "group.com.chriskremer.tracker"
    static let shared = SharedCache()

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadSnapshot() -> TrackerSnapshot? {
        load(TrackerSnapshot.self, from: "snapshot.json") ?? loadFromDefaults(TrackerSnapshot.self, key: DefaultsKey.snapshot)
    }

    func saveSnapshot(_ snapshot: TrackerSnapshot) throws {
        try save(snapshot, to: "snapshot.json")
        saveToDefaults(snapshot, key: DefaultsKey.snapshot)
    }

    func loadSyncState() -> SyncState {
        load(SyncState.self, from: "sync-state.json") ?? loadFromDefaults(SyncState.self, key: DefaultsKey.syncState) ?? .empty
    }

    func saveSyncState(_ state: SyncState) throws {
        try save(state, to: "sync-state.json")
        saveToDefaults(state, key: DefaultsKey.syncState)
    }

    func upsertTask(_ task: ScheduleItem) throws {
        var snapshot = loadSnapshot() ?? .empty
        snapshot.schedule.removeAll { $0.rowNumber == task.rowNumber }
        snapshot.schedule.append(task)
        snapshot.openTasks.removeAll { $0.rowNumber == task.rowNumber }
        if task.status != .done && task.status != .cancelled {
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
            saveToDefaults(value, key: fileName == "snapshot.json" ? DefaultsKey.snapshot : DefaultsKey.syncState)
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
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    private func loadFromDefaults<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else {
            return nil
        }
        return try? TrackerJSON.decoder.decode(T.self, from: data)
    }

    private func saveToDefaults<T: Encodable>(_ value: T, key: String) {
        guard let data = try? TrackerJSON.encoder.encode(value) else {
            return
        }
        defaults?.set(data, forKey: key)
    }

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupIdentifier)
    }

    private enum DefaultsKey {
        static let snapshot = "shared-cache.snapshot"
        static let syncState = "shared-cache.sync-state"
    }
}
