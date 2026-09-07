import Foundation
import XCTest
@testable import PacePrompt

final class WorkoutHistoryRepositoryTests: XCTestCase {
    func testCodecRoundTripsMeasuredZeroUnavailableValuesAndHumanConfirmation() throws {
        let summaries = [
            summary(id: uuid(1), activeDuration: .measured(seconds: 0), distance: .measured(metres: 0)),
            summary(id: uuid(2), outcome: .interrupted(reason: reason("connectionLost")), activeDuration: .unavailable(reason: reason("durationUnavailable")), distance: .unavailable(reason: reason("distanceUnavailable")), stop: .unconfirmed),
            summary(id: uuid(3), stop: .humanConfirmed(at: date(15))),
        ]
        let codec = WorkoutHistoryJSONCodec()
        let data = try codec.encode(.init(formatVersion: 1, summaries: summaries))
        let decoded = try codec.decodeStore(from: data)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encoded = try XCTUnwrap(root["summaries"] as? [[String: Any]])

        XCTAssertEqual(decoded.summaries, summaries)
        XCTAssertEqual(Set(root.keys), ["formatVersion", "summaries"])
        XCTAssertEqual(encoded[0]["activeDuration"] as? [String: AnyHashable], ["seconds": 0, "state": "measured"])
        XCTAssertEqual(encoded[1]["activeDuration"] as? [String: AnyHashable], ["reasonCode": "durationUnavailable", "state": "unavailable"])
    }

    func testRecordAppendsAndIncrementallyReplacesInStableOrder() throws {
        let fileSystem = MemoryWorkoutHistoryFileSystem()
        let repository = WorkoutHistoryRepository(fileSystem: fileSystem)
        let first = summary(id: uuid(1), updatedAt: date(20))
        let second = summary(id: uuid(2), updatedAt: date(20))
        let updated = summary(id: uuid(1), updatedAt: date(30), outcome: .completed, activeDuration: .measured(seconds: 240), distance: .measured(metres: decimal("800.5")), progress: .init(completedStepCount: 4, currentStepIndex: nil, activeSecondsInCurrentStep: 0), stop: .humanConfirmed(at: date(25)))

        try repository.record(first)
        try repository.record(second)
        try repository.record(updated)

        XCTAssertEqual(availableSummaries(repository), [updated, second])
        XCTAssertEqual(fileSystem.lastMutationOperations, [.createDirectory, .applyDirectoryProtection, .verifyDirectoryProtection, .applyDirectoryBackupExclusion, .verifyDirectoryBackupExclusion, .writeStaging, .readStaging, .synchronizeStaging, .applyStagingProtection, .verifyStagingProtection, .applyStagingBackupExclusion, .verifyStagingBackupExclusion, .atomicReplacement])
    }

    func testUpdateRejectsChangedImmutableFieldsAndOlderTimestampWithoutWriting() throws {
        let existing = summary(id: uuid(1), updatedAt: date(20))
        let fileSystem = try seededFileSystem([existing])
        let repository = WorkoutHistoryRepository(fileSystem: fileSystem)
        let original = try XCTUnwrap(fileSystem.files[fileSystem.canonicalURL])

        XCTAssertThrowsError(try repository.record(summary(id: uuid(1), plan: plan(name: "Changed"), updatedAt: date(30)))) {
            XCTAssertEqual($0 as? WorkoutHistoryMutationFailure, .immutableAttemptFieldsChanged(self.uuid(1)))
        }
        XCTAssertThrowsError(try repository.record(summary(id: uuid(1), updatedAt: date(19)))) {
            XCTAssertEqual($0 as? WorkoutHistoryMutationFailure, .staleUpdate(self.uuid(1)))
        }
        XCTAssertEqual(fileSystem.files[fileSystem.canonicalURL], original)
        XCTAssertTrue(fileSystem.lastMutationOperations.isEmpty)
    }

    func testStructurallyInvalidInputIsRejectedBeforeReadingOrWriting() {
        let fileSystem = MemoryWorkoutHistoryFileSystem()
        let repository = WorkoutHistoryRepository(fileSystem: fileSystem)

        XCTAssertThrowsError(try repository.record(summary(activeDuration: .unavailable(reason: reason("   "))))) {
            XCTAssertEqual($0 as? WorkoutHistoryMutationFailure, .invalidSummary)
        }
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testMissingFileIsOnlyEmptyStateAndStagingStateIsIndependent() {
        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: MemoryWorkoutHistoryFileSystem()).list(), .init(canonical: .empty, staging: .absent))
        let fileSystem = MemoryWorkoutHistoryFileSystem()
        fileSystem.files[fileSystem.stagingURL] = Data("stale".utf8)
        let repository = WorkoutHistoryRepository(fileSystem: fileSystem)

        XCTAssertEqual(repository.list(), .init(canonical: .empty, staging: .staleArtifactPresent))
        XCTAssertThrowsError(try repository.record(summary())) {
            XCTAssertEqual($0 as? WorkoutHistoryMutationFailure, .blocked(repository.list()))
        }
    }

    func testProtectedDataAndOrdinaryReadFailureAreDistinct() throws {
        let protectedFileSystem = try seededFileSystem([summary()])
        protectedFileSystem.failure = .protectedCanonicalRead
        let failedFileSystem = try seededFileSystem([summary()])
        failedFileSystem.failure = .canonicalRead

        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: protectedFileSystem).list().canonical, .protectedDataUnavailable)
        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: failedFileSystem).list().canonical, .readFailure)
    }

    func testCorruptPartialDuplicateAndInvalidRecordsRemainDistinctFromEmpty() throws {
        let corrupt = MemoryWorkoutHistoryFileSystem()
        corrupt.files[corrupt.canonicalURL] = Data(#"{"formatVersion":1,"summaries":!}"#.utf8)
        let partial = MemoryWorkoutHistoryFileSystem()
        partial.files[partial.canonicalURL] = Data(#"{"formatVersion":1,"summaries":["#.utf8)
        let duplicate = try seededFileSystem([summary(id: uuid(1)), summary(id: uuid(1))])
        let invalid = try seededFileSystem([summary(updatedAt: date(5))])

        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: corrupt).list().canonical, .corruptData)
        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: partial).list().canonical, .partialWriteDetected)
        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: duplicate).list().canonical, .corruptData)
        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: invalid).list().canonical, .corruptData)
    }

    func testUnexpectedFieldsAtEveryDefinedDepthAreRejected() throws {
        let locations = ["root", "summary", "outcome", "activeDuration", "distance", "progress", "stop", "plan", "step", "duration", "speed", "inclination"]
        for location in locations {
            let fileSystem = try seededFileSystem([summary()])
            let data = try XCTUnwrap(fileSystem.files[fileSystem.canonicalURL])
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            addFutureField(at: location, root: &root)
            fileSystem.files[fileSystem.canonicalURL] = try JSONSerialization.data(withJSONObject: root)
            XCTAssertEqual(WorkoutHistoryRepository(fileSystem: fileSystem).list().canonical, .corruptData, "Expected future field at \(location) to be rejected")
        }
    }

    func testUnsupportedVersionsAreReportedBeforeFuturePayloadDecoding() throws {
        let store = try seededFileSystem([summary()], formatVersion: 2)
        let futureSummary = MemoryWorkoutHistoryFileSystem()
        futureSummary.files[futureSummary.canonicalURL] = Data(#"{"formatVersion":1,"summaries":[{"id":"00000000-0000-0000-0000-000000000007","schemaVersion":9,"future":true}]}"#.utf8)
        let futurePlan = MemoryWorkoutHistoryFileSystem()
        futurePlan.files[futurePlan.canonicalURL] = Data(#"{"formatVersion":1,"summaries":[{"id":"00000000-0000-0000-0000-000000000008","schemaVersion":1,"planSnapshot":{"schemaVersion":9,"future":true}}]}"#.utf8)

        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: store).list().canonical, .unsupportedStoreVersion(2))
        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: futureSummary).list().canonical, .unsupportedSummaryVersion(summaryID: uuid(7), version: 9))
        XCTAssertEqual(WorkoutHistoryRepository(fileSystem: futurePlan).list().canonical, .unsupportedPlanVersion(summaryID: uuid(8), version: 9))
    }

    func testUnavailableStagingPresenceKeepsCanonicalReadableAndBlocksMutation() throws {
        let existing = summary()
        let fileSystem = try seededFileSystem([existing])
        fileSystem.failure = .stagingPresence
        let repository = WorkoutHistoryRepository(fileSystem: fileSystem)
        let status = repository.list()

        XCTAssertEqual(status.canonical, .available(summaries: [existing]))
        XCTAssertEqual(status.staging, .presenceUnavailable)
        XCTAssertThrowsError(try repository.record(summary(id: uuid(2)))) {
            XCTAssertEqual($0 as? WorkoutHistoryMutationFailure, .blocked(status))
        }
    }

    func testEveryWritePipelineFailurePreservesPreviousCanonicalBytes() throws {
        let scenarios: [(MemoryWorkoutHistoryFileSystem.Failure, WorkoutHistoryMutationFailure.WriteStage)] = [
            (.directoryPreparation, .directoryPreparation), (.applyDirectoryProtection, .fileProtection), (.verifyDirectoryProtection, .fileProtection), (.applyDirectoryBackupExclusion, .backupExclusion), (.verifyDirectoryBackupExclusion, .backupExclusion), (.stagingWrite, .stagingWrite), (.stagingValidation, .stagingValidation), (.synchronization, .synchronization), (.applyStagingProtection, .fileProtection), (.verifyStagingProtection, .fileProtection), (.applyStagingBackupExclusion, .backupExclusion), (.verifyStagingBackupExclusion, .backupExclusion), (.atomicReplacement, .atomicReplacement),
        ]
        for (failure, stage) in scenarios {
            let existing = summary(updatedAt: date(20))
            let fileSystem = try seededFileSystem([existing])
            let original = try XCTUnwrap(fileSystem.files[fileSystem.canonicalURL])
            fileSystem.failure = failure

            XCTAssertThrowsError(try WorkoutHistoryRepository(fileSystem: fileSystem).record(summary(updatedAt: date(30), outcome: .completed))) {
                XCTAssertEqual($0 as? WorkoutHistoryMutationFailure, .writeFailed(stage))
            }
            XCTAssertEqual(fileSystem.files[fileSystem.canonicalURL], original, "Canonical changed after \(failure)")
        }
    }

    func testEncodingFailurePreservesCanonicalWithoutCreatingStaging() throws {
        let fileSystem = try seededFileSystem([summary()])
        let original = try XCTUnwrap(fileSystem.files[fileSystem.canonicalURL])
        let repository = WorkoutHistoryRepository(fileSystem: fileSystem, codec: FailingHistoryCodec())

        XCTAssertThrowsError(try repository.record(summary(id: uuid(2)))) {
            XCTAssertEqual($0 as? WorkoutHistoryMutationFailure, .writeFailed(.encoding))
        }
        XCTAssertEqual(fileSystem.files[fileSystem.canonicalURL], original)
        XCTAssertNil(fileSystem.files[fileSystem.stagingURL])
    }

    private func availableSummaries(_ repository: WorkoutHistoryRepository) -> [WorkoutExecutionSummary] {
        guard case let .available(summaries) = repository.list().canonical else { XCTFail("Expected available summaries"); return [] }
        return summaries
    }

    private func summary(id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, plan suppliedPlan: WorkoutPlan? = nil, updatedAt: Date = Date(timeIntervalSince1970: 20), outcome: WorkoutExecutionOutcome = .inProgress, activeDuration: WorkoutActiveDuration = .measured(seconds: 10), distance: WorkoutDistance = .measured(metres: 25), progress: WorkoutExecutionProgress = .init(completedStepCount: 0, currentStepIndex: 0, activeSecondsInCurrentStep: 10), stop: WorkoutPhysicalStopConfirmation = .notRequired) -> WorkoutExecutionSummary {
        .init(id: id, schemaVersion: 1, sourcePlanID: uuid(99), planSnapshot: suppliedPlan ?? plan(), attemptedAt: date(10), lastUpdatedAt: updatedAt, outcome: outcome, activeDuration: activeDuration, distance: distance, progress: progress, physicalStopConfirmation: stop)
    }

    private func plan(name: String = "Synthetic plan") -> WorkoutPlan {
        .init(schemaVersion: 1, suggestedName: name, activity: .indoorRunning, steps: [step(.warmUp), step(.interval), step(.recovery), step(.coolDown)])
    }

    private func step(_ kind: WorkoutStepKind) -> WorkoutStep {
        .init(kind: kind, label: "Synthetic \(kind.rawValue)", duration: .init(value: 60, unit: .seconds), targetSpeed: .init(value: 8, unit: .kilometresPerHour), targetInclination: .init(value: 1, unit: .percent))
    }

    private func seededFileSystem(_ summaries: [WorkoutExecutionSummary], formatVersion: Int = 1) throws -> MemoryWorkoutHistoryFileSystem {
        let fileSystem = MemoryWorkoutHistoryFileSystem()
        fileSystem.files[fileSystem.canonicalURL] = try WorkoutHistoryJSONCodec().encode(.init(formatVersion: formatVersion, summaries: summaries))
        return fileSystem
    }

    private func addFutureField(at location: String, root: inout [String: Any]) {
        if location == "root" { root["future"] = true; return }
        var summaries = root["summaries"] as! [[String: Any]]
        if location == "summary" { summaries[0]["future"] = true }
        else if location == "plan" { var value = summaries[0]["planSnapshot"] as! [String: Any]; value["future"] = true; summaries[0]["planSnapshot"] = value }
        else if ["step", "duration", "speed", "inclination"].contains(location) {
            var plan = summaries[0]["planSnapshot"] as! [String: Any]
            var steps = plan["steps"] as! [[String: Any]]
            if location == "step" { steps[0]["future"] = true }
            else { let key = location == "duration" ? "duration" : location == "speed" ? "targetSpeed" : "targetInclination"; var value = steps[0][key] as! [String: Any]; value["future"] = true; steps[0][key] = value }
            plan["steps"] = steps; summaries[0]["planSnapshot"] = plan
        } else { let key = location == "stop" ? "physicalStopConfirmation" : location; var value = summaries[0][key] as! [String: Any]; value["future"] = true; summaries[0][key] = value }
        root["summaries"] = summaries
    }

    private func uuid(_ suffix: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))! }
    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
    private func decimal(_ value: String) -> Decimal { Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))! }
    private func reason(_ value: String) -> WorkoutExecutionReasonCode { .init(rawValue: value) }
}

private struct FailingHistoryCodec: WorkoutHistoryStoreCoding {
    private let base = WorkoutHistoryJSONCodec()
    func encode(_ store: WorkoutHistoryStore) throws -> Data { throw SyntheticHistoryFailure.injected }
    func decodeFormatVersion(from data: Data) throws -> Int { try base.decodeFormatVersion(from: data) }
    func decodeStore(from data: Data) throws -> WorkoutHistoryStore { try base.decodeStore(from: data) }
}

private enum SyntheticHistoryFailure: Error { case injected }

private final class MemoryWorkoutHistoryFileSystem: WorkoutHistoryFileSystem {
    enum Failure: Equatable { case canonicalRead, protectedCanonicalRead, stagingPresence, directoryPreparation, applyDirectoryProtection, verifyDirectoryProtection, applyDirectoryBackupExclusion, verifyDirectoryBackupExclusion, stagingWrite, stagingValidation, synchronization, applyStagingProtection, verifyStagingProtection, applyStagingBackupExclusion, verifyStagingBackupExclusion, atomicReplacement }
    enum Operation: Equatable { case createDirectory, applyDirectoryProtection, verifyDirectoryProtection, applyDirectoryBackupExclusion, verifyDirectoryBackupExclusion, writeStaging, readStaging, synchronizeStaging, applyStagingProtection, verifyStagingProtection, applyStagingBackupExclusion, verifyStagingBackupExclusion, atomicReplacement }

    let applicationSupportURL = URL(fileURLWithPath: "/synthetic/Application Support", isDirectory: true)
    var files: [URL: Data] = [:]
    var failure: Failure?
    private(set) var lastMutationOperations: [Operation] = []
    var directoryURL: URL { applicationSupportURL.appendingPathComponent("PacePrompt", isDirectory: true) }
    var canonicalURL: URL { directoryURL.appendingPathComponent("workout-history.json") }
    var stagingURL: URL { directoryURL.appendingPathComponent("workout-history.json.staging") }

    func applicationSupportDirectory() throws -> URL { applicationSupportURL }
    func fileExists(at url: URL) throws -> Bool { if url == stagingURL { try failIf(.stagingPresence) }; return files[url] != nil }
    func createProtectedDirectory(at url: URL) throws { lastMutationOperations = [.createDirectory]; try failIf(.directoryPreparation) }
    func readData(at url: URL) throws -> Data {
        if url == canonicalURL { if failure == .protectedCanonicalRead { throw WorkoutHistoryFileSystemError.protectedDataUnavailable }; try failIf(.canonicalRead) }
        else if url == stagingURL { lastMutationOperations.append(.readStaging); if failure == .stagingValidation { return Data(#"{"formatVersion":1,"summaries":["#.utf8) } }
        guard let data = files[url] else { throw SyntheticHistoryFailure.injected }; return data
    }
    func writeProtectedData(_ data: Data, to url: URL) throws { lastMutationOperations.append(.writeStaging); try failIf(.stagingWrite); files[url] = data }
    func synchronizeFile(at url: URL) throws { lastMutationOperations.append(.synchronizeStaging); try failIf(.synchronization) }
    func applyCompleteFileProtection(to url: URL) throws { lastMutationOperations.append(url == directoryURL ? .applyDirectoryProtection : .applyStagingProtection); try failIf(url == directoryURL ? .applyDirectoryProtection : .applyStagingProtection) }
    func hasCompleteFileProtection(at url: URL) throws -> Bool { lastMutationOperations.append(url == directoryURL ? .verifyDirectoryProtection : .verifyStagingProtection); return failure != (url == directoryURL ? .verifyDirectoryProtection : .verifyStagingProtection) }
    func excludeFromBackup(_ url: URL) throws { lastMutationOperations.append(url == directoryURL ? .applyDirectoryBackupExclusion : .applyStagingBackupExclusion); try failIf(url == directoryURL ? .applyDirectoryBackupExclusion : .applyStagingBackupExclusion) }
    func isExcludedFromBackup(_ url: URL) throws -> Bool { lastMutationOperations.append(url == directoryURL ? .verifyDirectoryBackupExclusion : .verifyStagingBackupExclusion); return failure != (url == directoryURL ? .verifyDirectoryBackupExclusion : .verifyStagingBackupExclusion) }
    func atomicallyReplaceItem(at canonicalURL: URL, with stagingURL: URL) throws { lastMutationOperations.append(.atomicReplacement); try failIf(.atomicReplacement); files[canonicalURL] = files[stagingURL]; files[stagingURL] = nil }
    private func failIf(_ candidate: Failure) throws { if failure == candidate { throw SyntheticHistoryFailure.injected } }
}
