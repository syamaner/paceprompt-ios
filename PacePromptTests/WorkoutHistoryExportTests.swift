import Foundation
import XCTest
@testable import PacePrompt

final class WorkoutHistoryExportTests: XCTestCase {
    func testCheckedFixtureLocksSchemaNumbersOrderingAndProhibitedExclusions() throws {
        let summary = makeSummary()
        let createdAt = date("2026-09-13T12:00:00Z")
        let document = WorkoutHistoryExportDocument(
            formatVersion: 1,
            createdAt: createdAt,
            workouts: [try WorkoutHistoryExportMapper.map(summary)]
        )
        let codec = WorkoutHistoryExportJSONCodec()
        let encoded = try codec.encode(document)
        XCTAssertEqual(encoded, try codec.encode(document), "Encoding must be deterministic")

        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/fixtures/paceprompt-workout-history-v1.synthetic.json")
        let fixture = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: encoded) as? NSDictionary,
            try JSONSerialization.jsonObject(with: fixture) as? NSDictionary
        )

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["formatVersion", "createdAt", "workouts"])
        let workout = try XCTUnwrap((root["workouts"] as? [[String: Any]])?.first)
        XCTAssertEqual(
            Set(workout.keys),
            ["summaryID", "summarySchemaVersion", "activity", "outcome", "timing",
             "prescribedSegments", "executedIntervals", "distance"]
        )
        let prescribed = try XCTUnwrap(workout["prescribedSegments"] as? [[String: Any]])
        XCTAssertEqual(prescribed.map { $0["segmentIndex"] as? Int }, [0, 1, 2])
        XCTAssertTrue(prescribed[0]["speedKilometresPerHour"] is NSNumber)
        let intervals = try XCTUnwrap(workout["executedIntervals"] as? [[String: Any]])
        XCTAssertEqual(intervals.map { $0["segmentIndex"] as? Int }, [0, 1, 1, 2])
        XCTAssertEqual(intervals.map { $0["intervalIndex"] as? Int }, [0, 0, 1, 0])
        XCTAssertEqual(
            (intervals[2]["effectiveSpeed"] as? [String: Any])?["source"] as? String,
            "manualOverride"
        )
        XCTAssertEqual(
            (intervals[2]["settledObservation"] as? [String: Any])?["state"] as? String,
            "observed"
        )
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for prohibited in [
            "healthExport", "workoutUUID", "sourcePlanID", "suggestedName", "label",
            "prompt", "provider", "peripheral", "packet", "command", "diagnostic",
        ] {
            XCTAssertFalse(text.contains(prohibited), "Unexpected prohibited field: \(prohibited)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(WorkoutHistoryExportDocument.self, from: encoded), document)
    }

    func testUnavailableDistanceIsExplicitAndNeverInferred() throws {
        let summary = copy(
            makeSummary(),
            distance: .unavailable(reason: .init(rawValue: "missingDistanceBoundary"))
        )
        let workout = try WorkoutHistoryExportMapper.map(summary)
        XCTAssertEqual(workout.distance, .unavailable(reasonCode: "missingDistanceBoundary"))
    }

    func testVersionOneAndUnavailableTimingFailWithoutReconstruction() {
        let current = makeSummary()
        let legacy = WorkoutExecutionSummary(
            id: current.id,
            schemaVersion: 1,
            sourcePlanID: current.sourcePlanID,
            planSnapshot: current.planSnapshot,
            attemptedAt: current.attemptedAt,
            lastUpdatedAt: current.lastUpdatedAt,
            outcome: current.outcome,
            activeDuration: current.activeDuration,
            distance: .measured(metres: 45),
            progress: current.progress,
            physicalStopConfirmation: current.physicalStopConfirmation
        )
        XCTAssertThrowsError(try WorkoutHistoryExportMapper.map(legacy)) {
            XCTAssertEqual($0 as? WorkoutHistoryExportEligibilityFailure, .versionOne)
        }

        let unavailable = copy(
            current,
            timeline: .unavailable(reason: .init(rawValue: "timingUnavailable"))
        )
        XCTAssertThrowsError(try WorkoutHistoryExportMapper.map(unavailable)) {
            XCTAssertEqual($0 as? WorkoutHistoryExportEligibilityFailure, .unavailableTimeline)
        }
    }

    func testInconsistentIntervalOrderDurationAndLegacyDistanceAreRejected() {
        let summary = makeSummary()
        guard case let .recorded(start, end, provenance, intervals)? = summary.activityTimeline else {
            return XCTFail("Expected recorded timeline")
        }
        let overlapping = copy(
            summary,
            timeline: .recorded(
                startedAt: start,
                endedAt: end,
                timingProvenance: provenance,
                executedIntervals: [intervals[0], copy(intervals[1], startedAt: start.addingTimeInterval(30))]
            ),
            activeDuration: .measured(seconds: 120)
        )
        XCTAssertThrowsError(try WorkoutHistoryExportMapper.map(overlapping)) {
            XCTAssertEqual($0 as? WorkoutHistoryExportEligibilityFailure, .inconsistentRecord)
        }

        let first = intervals[0]
        let mismatchedObservation = WorkoutExecutedInterval(
            segmentIndex: first.segmentIndex,
            intervalIndex: first.intervalIndex,
            startedAt: first.startedAt,
            endedAt: first.endedAt,
            prescribed: first.prescribed,
            effectiveSpeed: first.effectiveSpeed,
            effectiveInclination: first.effectiveInclination,
            settledObservation: .init(
                observedAt: first.startedAt,
                speedKilometresPerHour: 9,
                inclinationPercent: first.settledObservation.inclinationPercent,
                provenance: .fr30zTreadmillDataCurrentEpoch
            ),
            endReason: first.endReason
        )
        let collapsedEvidence = copy(
            summary,
            timeline: .recorded(
                startedAt: start,
                endedAt: end,
                timingProvenance: provenance,
                executedIntervals: [mismatchedObservation] + Array(intervals.dropFirst())
            )
        )
        XCTAssertThrowsError(try WorkoutHistoryExportMapper.map(collapsedEvidence)) {
            XCTAssertEqual($0 as? WorkoutHistoryExportEligibilityFailure, .inconsistentRecord)
        }

        let legacyDistance = copy(summary, distance: .measured(metres: 45))
        XCTAssertThrowsError(try WorkoutHistoryExportMapper.map(legacyDistance)) {
            XCTAssertEqual($0 as? WorkoutHistoryExportEligibilityFailure, .inconsistentRecord)
        }
    }

    func testExporterUsesProtectedTemporaryFileAndCleansOnlyItsArtifact() throws {
        let fileSystem = HistoryExportFileSystemDouble()
        let exporter = WorkoutHistoryExporter(fileSystem: fileSystem)
        let summary = makeSummary()
        let preview = WorkoutHistoryExportPreview(
            createdAt: date("2026-09-13T12:00:00Z"),
            fileName: WorkoutHistoryExportSchema.fileName,
            sourceSummaries: [summary],
            workouts: [try WorkoutHistoryExportMapper.map(summary)]
        )

        let artifact = try exporter.prepare(preview)
        XCTAssertEqual(
            artifact.url,
            fileSystem.root
                .appendingPathComponent("PacePrompt", isDirectory: true)
                .appendingPathComponent("Exports", isDirectory: true)
                .appendingPathComponent(WorkoutHistoryExportSchema.fileName)
        )
        XCTAssertEqual(fileSystem.events, ["directory", "protect", "verify", "remove", "write", "protect", "verify"])
        try exporter.cleanup(artifact)
        XCTAssertEqual(fileSystem.removedURLs.last, artifact.url)
    }

    func testExporterMapsEveryPreparationAndCleanupFailure() throws {
        let summary = makeSummary()
        let preview = WorkoutHistoryExportPreview(
            createdAt: date("2026-09-13T12:00:00Z"),
            fileName: WorkoutHistoryExportSchema.fileName,
            sourceSummaries: [summary],
            workouts: [try WorkoutHistoryExportMapper.map(summary)]
        )
        let cases: [(HistoryExportFileSystemDouble.Operation, WorkoutHistoryExportFailure)] = [
            (.directory, .directoryPreparation), (.remove, .previousArtifactCleanup),
            (.write, .protectedWrite), (.protect, .fileProtection), (.verify, .fileProtection),
        ]
        for (operation, expected) in cases {
            let exporter = WorkoutHistoryExporter(fileSystem: HistoryExportFileSystemDouble(failure: operation))
            XCTAssertThrowsError(try exporter.prepare(preview)) {
                XCTAssertEqual($0 as? WorkoutHistoryExportFailure, expected)
            }
        }
        let codecExporter = WorkoutHistoryExporter(
            fileSystem: HistoryExportFileSystemDouble(),
            codec: FailingHistoryExportCodec()
        )
        XCTAssertThrowsError(try codecExporter.prepare(preview)) {
            XCTAssertEqual($0 as? WorkoutHistoryExportFailure, .encoding)
        }
        let cleanupExporter = WorkoutHistoryExporter(
            fileSystem: HistoryExportFileSystemDouble(failure: .remove)
        )
        XCTAssertThrowsError(
            try cleanupExporter.cleanup(.init(url: URL(fileURLWithPath: "/synthetic/export.json")))
        ) {
            XCTAssertEqual($0 as? WorkoutHistoryExportFailure, .cleanup)
        }
    }

    fileprivate func makeSummary(id: Int = 1) -> WorkoutExecutionSummary {
        let start = date("2026-09-13T11:50:00Z")
        let steps = [
            step(.warmUp, duration: 60, speed: "0.5", inclination: "0"),
            step(.interval, duration: 180, speed: "0.6", inclination: "0"),
            step(.coolDown, duration: 60, speed: "0.5", inclination: "0"),
        ]
        let plan = WorkoutPlan(
            schemaVersion: 1,
            suggestedName: "Synthetic export fixture",
            activity: .indoorWalking,
            steps: steps
        )
        let intervals = [
            interval(plan, 0, 0, start, 60, "0.5", "0", .planned, .planned, .planTransition),
            interval(plan, 1, 0, start.addingTimeInterval(60), 60, "0.6", "0", .planned, .planned, .targetChanged),
            interval(plan, 1, 1, start.addingTimeInterval(120), 120, "0.7", "1", .manualOverride, .manualOverride, .planTransition),
            interval(plan, 2, 0, start.addingTimeInterval(240), 60, "0.5", "0", .planned, .planned, .completed),
        ]
        let end = start.addingTimeInterval(300)
        return .init(
            id: uuid(id),
            schemaVersion: 2,
            sourcePlanID: uuid(999),
            planSnapshot: plan,
            attemptedAt: start.addingTimeInterval(-10),
            lastUpdatedAt: end,
            outcome: .completed,
            activeDuration: .measured(seconds: 300),
            distance: .measuredWithProvenance(
                metres: 45,
                provenance: .init(
                    method: .fr30zCumulativeDistanceDelta,
                    startCumulativeMetres: 10,
                    startObservedAt: start,
                    finalCumulativeMetres: 55,
                    finalObservedAt: end
                )
            ),
            progress: .init(completedStepCount: 3, currentStepIndex: nil, activeSecondsInCurrentStep: 0),
            physicalStopConfirmation: .notRequired,
            activityTimeline: .recorded(
                startedAt: start,
                endedAt: end,
                timingProvenance: .executionClock,
                executedIntervals: intervals
            ),
            healthExport: .notRequested
        )
    }

    fileprivate func copy(
        _ summary: WorkoutExecutionSummary,
        timeline: WorkoutActivityTimeline? = nil,
        distance: WorkoutDistance? = nil,
        activeDuration: WorkoutActiveDuration? = nil
    ) -> WorkoutExecutionSummary {
        .init(
            id: summary.id,
            schemaVersion: summary.schemaVersion,
            sourcePlanID: summary.sourcePlanID,
            planSnapshot: summary.planSnapshot,
            attemptedAt: summary.attemptedAt,
            lastUpdatedAt: summary.lastUpdatedAt,
            outcome: summary.outcome,
            activeDuration: activeDuration ?? summary.activeDuration,
            distance: distance ?? summary.distance,
            progress: summary.progress,
            physicalStopConfirmation: summary.physicalStopConfirmation,
            activityTimeline: timeline ?? summary.activityTimeline,
            healthExport: summary.healthExport
        )
    }

    private func copy(_ interval: WorkoutExecutedInterval, startedAt: Date) -> WorkoutExecutedInterval {
        .init(
            segmentIndex: interval.segmentIndex,
            intervalIndex: interval.intervalIndex,
            startedAt: startedAt,
            endedAt: interval.endedAt,
            prescribed: interval.prescribed,
            effectiveSpeed: interval.effectiveSpeed,
            effectiveInclination: interval.effectiveInclination,
            settledObservation: .init(
                observedAt: startedAt,
                speedKilometresPerHour: interval.settledObservation.speedKilometresPerHour,
                inclinationPercent: interval.settledObservation.inclinationPercent,
                provenance: interval.settledObservation.provenance
            ),
            endReason: interval.endReason
        )
    }

    private func interval(
        _ plan: WorkoutPlan,
        _ segment: Int,
        _ index: Int,
        _ start: Date,
        _ seconds: Int,
        _ speed: String,
        _ inclination: String,
        _ speedSource: WorkoutTargetValueSource,
        _ inclinationSource: WorkoutTargetValueSource,
        _ endReason: WorkoutExecutedIntervalEndReason
    ) -> WorkoutExecutedInterval {
        let step = plan.steps[segment]
        return .init(
            segmentIndex: segment,
            intervalIndex: index,
            startedAt: start,
            endedAt: start.addingTimeInterval(TimeInterval(seconds)),
            prescribed: .init(
                kind: step.kind,
                speedKilometresPerHour: step.targetSpeed.value,
                inclinationPercent: step.targetInclination.value
            ),
            effectiveSpeed: .init(kilometresPerHour: decimal(speed), source: speedSource),
            effectiveInclination: .init(percent: decimal(inclination), source: inclinationSource),
            settledObservation: .init(
                observedAt: start,
                speedKilometresPerHour: decimal(speed),
                inclinationPercent: decimal(inclination),
                provenance: .fr30zTreadmillDataCurrentEpoch
            ),
            endReason: endReason
        )
    }

    private func step(
        _ kind: WorkoutStepKind,
        duration: Int,
        speed: String,
        inclination: String
    ) -> WorkoutStep {
        .init(
            kind: kind,
            label: "Synthetic",
            duration: .init(value: duration, unit: .seconds),
            targetSpeed: .init(value: decimal(speed), unit: .kilometresPerHour),
            targetInclination: .init(value: decimal(inclination), unit: .percent)
        )
    }

    fileprivate func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    fileprivate func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

@MainActor
final class WorkoutHistoryExportPresentationTests: XCTestCase {
    func testSelectionPreviewShareAndCleanupAreSeparateAndDoNotMutateHistory() throws {
        let fixtures = WorkoutHistoryExportTests()
        let first = fixtures.makeSummary(id: 1)
        let second = fixtures.makeSummary(id: 2)
        let repository = HistoryExportRepositoryDouble([second, first])
        let exporter = HistoryExporterDouble()
        let now = fixtures.date("2026-09-13T12:00:00Z")
        let model = HistoryLibraryViewModel(
            history: repository,
            healthStore: HistoryExportHealthStoreDouble(),
            historyExporter: exporter,
            now: { now }
        )
        model.reload()

        model.beginHistoryExport()
        XCTAssertTrue(model.isHistoryExportPresented)
        XCTAssertFalse(model.canReviewHistoryExport)
        model.toggleHistoryExportSelection(second.id)
        model.toggleHistoryExportSelection(first.id)
        model.reviewHistoryExport()

        XCTAssertEqual(model.historyExportPreview?.createdAt, now)
        XCTAssertEqual(model.historyExportPreview?.sourceSummaries, [first, second])
        XCTAssertEqual(model.historyExportPreview?.recordCount, 2)
        XCTAssertTrue(model.historyExportPreview?.includedFields.contains {
            $0.contains("effective-target and observed speed and inclination")
        } == true)
        XCTAssertEqual(repository.mutationCount, 0)
        XCTAssertTrue(exporter.previews.isEmpty)

        model.prepareHistoryExportForSharing()
        XCTAssertEqual(exporter.previews, [model.historyExportPreview])
        XCTAssertEqual(model.historyShareArtifact, exporter.artifact)
        model.completeHistorySharing()
        XCTAssertEqual(exporter.cleaned, [exporter.artifact])
        XCTAssertFalse(model.isHistoryExportPresented)
        XCTAssertEqual(repository.mutationCount, 0)

        model.beginHistoryExport(preselecting: first.id)
        model.reviewHistoryExport()
        model.prepareHistoryExportForSharing()
        model.cancelHistoryExport()
        XCTAssertEqual(exporter.cleaned, [exporter.artifact, exporter.artifact])
        XCTAssertFalse(model.isHistoryExportPresented)
        XCTAssertEqual(repository.mutationCount, 0)
    }

    func testVersionOneIsVisibleButCannotBeSelectedOrExported() {
        let fixtures = WorkoutHistoryExportTests()
        let current = fixtures.makeSummary()
        let legacy = WorkoutExecutionSummary(
            id: fixtures.uuid(3),
            schemaVersion: 1,
            sourcePlanID: nil,
            planSnapshot: current.planSnapshot,
            attemptedAt: current.attemptedAt,
            lastUpdatedAt: current.lastUpdatedAt,
            outcome: .completed,
            activeDuration: .measured(seconds: 300),
            distance: .measured(metres: 45),
            progress: current.progress,
            physicalStopConfirmation: .notRequired
        )
        let model = HistoryLibraryViewModel(
            history: HistoryExportRepositoryDouble([legacy]),
            healthStore: HistoryExportHealthStoreDouble(),
            historyExporter: HistoryExporterDouble()
        )
        model.reload()
        model.beginHistoryExport()

        XCTAssertTrue(model.isHistoryExportPresented)
        XCTAssertEqual(model.historyExportSelections.single?.failure, .versionOne)
        model.toggleHistoryExportSelection(legacy.id)
        XCTAssertTrue(model.selectedHistoryExportIDs.isEmpty)
        XCTAssertFalse(model.canExport(summaryID: legacy.id))
        XCTAssertTrue(model.historyExportFailure(summaryID: legacy.id)?.contains("cannot be reconstructed") == true)
    }

    func testBlockedRepositoryAndStagingNeverCreateStructuredExport() {
        let fixtures = WorkoutHistoryExportTests()
        let summary = fixtures.makeSummary()
        for canonical in [
            WorkoutHistoryCanonicalState.protectedDataUnavailable,
            .readFailure, .corruptData, .partialWriteDetected,
            .unsupportedStoreVersion(2), .unsupportedSummaryVersion(summaryID: summary.id, version: 3),
        ] {
            let repository = HistoryExportRepositoryDouble([summary], canonical: canonical)
            let model = HistoryLibraryViewModel(
                history: repository,
                healthStore: HistoryExportHealthStoreDouble(),
                historyExporter: HistoryExporterDouble()
            )
            model.reload()
            XCTAssertFalse(model.canBeginHistoryExport)
            model.beginHistoryExport()
            XCTAssertFalse(model.isHistoryExportPresented)
        }

        let staged = HistoryExportRepositoryDouble([summary], staging: .staleArtifactPresent)
        let model = HistoryLibraryViewModel(
            history: staged,
            healthStore: HistoryExportHealthStoreDouble(),
            historyExporter: HistoryExporterDouble()
        )
        model.reload()
        XCTAssertFalse(model.canBeginHistoryExport)
    }

    func testChangedRepositoryAfterPreviewFailsBeforeFileCreation() {
        let fixtures = WorkoutHistoryExportTests()
        let summary = fixtures.makeSummary()
        let repository = HistoryExportRepositoryDouble([summary])
        let exporter = HistoryExporterDouble()
        let model = HistoryLibraryViewModel(
            history: repository,
            healthStore: HistoryExportHealthStoreDouble(),
            historyExporter: exporter
        )
        model.reload()
        model.beginHistoryExport(preselecting: summary.id)
        model.reviewHistoryExport()
        repository.summaries = []

        model.prepareHistoryExportForSharing()

        XCTAssertNil(model.historyShareArtifact)
        XCTAssertTrue(exporter.previews.isEmpty)
        XCTAssertNil(model.historyExportPreview)
        XCTAssertTrue(model.historyExportError?.contains("changed or became unavailable") == true)
        XCTAssertEqual(repository.mutationCount, 0)
    }
}

private enum HistoryExportTestError: Error { case failed }

private struct FailingHistoryExportCodec: WorkoutHistoryExportCoding {
    func encode(_ document: WorkoutHistoryExportDocument) throws -> Data {
        throw HistoryExportTestError.failed
    }
}

private final class HistoryExportFileSystemDouble: WorkoutHistoryExportFileSystem {
    enum Operation { case directory, remove, write, protect, verify }
    let root = URL(fileURLWithPath: "/synthetic/tmp", isDirectory: true)
    let failure: Operation?
    private(set) var events: [String] = []
    private(set) var removedURLs: [URL] = []

    init(failure: Operation? = nil) { self.failure = failure }
    func temporaryDirectory() throws -> URL { root }
    func createProtectedDirectory(at url: URL) throws {
        events.append("directory")
        if failure == .directory { throw HistoryExportTestError.failed }
    }
    func removeItemIfPresent(at url: URL) throws {
        events.append("remove")
        removedURLs.append(url)
        if failure == .remove { throw HistoryExportTestError.failed }
    }
    func writeProtectedData(_ data: Data, to url: URL) throws {
        events.append("write")
        if failure == .write { throw HistoryExportTestError.failed }
    }
    func applyCompleteFileProtection(to url: URL) throws {
        events.append("protect")
        if failure == .protect { throw HistoryExportTestError.failed }
    }
    func hasCompleteFileProtection(at url: URL) throws -> Bool {
        events.append("verify")
        return failure != .verify
    }
}

private final class HistoryExportRepositoryDouble: WorkoutHistoryRepositoryProtocol {
    var summaries: [WorkoutExecutionSummary]
    var canonical: WorkoutHistoryCanonicalState?
    let staging: WorkoutHistoryStagingState
    private(set) var mutationCount = 0

    init(
        _ summaries: [WorkoutExecutionSummary],
        canonical: WorkoutHistoryCanonicalState? = nil,
        staging: WorkoutHistoryStagingState = .absent
    ) {
        self.summaries = summaries
        self.canonical = canonical
        self.staging = staging
    }
    func list() -> WorkoutHistoryRepositoryStatus {
        .init(canonical: canonical ?? .available(summaries: summaries), staging: staging)
    }
    func record(_ summary: WorkoutExecutionSummary) { mutationCount += 1 }
    func updateHealthExport(summaryID: UUID, state: WorkoutHealthExportState) throws {
        mutationCount += 1
    }
}

private final class HistoryExporterDouble: WorkoutHistoryExporting {
    let artifact = WorkoutHistoryExportArtifact(url: URL(fileURLWithPath: "/synthetic/export.json"))
    private(set) var previews: [WorkoutHistoryExportPreview] = []
    private(set) var cleaned: [WorkoutHistoryExportArtifact] = []
    func prepare(_ preview: WorkoutHistoryExportPreview) throws -> WorkoutHistoryExportArtifact {
        previews.append(preview)
        return artifact
    }
    func cleanup(_ artifact: WorkoutHistoryExportArtifact) throws { cleaned.append(artifact) }
}

private final class HistoryExportHealthStoreDouble: WorkoutHealthStoreProtocol {
    var isHealthDataAvailable: Bool { false }
    func requestWriteAuthorization() async throws {}
    func authorizationStatus(for type: WorkoutHealthWriteType) -> WorkoutHealthAuthorizationStatus {
        .denied
    }
    func save(_ payload: WorkoutHealthExportPayload) async throws -> UUID { UUID() }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
