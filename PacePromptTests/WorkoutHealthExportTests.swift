import Foundation
import XCTest

@testable import PacePrompt

@MainActor
final class WorkoutHealthExportTests: XCTestCase {
  func testPayloadUsesStableIdentifiersExactDecimalsAndIndependentSources() throws {
    let summary = fixture()
    guard case let .eligible(payload) = WorkoutHealthPayloadFactory.make(
      summary: summary,
      syncVersion: 4
    ) else { return XCTFail("Expected eligible payload") }

    XCTAssertEqual(
      payload.workoutSyncIdentifier,
      "com.sertanyamaner.PacePrompt.workout.00000000-0000-0000-0000-000000000064"
    )
    XCTAssertEqual(
      payload.distanceSyncIdentifier,
      "com.sertanyamaner.PacePrompt.distance.00000000-0000-0000-0000-000000000064"
    )
    XCTAssertEqual(payload.distanceMetres, decimal("12.50"))
    XCTAssertEqual(payload.intervals.count, 2)
    let metadata = payload.intervals[0].metadata
    XCTAssertEqual(metadata.count, 15)
    XCTAssertEqual(metadata[key("speedTargetSource")], .string("manualOverride"))
    XCTAssertEqual(metadata[key("inclinationTargetSource")], .string("planned"))
    XCTAssertEqual(metadata[key("effectiveTargetSpeedKilometresPerHour")], .decimal(decimal("5.20")))
    XCTAssertEqual(metadata[key("observedSpeedKilometresPerHour")], .decimal(decimal("5.20")))

    let foundation = HealthKitWorkoutStore.foundationMetadata(metadata)
    let exact = try XCTUnwrap(foundation[key("effectiveTargetSpeedKilometresPerHour")] as? NSDecimalNumber)
    XCTAssertEqual(exact.stringValue, "5.2")
    XCTAssertTrue(type(of: foundation[key("effectiveTargetSpeedKilometresPerHour")]!) == NSDecimalNumber.self)
  }

  func testVersionOneAndInconsistentVersionTwoRemainIneligibleWithoutReconstruction() {
    let current = fixture()
    let legacy = copy(
      current,
      schemaVersion: 1,
      timeline: .some(nil),
      distance: .measured(metres: decimal("12.5")),
      healthExport: .some(nil)
    )
    XCTAssertEqual(
      WorkoutHealthPayloadFactory.make(summary: legacy, syncVersion: 1),
      .ineligible
    )

    guard case let .recorded(start, end, provenance, intervals)? = current.activityTimeline else {
      return XCTFail("Expected fixture timeline")
    }
    let overlap = WorkoutExecutedInterval(
      segmentIndex: intervals[1].segmentIndex,
      intervalIndex: intervals[1].intervalIndex,
      startedAt: intervals[0].endedAt.addingTimeInterval(-1),
      endedAt: intervals[1].endedAt,
      prescribed: intervals[1].prescribed,
      effectiveSpeed: intervals[1].effectiveSpeed,
      effectiveInclination: intervals[1].effectiveInclination,
      settledObservation: .init(
        observedAt: intervals[0].endedAt.addingTimeInterval(-1),
        speedKilometresPerHour: intervals[1].settledObservation.speedKilometresPerHour,
        inclinationPercent: intervals[1].settledObservation.inclinationPercent,
        provenance: .fr30zTreadmillDataCurrentEpoch
      ),
      endReason: intervals[1].endReason
    )
    let invalid = copy(
      current,
      timeline: .recorded(
        startedAt: start,
        endedAt: end,
        timingProvenance: provenance,
        executedIntervals: [intervals[0], overlap]
      )
    )
    XCTAssertEqual(
      WorkoutHealthPayloadFactory.make(summary: invalid, syncVersion: 1),
      .ineligible
    )
  }

  func testUserInvokedSaveRequestsWriteOnlyAuthorizationAndAllowsDistanceDenial() async {
    let summary = fixture()
    let history = FakeHistory(summary)
    let store = FakeHealthStore()
    store.statuses = [.workout: .notDetermined, .walkingRunningDistance: .notDetermined]
    store.statusesAfterRequest = [.workout: .authorized, .walkingRunningDistance: .denied]
    let coordinator = WorkoutHealthExportCoordinator(
      history: history,
      healthStore: store,
      now: { Date(timeIntervalSince1970: 500) }
    )

    XCTAssertEqual(store.authorizationRequests, 0)
    let state = await coordinator.save(summary)
    guard case let .saved(_, version, _, count, distanceIncluded) = state else {
      return XCTFail("Expected saved state")
    }
    XCTAssertEqual(store.authorizationRequests, 1)
    XCTAssertEqual(version, 1)
    XCTAssertEqual(count, 2)
    XCTAssertFalse(distanceIncluded)
    XCTAssertNil(store.savedPayloads.single?.distanceMetres)
    XCTAssertEqual(history.summary.planSnapshot, summary.planSnapshot)
    XCTAssertEqual(history.summary.activityTimeline, summary.activityTimeline)
    XCTAssertEqual(history.summary.distance, summary.distance)
    XCTAssertEqual(history.summary.outcome, summary.outcome)
  }

  func testWorkoutDenialAndUnavailableHealthNeverCallSave() async {
    for unavailable in [false, true] {
      let summary = fixture()
      let history = FakeHistory(summary)
      let store = FakeHealthStore()
      store.isHealthDataAvailable = !unavailable
      store.statuses = [.workout: .denied, .walkingRunningDistance: .authorized]
      let state = await WorkoutHealthExportCoordinator(history: history, healthStore: store).save(summary)
      if unavailable {
        XCTAssertEqual(state, .unavailable(category: .unavailable))
      } else {
        XCTAssertEqual(state, .denied(writeType: .workout))
      }
      XCTAssertTrue(store.savedPayloads.isEmpty)
    }
  }

  func testEligibilityCoversEveryOutcomeAndPhysicalStopBoundary() {
    let eligible = fixture()
    XCTAssertNotEqual(
      WorkoutHealthPayloadFactory.make(summary: eligible, syncVersion: 1),
      .ineligible
    )
    XCTAssertNotEqual(
      WorkoutHealthPayloadFactory.make(
        summary: copy(eligible, stop: .notRequired),
        syncVersion: 1
      ),
      .ineligible
    )
    XCTAssertNotEqual(
      WorkoutHealthPayloadFactory.make(
        summary: copy(
          eligible,
          outcome: .stoppedByUser(reason: .init(rawValue: "synthetic-user-end")),
          stop: .humanConfirmed(at: eligible.lastUpdatedAt)
        ),
        syncVersion: 1
      ),
      .ineligible
    )

    let ineligible: [(WorkoutExecutionOutcome, WorkoutPhysicalStopConfirmation)] = [
      (.inProgress, .notRequired),
      (.interrupted(reason: .init(rawValue: "synthetic-interruption")), .humanConfirmed(at: eligible.lastUpdatedAt)),
      (.failed(reason: .init(rawValue: "synthetic-failure")), .humanConfirmed(at: eligible.lastUpdatedAt)),
      (.completed, .unconfirmed),
      (.stoppedByUser(reason: .init(rawValue: "synthetic-user-end")), .notRequired),
      (.stoppedByUser(reason: .init(rawValue: "synthetic-user-end")), .unconfirmed),
    ]
    for (outcome, stop) in ineligible {
      XCTAssertEqual(
        WorkoutHealthPayloadFactory.make(
          summary: copy(eligible, outcome: outcome, stop: stop),
          syncVersion: 1
        ),
        .ineligible
      )
    }
  }

  func testInvalidAndZeroDistanceAreOmittedWithoutInventingDistance() {
    let summary = fixture()
    let invalid = copy(
      summary,
      distance: .measuredWithProvenance(
        metres: decimal("12.50"),
        provenance: .init(
          method: .fr30zCumulativeDistanceDelta,
          startCumulativeMetres: decimal("112.75"),
          startObservedAt: summary.attemptedAt.addingTimeInterval(5),
          finalCumulativeMetres: decimal("100.25"),
          finalObservedAt: summary.lastUpdatedAt.addingTimeInterval(-2)
        )
      )
    )
    guard case let .eligible(invalidPayload) = WorkoutHealthPayloadFactory.make(
      summary: invalid,
      syncVersion: 1
    ) else { return XCTFail("Invalid distance must not invalidate the truthful workout") }
    XCTAssertNil(invalidPayload.distanceMetres)

    guard case let .measuredWithProvenance(_, provenance) = summary.distance else {
      return XCTFail("Expected fixture provenance")
    }
    let zero = copy(
      summary,
      distance: .measuredWithProvenance(
        metres: 0,
        provenance: .init(
          method: provenance.method,
          startCumulativeMetres: provenance.startCumulativeMetres,
          startObservedAt: provenance.startObservedAt,
          finalCumulativeMetres: provenance.startCumulativeMetres,
          finalObservedAt: provenance.finalObservedAt
        )
      )
    )
    guard case let .eligible(zeroPayload) = WorkoutHealthPayloadFactory.make(
      summary: zero,
      syncVersion: 1
    ) else { return XCTFail("Measured zero remains a truthful eligible workout") }
    XCTAssertNil(zeroPayload.distanceMetres)
  }

  func testAuthorizationFailureIsRetryableAndSavedStateCannotDuplicate() async {
    let history = FakeHistory(fixture())
    let store = FakeHealthStore()
    store.statuses = [.workout: .notDetermined, .walkingRunningDistance: .notDetermined]
    store.authorizationFailure = true
    let coordinator = WorkoutHealthExportCoordinator(history: history, healthStore: store)

    let failed = await coordinator.save(history.summary)
    XCTAssertEqual(failed, .failedRetryable(category: .authorization, syncVersion: 1))
    XCTAssertTrue(store.savedPayloads.isEmpty)

    store.authorizationFailure = false
    store.statusesAfterRequest = [.workout: .authorized, .walkingRunningDistance: .authorized]
    store.results = [.success(uuid(164))]
    guard case .saved = await coordinator.save(history.summary) else {
      return XCTFail("Expected authorized retry to save")
    }
    XCTAssertEqual(store.savedPayloads.map(\.syncVersion), [2])
    _ = await coordinator.save(history.summary)
    XCTAssertEqual(store.savedPayloads.count, 1)
  }

  func testEveryRetryAdvancesVersionSoAChangedAuthorizationPayloadCannotReuseOne() async {
    let history = FakeHistory(fixture())
    let store = FakeHealthStore()
    store.statuses = [.workout: .authorized, .walkingRunningDistance: .authorized]
    store.results = [.failure(.definite(.builder)), .success(uuid(164))]
    let coordinator = WorkoutHealthExportCoordinator(history: history, healthStore: store)

    let first = await coordinator.save(history.summary)
    XCTAssertEqual(first, .failedRetryable(category: .builder, syncVersion: 1))
    _ = await coordinator.save(history.summary)
    XCTAssertEqual(store.savedPayloads.map(\.syncVersion), [1, 2])

    history.summary = copy(
      history.summary,
      healthExport: .failedAmbiguous(category: .builder, syncVersion: 1)
    )
    store.results = [.success(uuid(264))]
    _ = await coordinator.save(history.summary)
    XCTAssertEqual(store.savedPayloads.last?.syncVersion, 2)
  }

  func testLocalReceiptFailureLeavesPendingAndNextRetryUsesHigherVersion() async {
    let history = FakeHistory(fixture())
    let store = FakeHealthStore()
    store.statuses = [.workout: .authorized, .walkingRunningDistance: .authorized]
    store.results = [.success(uuid(164)), .success(uuid(264))]
    history.failSavedReceiptOnce = true
    let coordinator = WorkoutHealthExportCoordinator(history: history, healthStore: store)

    let first = await coordinator.save(history.summary)
    XCTAssertEqual(first, .failedAmbiguous(category: .localReceipt, syncVersion: 1))
    guard case let .pending(_, version) = history.summary.healthExport else {
      return XCTFail("Pending receipt must remain after local write failure")
    }
    XCTAssertEqual(version, 1)
    _ = await coordinator.save(history.summary)
    XCTAssertEqual(store.savedPayloads.map(\.syncVersion), [1, 2])
  }

  func testPresentationDisclosesMirrorAndSavedStateHasNoAction() throws {
    let summary = fixture()
    let unsaved = try XCTUnwrap(
      HistoryHealthExportPresenter.make(summary: summary, isSaving: false)
    )
    XCTAssertEqual(unsaved.actionTitle, "Save to Apple Health")
    XCTAssertTrue(unsaved.confirmationMessage.contains("prescribed, effective-target and separately observed"))
    XCTAssertTrue(unsaved.confirmationMessage.contains("2 interval metadata records"))

    let savedSummary = copy(
      summary,
      healthExport: .saved(
        savedAt: Date(timeIntervalSince1970: 500),
        syncVersion: 1,
        workoutUUID: uuid(164),
        mirroredIntervalCount: 2,
        distanceIncluded: true
      )
    )
    let saved = try XCTUnwrap(
      HistoryHealthExportPresenter.make(summary: savedSummary, isSaving: false)
    )
    XCTAssertNil(saved.actionTitle)
    XCTAssertEqual(saved.status, "Saved to Apple Health with distance")
  }

  private func fixture() -> WorkoutExecutionSummary {
    let start = Date(timeIntervalSince1970: 100)
    let firstEnd = start.addingTimeInterval(10)
    let secondStart = firstEnd.addingTimeInterval(5)
    let end = secondStart.addingTimeInterval(10)
    let plan = WorkoutPlan(
      schemaVersion: 1,
      suggestedName: "Synthetic intervals",
      activity: .indoorRunning,
      steps: [
        step(.interval, speed: "5.00", inclination: "1.00"),
        step(.recovery, speed: "4.00", inclination: "0.00"),
      ]
    )
    let first = interval(
      segment: 0,
      start: start,
      end: firstEnd,
      prescribed: plan.steps[0],
      speed: "5.20",
      speedSource: .manualOverride,
      inclination: "1.00",
      inclinationSource: .planned,
      observedSpeed: "5.20",
      observedInclination: "1.00",
      reason: .paused
    )
    let second = interval(
      segment: 1,
      start: secondStart,
      end: end,
      prescribed: plan.steps[1],
      speed: "4.00",
      speedSource: .planned,
      inclination: "0.50",
      inclinationSource: .manualOverride,
      observedSpeed: "4.00",
      observedInclination: "0.50",
      reason: .completed
    )
    return .init(
      id: uuid(64),
      schemaVersion: 2,
      sourcePlanID: uuid(63),
      planSnapshot: plan,
      attemptedAt: start.addingTimeInterval(-5),
      lastUpdatedAt: end.addingTimeInterval(2),
      outcome: .completed,
      activeDuration: .measured(seconds: 20),
      distance: .measuredWithProvenance(
        metres: decimal("12.50"),
        provenance: .init(
          method: .fr30zCumulativeDistanceDelta,
          startCumulativeMetres: decimal("100.25"),
          startObservedAt: start,
          finalCumulativeMetres: decimal("112.75"),
          finalObservedAt: end
        )
      ),
      progress: .init(completedStepCount: 2, currentStepIndex: nil, activeSecondsInCurrentStep: 0),
      physicalStopConfirmation: .humanConfirmed(at: end.addingTimeInterval(1)),
      activityTimeline: .recorded(
        startedAt: start,
        endedAt: end,
        timingProvenance: .executionClock,
        executedIntervals: [first, second]
      ),
      healthExport: .notRequested
    )
  }

  private func interval(
    segment: Int,
    start: Date,
    end: Date,
    prescribed: WorkoutStep,
    speed: String,
    speedSource: WorkoutTargetValueSource,
    inclination: String,
    inclinationSource: WorkoutTargetValueSource,
    observedSpeed: String,
    observedInclination: String,
    reason: WorkoutExecutedIntervalEndReason
  ) -> WorkoutExecutedInterval {
    .init(
      segmentIndex: segment,
      intervalIndex: 0,
      startedAt: start,
      endedAt: end,
      prescribed: .init(
        kind: prescribed.kind,
        speedKilometresPerHour: prescribed.targetSpeed.value,
        inclinationPercent: prescribed.targetInclination.value
      ),
      effectiveSpeed: .init(kilometresPerHour: decimal(speed), source: speedSource),
      effectiveInclination: .init(percent: decimal(inclination), source: inclinationSource),
      settledObservation: .init(
        observedAt: start,
        speedKilometresPerHour: decimal(observedSpeed),
        inclinationPercent: decimal(observedInclination),
        provenance: .fr30zTreadmillDataCurrentEpoch
      ),
      endReason: reason
    )
  }

  private func copy(
    _ summary: WorkoutExecutionSummary,
    schemaVersion: Int? = nil,
    timeline: WorkoutActivityTimeline?? = nil,
    distance: WorkoutDistance? = nil,
    healthExport: WorkoutHealthExportState?? = nil,
    outcome: WorkoutExecutionOutcome? = nil,
    stop: WorkoutPhysicalStopConfirmation? = nil
  ) -> WorkoutExecutionSummary {
    .init(
      id: summary.id,
      schemaVersion: schemaVersion ?? summary.schemaVersion,
      sourcePlanID: summary.sourcePlanID,
      planSnapshot: summary.planSnapshot,
      attemptedAt: summary.attemptedAt,
      lastUpdatedAt: summary.lastUpdatedAt,
      outcome: outcome ?? summary.outcome,
      activeDuration: summary.activeDuration,
      distance: distance ?? summary.distance,
      progress: summary.progress,
      physicalStopConfirmation: stop ?? summary.physicalStopConfirmation,
      activityTimeline: timeline ?? summary.activityTimeline,
      healthExport: healthExport ?? summary.healthExport
    )
  }

  private func step(_ kind: WorkoutStepKind, speed: String, inclination: String) -> WorkoutStep {
    .init(
      kind: kind,
      label: "Synthetic",
      duration: .init(value: 10, unit: .seconds),
      targetSpeed: .init(value: decimal(speed), unit: .kilometresPerHour),
      targetInclination: .init(value: decimal(inclination), unit: .percent)
    )
  }

  private func decimal(_ value: String) -> Decimal {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
  }
  private func key(_ suffix: String) -> String { "com.sertanyamaner.PacePrompt.\(suffix)" }
  private func uuid(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
  }
}

private final class FakeHistory: WorkoutHistoryRepositoryProtocol {
  var summary: WorkoutExecutionSummary
  var failSavedReceiptOnce = false
  init(_ summary: WorkoutExecutionSummary) { self.summary = summary }
  func list() -> WorkoutHistoryRepositoryStatus {
    .init(canonical: .available(summaries: [summary]), staging: .absent)
  }
  func record(_ summary: WorkoutExecutionSummary) { self.summary = summary }
  func updateHealthExport(summaryID: UUID, state: WorkoutHealthExportState) throws {
    if case .saved = state, failSavedReceiptOnce {
      failSavedReceiptOnce = false
      throw WorkoutHistoryMutationFailure.writeFailed(.atomicReplacement)
    }
    summary = summary.replacingHealthExport(with: state)
  }
}

private final class FakeHealthStore: WorkoutHealthStoreProtocol {
  var isHealthDataAvailable = true
  var statuses: [WorkoutHealthWriteType: WorkoutHealthAuthorizationStatus] = [:]
  var statusesAfterRequest: [WorkoutHealthWriteType: WorkoutHealthAuthorizationStatus] = [:]
  var authorizationFailure = false
  var results: [Result<UUID, WorkoutHealthStoreFailure>] = []
  private(set) var authorizationRequests = 0
  private(set) var savedPayloads: [WorkoutHealthExportPayload] = []

  func requestWriteAuthorization() async throws {
    authorizationRequests += 1
    if authorizationFailure {
      throw WorkoutHealthStoreFailure.definite(.authorization)
    }
    statuses.merge(statusesAfterRequest) { _, new in new }
  }
  func authorizationStatus(for type: WorkoutHealthWriteType) -> WorkoutHealthAuthorizationStatus {
    statuses[type] ?? .notDetermined
  }
  func save(_ payload: WorkoutHealthExportPayload) async throws -> UUID {
    savedPayloads.append(payload)
    if results.isEmpty { return UUID() }
    return try results.removeFirst().get()
  }
}

private extension Array {
  var single: Element? { count == 1 ? first : nil }
}
