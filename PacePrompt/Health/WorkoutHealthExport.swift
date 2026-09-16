import Foundation
import HealthKit

enum WorkoutHealthAuthorizationStatus: Equatable {
  case notDetermined
  case denied
  case authorized
}

enum WorkoutHealthStoreFailure: Error, Equatable {
  case definite(WorkoutHealthExportFailureCategory)
  case ambiguous(WorkoutHealthExportFailureCategory)
}

struct WorkoutHealthIntervalPayload: Equatable {
  let startedAt: Date
  let endedAt: Date
  let metadata: [String: WorkoutHealthMetadataValue]
}

enum WorkoutHealthMetadataValue: Equatable {
  case integer(Int)
  case decimal(Decimal)
  case string(String)
  case date(Date)
}

struct WorkoutHealthExportPayload: Equatable {
  let summaryID: UUID
  let activity: WorkoutActivity
  let startedAt: Date
  let endedAt: Date
  let activeDurationSeconds: Int
  let intervals: [WorkoutHealthIntervalPayload]
  let distanceMetres: Decimal?
  let syncVersion: Int

  var workoutSyncIdentifier: String {
    "com.otherweather.PromptPace.workout.\(summaryID.uuidString.lowercased())"
  }

  var distanceSyncIdentifier: String {
    "com.otherweather.PromptPace.distance.\(summaryID.uuidString.lowercased())"
  }

  func withoutDistance() -> Self {
    .init(
      summaryID: summaryID,
      activity: activity,
      startedAt: startedAt,
      endedAt: endedAt,
      activeDurationSeconds: activeDurationSeconds,
      intervals: intervals,
      distanceMetres: nil,
      syncVersion: syncVersion
    )
  }
}

enum WorkoutHealthExportEligibility: Equatable {
  case eligible(WorkoutHealthExportPayload)
  case ineligible
}

enum WorkoutHealthPayloadFactory {
  static let namespace = "com.otherweather.PromptPace"
  static let timelineSchemaVersion = 1

  static func make(
    summary: WorkoutExecutionSummary,
    syncVersion: Int
  ) -> WorkoutHealthExportEligibility {
    guard summary.schemaVersion == WorkoutExecutionSummarySchema.currentVersion,
          syncVersion > 0,
          outcomeAndStopAreEligible(summary.outcome, summary.physicalStopConfirmation),
          case let .measured(activeSeconds) = summary.activeDuration,
          activeSeconds > 0,
          case let .recorded(startedAt, endedAt, .executionClock, intervals)? =
            summary.activityTimeline,
          !intervals.isEmpty,
          startedAt == intervals.first?.startedAt,
          endedAt == intervals.last?.endedAt,
          intervalsAreEligible(intervals, plan: summary.planSnapshot),
          summedDuration(intervals) == activeSeconds
    else { return .ineligible }

    let distance: Decimal?
    switch summary.distance {
    case let .measuredWithProvenance(metres, provenance)
      where distanceIsAccepted(
        metres: metres,
        provenance: provenance,
        timelineStart: startedAt,
        timelineEnd: endedAt
      ):
      distance = metres > 0 ? metres : nil
    case .measured, .measuredWithProvenance, .unavailable:
      distance = nil
    }

    return .eligible(
      .init(
        summaryID: summary.id,
        activity: summary.planSnapshot.activity,
        startedAt: startedAt,
        endedAt: endedAt,
        activeDurationSeconds: activeSeconds,
        intervals: intervals.map {
          .init(startedAt: $0.startedAt, endedAt: $0.endedAt, metadata: metadata(for: $0))
        },
        distanceMetres: distance,
        syncVersion: syncVersion
      )
    )
  }

  private static func outcomeAndStopAreEligible(
    _ outcome: WorkoutExecutionOutcome,
    _ stop: WorkoutPhysicalStopConfirmation
  ) -> Bool {
    switch (outcome, stop) {
    case (.completed, .notRequired), (.completed, .humanConfirmed),
         (.stoppedByUser, .humanConfirmed): true
    case (.inProgress, _), (.interrupted, _), (.failed, _),
         (.completed, .unconfirmed), (.stoppedByUser, .notRequired),
         (.stoppedByUser, .unconfirmed): false
    }
  }

  private static func intervalsAreEligible(
    _ intervals: [WorkoutExecutedInterval],
    plan: WorkoutPlan
  ) -> Bool {
    var previousEnd: Date?
    var previousSegmentIndex: Int?
    var nextIndex: [Int: Int] = [:]
    for interval in intervals {
      guard plan.steps.indices.contains(interval.segmentIndex),
            previousSegmentIndex.map({ interval.segmentIndex >= $0 }) ?? true,
            interval.intervalIndex == nextIndex[interval.segmentIndex, default: 0],
            interval.startedAt < interval.endedAt,
            previousEnd.map({ interval.startedAt >= $0 }) ?? true,
            interval.settledObservation.observedAt == interval.startedAt else { return false }
      let prescribed = plan.steps[interval.segmentIndex]
      guard interval.prescribed.kind == prescribed.kind,
            interval.prescribed.speedKilometresPerHour == prescribed.targetSpeed.value,
            interval.prescribed.inclinationPercent == prescribed.targetInclination.value,
            interval.effectiveSpeed.source != .planned
              || interval.effectiveSpeed.kilometresPerHour == interval.prescribed.speedKilometresPerHour,
            interval.effectiveInclination.source != .planned
              || interval.effectiveInclination.percent == interval.prescribed.inclinationPercent,
            interval.effectiveSpeed.kilometresPerHour.isFinite,
            interval.effectiveInclination.percent.isFinite,
            interval.settledObservation.speedKilometresPerHour.isFinite,
            interval.settledObservation.inclinationPercent.isFinite,
            interval.settledObservation.speedKilometresPerHour
              == interval.effectiveSpeed.kilometresPerHour,
            interval.settledObservation.inclinationPercent
              == interval.effectiveInclination.percent else { return false }
      nextIndex[interval.segmentIndex, default: 0] += 1
      previousEnd = interval.endedAt
      previousSegmentIndex = interval.segmentIndex
    }
    return true
  }

  private static func summedDuration(_ intervals: [WorkoutExecutedInterval]) -> Int {
    Int(floor(intervals.reduce(0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) } + 0.000_000_001))
  }

  private static func distanceIsAccepted(
    metres: Decimal,
    provenance: WorkoutDistanceProvenance,
    timelineStart: Date,
    timelineEnd: Date
  ) -> Bool {
    metres.isFinite && metres >= 0
      && provenance.method == .fr30zCumulativeDistanceDelta
      && provenance.startCumulativeMetres.isFinite
      && provenance.finalCumulativeMetres.isFinite
      && provenance.startCumulativeMetres >= 0
      && provenance.finalCumulativeMetres >= provenance.startCumulativeMetres
      && provenance.finalCumulativeMetres - provenance.startCumulativeMetres == metres
      && provenance.startObservedAt == timelineStart
      && provenance.finalObservedAt >= timelineEnd
      && provenance.finalObservedAt >= provenance.startObservedAt
  }

  private static func key(_ suffix: String) -> String { "\(namespace).\(suffix)" }

  private static func metadata(
    for interval: WorkoutExecutedInterval
  ) -> [String: WorkoutHealthMetadataValue] {
    [
      key("timelineSchemaVersion"): .integer(timelineSchemaVersion),
      key("segmentIndex"): .integer(interval.segmentIndex),
      key("intervalIndex"): .integer(interval.intervalIndex),
      key("prescribedSegmentKind"): .string(interval.prescribed.kind.rawValue),
      key("prescribedSpeedKilometresPerHour"): .decimal(
        interval.prescribed.speedKilometresPerHour),
      key("prescribedInclinationPercent"): .decimal(interval.prescribed.inclinationPercent),
      key("effectiveTargetSpeedKilometresPerHour"): .decimal(
        interval.effectiveSpeed.kilometresPerHour),
      key("effectiveTargetInclinationPercent"): .decimal(interval.effectiveInclination.percent),
      key("speedTargetSource"): .string(interval.effectiveSpeed.source.rawValue),
      key("inclinationTargetSource"): .string(interval.effectiveInclination.source.rawValue),
      key("observedSpeedKilometresPerHour"): .decimal(
        interval.settledObservation.speedKilometresPerHour),
      key("observedInclinationPercent"): .decimal(
        interval.settledObservation.inclinationPercent),
      key("observedAt"): .date(interval.settledObservation.observedAt),
      key("observationProvenance"): .string(interval.settledObservation.provenance.rawValue),
      key("intervalEndReason"): .string(interval.endReason.rawValue),
    ]
  }
}

protocol WorkoutHealthStoreProtocol {
  var isHealthDataAvailable: Bool { get }
  func requestWriteAuthorization() async throws
  func authorizationStatus(for type: WorkoutHealthWriteType) -> WorkoutHealthAuthorizationStatus
  func save(_ payload: WorkoutHealthExportPayload) async throws -> UUID
}

final class HealthKitWorkoutStore: WorkoutHealthStoreProtocol {
  private let store: HKHealthStore

  init(store: HKHealthStore = HKHealthStore()) { self.store = store }

  var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  func requestWriteAuthorization() async throws {
    try await store.requestAuthorization(
      toShare: [HKObjectType.workoutType(), Self.distanceType],
      read: []
    )
  }

  func authorizationStatus(for type: WorkoutHealthWriteType) -> WorkoutHealthAuthorizationStatus {
    let sampleType: HKSampleType = type == .workout ? HKObjectType.workoutType() : Self.distanceType
    return switch store.authorizationStatus(for: sampleType) {
    case .notDetermined: WorkoutHealthAuthorizationStatus.notDetermined
    case .sharingDenied: WorkoutHealthAuthorizationStatus.denied
    case .sharingAuthorized: WorkoutHealthAuthorizationStatus.authorized
    @unknown default: WorkoutHealthAuthorizationStatus.denied
    }
  }

  func save(_ payload: WorkoutHealthExportPayload) async throws -> UUID {
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = payload.activity == .indoorWalking ? .walking : .running
    configuration.locationType = .indoor
    let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
    do {
      try await builder.beginCollection(at: payload.startedAt)
      try await builder.addMetadata([
        HKMetadataKeyIndoorWorkout: true,
        HKMetadataKeySyncIdentifier: payload.workoutSyncIdentifier,
        HKMetadataKeySyncVersion: payload.syncVersion,
      ])
      for interval in payload.intervals {
        let activity = HKWorkoutActivity(
          workoutConfiguration: configuration,
          start: interval.startedAt,
          end: interval.endedAt,
          metadata: Self.foundationMetadata(interval.metadata)
        )
        try await builder.addWorkoutActivity(activity)
      }
      let gaps = zip(payload.intervals, payload.intervals.dropFirst()).compactMap { earlier, later in
        earlier.endedAt < later.startedAt ? (earlier.endedAt, later.startedAt) : nil
      }
      for (pause, resume) in gaps {
        try await builder.addWorkoutEvents([
          HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause, end: pause), metadata: nil),
          HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: resume, end: resume), metadata: nil),
        ])
      }
      if let metres = payload.distanceMetres {
        let distance = HKQuantitySample(
          type: Self.distanceType,
          quantity: HKQuantity(unit: .meter(), doubleValue: NSDecimalNumber(decimal: metres).doubleValue),
          start: payload.startedAt,
          end: payload.endedAt,
          metadata: [
            HKMetadataKeySyncIdentifier: payload.distanceSyncIdentifier,
            HKMetadataKeySyncVersion: payload.syncVersion,
          ]
        )
        try await builder.addSamples([distance])
      }
      try await builder.endCollection(at: payload.endedAt)
    } catch {
      builder.discardWorkout()
      throw WorkoutHealthStoreFailure.definite(.builder)
    }

    return try await withCheckedThrowingContinuation { continuation in
      builder.finishWorkout { workout, error in
        if let workout {
          continuation.resume(returning: workout.uuid)
        } else {
          continuation.resume(throwing: WorkoutHealthStoreFailure.ambiguous(.builder))
        }
      }
    }
  }

  static func foundationMetadata(
    _ values: [String: WorkoutHealthMetadataValue]
  ) -> [String: Any] {
    values.mapValues {
      switch $0 {
      case let .integer(value): NSNumber(value: value)
      case let .decimal(value): NSDecimalNumber(decimal: value)
      case let .string(value): NSString(string: value)
      case let .date(value): value as NSDate
      }
    }
  }

  private static let distanceType = HKObjectType.quantityType(
    forIdentifier: .distanceWalkingRunning)!
}

@MainActor
final class WorkoutHealthExportCoordinator: ObservableObject {
  @Published private(set) var isSaving = false
  private let history: any WorkoutHistoryRepositoryProtocol
  private let healthStore: any WorkoutHealthStoreProtocol
  private let now: () -> Date

  init(
    history: any WorkoutHistoryRepositoryProtocol,
    healthStore: any WorkoutHealthStoreProtocol,
    now: @escaping () -> Date = Date.init
  ) {
    self.history = history
    self.healthStore = healthStore
    self.now = now
  }

  func save(_ summary: WorkoutExecutionSummary) async -> WorkoutHealthExportState {
    guard !isSaving else { return summary.healthExport ?? .notRequested }
    if case let .saved(savedAt, version, uuid, count, distance)? = summary.healthExport {
      return .saved(
        savedAt: savedAt,
        syncVersion: version,
        workoutUUID: uuid,
        mirroredIntervalCount: count,
        distanceIncluded: distance
      )
    }

    let version = nextSyncVersion(after: summary.healthExport)
    guard case let .eligible(payload) = WorkoutHealthPayloadFactory.make(
      summary: summary,
      syncVersion: version
    ) else { return summary.healthExport ?? .notRequested }

    isSaving = true
    defer { isSaving = false }
    let pending = WorkoutHealthExportState.pending(attemptedAt: now(), syncVersion: version)
    guard persist(pending, summaryID: summary.id) else {
      return .failedRetryable(category: .localReceipt, syncVersion: version)
    }

    guard healthStore.isHealthDataAvailable else {
      let state = WorkoutHealthExportState.unavailable(category: .unavailable)
      _ = persist(state, summaryID: summary.id)
      return state
    }

    do {
      if healthStore.authorizationStatus(for: .workout) == .notDetermined
        || healthStore.authorizationStatus(for: .walkingRunningDistance) == .notDetermined {
        try await healthStore.requestWriteAuthorization()
      }
    } catch {
      let state = WorkoutHealthExportState.failedRetryable(
        category: .authorization,
        syncVersion: version
      )
      _ = persist(state, summaryID: summary.id)
      return state
    }

    guard healthStore.authorizationStatus(for: .workout) == .authorized else {
      let state = WorkoutHealthExportState.denied(writeType: .workout)
      _ = persist(state, summaryID: summary.id)
      return state
    }
    let includeDistance = payload.distanceMetres != nil
      && healthStore.authorizationStatus(for: .walkingRunningDistance) == .authorized
    let finalPayload = includeDistance ? payload : payload.withoutDistance()

    do {
      let uuid = try await healthStore.save(finalPayload)
      let state = WorkoutHealthExportState.saved(
        savedAt: now(),
        syncVersion: version,
        workoutUUID: uuid,
        mirroredIntervalCount: payload.intervals.count,
        distanceIncluded: includeDistance
      )
      guard persist(state, summaryID: summary.id) else {
        return .failedAmbiguous(category: .localReceipt, syncVersion: version)
      }
      return state
    } catch let failure as WorkoutHealthStoreFailure {
      let state: WorkoutHealthExportState
      switch failure {
      case let .definite(category):
        state = .failedRetryable(category: category, syncVersion: version)
      case let .ambiguous(category):
        state = .failedAmbiguous(category: category, syncVersion: version)
      }
      _ = persist(state, summaryID: summary.id)
      return state
    } catch {
      let state = WorkoutHealthExportState.failedAmbiguous(
        category: .unknown,
        syncVersion: version
      )
      _ = persist(state, summaryID: summary.id)
      return state
    }
  }

  private func nextSyncVersion(after state: WorkoutHealthExportState?) -> Int {
    switch state {
    case let .pending(_, version)?, let .failedAmbiguous(_, version)?: version + 1
    case let .failedRetryable(_, version)?: version + 1
    case let .saved(_, version, _, _, _)?: version
    case .notRequested?, .denied?, .unavailable?, nil: 1
    }
  }

  private func persist(_ state: WorkoutHealthExportState, summaryID: UUID) -> Bool {
    do {
      try history.updateHealthExport(summaryID: summaryID, state: state)
      return true
    } catch {
      return false
    }
  }
}
