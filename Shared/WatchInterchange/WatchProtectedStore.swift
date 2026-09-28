import Foundation

// One atomically replaced journal, protected on disk and excluded from backup.
// A leftover staging file is uncertainty, never permission to recreate a workout.
struct WatchProtectedFile {
    let url: URL
    private var staging: URL { url.appendingPathExtension("staging") }
    func read() throws -> Data? {
        let fm = FileManager.default
        if fm.fileExists(atPath: staging.path) { throw WatchStoreError.ambiguous }
        do { return try Data(contentsOf: url) }
        catch let e as NSError where e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoSuchFileError { return nil }
    }
    func write(_ data: Data) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: staging.path) { throw WatchStoreError.ambiguous }
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var mutableDirectory = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try mutableDirectory.setResourceValues(values)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        try data.write(to: staging, options: .completeFileProtection)
        var mutableStaging = staging; try mutableStaging.setResourceValues(values)
        let handle = try FileHandle(forWritingTo: staging); try handle.synchronize(); try handle.close()
        guard try Data(contentsOf: staging) == data else { throw WatchStoreError.ambiguous }
        if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: staging) }
        else { try fm.moveItem(at: staging, to: url) }
        guard try Data(contentsOf: url) == data,
              try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else { throw WatchStoreError.ambiguous }
        // Simulator filesystems do not expose NSFileProtectionKey. This is not
        // evidence of device encryption; device builds fail closed on readback.
        #if !targetEnvironment(simulator)
        guard (try fm.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType) == .complete else { throw WatchStoreError.ambiguous }
        #endif
    }
    static func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PacePromptWatchOwnership", isDirectory: true)
    }
}

@MainActor final class ProtectedWatchJournal: WatchJournalStore {
    private let directory: () throws -> URL
    init(directory: @escaping () throws -> URL = WatchProtectedFile.directory) { self.directory = directory }
    func load() throws -> WatchWorkoutJournal? {
        let file = WatchProtectedFile(url: try directory().appendingPathComponent("watch-journal-v1.json"))
        guard let data = try file.read() else { return nil }
        guard data.count <= 65_536 else { throw WatchStoreError.ambiguous }
        let value = try JSONDecoder().decode(WatchWorkoutJournal.self, from: data)
        guard value.formatVersion == 1, ["indoorWalking", "indoorRunning"].contains(value.activity),
              value.manifest.map({ (try? WatchWire.encode($0)) != nil && $0.summaryID == value.summaryID }) ?? true,
              value.summaryID.map({ UUID(uuidString: $0)?.uuidString.lowercased() == $0 }) ?? true else { throw WatchStoreError.ambiguous }
        return value
    }
    func save(_ value: WatchWorkoutJournal) throws {
        try WatchProtectedFile(url: try directory().appendingPathComponent("watch-journal-v1.json")).write(JSONEncoder().encode(value))
    }
}

// Immutable reservation files outlive all transport/results. No deletion API exists in v1.
struct WatchOwnershipStore {
    private struct Reservation: Codable, Equatable { let schemaVersion: Int; let summaryID: String; let owner: String }
    var directory: () throws -> URL = WatchProtectedFile.directory
    func reserve(_ id: UUID) throws {
        let value = Reservation(schemaVersion: 1, summaryID: id.uuidString.lowercased(), owner: "watchPrimary")
        let file = WatchProtectedFile(url: try directory().appendingPathComponent(value.summaryID + ".json"))
        if let data = try file.read() {
            guard try JSONDecoder().decode(Reservation.self, from: data) == value else { throw WatchStoreError.ambiguous }
            throw WatchStoreError.ambiguous // A previously reserved identity cannot start a new primary.
        }
        try file.write(JSONEncoder().encode(value))
    }
    func phoneSaveAllowed(_ id: UUID) -> Bool {
        do { return try WatchProtectedFile(url: directory().appendingPathComponent(id.uuidString.lowercased() + ".json")).read() == nil }
        catch { return false }
    }
}
