import Foundation

enum WorkoutHistoryExportSchema {
    static let currentVersion = 1
    static let fileName = "PacePrompt-workout-history.json"
    static let includedFields = [
        "formatVersion and UTC createdAt",
        "workout identity, schema, activity and outcome",
        "execution-clock start, end and active duration",
        "prescribed segment speed and inclination",
        "executed interval prescribed, effective-target and observed speed and inclination",
        "interval timing, target sources, observation provenance and end reason",
        "trustworthy distance and cumulative-distance provenance when available",
    ]
}

struct WorkoutHistoryExportDocument: Codable, Equatable {
    let formatVersion: Int
    let createdAt: Date
    let workouts: [WorkoutHistoryExportWorkout]
}

struct WorkoutHistoryExportWorkout: Codable, Equatable {
    let summaryID: UUID
    let summarySchemaVersion: Int
    let activity: WorkoutActivity
    let outcome: String
    let timing: WorkoutHistoryExportTiming
    let prescribedSegments: [WorkoutHistoryExportPrescribedSegment]
    let executedIntervals: [WorkoutHistoryExportExecutedInterval]
    let distance: WorkoutHistoryExportDistance
}

struct WorkoutHistoryExportTiming: Codable, Equatable {
    let startedAt: Date
    let endedAt: Date
    let activeDurationSeconds: Int
    let provenance: WorkoutTimingProvenance
}

struct WorkoutHistoryExportPrescribedSegment: Codable, Equatable {
    let segmentIndex: Int
    let kind: WorkoutStepKind
    let durationSeconds: Int
    let speedKilometresPerHour: Decimal
    let inclinationPercent: Decimal
}

struct WorkoutHistoryExportExecutedInterval: Codable, Equatable {
    let segmentIndex: Int
    let intervalIndex: Int
    let startedAt: Date
    let endedAt: Date
    let prescribed: WorkoutPrescribedIntervalValues
    let effectiveSpeed: WorkoutEffectiveSpeed
    let effectiveInclination: WorkoutEffectiveInclination
    let settledObservation: WorkoutHistoryExportSettledObservation
    let endReason: WorkoutExecutedIntervalEndReason
}

struct WorkoutHistoryExportSettledObservation: Codable, Equatable {
    let state: String
    let observedAt: Date
    let speedKilometresPerHour: Decimal
    let inclinationPercent: Decimal
    let provenance: WorkoutSettledObservation.Provenance
}

enum WorkoutHistoryExportDistance: Codable, Equatable {
    case measured(
        metres: Decimal,
        provenance: WorkoutDistanceProvenance.Method,
        startCumulativeMetres: Decimal,
        startObservedAt: Date,
        finalCumulativeMetres: Decimal,
        finalObservedAt: Date
    )
    case unavailable(reasonCode: String)

    private enum State: String, Codable { case measured, unavailable }
    private enum CodingKeys: String, CodingKey {
        case state, metres, provenance, startCumulativeMetres, startObservedAt,
            finalCumulativeMetres, finalObservedAt, reasonCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .measured:
            self = .measured(
                metres: try container.decode(Decimal.self, forKey: .metres),
                provenance: try container.decode(
                    WorkoutDistanceProvenance.Method.self,
                    forKey: .provenance
                ),
                startCumulativeMetres: try container.decode(
                    Decimal.self,
                    forKey: .startCumulativeMetres
                ),
                startObservedAt: try container.decode(Date.self, forKey: .startObservedAt),
                finalCumulativeMetres: try container.decode(
                    Decimal.self,
                    forKey: .finalCumulativeMetres
                ),
                finalObservedAt: try container.decode(Date.self, forKey: .finalObservedAt)
            )
        case .unavailable:
            self = .unavailable(reasonCode: try container.decode(String.self, forKey: .reasonCode))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .measured(metres, provenance, startMetres, startAt, finalMetres, finalAt):
            try container.encode(State.measured, forKey: .state)
            try container.encode(metres, forKey: .metres)
            try container.encode(provenance, forKey: .provenance)
            try container.encode(startMetres, forKey: .startCumulativeMetres)
            try container.encode(startAt, forKey: .startObservedAt)
            try container.encode(finalMetres, forKey: .finalCumulativeMetres)
            try container.encode(finalAt, forKey: .finalObservedAt)
        case let .unavailable(reasonCode):
            try container.encode(State.unavailable, forKey: .state)
            try container.encode(reasonCode, forKey: .reasonCode)
        }
    }
}

enum WorkoutHistoryExportEligibilityFailure: Error, Equatable {
    case versionOne
    case unsupportedSummaryVersion(Int)
    case unsupportedPlanVersion(Int)
    case unavailableTimeline
    case unavailableDuration
    case inconsistentRecord

    var message: String {
        switch self {
        case .versionOne:
            "Version-1 workouts remain readable but cannot be reconstructed for JSON export."
        case let .unsupportedSummaryVersion(version):
            "Workout summary schema v\(version) is not supported for JSON export."
        case let .unsupportedPlanVersion(version):
            "Plan schema v\(version) is not supported for JSON export."
        case .unavailableTimeline:
            "This workout has no recorded execution timeline and cannot be exported without inference."
        case .unavailableDuration:
            "This workout has no measured active duration and cannot be exported without inference."
        case .inconsistentRecord:
            "This workout is not internally consistent enough for structured JSON export."
        }
    }
}

enum WorkoutHistoryExportMapper {
    static func map(_ summary: WorkoutExecutionSummary) throws -> WorkoutHistoryExportWorkout {
        guard summary.schemaVersion != WorkoutExecutionSummarySchema.legacyVersion else {
            throw WorkoutHistoryExportEligibilityFailure.versionOne
        }
        guard summary.schemaVersion == WorkoutExecutionSummarySchema.currentVersion else {
            throw WorkoutHistoryExportEligibilityFailure.unsupportedSummaryVersion(
                summary.schemaVersion
            )
        }
        guard summary.planSnapshot.schemaVersion == WorkoutPlanSchema.currentVersion else {
            throw WorkoutHistoryExportEligibilityFailure.unsupportedPlanVersion(
                summary.planSnapshot.schemaVersion
            )
        }
        guard WorkoutPlanValidator.structuralIssues(in: summary.planSnapshot).isEmpty,
              summary.attemptedAt <= summary.lastUpdatedAt else {
            throw WorkoutHistoryExportEligibilityFailure.inconsistentRecord
        }
        guard case let .recorded(startedAt, endedAt, provenance, intervals)? =
            summary.activityTimeline else {
            throw WorkoutHistoryExportEligibilityFailure.unavailableTimeline
        }
        guard case let .measured(activeSeconds) = summary.activeDuration else {
            throw WorkoutHistoryExportEligibilityFailure.unavailableDuration
        }
        guard provenance == .executionClock,
              !intervals.isEmpty,
              intervals.first?.startedAt == startedAt,
              intervals.last?.endedAt == endedAt,
              startedAt >= summary.attemptedAt,
              endedAt <= summary.lastUpdatedAt,
              startedAt < endedAt,
              activeSeconds > 0,
              intervalsAreConsistent(
                intervals,
                with: summary.planSnapshot,
                timelineStart: startedAt,
                timelineEnd: endedAt,
                seconds: activeSeconds
              )
        else {
            throw WorkoutHistoryExportEligibilityFailure.inconsistentRecord
        }

        return .init(
            summaryID: summary.id,
            summarySchemaVersion: summary.schemaVersion,
            activity: summary.planSnapshot.activity,
            outcome: outcome(summary.outcome),
            timing: .init(
                startedAt: startedAt,
                endedAt: endedAt,
                activeDurationSeconds: activeSeconds,
                provenance: provenance
            ),
            prescribedSegments: summary.planSnapshot.steps.enumerated().map { index, step in
                .init(
                    segmentIndex: index,
                    kind: step.kind,
                    durationSeconds: step.duration.value,
                    speedKilometresPerHour: step.targetSpeed.value,
                    inclinationPercent: step.targetInclination.value
                )
            },
            executedIntervals: intervals.map {
                .init(
                    segmentIndex: $0.segmentIndex,
                    intervalIndex: $0.intervalIndex,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    prescribed: $0.prescribed,
                    effectiveSpeed: $0.effectiveSpeed,
                    effectiveInclination: $0.effectiveInclination,
                    settledObservation: .init(
                        state: "observed",
                        observedAt: $0.settledObservation.observedAt,
                        speedKilometresPerHour: $0.settledObservation.speedKilometresPerHour,
                        inclinationPercent: $0.settledObservation.inclinationPercent,
                        provenance: $0.settledObservation.provenance
                    ),
                    endReason: $0.endReason
                )
            },
            distance: try distance(
                summary.distance,
                timelineStart: startedAt,
                timelineEnd: endedAt
            )
        )
    }

    static func eligibility(of summary: WorkoutExecutionSummary) -> Result<Void, WorkoutHistoryExportEligibilityFailure> {
        do {
            _ = try map(summary)
            return .success(())
        } catch let failure as WorkoutHistoryExportEligibilityFailure {
            return .failure(failure)
        } catch {
            return .failure(.inconsistentRecord)
        }
    }

    private static func intervalsAreConsistent(
        _ intervals: [WorkoutExecutedInterval],
        with plan: WorkoutPlan,
        timelineStart: Date,
        timelineEnd: Date,
        seconds: Int
    ) -> Bool {
        var previousEnd: Date?
        var previousSegment = -1
        var nextIntervalIndex: [Int: Int] = [:]
        var duration: TimeInterval = 0
        for interval in intervals {
            guard plan.steps.indices.contains(interval.segmentIndex),
                  interval.segmentIndex >= previousSegment,
                  interval.intervalIndex == nextIntervalIndex[interval.segmentIndex, default: 0],
                  interval.startedAt < interval.endedAt,
                  interval.startedAt >= timelineStart,
                  interval.endedAt <= timelineEnd,
                  previousEnd.map({ interval.startedAt >= $0 }) ?? true,
                  interval.settledObservation.observedAt == interval.startedAt
            else { return false }
            let step = plan.steps[interval.segmentIndex]
            guard interval.prescribed.kind == step.kind,
                  interval.prescribed.speedKilometresPerHour == step.targetSpeed.value,
                  interval.prescribed.inclinationPercent == step.targetInclination.value,
                  interval.prescribed.speedKilometresPerHour.isFinite,
                  interval.prescribed.inclinationPercent.isFinite,
                  interval.effectiveSpeed.source != .planned
                    || interval.effectiveSpeed.kilometresPerHour
                      == interval.prescribed.speedKilometresPerHour,
                  interval.effectiveInclination.source != .planned
                    || interval.effectiveInclination.percent
                      == interval.prescribed.inclinationPercent,
                  interval.effectiveSpeed.kilometresPerHour.isFinite,
                  interval.effectiveInclination.percent.isFinite,
                  interval.settledObservation.speedKilometresPerHour.isFinite,
                  interval.settledObservation.inclinationPercent.isFinite,
                  interval.settledObservation.speedKilometresPerHour
                    == interval.effectiveSpeed.kilometresPerHour,
                  interval.settledObservation.inclinationPercent
                    == interval.effectiveInclination.percent
            else { return false }
            nextIntervalIndex[interval.segmentIndex, default: 0] += 1
            previousSegment = interval.segmentIndex
            previousEnd = interval.endedAt
            duration += interval.endedAt.timeIntervalSince(interval.startedAt)
        }
        return Int(floor(duration + 0.000_000_001)) == seconds
    }

    private static func outcome(_ outcome: WorkoutExecutionOutcome) -> String {
        switch outcome {
        case .inProgress: "inProgress"
        case .completed: "completed"
        case .stoppedByUser: "stoppedByUser"
        case .interrupted: "interrupted"
        case .failed: "failed"
        }
    }

    private static func distance(
        _ distance: WorkoutDistance,
        timelineStart: Date,
        timelineEnd: Date
    ) throws -> WorkoutHistoryExportDistance {
        switch distance {
        case let .measuredWithProvenance(metres, provenance):
            guard metres.isFinite,
                  metres >= 0,
                  provenance.startCumulativeMetres.isFinite,
                  provenance.finalCumulativeMetres.isFinite,
                  provenance.startCumulativeMetres >= 0,
                  provenance.finalCumulativeMetres >= provenance.startCumulativeMetres,
                  provenance.finalCumulativeMetres - provenance.startCumulativeMetres == metres,
                  provenance.startObservedAt == timelineStart,
                  provenance.finalObservedAt >= timelineEnd
            else { throw WorkoutHistoryExportEligibilityFailure.inconsistentRecord }
            return .measured(
                metres: metres,
                provenance: provenance.method,
                startCumulativeMetres: provenance.startCumulativeMetres,
                startObservedAt: provenance.startObservedAt,
                finalCumulativeMetres: provenance.finalCumulativeMetres,
                finalObservedAt: provenance.finalObservedAt
            )
        case .measured:
            throw WorkoutHistoryExportEligibilityFailure.inconsistentRecord
        case let .unavailable(reason):
            guard !reason.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkoutHistoryExportEligibilityFailure.inconsistentRecord
            }
            return .unavailable(reasonCode: reason.rawValue)
        }
    }
}

struct WorkoutHistoryExportPreview: Equatable {
    let createdAt: Date
    let fileName: String
    let sourceSummaries: [WorkoutExecutionSummary]
    let workouts: [WorkoutHistoryExportWorkout]

    var recordCount: Int { workouts.count }
    var includedFields: [String] { WorkoutHistoryExportSchema.includedFields }
}

struct WorkoutHistoryExportArtifact: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}

enum WorkoutHistoryExportFailure: Error, Equatable {
    case noRecords
    case encoding
    case directoryPreparation
    case previousArtifactCleanup
    case protectedWrite
    case fileProtection
    case cleanup
}

protocol WorkoutHistoryExportCoding {
    func encode(_ document: WorkoutHistoryExportDocument) throws -> Data
}

struct WorkoutHistoryExportJSONCodec: WorkoutHistoryExportCoding {
    func encode(_ document: WorkoutHistoryExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
}

protocol WorkoutHistoryExportFileSystem {
    func temporaryDirectory() throws -> URL
    func createProtectedDirectory(at url: URL) throws
    func removeItemIfPresent(at url: URL) throws
    func writeProtectedData(_ data: Data, to url: URL) throws
    func applyCompleteFileProtection(to url: URL) throws
    func hasCompleteFileProtection(at url: URL) throws -> Bool
}

struct FoundationWorkoutHistoryExportFileSystem: WorkoutHistoryExportFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func temporaryDirectory() throws -> URL { fileManager.temporaryDirectory }

    func createProtectedDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    func removeItemIfPresent(at url: URL) throws {
        do { try fileManager.removeItem(at: url) }
        catch {
            let error = error as NSError
            guard error.domain == NSCocoaErrorDomain,
                  error.code == CocoaError.fileNoSuchFile.rawValue
                    || error.code == CocoaError.fileReadNoSuchFile.rawValue
            else { throw error }
        }
    }

    func writeProtectedData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
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
}

protocol WorkoutHistoryExporting {
    func prepare(_ preview: WorkoutHistoryExportPreview) throws -> WorkoutHistoryExportArtifact
    func cleanup(_ artifact: WorkoutHistoryExportArtifact) throws
}

final class WorkoutHistoryExporter: WorkoutHistoryExporting {
    private let fileSystem: any WorkoutHistoryExportFileSystem
    private let codec: any WorkoutHistoryExportCoding

    init(
        fileSystem: any WorkoutHistoryExportFileSystem = FoundationWorkoutHistoryExportFileSystem(),
        codec: any WorkoutHistoryExportCoding = WorkoutHistoryExportJSONCodec()
    ) {
        self.fileSystem = fileSystem
        self.codec = codec
    }

    func prepare(_ preview: WorkoutHistoryExportPreview) throws -> WorkoutHistoryExportArtifact {
        guard !preview.workouts.isEmpty else { throw WorkoutHistoryExportFailure.noRecords }
        let directory: URL
        do {
            directory = try fileSystem.temporaryDirectory()
                .appendingPathComponent("PacePrompt", isDirectory: true)
                .appendingPathComponent("Exports", isDirectory: true)
            try fileSystem.createProtectedDirectory(at: directory)
        } catch { throw WorkoutHistoryExportFailure.directoryPreparation }

        do {
            try fileSystem.applyCompleteFileProtection(to: directory)
            guard try fileSystem.hasCompleteFileProtection(at: directory) else {
                throw WorkoutHistoryExportFailure.fileProtection
            }
        } catch { throw WorkoutHistoryExportFailure.fileProtection }

        let url = directory.appendingPathComponent(preview.fileName)
        do { try fileSystem.removeItemIfPresent(at: url) }
        catch { throw WorkoutHistoryExportFailure.previousArtifactCleanup }

        let data: Data
        do {
            data = try codec.encode(.init(
                formatVersion: WorkoutHistoryExportSchema.currentVersion,
                createdAt: preview.createdAt,
                workouts: preview.workouts
            ))
        } catch { throw WorkoutHistoryExportFailure.encoding }

        do { try fileSystem.writeProtectedData(data, to: url) }
        catch { throw WorkoutHistoryExportFailure.protectedWrite }

        do {
            try fileSystem.applyCompleteFileProtection(to: url)
            guard try fileSystem.hasCompleteFileProtection(at: url) else {
                throw WorkoutHistoryExportFailure.fileProtection
            }
        } catch {
            try? fileSystem.removeItemIfPresent(at: url)
            throw WorkoutHistoryExportFailure.fileProtection
        }
        return .init(url: url)
    }

    func cleanup(_ artifact: WorkoutHistoryExportArtifact) throws {
        do { try fileSystem.removeItemIfPresent(at: artifact.url) }
        catch { throw WorkoutHistoryExportFailure.cleanup }
    }
}

struct WorkoutHistoryExportSelection: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String
    let failure: WorkoutHistoryExportEligibilityFailure?

    var isEligible: Bool { failure == nil }
}
