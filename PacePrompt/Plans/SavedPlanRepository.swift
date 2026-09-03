import Foundation

enum SavedPlanStoreSchema {
    static let currentVersion = 1
}

struct SavedPlanRecord: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let modifiedAt: Date
    let plan: WorkoutPlan
}

struct SavedPlanStore: Codable, Equatable {
    let formatVersion: Int
    let records: [SavedPlanRecord]
}

enum SavedPlanCanonicalState: Equatable {
    case empty
    case available(records: [SavedPlanRecord])
    case protectedDataUnavailable
    case readFailure
    case corruptData
    case partialWriteDetected
    case unsupportedStoreVersion(Int)
    case unsupportedPlanVersion(recordID: UUID, version: Int)
}

enum SavedPlanStagingState: Equatable {
    case absent
    case staleArtifactPresent
    case presenceUnavailable
}

struct SavedPlanRepositoryStatus: Equatable {
    let canonical: SavedPlanCanonicalState
    let staging: SavedPlanStagingState
}

enum SavedPlanMutationFailure: Error, Equatable {
    enum WriteStage: Equatable {
        case encoding
        case directoryPreparation
        case fileProtection
        case backupExclusion
        case stagingWrite
        case stagingValidation
        case synchronization
        case atomicReplacement
    }

    case blocked(SavedPlanRepositoryStatus)
    case recordNotFound(UUID)
    case writeFailed(WriteStage)
}

enum SavedPlanFileSystemError: Error {
    case protectedDataUnavailable
}

protocol SavedPlanFileSystem {
    func applicationSupportDirectory() throws -> URL
    func fileExists(at url: URL) throws -> Bool
    func createProtectedDirectory(at url: URL) throws
    func readData(at url: URL) throws -> Data
    func writeProtectedData(_ data: Data, to url: URL) throws
    func synchronizeFile(at url: URL) throws
    func applyCompleteFileProtection(to url: URL) throws
    func hasCompleteFileProtection(at url: URL) throws -> Bool
    func excludeFromBackup(_ url: URL) throws
    func isExcludedFromBackup(_ url: URL) throws -> Bool
    func atomicallyReplaceItem(at canonicalURL: URL, with stagingURL: URL) throws
}

struct FoundationSavedPlanFileSystem: SavedPlanFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func applicationSupportDirectory() throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    func fileExists(at url: URL) throws -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: url.path)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return false
        }
    }

    func createProtectedDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeProtectedData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .completeFileProtection)
    }

    func synchronizeFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func applyCompleteFileProtection(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    func hasCompleteFileProtection(at url: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.protectionKey] as? FileProtectionType) == .complete
    }

    func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

    func atomicallyReplaceItem(at canonicalURL: URL, with stagingURL: URL) throws {
        if try fileExists(at: canonicalURL) {
            _ = try fileManager.replaceItemAt(
                canonicalURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: stagingURL, to: canonicalURL)
        }
    }
}

protocol SavedPlanStoreCoding {
    func encode(_ store: SavedPlanStore) throws -> Data
    func decodeFormatVersion(from data: Data) throws -> Int
    func decodeStore(from data: Data) throws -> SavedPlanStore
}

struct SavedPlanJSONCodec: SavedPlanStoreCoding {
    func encode(_ store: SavedPlanStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(store)
    }

    func decodeFormatVersion(from data: Data) throws -> Int {
        try JSONDecoder().decode(StoreHeader.self, from: data).formatVersion
    }

    func decodeStore(from data: Data) throws -> SavedPlanStore {
        try JSONDecoder().decode(SavedPlanStore.self, from: data)
    }

    private struct StoreHeader: Decodable {
        let formatVersion: Int
    }
}

final class SavedPlanRepository {
    private enum FileName {
        static let directory = "PacePrompt"
        static let canonical = "saved-plans.json"
        static let staging = "saved-plans.json.staging"
    }

    private let fileSystem: any SavedPlanFileSystem
    private let codec: any SavedPlanStoreCoding
    private let now: () -> Date
    private let makeUUID: () -> UUID

    init(
        fileSystem: any SavedPlanFileSystem = FoundationSavedPlanFileSystem(),
        codec: any SavedPlanStoreCoding = SavedPlanJSONCodec(),
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init
    ) {
        self.fileSystem = fileSystem
        self.codec = codec
        self.now = now
        self.makeUUID = makeUUID
    }

    func list() -> SavedPlanRepositoryStatus {
        let urls: StoreURLs
        do {
            urls = try storeURLs()
        } catch {
            return SavedPlanRepositoryStatus(
                canonical: canonicalReadState(for: error),
                staging: .presenceUnavailable
            )
        }

        let staging: SavedPlanStagingState
        do {
            staging = try fileSystem.fileExists(at: urls.staging)
                ? .staleArtifactPresent
                : .absent
        } catch {
            staging = .presenceUnavailable
        }

        do {
            guard try fileSystem.fileExists(at: urls.canonical) else {
                return SavedPlanRepositoryStatus(canonical: .empty, staging: staging)
            }
        } catch {
            return SavedPlanRepositoryStatus(canonical: canonicalReadState(for: error), staging: staging)
        }

        do {
            let data = try fileSystem.readData(at: urls.canonical)
            return SavedPlanRepositoryStatus(canonical: decodeCanonical(data), staging: staging)
        } catch {
            return SavedPlanRepositoryStatus(canonical: canonicalReadState(for: error), staging: staging)
        }
    }

    @discardableResult
    func create(_ validatedPlan: WorkoutPlanValidator.ValidatedPlan) throws -> SavedPlanRecord {
        var records = try recordsForMutation()
        let timestamp = now()
        let record = SavedPlanRecord(
            id: makeUUID(),
            createdAt: timestamp,
            modifiedAt: timestamp,
            plan: validatedPlan.plan
        )
        records.append(record)
        try persist(records)
        return record
    }

    @discardableResult
    func replace(
        id: UUID,
        with validatedPlan: WorkoutPlanValidator.ValidatedPlan
    ) throws -> SavedPlanRecord {
        var records = try recordsForMutation()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw SavedPlanMutationFailure.recordNotFound(id)
        }

        let existing = records[index]
        let replacement = SavedPlanRecord(
            id: existing.id,
            createdAt: existing.createdAt,
            modifiedAt: now(),
            plan: validatedPlan.plan
        )
        records[index] = replacement
        try persist(records)
        return replacement
    }

    func delete(id: UUID) throws {
        var records = try recordsForMutation()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw SavedPlanMutationFailure.recordNotFound(id)
        }
        records.remove(at: index)
        try persist(records)
    }

    private func recordsForMutation() throws -> [SavedPlanRecord] {
        let status = list()
        guard status.staging == .absent else {
            throw SavedPlanMutationFailure.blocked(status)
        }

        switch status.canonical {
        case .empty:
            return []
        case let .available(records):
            return records
        case .protectedDataUnavailable,
             .readFailure,
             .corruptData,
             .partialWriteDetected,
             .unsupportedStoreVersion,
             .unsupportedPlanVersion:
            throw SavedPlanMutationFailure.blocked(status)
        }
    }

    private func persist(_ records: [SavedPlanRecord]) throws {
        let store = SavedPlanStore(
            formatVersion: SavedPlanStoreSchema.currentVersion,
            records: records
        )

        let encoded: Data
        do {
            encoded = try codec.encode(store)
        } catch {
            throw SavedPlanMutationFailure.writeFailed(.encoding)
        }

        let urls: StoreURLs
        do {
            urls = try storeURLs()
            try fileSystem.createProtectedDirectory(at: urls.directory)
        } catch {
            throw SavedPlanMutationFailure.writeFailed(.directoryPreparation)
        }

        try applyAndVerifyProtection(to: urls.directory)
        try applyAndVerifyBackupExclusion(to: urls.directory)

        do {
            try fileSystem.writeProtectedData(encoded, to: urls.staging)
        } catch {
            throw SavedPlanMutationFailure.writeFailed(.stagingWrite)
        }

        do {
            let stagedData = try fileSystem.readData(at: urls.staging)
            let expectedState: SavedPlanCanonicalState = records.isEmpty
                ? .empty
                : .available(records: records)
            guard decodeCanonical(stagedData) == expectedState else {
                throw SavedPlanMutationFailure.writeFailed(.stagingValidation)
            }
        } catch let failure as SavedPlanMutationFailure {
            throw failure
        } catch {
            throw SavedPlanMutationFailure.writeFailed(.stagingValidation)
        }

        do {
            try fileSystem.synchronizeFile(at: urls.staging)
        } catch {
            throw SavedPlanMutationFailure.writeFailed(.synchronization)
        }

        try applyAndVerifyProtection(to: urls.staging)
        try applyAndVerifyBackupExclusion(to: urls.staging)

        do {
            try fileSystem.atomicallyReplaceItem(at: urls.canonical, with: urls.staging)
        } catch {
            throw SavedPlanMutationFailure.writeFailed(.atomicReplacement)
        }
    }

    private func applyAndVerifyProtection(to url: URL) throws {
        do {
            try fileSystem.applyCompleteFileProtection(to: url)
            guard try fileSystem.hasCompleteFileProtection(at: url) else {
                throw SavedPlanMutationFailure.writeFailed(.fileProtection)
            }
        } catch let failure as SavedPlanMutationFailure {
            throw failure
        } catch {
            throw SavedPlanMutationFailure.writeFailed(.fileProtection)
        }
    }

    private func applyAndVerifyBackupExclusion(to url: URL) throws {
        do {
            try fileSystem.excludeFromBackup(url)
            guard try fileSystem.isExcludedFromBackup(url) else {
                throw SavedPlanMutationFailure.writeFailed(.backupExclusion)
            }
        } catch let failure as SavedPlanMutationFailure {
            throw failure
        } catch {
            throw SavedPlanMutationFailure.writeFailed(.backupExclusion)
        }
    }

    private func decodeCanonical(_ data: Data) -> SavedPlanCanonicalState {
        let formatVersion: Int
        do {
            formatVersion = try codec.decodeFormatVersion(from: data)
        } catch {
            return appearsTruncatedJSON(data) ? .partialWriteDetected : .corruptData
        }

        guard formatVersion == SavedPlanStoreSchema.currentVersion else {
            return .unsupportedStoreVersion(formatVersion)
        }

        guard hasExpectedStoreShape(data) else {
            return .corruptData
        }

        if let unsupported = unsupportedNestedPlanVersion(in: data) {
            return .unsupportedPlanVersion(
                recordID: unsupported.recordID,
                version: unsupported.version
            )
        }

        let store: SavedPlanStore
        do {
            store = try codec.decodeStore(from: data)
        } catch {
            return appearsTruncatedJSON(data) ? .partialWriteDetected : .corruptData
        }

        if let unsupported = store.records.first(where: {
            $0.plan.schemaVersion != WorkoutPlanSchema.currentVersion
        }) {
            return .unsupportedPlanVersion(
                recordID: unsupported.id,
                version: unsupported.plan.schemaVersion
            )
        }

        guard recordsAreStructurallyValid(store.records) else {
            return .corruptData
        }

        return store.records.isEmpty ? .empty : .available(records: store.records)
    }

    private func hasExpectedStoreShape(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any],
              Set(envelope.keys) == ["formatVersion", "records"],
              let records = envelope["records"] as? [[String: Any]] else {
            return false
        }

        let recordKeys: Set<String> = ["id", "createdAt", "modifiedAt", "plan"]
        return records.allSatisfy { Set($0.keys) == recordKeys }
    }

    private func unsupportedNestedPlanVersion(in data: Data) -> (recordID: UUID, version: Int)? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any],
              let records = envelope["records"] as? [[String: Any]] else {
            return nil
        }

        for record in records {
            guard let identifierText = record["id"] as? String,
                  let identifier = UUID(uuidString: identifierText),
                  let plan = record["plan"] as? [String: Any],
                  let version = plan["schemaVersion"] as? Int else {
                continue
            }
            if version != WorkoutPlanSchema.currentVersion {
                return (identifier, version)
            }
        }
        return nil
    }

    private func recordsAreStructurallyValid(_ records: [SavedPlanRecord]) -> Bool {
        var identifiers = Set<UUID>()
        for record in records {
            guard identifiers.insert(record.id).inserted,
                  record.createdAt <= record.modifiedAt,
                  WorkoutPlanValidator.structuralIssues(in: record.plan).isEmpty else {
                return false
            }
        }
        return true
    }

    private func appearsTruncatedJSON(_ data: Data) -> Bool {
        let bytes = Array(data)
        guard let first = bytes.first(where: { !Self.isJSONWhitespace($0) }) else {
            return true
        }
        guard first == UInt8(ascii: "{") || first == UInt8(ascii: "[") else {
            return false
        }

        var depth = 0
        var inString = false
        var escaped = false
        for byte in bytes {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }

            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if depth < 0 { return false }
            default:
                break
            }
        }
        return inString || depth > 0
    }

    private func isProtectedDataError(_ error: Error) -> Bool {
        if let fileSystemError = error as? SavedPlanFileSystemError,
           case .protectedDataUnavailable = fileSystemError {
            return true
        }

        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain
            && cocoaError.code == CocoaError.fileReadNoPermission.rawValue
    }

    private func canonicalReadState(for error: Error) -> SavedPlanCanonicalState {
        isProtectedDataError(error) ? .protectedDataUnavailable : .readFailure
    }

    private func storeURLs() throws -> StoreURLs {
        let applicationSupport = try fileSystem.applicationSupportDirectory()
        let directory = applicationSupport.appendingPathComponent(FileName.directory, isDirectory: true)
        return StoreURLs(
            directory: directory,
            canonical: directory.appendingPathComponent(FileName.canonical, isDirectory: false),
            staging: directory.appendingPathComponent(FileName.staging, isDirectory: false)
        )
    }

    private struct StoreURLs {
        let directory: URL
        let canonical: URL
        let staging: URL
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}
