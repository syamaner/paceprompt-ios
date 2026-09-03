import Foundation
import XCTest
@testable import PacePrompt

final class SavedPlanRepositoryTests: XCTestCase {
    func testStoreCodecRoundTripsOnlyVersionedRecordsAndCompletePlansInOrder() throws {
        let codec = SavedPlanJSONCodec()
        let records = [
            record(id: uuid(1), name: "Synthetic first", createdAt: date(10), modifiedAt: date(20)),
            record(id: uuid(2), name: "Synthetic second", createdAt: date(30), modifiedAt: date(30)),
        ]
        let store = SavedPlanStore(formatVersion: 1, records: records)

        let data = try codec.encode(store)
        let decoded = try codec.decodeStore(from: data)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedRecords = try XCTUnwrap(root["records"] as? [[String: Any]])

        XCTAssertEqual(decoded, store)
        XCTAssertEqual(Set(root.keys), ["formatVersion", "records"])
        XCTAssertEqual(Set(encodedRecords[0].keys), ["id", "createdAt", "modifiedAt", "plan"])
        XCTAssertEqual(decoded.records.map(\.id), [uuid(1), uuid(2)])
        XCTAssertEqual(decoded.records[0].plan.steps.map(\.kind), [.warmUp, .interval, .recovery, .coolDown])
        XCTAssertEqual(decoded.records[0].plan.steps[1].targetSpeed.value, decimal("10.0"))
    }

    func testCreateUsesInjectedIdentityAndClockAndWritesProtectedAtomicStore() throws {
        let fileSystem = MemorySavedPlanFileSystem()
        let expectedID = uuid(7)
        let expectedDate = date(70)
        let repository = SavedPlanRepository(
            fileSystem: fileSystem,
            now: { expectedDate },
            makeUUID: { expectedID }
        )

        let created = try repository.create(validatedPlan(name: "Synthetic created"))

        XCTAssertEqual(created.id, expectedID)
        XCTAssertEqual(created.createdAt, expectedDate)
        XCTAssertEqual(created.modifiedAt, expectedDate)
        XCTAssertEqual(
            repository.list(),
            .init(canonical: .available(records: [created]), staging: .absent)
        )
        XCTAssertEqual(
            fileSystem.mutationOperations,
            [
                .createDirectory,
                .applyDirectoryProtection,
                .verifyDirectoryProtection,
                .applyDirectoryBackupExclusion,
                .verifyDirectoryBackupExclusion,
                .writeStaging,
                .readStaging,
                .synchronizeStaging,
                .applyStagingProtection,
                .verifyStagingProtection,
                .applyStagingBackupExclusion,
                .verifyStagingBackupExclusion,
                .atomicReplacement,
            ]
        )
    }

    func testCreateListReplaceAndDeletePreserveOrderAndLifecycleMetadata() throws {
        let fileSystem = MemorySavedPlanFileSystem()
        let identities = ValueSequence([uuid(1), uuid(2)])
        let timestamps = ValueSequence([date(10), date(20), date(30)])
        let repository = SavedPlanRepository(
            fileSystem: fileSystem,
            now: { timestamps.next() },
            makeUUID: { identities.next() }
        )

        let first = try repository.create(validatedPlan(name: "Synthetic first"))
        let second = try repository.create(validatedPlan(name: "Synthetic second"))
        let replacementPlan = plan(name: "Synthetic replacement", intervalSpeed: "11.0")
        let replacement = try repository.replace(
            id: first.id,
            with: validatedPlan(replacementPlan)
        )

        XCTAssertEqual(replacement.id, first.id)
        XCTAssertEqual(replacement.createdAt, first.createdAt)
        XCTAssertEqual(replacement.modifiedAt, date(30))
        XCTAssertEqual(replacement.plan, replacementPlan)
        XCTAssertEqual(availableRecords(repository).map(\.id), [first.id, second.id])
        XCTAssertEqual(availableRecords(repository).map(\.plan.suggestedName), ["Synthetic replacement", "Synthetic second"])

        try repository.delete(id: first.id)
        XCTAssertEqual(availableRecords(repository), [second])
        try repository.delete(id: second.id)
        XCTAssertEqual(repository.list(), .init(canonical: .empty, staging: .absent))
    }

    func testInvalidPlanCannotProduceTheValidatedBoundaryRequiredByCreate() {
        let fileSystem = MemorySavedPlanFileSystem()
        let repository = SavedPlanRepository(fileSystem: fileSystem)
        let invalid = plan(name: "   ")

        let validation = WorkoutPlanValidator.validate(invalid, against: capabilities())

        guard case .failure = validation else {
            return XCTFail("An invalid plan unexpectedly produced a ValidatedPlan")
        }
        XCTAssertEqual(repository.list(), .init(canonical: .empty, staging: .absent))
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testMissingCanonicalFileIsTheOnlyEmptyState() {
        let repository = SavedPlanRepository(fileSystem: MemorySavedPlanFileSystem())

        XCTAssertEqual(repository.list(), .init(canonical: .empty, staging: .absent))
    }

    func testProtectedDataAndOrdinaryReadFailuresRemainDistinct() throws {
        let protectedFileSystem = try seededFileSystem(records: [record()])
        protectedFileSystem.failure = .protectedCanonicalRead
        let readFailureFileSystem = try seededFileSystem(records: [record()])
        readFailureFileSystem.failure = .canonicalRead

        XCTAssertEqual(
            SavedPlanRepository(fileSystem: protectedFileSystem).list().canonical,
            .protectedDataUnavailable
        )
        XCTAssertEqual(
            SavedPlanRepository(fileSystem: readFailureFileSystem).list().canonical,
            .readFailure
        )
    }

    func testCorruptAndStructurallyInvalidCanonicalDataBlockMutation() throws {
        let corruptFileSystem = MemorySavedPlanFileSystem()
        corruptFileSystem.files[corruptFileSystem.canonicalURL] = Data(#"{"formatVersion":1,"records":!}"#.utf8)
        let invalidFileSystem = try seededFileSystem(
            records: [record(createdAt: date(20), modifiedAt: date(10))]
        )
        let duplicateFileSystem = try seededFileSystem(
            records: [record(id: uuid(1)), record(id: uuid(1), name: "Synthetic duplicate")]
        )

        XCTAssertEqual(SavedPlanRepository(fileSystem: corruptFileSystem).list().canonical, .corruptData)
        XCTAssertEqual(SavedPlanRepository(fileSystem: invalidFileSystem).list().canonical, .corruptData)
        XCTAssertEqual(SavedPlanRepository(fileSystem: duplicateFileSystem).list().canonical, .corruptData)

        XCTAssertThrowsError(try SavedPlanRepository(fileSystem: invalidFileSystem).create(validatedPlan())) { error in
            guard case SavedPlanMutationFailure.blocked = error else {
                return XCTFail("Expected invalid canonical data to block mutation, got \(error)")
            }
        }
    }

    func testUnexpectedStoreOrRecordFieldsAreNotSilentlyIgnored() throws {
        let storeFieldFileSystem = MemorySavedPlanFileSystem()
        storeFieldFileSystem.files[storeFieldFileSystem.canonicalURL] = Data(
            #"{"formatVersion":1,"records":[],"futureField":true}"#.utf8
        )
        let recordFieldFileSystem = try seededFileSystem(records: [record()])
        let encoded = try XCTUnwrap(recordFieldFileSystem.files[recordFieldFileSystem.canonicalURL])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var records = try XCTUnwrap(object["records"] as? [[String: Any]])
        records[0]["duplicatedName"] = "Must not be accepted"
        object["records"] = records
        recordFieldFileSystem.files[recordFieldFileSystem.canonicalURL] = try JSONSerialization.data(withJSONObject: object)

        XCTAssertEqual(SavedPlanRepository(fileSystem: storeFieldFileSystem).list().canonical, .corruptData)
        XCTAssertEqual(SavedPlanRepository(fileSystem: recordFieldFileSystem).list().canonical, .corruptData)
    }

    func testStructurallyInvalidNestedPlanIsCorruptWithoutCapabilityReinterpretation() throws {
        let invalidPlan = plan(name: " ")
        let fileSystem = try seededFileSystem(records: [record(plan: invalidPlan)])

        XCTAssertEqual(SavedPlanRepository(fileSystem: fileSystem).list().canonical, .corruptData)
    }

    func testUnsupportedStoreAndNestedPlanVersionsRemainDistinct() throws {
        let storeFileSystem = try seededFileSystem(records: [record()], formatVersion: 2)
        let unsupportedPlan = WorkoutPlan(
            schemaVersion: 9,
            suggestedName: "Synthetic future plan",
            activity: .indoorRunning,
            steps: plan().steps
        )
        let planFileSystem = try seededFileSystem(
            records: [record(id: uuid(9), plan: unsupportedPlan)]
        )

        XCTAssertEqual(
            SavedPlanRepository(fileSystem: storeFileSystem).list().canonical,
            .unsupportedStoreVersion(2)
        )
        XCTAssertEqual(
            SavedPlanRepository(fileSystem: planFileSystem).list().canonical,
            .unsupportedPlanVersion(recordID: uuid(9), version: 9)
        )
    }

    func testNestedVersionIsRejectedBeforeFuturePlanFieldsAreDecoded() throws {
        let fileSystem = MemorySavedPlanFileSystem()
        let json = #"""
        {
          "formatVersion": 1,
          "records": [{
            "id": "00000000-0000-0000-0000-000000000009",
            "createdAt": 10,
            "modifiedAt": 10,
            "plan": {
              "schemaVersion": 9,
              "suggestedName": "Synthetic future plan",
              "activity": "futureActivity",
              "steps": []
            }
          }]
        }
        """#
        fileSystem.files[fileSystem.canonicalURL] = Data(json.utf8)

        XCTAssertEqual(
            SavedPlanRepository(fileSystem: fileSystem).list().canonical,
            .unsupportedPlanVersion(recordID: uuid(9), version: 9)
        )
    }

    func testPartialCanonicalAndOrphanedStagingAreNotEmpty() throws {
        let partialFileSystem = MemorySavedPlanFileSystem()
        partialFileSystem.files[partialFileSystem.canonicalURL] = Data(#"{"formatVersion":1,"records":["#.utf8)
        let orphanedFileSystem = MemorySavedPlanFileSystem()
        orphanedFileSystem.files[orphanedFileSystem.stagingURL] = Data(#"{"incomplete":true"#.utf8)

        XCTAssertEqual(
            SavedPlanRepository(fileSystem: partialFileSystem).list(),
            .init(canonical: .partialWriteDetected, staging: .absent)
        )
        let orphanedStatus = SavedPlanRepository(fileSystem: orphanedFileSystem).list()
        XCTAssertEqual(orphanedStatus, .init(canonical: .empty, staging: .staleArtifactPresent))
        XCTAssertThrowsError(try SavedPlanRepository(fileSystem: orphanedFileSystem).create(validatedPlan())) { error in
            XCTAssertEqual(error as? SavedPlanMutationFailure, .blocked(orphanedStatus))
        }
    }

    func testValidCanonicalRemainsAuthoritativeButStaleStagingBlocksMutation() throws {
        let existing = record()
        let fileSystem = try seededFileSystem(records: [existing])
        let originalBytes = try XCTUnwrap(fileSystem.files[fileSystem.canonicalURL])
        fileSystem.files[fileSystem.stagingURL] = Data("stale".utf8)
        let repository = SavedPlanRepository(fileSystem: fileSystem)

        let status = repository.list()

        XCTAssertEqual(status.canonical, .available(records: [existing]))
        XCTAssertEqual(status.staging, .staleArtifactPresent)
        XCTAssertThrowsError(try repository.delete(id: existing.id)) { error in
            XCTAssertEqual(error as? SavedPlanMutationFailure, .blocked(status))
        }
        XCTAssertEqual(fileSystem.files[fileSystem.canonicalURL], originalBytes)
        XCTAssertEqual(fileSystem.files[fileSystem.stagingURL], Data("stale".utf8))
    }

    func testUnavailableStagingPresenceKeepsCanonicalReadableAndBlocksMutation() throws {
        let existing = record()
        let fileSystem = try seededFileSystem(records: [existing])
        fileSystem.failure = .stagingPresence
        let repository = SavedPlanRepository(fileSystem: fileSystem)

        let status = repository.list()

        XCTAssertEqual(status.canonical, .available(records: [existing]))
        XCTAssertEqual(status.staging, .presenceUnavailable)
        XCTAssertThrowsError(try repository.delete(id: existing.id)) { error in
            XCTAssertEqual(error as? SavedPlanMutationFailure, .blocked(status))
        }
    }

    func testMissingReplacementOrDeletionRecordDoesNotWrite() throws {
        let existing = record()
        let fileSystem = try seededFileSystem(records: [existing])
        let repository = SavedPlanRepository(fileSystem: fileSystem)
        let originalBytes = try XCTUnwrap(fileSystem.files[fileSystem.canonicalURL])

        XCTAssertThrowsError(try repository.replace(id: uuid(99), with: validatedPlan())) { error in
            XCTAssertEqual(error as? SavedPlanMutationFailure, .recordNotFound(uuid(99)))
        }
        XCTAssertThrowsError(try repository.delete(id: uuid(99))) { error in
            XCTAssertEqual(error as? SavedPlanMutationFailure, .recordNotFound(uuid(99)))
        }
        XCTAssertEqual(fileSystem.files[fileSystem.canonicalURL], originalBytes)
        XCTAssertFalse(fileSystem.files.keys.contains(fileSystem.stagingURL))
    }

    func testEveryWritePipelineFailurePreservesPreviousCanonicalBytes() throws {
        let scenarios: [(MemorySavedPlanFileSystem.Failure, SavedPlanMutationFailure.WriteStage)] = [
            (.directoryPreparation, .directoryPreparation),
            (.applyDirectoryProtection, .fileProtection),
            (.verifyDirectoryProtection, .fileProtection),
            (.applyDirectoryBackupExclusion, .backupExclusion),
            (.verifyDirectoryBackupExclusion, .backupExclusion),
            (.stagingWrite, .stagingWrite),
            (.stagingValidation, .stagingValidation),
            (.synchronization, .synchronization),
            (.applyStagingProtection, .fileProtection),
            (.verifyStagingProtection, .fileProtection),
            (.applyStagingBackupExclusion, .backupExclusion),
            (.verifyStagingBackupExclusion, .backupExclusion),
            (.atomicReplacement, .atomicReplacement),
        ]

        for (failure, expectedStage) in scenarios {
            let existing = record()
            let fileSystem = try seededFileSystem(records: [existing])
            let originalBytes = try XCTUnwrap(fileSystem.files[fileSystem.canonicalURL])
            fileSystem.failure = failure
            let repository = SavedPlanRepository(fileSystem: fileSystem, now: { self.date(50) })

            XCTAssertThrowsError(
                try repository.replace(id: existing.id, with: validatedPlan(name: "Synthetic edited")),
                "Expected \(failure) to fail"
            ) { error in
                XCTAssertEqual(error as? SavedPlanMutationFailure, .writeFailed(expectedStage))
            }
            XCTAssertEqual(
                fileSystem.files[fileSystem.canonicalURL],
                originalBytes,
                "Canonical bytes changed after \(failure)"
            )
        }
    }

    func testEncodingFailurePreservesPreviousCanonicalAndCreatesNoStagingFile() throws {
        let existing = record()
        let fileSystem = try seededFileSystem(records: [existing])
        let originalBytes = try XCTUnwrap(fileSystem.files[fileSystem.canonicalURL])
        let repository = SavedPlanRepository(
            fileSystem: fileSystem,
            codec: FailingEncodeCodec(),
            now: { self.date(50) }
        )

        XCTAssertThrowsError(try repository.delete(id: existing.id)) { error in
            XCTAssertEqual(error as? SavedPlanMutationFailure, .writeFailed(.encoding))
        }
        XCTAssertEqual(fileSystem.files[fileSystem.canonicalURL], originalBytes)
        XCTAssertFalse(fileSystem.files.keys.contains(fileSystem.stagingURL))
    }

    private func availableRecords(_ repository: SavedPlanRepository) -> [SavedPlanRecord] {
        guard case let .available(records) = repository.list().canonical else {
            XCTFail("Expected available records")
            return []
        }
        return records
    }

    private func validatedPlan(name: String = "Synthetic plan") -> WorkoutPlanValidator.ValidatedPlan {
        validatedPlan(plan(name: name))
    }

    private func validatedPlan(_ plan: WorkoutPlan) -> WorkoutPlanValidator.ValidatedPlan {
        do {
            return try WorkoutPlanValidator.validate(plan, against: capabilities()).get()
        } catch {
            XCTFail("Synthetic fixture should validate: \(error)")
            fatalError("Invalid synthetic test fixture")
        }
    }

    private func plan(
        name: String = "Synthetic plan",
        intervalSpeed: String = "10.0"
    ) -> WorkoutPlan {
        WorkoutPlan(
            schemaVersion: WorkoutPlanSchema.currentVersion,
            suggestedName: name,
            activity: .indoorRunning,
            steps: [
                step(.warmUp, label: "Warm up", speed: "5.0", inclination: "0.0"),
                step(.interval, label: "Run", speed: intervalSpeed, inclination: "1.0"),
                step(.recovery, label: "Recover", speed: "6.0", inclination: "0.5"),
                step(.coolDown, label: "Cool down", speed: "4.0", inclination: "0.0"),
            ]
        )
    }

    private func step(
        _ kind: WorkoutStepKind,
        label: String,
        speed: String,
        inclination: String
    ) -> WorkoutStep {
        WorkoutStep(
            kind: kind,
            label: label,
            duration: .init(value: 120, unit: .seconds),
            targetSpeed: .init(value: decimal(speed), unit: .kilometresPerHour),
            targetInclination: .init(value: decimal(inclination), unit: .percent)
        )
    }

    private func capabilities() -> WorkoutPlanCapabilities {
        WorkoutPlanCapabilities(
            speed: .supported(
                .init(
                    minimum: .init(value: decimal("0.5"), unit: .kilometresPerHour),
                    maximum: .init(value: decimal("20.0"), unit: .kilometresPerHour),
                    increment: .init(value: decimal("0.1"), unit: .kilometresPerHour)
                )
            ),
            inclination: .supported(
                .init(
                    minimum: .init(value: decimal("-3.0"), unit: .percent),
                    maximum: .init(value: decimal("15.0"), unit: .percent),
                    increment: .init(value: decimal("0.5"), unit: .percent)
                )
            )
        )
    }

    private func record(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: String = "Synthetic plan",
        createdAt: Date = Date(timeIntervalSince1970: 10),
        modifiedAt: Date = Date(timeIntervalSince1970: 10),
        plan suppliedPlan: WorkoutPlan? = nil
    ) -> SavedPlanRecord {
        SavedPlanRecord(
            id: id,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            plan: suppliedPlan ?? plan(name: name)
        )
    }

    private func seededFileSystem(
        records: [SavedPlanRecord],
        formatVersion: Int = SavedPlanStoreSchema.currentVersion
    ) throws -> MemorySavedPlanFileSystem {
        let fileSystem = MemorySavedPlanFileSystem()
        fileSystem.files[fileSystem.canonicalURL] = try SavedPlanJSONCodec().encode(
            SavedPlanStore(formatVersion: formatVersion, records: records)
        )
        return fileSystem
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}

private final class ValueSequence<Value> {
    private var values: [Value]

    init(_ values: [Value]) {
        self.values = values
    }

    func next() -> Value {
        precondition(!values.isEmpty)
        return values.removeFirst()
    }
}

private struct FailingEncodeCodec: SavedPlanStoreCoding {
    private let base = SavedPlanJSONCodec()

    func encode(_ store: SavedPlanStore) throws -> Data {
        throw TestFailure.injected
    }

    func decodeFormatVersion(from data: Data) throws -> Int {
        try base.decodeFormatVersion(from: data)
    }

    func decodeStore(from data: Data) throws -> SavedPlanStore {
        try base.decodeStore(from: data)
    }
}

private enum TestFailure: Error {
    case injected
}

private final class MemorySavedPlanFileSystem: SavedPlanFileSystem {
    enum Failure: Equatable {
        case canonicalRead
        case protectedCanonicalRead
        case stagingPresence
        case directoryPreparation
        case applyDirectoryProtection
        case verifyDirectoryProtection
        case applyDirectoryBackupExclusion
        case verifyDirectoryBackupExclusion
        case stagingWrite
        case stagingValidation
        case synchronization
        case applyStagingProtection
        case verifyStagingProtection
        case applyStagingBackupExclusion
        case verifyStagingBackupExclusion
        case atomicReplacement

    }

    enum Operation: Equatable {
        case createDirectory
        case applyDirectoryProtection
        case verifyDirectoryProtection
        case applyDirectoryBackupExclusion
        case verifyDirectoryBackupExclusion
        case writeStaging
        case readStaging
        case synchronizeStaging
        case applyStagingProtection
        case verifyStagingProtection
        case applyStagingBackupExclusion
        case verifyStagingBackupExclusion
        case atomicReplacement
    }

    let applicationSupportURL = URL(fileURLWithPath: "/synthetic/Application Support", isDirectory: true)
    var files: [URL: Data] = [:]
    var failure: Failure?
    private(set) var mutationOperations: [Operation] = []

    var directoryURL: URL {
        applicationSupportURL.appendingPathComponent("PacePrompt", isDirectory: true)
    }

    var canonicalURL: URL {
        directoryURL.appendingPathComponent("saved-plans.json", isDirectory: false)
    }

    var stagingURL: URL {
        directoryURL.appendingPathComponent("saved-plans.json.staging", isDirectory: false)
    }

    func applicationSupportDirectory() throws -> URL {
        applicationSupportURL
    }

    func fileExists(at url: URL) throws -> Bool {
        if url == stagingURL {
            try failIf(.stagingPresence)
        }
        return files[url] != nil
    }

    func createProtectedDirectory(at url: URL) throws {
        mutationOperations.append(.createDirectory)
        try failIf(.directoryPreparation)
    }

    func readData(at url: URL) throws -> Data {
        if url == canonicalURL {
            if failureMatches(.protectedCanonicalRead) {
                throw SavedPlanFileSystemError.protectedDataUnavailable
            }
            try failIf(.canonicalRead)
        } else if url == stagingURL {
            mutationOperations.append(.readStaging)
            if failureMatches(.stagingValidation) {
                return Data(#"{"formatVersion":1,"records":["#.utf8)
            }
        }
        guard let data = files[url] else { throw TestFailure.injected }
        return data
    }

    func writeProtectedData(_ data: Data, to url: URL) throws {
        mutationOperations.append(.writeStaging)
        try failIf(.stagingWrite)
        files[url] = data
    }

    func synchronizeFile(at url: URL) throws {
        mutationOperations.append(.synchronizeStaging)
        try failIf(.synchronization)
    }

    func applyCompleteFileProtection(to url: URL) throws {
        if url == directoryURL {
            mutationOperations.append(.applyDirectoryProtection)
            try failIf(.applyDirectoryProtection)
        } else {
            mutationOperations.append(.applyStagingProtection)
            try failIf(.applyStagingProtection)
        }
    }

    func hasCompleteFileProtection(at url: URL) throws -> Bool {
        if url == directoryURL {
            mutationOperations.append(.verifyDirectoryProtection)
            return !failureMatches(.verifyDirectoryProtection)
        }
        mutationOperations.append(.verifyStagingProtection)
        return !failureMatches(.verifyStagingProtection)
    }

    func excludeFromBackup(_ url: URL) throws {
        if url == directoryURL {
            mutationOperations.append(.applyDirectoryBackupExclusion)
            try failIf(.applyDirectoryBackupExclusion)
        } else {
            mutationOperations.append(.applyStagingBackupExclusion)
            try failIf(.applyStagingBackupExclusion)
        }
    }

    func isExcludedFromBackup(_ url: URL) throws -> Bool {
        if url == directoryURL {
            mutationOperations.append(.verifyDirectoryBackupExclusion)
            return !failureMatches(.verifyDirectoryBackupExclusion)
        }
        mutationOperations.append(.verifyStagingBackupExclusion)
        return !failureMatches(.verifyStagingBackupExclusion)
    }

    func atomicallyReplaceItem(at canonicalURL: URL, with stagingURL: URL) throws {
        mutationOperations.append(.atomicReplacement)
        try failIf(.atomicReplacement)
        guard let stagedData = files.removeValue(forKey: stagingURL) else {
            throw TestFailure.injected
        }
        files[canonicalURL] = stagedData
    }

    private func failIf(_ expected: Failure) throws {
        if failureMatches(expected) { throw TestFailure.injected }
    }

    private func failureMatches(_ expected: Failure) -> Bool {
        failure == expected
    }
}
