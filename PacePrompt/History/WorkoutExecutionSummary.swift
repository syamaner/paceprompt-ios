import Foundation

enum WorkoutExecutionSummarySchema {
    static let legacyVersion = 1
    static let currentVersion = 2
    static let supportedVersions: Set<Int> = [legacyVersion, currentVersion]
}

struct WorkoutExecutionReasonCode: RawRepresentable, Codable, Equatable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum WorkoutExecutionOutcome: Equatable, Codable {
    case inProgress
    case completed
    case stoppedByUser(reason: WorkoutExecutionReasonCode)
    case interrupted(reason: WorkoutExecutionReasonCode)
    case failed(reason: WorkoutExecutionReasonCode)

    private enum State: String, Codable {
        case inProgress
        case completed
        case stoppedByUser
        case interrupted
        case failed
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case reasonCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(State.self, forKey: .state)
        switch state {
        case .inProgress:
            self = .inProgress
        case .completed:
            self = .completed
        case .stoppedByUser:
            self = .stoppedByUser(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        case .interrupted:
            self = .interrupted(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        case .failed:
            self = .failed(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inProgress:
            try container.encode(State.inProgress, forKey: .state)
        case .completed:
            try container.encode(State.completed, forKey: .state)
        case let .stoppedByUser(reason):
            try container.encode(State.stoppedByUser, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        case let .interrupted(reason):
            try container.encode(State.interrupted, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        case let .failed(reason):
            try container.encode(State.failed, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        }
    }
}

enum WorkoutActiveDuration: Equatable, Codable {
    case measured(seconds: Int)
    case unavailable(reason: WorkoutExecutionReasonCode)

    private enum State: String, Codable { case measured, unavailable }
    private enum CodingKeys: String, CodingKey { case state, seconds, reasonCode }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .measured:
            self = .measured(seconds: try container.decode(Int.self, forKey: .seconds))
        case .unavailable:
            self = .unavailable(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .measured(seconds):
            try container.encode(State.measured, forKey: .state)
            try container.encode(seconds, forKey: .seconds)
        case let .unavailable(reason):
            try container.encode(State.unavailable, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        }
    }
}

enum WorkoutDistance: Equatable, Codable {
    case measured(metres: Decimal)
    case measuredWithProvenance(metres: Decimal, provenance: WorkoutDistanceProvenance)
    case unavailable(reason: WorkoutExecutionReasonCode)

    private enum State: String, Codable { case measured, unavailable }
    private enum CodingKeys: String, CodingKey { case state, metres, reasonCode, provenance }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .measured:
            let metres = try container.decode(Decimal.self, forKey: .metres)
            if let provenance = try container.decodeIfPresent(
                WorkoutDistanceProvenance.self,
                forKey: .provenance
            ) {
                self = .measuredWithProvenance(metres: metres, provenance: provenance)
            } else {
                self = .measured(metres: metres)
            }
        case .unavailable:
            self = .unavailable(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .measured(metres):
            try container.encode(State.measured, forKey: .state)
            try container.encode(metres, forKey: .metres)
        case let .measuredWithProvenance(metres, provenance):
            try container.encode(State.measured, forKey: .state)
            try container.encode(metres, forKey: .metres)
            try container.encode(provenance, forKey: .provenance)
        case let .unavailable(reason):
            try container.encode(State.unavailable, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        }
    }
}

struct WorkoutDistanceProvenance: Codable, Equatable {
    enum Method: String, Codable { case fr30zCumulativeDistanceDelta }

    let method: Method
    let startCumulativeMetres: Decimal
    let startObservedAt: Date
    let finalCumulativeMetres: Decimal
    let finalObservedAt: Date
}

enum WorkoutTargetValueSource: String, Codable, Equatable {
    case planned
    case manualOverride
}

struct WorkoutPrescribedIntervalValues: Codable, Equatable {
    let kind: WorkoutStepKind
    let speedKilometresPerHour: Decimal
    let inclinationPercent: Decimal
}

struct WorkoutEffectiveSpeed: Codable, Equatable {
    let kilometresPerHour: Decimal
    let source: WorkoutTargetValueSource
}

struct WorkoutEffectiveInclination: Codable, Equatable {
    let percent: Decimal
    let source: WorkoutTargetValueSource
}

struct WorkoutSettledObservation: Codable, Equatable {
    enum Provenance: String, Codable { case fr30zTreadmillDataCurrentEpoch }

    let observedAt: Date
    let speedKilometresPerHour: Decimal
    let inclinationPercent: Decimal
    let provenance: Provenance
}

enum WorkoutExecutedIntervalEndReason: String, Codable, Equatable {
    case planTransition
    case targetChanged
    case paused
    case completed
    case endedByUser
    case interrupted
    case failed
}

struct WorkoutExecutedInterval: Codable, Equatable {
    let segmentIndex: Int
    let intervalIndex: Int
    let startedAt: Date
    let endedAt: Date
    let prescribed: WorkoutPrescribedIntervalValues
    let effectiveSpeed: WorkoutEffectiveSpeed
    let effectiveInclination: WorkoutEffectiveInclination
    let settledObservation: WorkoutSettledObservation
    let endReason: WorkoutExecutedIntervalEndReason
}

enum WorkoutActivityTimeline: Codable, Equatable {
    case recorded(
        startedAt: Date,
        endedAt: Date,
        timingProvenance: WorkoutTimingProvenance,
        executedIntervals: [WorkoutExecutedInterval]
    )
    case unavailable(reason: WorkoutExecutionReasonCode)

    private enum State: String, Codable { case recorded, unavailable }
    private enum CodingKeys: String, CodingKey {
        case state, startedAt, endedAt, timingProvenance, executedIntervals, reasonCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .recorded:
            self = .recorded(
                startedAt: try container.decode(Date.self, forKey: .startedAt),
                endedAt: try container.decode(Date.self, forKey: .endedAt),
                timingProvenance: try container.decode(
                    WorkoutTimingProvenance.self,
                    forKey: .timingProvenance
                ),
                executedIntervals: try container.decode(
                    [WorkoutExecutedInterval].self,
                    forKey: .executedIntervals
                )
            )
        case .unavailable:
            self = .unavailable(
                reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .recorded(startedAt, endedAt, provenance, intervals):
            try container.encode(State.recorded, forKey: .state)
            try container.encode(startedAt, forKey: .startedAt)
            try container.encode(endedAt, forKey: .endedAt)
            try container.encode(provenance, forKey: .timingProvenance)
            try container.encode(intervals, forKey: .executedIntervals)
        case let .unavailable(reason):
            try container.encode(State.unavailable, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        }
    }
}

enum WorkoutTimingProvenance: String, Codable, Equatable { case executionClock }

enum WorkoutHealthWriteType: String, Codable, Equatable, Hashable { case workout, walkingRunningDistance }

enum WorkoutHealthExportFailureCategory: String, Codable, Equatable {
    case authorization
    case builder
    case localReceipt
    case unavailable
    case unknown
}

enum WorkoutHealthExportState: Codable, Equatable {
    case notRequested
    case pending(attemptedAt: Date, syncVersion: Int)
    case saved(
        savedAt: Date,
        syncVersion: Int,
        workoutUUID: UUID,
        mirroredIntervalCount: Int,
        distanceIncluded: Bool
    )
    case denied(writeType: WorkoutHealthWriteType)
    case unavailable(category: WorkoutHealthExportFailureCategory)
    case failedRetryable(category: WorkoutHealthExportFailureCategory, syncVersion: Int)
    case failedAmbiguous(category: WorkoutHealthExportFailureCategory, syncVersion: Int)

    private enum State: String, Codable {
        case notRequested, pending, saved, denied, unavailable, failedRetryable, failedAmbiguous
    }
    private enum CodingKeys: String, CodingKey {
        case state, attemptedAt, savedAt, syncVersion, workoutUUID, mirroredIntervalCount,
            distanceIncluded, writeType, category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .notRequested: self = .notRequested
        case .pending:
            self = .pending(
                attemptedAt: try container.decode(Date.self, forKey: .attemptedAt),
                syncVersion: try container.decode(Int.self, forKey: .syncVersion)
            )
        case .saved:
            self = .saved(
                savedAt: try container.decode(Date.self, forKey: .savedAt),
                syncVersion: try container.decode(Int.self, forKey: .syncVersion),
                workoutUUID: try container.decode(UUID.self, forKey: .workoutUUID),
                mirroredIntervalCount: try container.decode(
                    Int.self,
                    forKey: .mirroredIntervalCount
                ),
                distanceIncluded: try container.decode(Bool.self, forKey: .distanceIncluded)
            )
        case .denied:
            self = .denied(
                writeType: try container.decode(WorkoutHealthWriteType.self, forKey: .writeType)
            )
        case .unavailable:
            self = .unavailable(
                category: try container.decode(
                    WorkoutHealthExportFailureCategory.self,
                    forKey: .category
                )
            )
        case .failedRetryable:
            self = .failedRetryable(
                category: try container.decode(
                    WorkoutHealthExportFailureCategory.self,
                    forKey: .category
                ),
                syncVersion: try container.decode(Int.self, forKey: .syncVersion)
            )
        case .failedAmbiguous:
            self = .failedAmbiguous(
                category: try container.decode(
                    WorkoutHealthExportFailureCategory.self,
                    forKey: .category
                ),
                syncVersion: try container.decode(Int.self, forKey: .syncVersion)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notRequested:
            try container.encode(State.notRequested, forKey: .state)
        case let .pending(attemptedAt, version):
            try container.encode(State.pending, forKey: .state)
            try container.encode(attemptedAt, forKey: .attemptedAt)
            try container.encode(version, forKey: .syncVersion)
        case let .saved(savedAt, version, uuid, count, distanceIncluded):
            try container.encode(State.saved, forKey: .state)
            try container.encode(savedAt, forKey: .savedAt)
            try container.encode(version, forKey: .syncVersion)
            try container.encode(uuid, forKey: .workoutUUID)
            try container.encode(count, forKey: .mirroredIntervalCount)
            try container.encode(distanceIncluded, forKey: .distanceIncluded)
        case let .denied(type):
            try container.encode(State.denied, forKey: .state)
            try container.encode(type, forKey: .writeType)
        case let .unavailable(category):
            try container.encode(State.unavailable, forKey: .state)
            try container.encode(category, forKey: .category)
        case let .failedRetryable(category, version):
            try container.encode(State.failedRetryable, forKey: .state)
            try container.encode(category, forKey: .category)
            try container.encode(version, forKey: .syncVersion)
        case let .failedAmbiguous(category, version):
            try container.encode(State.failedAmbiguous, forKey: .state)
            try container.encode(category, forKey: .category)
            try container.encode(version, forKey: .syncVersion)
        }
    }
}

struct WorkoutExecutionProgress: Codable, Equatable {
    let completedStepCount: Int
    let currentStepIndex: Int?
    let activeSecondsInCurrentStep: Int
}

enum WorkoutPhysicalStopConfirmation: Equatable, Codable {
    case notRequired
    case humanConfirmed(at: Date)
    case unconfirmed

    private enum State: String, Codable { case notRequired, humanConfirmed, unconfirmed }
    private enum CodingKeys: String, CodingKey { case state, confirmedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .notRequired:
            self = .notRequired
        case .humanConfirmed:
            self = .humanConfirmed(at: try container.decode(Date.self, forKey: .confirmedAt))
        case .unconfirmed:
            self = .unconfirmed
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notRequired:
            try container.encode(State.notRequired, forKey: .state)
        case let .humanConfirmed(at):
            try container.encode(State.humanConfirmed, forKey: .state)
            try container.encode(at, forKey: .confirmedAt)
        case .unconfirmed:
            try container.encode(State.unconfirmed, forKey: .state)
        }
    }
}

struct WorkoutExecutionSummary: Codable, Equatable {
    let id: UUID
    let schemaVersion: Int
    let sourcePlanID: UUID?
    let planSnapshot: WorkoutPlan
    let attemptedAt: Date
    let lastUpdatedAt: Date
    let outcome: WorkoutExecutionOutcome
    let activeDuration: WorkoutActiveDuration
    let distance: WorkoutDistance
    let progress: WorkoutExecutionProgress
    let physicalStopConfirmation: WorkoutPhysicalStopConfirmation
    let activityTimeline: WorkoutActivityTimeline?
    let healthExport: WorkoutHealthExportState?

    init(
        id: UUID,
        schemaVersion: Int,
        sourcePlanID: UUID?,
        planSnapshot: WorkoutPlan,
        attemptedAt: Date,
        lastUpdatedAt: Date,
        outcome: WorkoutExecutionOutcome,
        activeDuration: WorkoutActiveDuration,
        distance: WorkoutDistance,
        progress: WorkoutExecutionProgress,
        physicalStopConfirmation: WorkoutPhysicalStopConfirmation,
        activityTimeline: WorkoutActivityTimeline? = nil,
        healthExport: WorkoutHealthExportState? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.sourcePlanID = sourcePlanID
        self.planSnapshot = planSnapshot
        self.attemptedAt = attemptedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.outcome = outcome
        self.activeDuration = activeDuration
        self.distance = distance
        self.progress = progress
        self.physicalStopConfirmation = physicalStopConfirmation
        self.activityTimeline = activityTimeline
        self.healthExport = healthExport
    }

    func replacingHealthExport(with state: WorkoutHealthExportState) -> Self {
        .init(
            id: id,
            schemaVersion: schemaVersion,
            sourcePlanID: sourcePlanID,
            planSnapshot: planSnapshot,
            attemptedAt: attemptedAt,
            lastUpdatedAt: lastUpdatedAt,
            outcome: outcome,
            activeDuration: activeDuration,
            distance: distance,
            progress: progress,
            physicalStopConfirmation: physicalStopConfirmation,
            activityTimeline: activityTimeline,
            healthExport: state
        )
    }
}
