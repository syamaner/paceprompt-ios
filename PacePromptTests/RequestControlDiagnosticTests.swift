import Foundation
import XCTest
@testable import PacePrompt

@MainActor
final class RequestControlDiagnosticTests: XCTestCase {
    func testDefaultGateUsesFreshThirdPersistentAttemptKey() {
        XCTAssertEqual(
            RequestControlWriteGate.defaultAttemptKey,
            "PacePrompt.issue51.requestControlAttemptConsumed.v3"
        )
    }

    func testGateConsumesOnlyExactRequestControlAndPersistsAcrossInstances() throws {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let gate = RequestControlWriteGate(
            defaults: fixture.defaults,
            attemptKey: "attempt"
        )

        try gate.consume(Data([0x00]))

        XCTAssertTrue(gate.wasConsumed)
        let reloaded = RequestControlWriteGate(
            defaults: fixture.defaults,
            attemptKey: "attempt"
        )
        XCTAssertThrowsError(try reloaded.consume(Data([0x00]))) { error in
            XCTAssertEqual(error as? RequestControlWriteGateError, .attemptAlreadyConsumed)
        }
    }

    func testGateRejectsEveryScopedDisallowedOpcodeWithoutConsumingAttempt() {
        let disallowedRequests = [
            Data([0x01]),
            Data([0x02, 0x64, 0x00]),
            Data([0x03, 0x00, 0x00]),
            Data([0x07]),
            Data([0x08, 0x01]),
            Data([0x08, 0x02]),
        ]

        for (index, request) in disallowedRequests.enumerated() {
            let fixture = makeDefaults(suffix: "\(index)")
            defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
            let gate = RequestControlWriteGate(
                defaults: fixture.defaults,
                attemptKey: "attempt"
            )

            XCTAssertThrowsError(try gate.consume(request)) { error in
                XCTAssertEqual(error as? RequestControlWriteGateError, .disallowedBytes(request))
            }
            XCTAssertFalse(gate.wasConsumed)
        }
    }

    func testRestrictedLinkForwardsExactRequestOnceWithResponse() {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let underlying = FakeControlPointLink()
        let journal = FakeRequestControlDiagnosticJournal()
        let link = RequestControlOnlyLink(
            underlying: underlying,
            gate: RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt"),
            journal: journal
        )
        var audited: [Data] = []
        link.requestSubmitted = { audited.append($0) }

        link.writeWithResponse(Data([0x00]))

        XCTAssertEqual(underlying.writes, [Data([0x00])])
        XCTAssertEqual(audited, [Data([0x00])])
        XCTAssertEqual(underlying.invalidateCount, 0)
        XCTAssertEqual(
            journal.kinds,
            [.requestPathEntered, .gateConsumed, .forwardingStarted]
        )
    }

    func testRestrictedLinkReportsSubmissionOnlyAfterUnderlyingWriteReturns() {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        var operations: [String] = []
        let underlying = FakeControlPointLink()
        underlying.onWrite = { operations.append("underlying write returned") }
        let journal = FakeRequestControlDiagnosticJournal(
            onRecord: { operations.append($0.rawValue) }
        )
        let link = RequestControlOnlyLink(
            underlying: underlying,
            gate: RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt"),
            journal: journal
        )
        link.requestSubmitted = { _ in operations.append("submission callback") }

        link.writeWithResponse(Data([0x00]))

        XCTAssertEqual(
            operations,
            [
                "requestPathEntered",
                "gateConsumed",
                "forwardingStarted",
                "underlying write returned",
                "submission callback",
            ]
        )
    }

    func testRestrictedLinkBlocksDuplicateBeforeCoreBluetoothWrite() {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let underlying = FakeControlPointLink()
        let journal = FakeRequestControlDiagnosticJournal()
        let link = RequestControlOnlyLink(
            underlying: underlying,
            gate: RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt"),
            journal: journal
        )
        var blocked: [String] = []
        var events: [FTMSControlPointLinkEvent] = []
        link.requestBlocked = { blocked.append($0) }
        link.eventHandler = { events.append($0) }

        link.writeWithResponse(Data([0x00]))
        link.writeWithResponse(Data([0x00]))

        XCTAssertEqual(underlying.writes, [Data([0x00])])
        XCTAssertEqual(blocked.count, 1)
        XCTAssertEqual(underlying.invalidateCount, 1)
        XCTAssertEqual(events.count, 1)
        guard case let .writeDeliveryUnknown(message) = events[0] else {
            return XCTFail("Expected a local block event")
        }
        XCTAssertTrue(message.contains("No retry occurred"))
    }

    func testRestrictedLinkBlocksNonRequestBytesBeforeUnderlyingWrite() {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let underlying = FakeControlPointLink()
        let link = RequestControlOnlyLink(
            underlying: underlying,
            gate: RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt"),
            journal: FakeRequestControlDiagnosticJournal()
        )

        link.writeWithResponse(Data([0x07]))

        XCTAssertTrue(underlying.writes.isEmpty)
        XCTAssertEqual(underlying.invalidateCount, 1)
    }

    func testRestrictedLinkAbortInvalidatesWithoutWritingAndPublishesFailure() {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let underlying = FakeControlPointLink()
        let link = RequestControlOnlyLink(
            underlying: underlying,
            gate: RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt"),
            journal: FakeRequestControlDiagnosticJournal()
        )
        var events: [FTMSControlPointLinkEvent] = []
        link.eventHandler = { events.append($0) }

        link.abort(reason: "Malformed passive packet")

        XCTAssertTrue(underlying.writes.isEmpty)
        XCTAssertEqual(underlying.invalidateCount, 1)
        XCTAssertEqual(events, [.indicationFailed("Malformed passive packet")])
        XCTAssertFalse(RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt").wasConsumed)
    }

    func testJournalPersistsPreTriggerProcessTerminationShapeAcrossRestart() throws {
        let store = FakeRequestControlDiagnosticJournalStore()
        let firstSession = try RequestControlDiagnosticJournal(
            store: store,
            now: { Date(timeIntervalSince1970: 1_000) },
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        try firstSession.record(.readiness, detail: "Readiness: Ready for one request")

        let recovered = try RequestControlDiagnosticJournal(
            store: store,
            now: { Date(timeIntervalSince1970: 2_000) },
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )

        XCTAssertEqual(
            recovered.records.map(\.kind),
            [.sessionStarted, .readiness, .sessionStarted, .previousSessionRecovered]
        )
        XCTAssertFalse(recovered.records.contains { $0.kind == .requestPathEntered })
        XCTAssertTrue(recovered.records.last?.detail.contains("no explicit disconnect was recorded") == true)
        XCTAssertTrue(recovered.records.last?.detail.contains("process-exit cause") == true)
        XCTAssertTrue(recovered.records.last?.detail.contains("no retry or write authority") == true)
    }

    func testReadOnlyJournalLoadValidatesWithoutAppendingOrSaving() throws {
        let store = FakeRequestControlDiagnosticJournalStore()
        let journal = try RequestControlDiagnosticJournal(
            store: store,
            now: { Date(timeIntervalSince1970: 1_000) },
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        try journal.record(.outcome, detail: "Historical accepted proof")
        let savedData = store.data
        let saveCount = store.saveCount

        let records = try RequestControlDiagnosticJournal.readOnlyRecords(store: store)

        XCTAssertEqual(records, journal.records)
        XCTAssertEqual(store.data, savedData)
        XCTAssertEqual(store.saveCount, saveCount)
    }

    func testFileStoreAppliesCompleteProtectionAndBackupExclusion() throws {
        let fileSystem = FakeRequestControlDiagnosticJournalFileSystem()
        let store = try RequestControlDiagnosticJournalFileStore(fileSystem: fileSystem)
        let expected = Data("protected evidence".utf8)

        try store.saveAtomicallyProtected(expected)

        XCTAssertEqual(try store.load(), expected)
        XCTAssertEqual(
            fileSystem.operations,
            [
                .applicationSupportDirectory,
                .createProtectedDirectory,
                .applyCompleteProtectionToDirectory,
                .excludeDirectoryFromBackup,
                .verifyDirectoryProtection,
                .verifyDirectoryBackupExclusion,
                .atomicProtectedWrite,
                .applyCompleteProtectionToFile,
                .excludeFileFromBackup,
                .verifyFileProtection,
                .verifyFileBackupExclusion,
                .fileExists,
                .verifyFileProtection,
                .verifyFileBackupExclusion,
                .readData,
            ]
        )
    }

    func testJournalRecordsExplicitDisconnectWithoutInferringProcessCause() throws {
        let store = FakeRequestControlDiagnosticJournalStore()
        let first = try RequestControlDiagnosticJournal(store: store)
        try first.record(.disconnectRequested, detail: "Explicit disconnect requested")
        try first.record(.disconnected, detail: "CoreBluetooth disconnected")

        let recovered = try RequestControlDiagnosticJournal(store: store)

        XCTAssertTrue(recovered.records.last?.detail.contains("an explicit disconnect was recorded") == true)
        XCTAssertFalse(recovered.records.last?.detail.contains("process-exit cause") == true)
    }

    func testJournalRejectsUnsupportedAndRolledBackDocuments() throws {
        let store = FakeRequestControlDiagnosticJournalStore()
        store.data = try JSONEncoder().encode(
            RequestControlDiagnosticJournalDocument(
                schemaVersion: 99,
                nextSequence: 1,
                entries: []
            )
        )
        XCTAssertThrowsError(try RequestControlDiagnosticJournal(store: store)) { error in
            XCTAssertEqual(
                error as? RequestControlDiagnosticJournalError,
                .unsupportedSchema(99)
            )
        }

        store.data = try JSONEncoder().encode(
            RequestControlDiagnosticJournalDocument(
                schemaVersion: RequestControlDiagnosticJournalDocument.currentSchemaVersion,
                nextSequence: 2,
                entries: []
            )
        )
        XCTAssertThrowsError(try RequestControlDiagnosticJournal(store: store)) { error in
            XCTAssertEqual(error as? RequestControlDiagnosticJournalError, .invalidSequence)
        }
    }

    func testJournalRejectsMalformedDocumentWithoutReplacingIt() {
        let store = FakeRequestControlDiagnosticJournalStore()
        let malformed = Data("not-json".utf8)
        store.data = malformed

        XCTAssertThrowsError(try RequestControlDiagnosticJournal(store: store))
        XCTAssertEqual(store.data, malformed)
    }

    func testJournalRejectsContradictoryDuplicateSequenceEvidence() throws {
        let store = FakeRequestControlDiagnosticJournalStore()
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let entries = [
            RequestControlDiagnosticJournalEntry(
                sequence: 7,
                timestamp: Date(timeIntervalSince1970: 1_000),
                sessionID: sessionID,
                kind: .requestPathEntered,
                detail: "Trigger boundary"
            ),
            RequestControlDiagnosticJournalEntry(
                sequence: 7,
                timestamp: Date(timeIntervalSince1970: 1_001),
                sessionID: sessionID,
                kind: .forwardingStarted,
                detail: "Contradictory duplicate sequence"
            ),
        ]
        store.data = try JSONEncoder().encode(
            RequestControlDiagnosticJournalDocument(
                schemaVersion: RequestControlDiagnosticJournalDocument.currentSchemaVersion,
                nextSequence: 8,
                entries: entries
            )
        )

        XCTAssertThrowsError(try RequestControlDiagnosticJournal(store: store)) { error in
            XCTAssertEqual(error as? RequestControlDiagnosticJournalError, .invalidSequence)
        }
    }

    func testJournalSaveFailurePreservesLastCommittedDocument() throws {
        let store = FakeRequestControlDiagnosticJournalStore()
        let journal = try RequestControlDiagnosticJournal(store: store)
        let committedData = try XCTUnwrap(store.data)
        let committedRecords = journal.records
        store.failSave = true

        XCTAssertThrowsError(try journal.record(.readiness, detail: "Ready"))

        XCTAssertEqual(store.data, committedData)
        XCTAssertEqual(journal.records, committedRecords)
    }

    func testJournalBoundsRecordsAndPreservesExactDuplicateAndLateEvidence() throws {
        let store = FakeRequestControlDiagnosticJournalStore()
        let journal = try RequestControlDiagnosticJournal(
            store: store,
            maximumRecordCount: 4
        )

        try journal.record(.indicationReceived, detail: "80 00 01")
        try journal.record(.indicationReceived, detail: "80 00 01 duplicate")
        try journal.record(.outcome, detail: "protocol anomaly duplicate")
        try journal.record(.indicationReceived, detail: "80 00 01 late")

        XCTAssertEqual(journal.records.count, 4)
        XCTAssertEqual(journal.records.map(\.sequence), [2, 3, 4, 5])
        XCTAssertEqual(
            journal.records.map(\.detail),
            ["80 00 01", "80 00 01 duplicate", "protocol anomaly duplicate", "80 00 01 late"]
        )
    }

    func testEveryJournalFailureBeforeForwardingInvalidatesAndWritesNothing() {
        for (index, failureKind) in [
            RequestControlDiagnosticJournalKind.requestPathEntered,
            .gateConsumed,
            .forwardingStarted,
        ].enumerated() {
            let fixture = makeDefaults(suffix: "journal-failure-\(index)")
            defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
            let gate = RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt")
            let underlying = FakeControlPointLink()
            let journal = FakeRequestControlDiagnosticJournal(failOn: failureKind)
            let link = RequestControlOnlyLink(
                underlying: underlying,
                gate: gate,
                journal: journal
            )
            var blocked: [String] = []
            var events: [FTMSControlPointLinkEvent] = []
            link.requestBlocked = { blocked.append($0) }
            link.eventHandler = { events.append($0) }

            link.writeWithResponse(Data([0x00]))

            XCTAssertTrue(underlying.writes.isEmpty, "Unexpected write for \(failureKind)")
            XCTAssertEqual(underlying.invalidateCount, 1)
            XCTAssertEqual(blocked.count, 1)
            XCTAssertTrue(blocked[0].contains("No CoreBluetooth write occurred"))
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(gate.wasConsumed, failureKind != .requestPathEntered)
            guard case let .writeDeliveryUnknown(message) = events[0] else {
                return XCTFail("Expected fail-closed delivery uncertainty for \(failureKind)")
            }
            XCTAssertTrue(message.contains("no retry is authorised"))
        }
    }

    private func makeDefaults(suffix: String = UUID().uuidString) -> (defaults: UserDefaults, suite: String) {
        let suite = "RequestControlDiagnosticTests.\(suffix)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}

private enum SyntheticJournalError: Error {
    case saveFailed
    case boundaryFailed
}

private final class FakeRequestControlDiagnosticJournalFileSystem: RequestControlDiagnosticJournalFileSystem {
    enum Operation: Equatable {
        case applicationSupportDirectory
        case createProtectedDirectory
        case applyCompleteProtectionToDirectory
        case applyCompleteProtectionToFile
        case excludeDirectoryFromBackup
        case excludeFileFromBackup
        case verifyDirectoryProtection
        case verifyFileProtection
        case verifyDirectoryBackupExclusion
        case verifyFileBackupExclusion
        case atomicProtectedWrite
        case fileExists
        case readData
    }

    private let directoryURL = URL(fileURLWithPath: "/synthetic/application-support/PacePromptIssue51Diagnostic")
    private var data: Data?
    private(set) var operations: [Operation] = []

    func applicationSupportDirectory() throws -> URL {
        operations.append(.applicationSupportDirectory)
        return directoryURL.deletingLastPathComponent()
    }

    func fileExists(at url: URL) throws -> Bool {
        operations.append(.fileExists)
        return data != nil
    }

    func createProtectedDirectory(at url: URL) throws {
        operations.append(.createProtectedDirectory)
    }

    func readData(at url: URL) throws -> Data {
        operations.append(.readData)
        return data!
    }

    func writeAtomicallyProtectedData(_ data: Data, to url: URL) throws {
        operations.append(.atomicProtectedWrite)
        self.data = data
    }

    func applyCompleteFileProtection(to url: URL) throws {
        operations.append(url.path == directoryURL.path ? .applyCompleteProtectionToDirectory : .applyCompleteProtectionToFile)
    }

    func hasCompleteFileProtection(at url: URL) throws -> Bool {
        operations.append(url.path == directoryURL.path ? .verifyDirectoryProtection : .verifyFileProtection)
        return true
    }

    func excludeFromBackup(_ url: URL) throws {
        operations.append(url.path == directoryURL.path ? .excludeDirectoryFromBackup : .excludeFileFromBackup)
    }

    func isExcludedFromBackup(_ url: URL) throws -> Bool {
        operations.append(url.path == directoryURL.path ? .verifyDirectoryBackupExclusion : .verifyFileBackupExclusion)
        return true
    }
}

private final class FakeRequestControlDiagnosticJournalStore: RequestControlDiagnosticJournalStore {
    var data: Data?
    var failSave = false
    private(set) var saveCount = 0

    func load() throws -> Data? {
        data
    }

    func saveAtomicallyProtected(_ data: Data) throws {
        if failSave {
            throw SyntheticJournalError.saveFailed
        }
        saveCount += 1
        self.data = data
    }
}

@MainActor
private final class FakeRequestControlDiagnosticJournal: RequestControlDiagnosticJournaling {
    private(set) var kinds: [RequestControlDiagnosticJournalKind] = []
    let failOn: RequestControlDiagnosticJournalKind?
    let onRecord: ((RequestControlDiagnosticJournalKind) -> Void)?

    init(
        failOn: RequestControlDiagnosticJournalKind? = nil,
        onRecord: ((RequestControlDiagnosticJournalKind) -> Void)? = nil
    ) {
        self.failOn = failOn
        self.onRecord = onRecord
    }

    var records: [RequestControlDiagnosticJournalEntry] { [] }

    func record(
        _ kind: RequestControlDiagnosticJournalKind,
        detail: String
    ) throws {
        if kind == failOn {
            throw SyntheticJournalError.boundaryFailed
        }
        kinds.append(kind)
        onRecord?(kind)
    }
}

@MainActor
private final class FakeControlPointLink: FTMSControlPointLink {
    let supportsWriteWithResponse = true
    let supportsIndications = true
    var eventHandler: ((FTMSControlPointLinkEvent) -> Void)?
    private(set) var enableIndicationsCount = 0
    private(set) var writes: [Data] = []
    private(set) var invalidateCount = 0
    var onWrite: (() -> Void)?

    func enableIndications() {
        enableIndicationsCount += 1
    }

    func writeWithResponse(_ data: Data) {
        writes.append(data)
        onWrite?()
    }

    func invalidate() {
        invalidateCount += 1
    }
}
