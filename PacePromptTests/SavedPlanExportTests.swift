import Foundation
import XCTest
@testable import PacePrompt

final class SavedPlanExportTests: XCTestCase {
    func testCodecProducesVersionedSavedPlansEnvelopeWithISO8601Date() throws {
        let record = makeRecord(id: uuid(1), name: "Synthetic intervals")
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let document = SavedPlanExportDocument(
            formatVersion: 1,
            createdAt: createdAt,
            savedPlans: [record]
        )

        let data = try SavedPlanExportJSONCodec().encode(document)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["createdAt", "formatVersion", "savedPlans"])
        XCTAssertEqual(object["formatVersion"] as? Int, 1)
        XCTAssertEqual(object["createdAt"] as? String, "2023-11-14T22:13:20Z")
        let records = try XCTUnwrap(object["savedPlans"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(Set(records[0].keys), ["createdAt", "id", "modifiedAt", "plan"])
        XCTAssertEqual(records[0]["id"] as? String, record.id.uuidString)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(SavedPlanExportDocument.self, from: data), document)
    }

    func testExporterCleansPreviousArtifactBeforeProtectedWriteAndReturnsExactURL() throws {
        let fileSystem = ExportFileSystemDouble()
        let exporter = SavedPlanExporter(fileSystem: fileSystem)
        let preview = SavedPlanExportPreview(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            fileName: SavedPlanExportSchema.fileName,
            records: [makeRecord(id: uuid(2), name: "Synthetic progression")]
        )

        let artifact = try exporter.prepare(preview)

        XCTAssertEqual(
            artifact.url,
            fileSystem.root
                .appendingPathComponent("PacePrompt", isDirectory: true)
                .appendingPathComponent("Exports", isDirectory: true)
                .appendingPathComponent(SavedPlanExportSchema.fileName)
        )
        XCTAssertEqual(
            fileSystem.events,
            ["directory", "protect", "verify", "remove", "write", "protect", "verify"]
        )
        let data = try XCTUnwrap(fileSystem.writtenData)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["formatVersion"] as? Int, SavedPlanExportSchema.currentVersion)
        XCTAssertEqual((json["savedPlans"] as? [Any])?.count, 1)
    }

    func testExporterRejectsEmptySelectionBeforeTouchingTemporaryStorage() {
        let fileSystem = ExportFileSystemDouble()
        let exporter = SavedPlanExporter(fileSystem: fileSystem)
        let preview = SavedPlanExportPreview(
            createdAt: Date(timeIntervalSince1970: 1),
            fileName: SavedPlanExportSchema.fileName,
            records: []
        )

        XCTAssertThrowsError(try exporter.prepare(preview)) { error in
            XCTAssertEqual(error as? SavedPlanExportFailure, .noRecords)
        }
        XCTAssertEqual(fileSystem.events, [])
    }

    func testExporterMapsEncodingDirectoryCleanupWriteAndProtectionFailures() {
        assertPreparationFailure(.encoding, codecFails: true)
        assertPreparationFailure(.directoryPreparation, fileSystemFailure: .directory)
        assertPreparationFailure(.previousArtifactCleanup, fileSystemFailure: .remove)
        assertPreparationFailure(.protectedWrite, fileSystemFailure: .write)
        assertPreparationFailure(.fileProtection, fileSystemFailure: .protect)
        assertPreparationFailure(.fileProtection, fileSystemFailure: .verify)
    }

    func testCleanupRemovesOnlyThePreparedArtifactURL() throws {
        let fileSystem = ExportFileSystemDouble()
        let exporter = SavedPlanExporter(fileSystem: fileSystem)
        let artifact = SavedPlanExportArtifact(url: fileSystem.root.appendingPathComponent("export.json"))

        try exporter.cleanup(artifact)

        XCTAssertEqual(fileSystem.removedURLs, [artifact.url])
    }

    func testCleanupFailureIsExplicit() {
        let fileSystem = ExportFileSystemDouble(failure: .remove)
        let exporter = SavedPlanExporter(fileSystem: fileSystem)

        XCTAssertThrowsError(
            try exporter.cleanup(.init(url: fileSystem.root.appendingPathComponent("export.json")))
        ) { error in
            XCTAssertEqual(error as? SavedPlanExportFailure, .cleanup)
        }
    }

    private func assertPreparationFailure(
        _ expected: SavedPlanExportFailure,
        fileSystemFailure: ExportFileSystemDouble.Operation? = nil,
        codecFails: Bool = false
    ) {
        let fileSystem = ExportFileSystemDouble(failure: fileSystemFailure)
        let exporter = SavedPlanExporter(
            fileSystem: fileSystem,
            codec: codecFails ? FailingExportCodec() : SavedPlanExportJSONCodec()
        )
        let preview = SavedPlanExportPreview(
            createdAt: Date(timeIntervalSince1970: 1),
            fileName: SavedPlanExportSchema.fileName,
            records: [makeRecord(id: uuid(3), name: "Synthetic plan")]
        )

        XCTAssertThrowsError(try exporter.prepare(preview)) { error in
            XCTAssertEqual(error as? SavedPlanExportFailure, expected)
        }
    }
}

@MainActor
final class SavedPlanExportPresentationTests: XCTestCase {
    func testSelectionPreviewAndShareRemainSeparateAndPreserveRepositoryOrder() {
        let first = makeRecord(id: uuid(10), name: "First synthetic plan")
        let second = makeRecord(id: uuid(11), name: "Second synthetic plan")
        let repository = ExportRepositoryDouble(records: [first, second])
        let exporter = ExporterDouble()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_100)
        let model = PlansViewModel(
            repository: repository,
            exporter: exporter,
            now: { createdAt }
        )

        model.beginExport()
        XCTAssertTrue(model.isExportPresented)
        XCTAssertTrue(model.selectedExportRecordIDs.isEmpty)
        XCTAssertFalse(model.canPreviewExport)
        XCTAssertEqual(exporter.previews.count, 0)

        model.toggleExportSelection(second)
        model.toggleExportSelection(first)
        model.reviewExport()

        XCTAssertEqual(model.exportPreview?.createdAt, createdAt)
        XCTAssertEqual(model.exportPreview?.fileName, "PacePrompt-saved-plans.json")
        XCTAssertEqual(model.exportPreview?.category, "savedPlans")
        XCTAssertEqual(model.exportPreview?.records, [first, second])
        XCTAssertEqual(exporter.previews.count, 0)
        XCTAssertEqual(repository.mutationCount, 0)

        model.prepareExportForSharing()

        XCTAssertEqual(exporter.previews, [model.exportPreview])
        XCTAssertEqual(model.shareArtifact, exporter.artifact)
        XCTAssertEqual(repository.mutationCount, 0)

        model.completeSharing()

        XCTAssertEqual(exporter.cleanedArtifacts, [exporter.artifact])
        XCTAssertFalse(model.isExportPresented)
        XCTAssertNil(model.exportPreview)
        XCTAssertEqual(repository.mutationCount, 0)
    }

    func testExportIsUnavailableForEveryBlockedRepositoryStateAndStaleStaging() {
        let record = makeRecord(id: uuid(20), name: "Synthetic plan")
        let blockedStates: [SavedPlanCanonicalState] = [
            .protectedDataUnavailable,
            .readFailure,
            .corruptData,
            .partialWriteDetected,
            .unsupportedStoreVersion(2),
            .unsupportedPlanVersion(recordID: record.id, version: 2),
        ]

        for state in blockedStates {
            let model = PlansViewModel(
                repository: ExportRepositoryDouble(records: [record], canonical: state),
                exporter: ExporterDouble()
            )
            XCTAssertFalse(model.canBeginExport, "Unexpected export for \(state)")
            model.beginExport()
            XCTAssertFalse(model.isExportPresented)
        }

        let staleModel = PlansViewModel(
            repository: ExportRepositoryDouble(records: [record], staging: .staleArtifactPresent),
            exporter: ExporterDouble()
        )
        XCTAssertFalse(staleModel.canBeginExport)
        staleModel.beginExport()
        XCTAssertFalse(staleModel.isExportPresented)
    }

    func testRepositoryChangeAfterPreviewFailsBeforeCreatingArtifact() {
        let record = makeRecord(id: uuid(30), name: "Original synthetic plan")
        let repository = ExportRepositoryDouble(records: [record])
        let exporter = ExporterDouble()
        let model = PlansViewModel(repository: repository, exporter: exporter)
        model.beginExport()
        model.toggleExportSelection(record)
        model.reviewExport()

        repository.records = []
        model.prepareExportForSharing()

        XCTAssertNil(model.shareArtifact)
        XCTAssertNil(model.exportPreview)
        XCTAssertEqual(exporter.previews.count, 0)
        XCTAssertEqual(
            model.exportError,
            "Saved plans changed or became unavailable after preview. Review the current records again. No file was created."
        )
    }

    func testPreparationAndCleanupFailuresStayVisibleWithoutMutatingPlans() {
        let record = makeRecord(id: uuid(40), name: "Synthetic plan")
        let repository = ExportRepositoryDouble(records: [record])
        let exporter = ExporterDouble()
        let model = PlansViewModel(repository: repository, exporter: exporter)
        model.beginExport()
        model.toggleExportSelection(record)
        model.reviewExport()

        exporter.prepareFailure = .fileProtection
        model.prepareExportForSharing()
        XCTAssertNil(model.shareArtifact)
        XCTAssertEqual(
            model.exportError,
            "Complete file protection could not be verified, so the temporary export was not shared."
        )

        exporter.prepareFailure = nil
        model.prepareExportForSharing()
        exporter.cleanupFailure = .cleanup
        model.completeSharing()

        XCTAssertFalse(model.isExportPresented)
        XCTAssertEqual(
            model.exportError,
            "The temporary export could not be removed after sharing. Retry export cleanup before creating another copy."
        )

        model.completeSharing()
        XCTAssertEqual(
            model.exportError,
            "The temporary export could not be removed after sharing. Retry export cleanup before creating another copy."
        )
        XCTAssertEqual(repository.mutationCount, 0)
    }
}

private enum ExportTestError: Error {
    case failed
}

private struct FailingExportCodec: SavedPlanExportCoding {
    func encode(_ document: SavedPlanExportDocument) throws -> Data {
        throw ExportTestError.failed
    }
}

private final class ExportFileSystemDouble: SavedPlanExportFileSystem {
    enum Operation {
        case directory
        case remove
        case write
        case protect
        case verify
    }

    let root = URL(fileURLWithPath: "/synthetic/tmp", isDirectory: true)
    let failure: Operation?
    private(set) var events: [String] = []
    private(set) var removedURLs: [URL] = []
    private(set) var writtenData: Data?

    init(failure: Operation? = nil) {
        self.failure = failure
    }

    func temporaryDirectory() throws -> URL { root }

    func createProtectedDirectory(at url: URL) throws {
        events.append("directory")
        if failure == .directory { throw ExportTestError.failed }
    }

    func removeItemIfPresent(at url: URL) throws {
        events.append("remove")
        removedURLs.append(url)
        if failure == .remove { throw ExportTestError.failed }
    }

    func writeProtectedData(_ data: Data, to url: URL) throws {
        events.append("write")
        if failure == .write { throw ExportTestError.failed }
        writtenData = data
    }

    func applyCompleteFileProtection(to url: URL) throws {
        events.append("protect")
        if failure == .protect { throw ExportTestError.failed }
    }

    func hasCompleteFileProtection(at url: URL) throws -> Bool {
        events.append("verify")
        return failure != .verify
    }
}

private final class ExporterDouble: SavedPlanExporting {
    let artifact = SavedPlanExportArtifact(
        url: URL(fileURLWithPath: "/synthetic/PacePrompt-saved-plans.json")
    )
    var prepareFailure: SavedPlanExportFailure?
    var cleanupFailure: SavedPlanExportFailure?
    private(set) var previews: [SavedPlanExportPreview?] = []
    private(set) var cleanedArtifacts: [SavedPlanExportArtifact] = []

    func prepare(_ preview: SavedPlanExportPreview) throws -> SavedPlanExportArtifact {
        previews.append(preview)
        if let prepareFailure { throw prepareFailure }
        return artifact
    }

    func cleanup(_ artifact: SavedPlanExportArtifact) throws {
        cleanedArtifacts.append(artifact)
        if let cleanupFailure { throw cleanupFailure }
    }
}

private final class ExportRepositoryDouble: SavedPlanRepositoryProtocol {
    var records: [SavedPlanRecord]
    var canonical: SavedPlanCanonicalState?
    var staging: SavedPlanStagingState
    private(set) var mutationCount = 0

    init(
        records: [SavedPlanRecord],
        canonical: SavedPlanCanonicalState? = nil,
        staging: SavedPlanStagingState = .absent
    ) {
        self.records = records
        self.canonical = canonical
        self.staging = staging
    }

    func list() -> SavedPlanRepositoryStatus {
        .init(
            canonical: canonical ?? (records.isEmpty ? .empty : .available(records: records)),
            staging: staging
        )
    }

    func create(_ validatedPlan: WorkoutPlanValidator.ValidatedPlan) throws -> SavedPlanRecord {
        mutationCount += 1
        throw ExportTestError.failed
    }

    func replace(
        id: UUID,
        with validatedPlan: WorkoutPlanValidator.ValidatedPlan
    ) throws -> SavedPlanRecord {
        mutationCount += 1
        throw ExportTestError.failed
    }

    func delete(id: UUID) throws {
        mutationCount += 1
        throw ExportTestError.failed
    }
}

private func makeRecord(id: UUID, name: String) -> SavedPlanRecord {
    SavedPlanRecord(
        id: id,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        modifiedAt: Date(timeIntervalSince1970: 1_700_000_050),
        plan: WorkoutPlan(
            schemaVersion: WorkoutPlanSchema.currentVersion,
            suggestedName: name,
            activity: .indoorRunning,
            steps: [
                WorkoutStep(
                    kind: .interval,
                    label: "Synthetic effort",
                    duration: .init(value: 60, unit: .seconds),
                    targetSpeed: .init(value: Decimal(string: "8.5")!, unit: .kilometresPerHour),
                    targetInclination: .init(value: Decimal(string: "1.0")!, unit: .percent)
                ),
            ]
        )
    )
}

private func uuid(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
}
