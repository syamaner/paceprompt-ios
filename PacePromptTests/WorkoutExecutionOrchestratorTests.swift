import Foundation
import XCTest

@testable import PacePrompt

@MainActor
final class WorkoutExecutionOrchestratorTests: XCTestCase {
  func testCompleteHappyPathFreezesInputsSequencesOnlyAllowedIntentsAndPersistsCompletion()
    throws
  {
    let h = Harness()
    let sourcePlanID = h.uuid(44)
    try h.prepare(sourcePlanID: sourcePlanID)
    let request = try h.begin()

    XCTAssertEqual(request.intent, .requestControl)
    XCTAssertEqual(h.orchestrator.frozenAttempt?.sourcePlanID, sourcePlanID)
    XCTAssertEqual(h.orchestrator.frozenAttempt?.plan, h.plan)
    XCTAssertEqual(h.orchestrator.frozenAttempt?.capability, h.capability)
    XCTAssertEqual(h.orchestrator.frozenAttempt?.ceilings, h.ceilings)
    XCTAssertEqual(
      h.orchestrator.frozenAttempt?.executionProfileIdentity,
      FR30zExecutionProfile.identity
    )
    XCTAssertEqual(h.history.records.count, 1)
    XCTAssertEqual(h.history.records[0].outcome, .inProgress)
    XCTAssertEqual(h.history.records[0].activeDuration, .measured(seconds: 0))

    h.send(.intentSubmitted(epoch: h.epoch, procedureID: request.id))
    guard case .submitted = h.orchestrator.state.procedure else {
      return XCTFail("Submission must remain distinct")
    }
    h.send(.attAccepted(epoch: h.epoch, procedureID: request.id))
    guard case .attAccepted = h.orchestrator.state.procedure else {
      return XCTFail("ATT acceptance must remain distinct")
    }
    h.send(.protocolAcknowledged(epoch: h.epoch, procedureID: request.id))
    XCTAssertEqual(h.orchestrator.state.execution, .waitingForPhysicalStart)

    let noTargetCount = h.transport.submissions.count
    h.send(.telemetry(epoch: h.epoch, h.sample("0", "0", distance: "0")))
    XCTAssertEqual(h.transport.submissions.count, noTargetCount)
    h.send(.telemetry(epoch: h.epoch, h.sample("0.5", "0", distance: "1")))
    XCTAssertEqual(h.transport.submissions.last?.intent, .setTargetSpeed(h.speed("5")))
    try h.acknowledgeCurrent()
    XCTAssertEqual(
      h.transport.submissions.last?.intent,
      .setTargetInclination(h.inclination("0"))
    )
    try h.acknowledgeCurrent()
    h.send(.telemetry(epoch: h.epoch, h.sample("5", "0", distance: "3")))
    XCTAssertEqual(h.orchestrator.state.execution, .runningSegment)

    h.send(.setSpeedOverride(epoch: h.epoch, h.speed("5.5")))
    XCTAssertEqual(h.orchestrator.targetEvidence.planned?.speed, h.speed("5"))
    XCTAssertEqual(h.orchestrator.targetEvidence.effective?.speed, h.speed("5.5"))
    XCTAssertEqual(h.transport.submissions.last?.intent, .setTargetSpeed(h.speed("5.5")))
    try h.acknowledgeCurrent()
    h.send(.telemetry(epoch: h.epoch, h.sample("5.5", "0", distance: "5")))
    h.send(.returnToPlan(epoch: h.epoch))
    XCTAssertEqual(h.orchestrator.targetEvidence.effective, h.orchestrator.targetEvidence.planned)
    XCTAssertEqual(h.transport.submissions.last?.intent, .setTargetSpeed(h.speed("5")))
    try h.acknowledgeCurrent()
    h.send(.telemetry(epoch: h.epoch, h.sample("5", "0", distance: "7")))

    try h.finishCurrentStep()
    XCTAssertEqual(h.orchestrator.state.currentSegment?.stepIndex, 1)
    try h.finishTargetSequenceAndObserve()
    try h.finishCurrentStep()
    XCTAssertEqual(h.orchestrator.state.currentSegment?.stepIndex, 2)
    try h.finishTargetSequenceAndObserve()
    try h.finishCurrentStep()
    XCTAssertEqual(h.orchestrator.state.execution, .awaitingPhysicalStopForCompletion)

    h.send(.telemetry(epoch: h.epoch, h.sample("0", "0", distance: "42")))
    guard case .readyToEnd = h.orchestrator.state.execution else {
      return XCTFail("Expected accepted stationary evidence")
    }
    let end = h.send(.userEndsWorkout(epoch: h.epoch))
    guard case .finished = end.state.execution else { return XCTFail("Expected local finish") }
    let final = try XCTUnwrap(h.orchestrator.lastPersistedSummary)
    XCTAssertEqual(final.outcome, .completed)
    XCTAssertEqual(final.progress.completedStepCount, 3)
    XCTAssertNil(final.progress.currentStepIndex)
    XCTAssertEqual(final.activeDuration, .measured(seconds: 15))
    XCTAssertEqual(final.distance, .measured(metres: h.decimal("42")))
    XCTAssertEqual(final.physicalStopConfirmation, .notRequired)

    XCTAssertTrue(
      h.transport.submissions.allSatisfy {
        switch $0.intent {
        case .requestControl, .setTargetSpeed, .setTargetInclination: true
        }
      }
    )
  }

  func testHighFrequencyTelemetryIsFoldedIntoAggregateProgressCheckpoints() throws {
    let h = try Harness.running(stepDuration: 20)
    let writes = h.history.recordCalls.count
    let start = h.orchestrator.state.lastEventTime.seconds
    h.send(
      .telemetry(epoch: h.epoch, h.sample("5", "0", distance: "4")),
      monotonic: start + 0.1
    )
    h.send(
      .telemetry(epoch: h.epoch, h.sample("5", "0", distance: "5")),
      monotonic: start + 0.2
    )
    XCTAssertEqual(h.history.recordCalls.count, writes)
    XCTAssertEqual(
      h.orchestrator.targetEvidence.latestReported?.totalDistanceMetres, h.decimal("5"))

    h.send(
      .telemetry(epoch: h.epoch, h.sample("5", "0", distance: "6")),
      monotonic: start + 1
    )
    XCTAssertEqual(h.history.recordCalls.count, writes + 1)
    XCTAssertEqual(h.orchestrator.lastPersistedSummary?.distance, .measured(metres: h.decimal("6")))
  }

  func testPausedAdjustmentChangesPendingTargetsAndResumeRestoresSpeedThenInclination() throws {
    let h = try Harness.running(stepDuration: 20)
    let startedAt = try XCTUnwrap(h.orchestrator.state.currentSegment?.activeStartedAt).seconds
    h.send(
      .telemetry(epoch: h.epoch, h.sample("0", "0", distance: "8")),
      monotonic: startedAt + 3
    )
    guard case .paused = h.orchestrator.state.execution else { return XCTFail("Expected pause") }
    let count = h.transport.submissions.count

    h.send(.setSpeedOverride(epoch: h.epoch, h.speed("5.5")))
    h.send(.setInclinationOverride(epoch: h.epoch, h.inclination("1")))
    XCTAssertEqual(h.transport.submissions.count, count)
    XCTAssertEqual(
      h.orchestrator.targetEvidence.planned,
      .init(speed: h.speed("5"), inclination: h.inclination("0")))
    XCTAssertEqual(
      h.orchestrator.targetEvidence.effective,
      .init(speed: h.speed("5.5"), inclination: h.inclination("1")))

    h.send(.telemetry(epoch: h.epoch, h.sample("0.5", "0", distance: "9")))
    XCTAssertEqual(h.orchestrator.state.execution, .restoringTargets)
    XCTAssertEqual(h.transport.submissions.last?.intent, .setTargetSpeed(h.speed("5.5")))
    try h.acknowledgeCurrent()
    XCTAssertEqual(h.transport.submissions.last?.intent, .setTargetInclination(h.inclination("1")))
    try h.acknowledgeCurrent()
    XCTAssertNil(h.orchestrator.state.currentSegment?.activeStartedAt)
    h.send(.telemetry(epoch: h.epoch, h.sample("5.5", "1", distance: "10")))
    XCTAssertEqual(h.orchestrator.state.execution, .runningSegment)
    XCTAssertEqual(h.orchestrator.state.currentSegment?.accumulatedActiveSeconds, 3)
  }

  func testInflightAdjustmentDoesNotCompeteAndInvalidIncrementEmitsNothing() throws {
    let h = try Harness.running(stepDuration: 20)
    let invalid = h.send(.setSpeedOverride(epoch: h.epoch, h.speed("5.55")))
    XCTAssertEqual(invalid.reducerDisposition, .rejected(.invalidAdjustment))
    let before = h.transport.submissions.count

    h.send(.setSpeedOverride(epoch: h.epoch, h.speed("5.5")))
    let speed = try XCTUnwrap(h.orchestrator.state.procedure.unresolvedRecord)
    XCTAssertEqual(h.transport.submissions.count, before + 1)
    h.send(.setInclinationOverride(epoch: h.epoch, h.inclination("1")))
    XCTAssertEqual(h.transport.submissions.count, before + 1)
    XCTAssertEqual(h.orchestrator.state.procedure.unresolvedRecord?.id, speed.id)

    try h.acknowledgeCurrent()
    XCTAssertEqual(h.transport.submissions.count, before + 2)
    XCTAssertEqual(h.transport.submissions.last?.intent, .setTargetInclination(h.inclination("1")))
  }

  func testHumanStationaryEvidenceRemainsDistinctInEarlyEndHistory() throws {
    let h = try Harness.running(stepDuration: 20)
    let sampleAt = h.orchestrator.state.lastEventTime.seconds
    h.send(.tick(epoch: h.epoch), monotonic: sampleAt + 2.1)
    h.clock.set(monotonic: sampleAt + 3, wall: 2_000)
    let confirmed = h.orchestrator.handle(
      .humanConfirmsStationary(epoch: h.epoch, note: "Synthetic direct observation")
    )
    XCTAssertEqual(confirmed.reducerDisposition, .accepted)
    guard case .paused(.human) = h.orchestrator.state.execution else {
      return XCTFail("Expected separate human evidence")
    }
    h.send(.userEndsWorkout(epoch: h.epoch))
    let final = try XCTUnwrap(h.orchestrator.lastPersistedSummary)
    XCTAssertEqual(
      final.outcome,
      .stoppedByUser(reason: .init(rawValue: "ended-from-accepted-pause"))
    )
    XCTAssertEqual(
      final.physicalStopConfirmation,
      .humanConfirmed(at: Date(timeIntervalSince1970: 2_000))
    )
  }

  func testLaterMotionExpiresHumanStationaryEvidenceBeforeInterruptionAndCompletion() throws {
    let interrupted = try Harness.running(stepDuration: 20)
    let interruptedSampleAt = interrupted.orchestrator.state.lastEventTime.seconds
    interrupted.send(
      .tick(epoch: interrupted.epoch),
      monotonic: interruptedSampleAt + 2.1
    )
    interrupted.clock.set(monotonic: interruptedSampleAt + 3, wall: 2_000)
    interrupted.orchestrator.handle(
      .humanConfirmsStationary(
        epoch: interrupted.epoch,
        note: "Synthetic direct observation"
      )
    )
    interrupted.send(
      .humanObservesMotion(epoch: interrupted.epoch, note: "Synthetic later motion")
    )
    interrupted.send(
      .connectionLost(epoch: interrupted.epoch, reason: "Synthetic interruption")
    )
    XCTAssertEqual(
      interrupted.orchestrator.lastPersistedSummary?.physicalStopConfirmation,
      .unconfirmed
    )

    let completed = try Harness.running(stepDuration: 1)
    let completedSampleAt = completed.orchestrator.state.lastEventTime.seconds
    completed.send(.tick(epoch: completed.epoch), monotonic: completedSampleAt + 2.1)
    completed.clock.set(monotonic: completedSampleAt + 3, wall: 3_000)
    completed.orchestrator.handle(
      .humanConfirmsStationary(epoch: completed.epoch, note: "Synthetic direct observation")
    )
    completed.send(.telemetry(epoch: completed.epoch, completed.sample("0.5", "0")))
    try completed.acknowledgeCurrent()
    try completed.acknowledgeCurrent()
    completed.send(.telemetry(epoch: completed.epoch, completed.sample("5", "0")))
    try completed.finishCurrentStep()
    try completed.finishTargetSequenceAndObserve()
    try completed.finishCurrentStep()
    try completed.finishTargetSequenceAndObserve()
    try completed.finishCurrentStep()
    completed.send(.telemetry(epoch: completed.epoch, completed.sample("0", "0")))
    completed.send(.userEndsWorkout(epoch: completed.epoch))
    XCTAssertEqual(
      completed.orchestrator.lastPersistedSummary?.physicalStopConfirmation,
      .notRequired
    )
  }

  func testEveryTargetFailureStageStopsSequenceAndPersistsStableFailure() throws {
    enum Stage: CaseIterable { case submission, att, ftms, observation }

    for stage in Stage.allCases {
      let h = try Harness.applyingInitialTarget()
      let speed = try XCTUnwrap(h.orchestrator.state.procedure.unresolvedRecord)
      switch stage {
      case .submission:
        h.send(
          .intentSubmissionRejected(
            epoch: h.epoch, procedureID: speed.id, reason: "synthetic submission rejection")
        )
      case .att:
        h.send(.intentSubmitted(epoch: h.epoch, procedureID: speed.id))
        h.send(
          .attRejected(epoch: h.epoch, procedureID: speed.id, reason: "synthetic ATT rejection")
        )
      case .ftms:
        h.send(.intentSubmitted(epoch: h.epoch, procedureID: speed.id))
        h.send(.attAccepted(epoch: h.epoch, procedureID: speed.id))
        h.send(
          .protocolRejected(
            epoch: h.epoch, procedureID: speed.id, reason: "synthetic FTMS rejection")
        )
      case .observation:
        try h.acknowledgeCurrent()
        try h.acknowledgeCurrent()
        let deadline = try XCTUnwrap(h.orchestrator.state.targetSequence?.observationDeadline)
        h.send(.tick(epoch: h.epoch), monotonic: deadline.seconds)
      }

      guard case .failed = h.orchestrator.state.execution else {
        return XCTFail("Expected target stage \(stage) to fail closed")
      }
      let terminalSubmissionCount = h.transport.submissions.count
      h.send(.tick(epoch: h.epoch))
      XCTAssertEqual(h.transport.submissions.count, terminalSubmissionCount)
      guard case .failed = h.orchestrator.lastPersistedSummary?.outcome else {
        return XCTFail("Expected stable failed history for \(stage)")
      }
    }
  }

  func testDelayedZeroPausesButAbsentZeroInterruptsWithoutRetry() throws {
    let delayed = try Harness.running(stepDuration: 20)
    let sampleAt = delayed.orchestrator.state.lastEventTime.seconds
    delayed.send(.tick(epoch: delayed.epoch), monotonic: sampleAt + 2.1)
    guard case .checkingTreadmill = delayed.orchestrator.state.execution else {
      return XCTFail("Expected checking")
    }
    let count = delayed.transport.submissions.count
    delayed.send(
      .telemetry(epoch: delayed.epoch, delayed.sample("0", "0")),
      monotonic: sampleAt + 8.01
    )
    guard case .paused = delayed.orchestrator.state.execution else {
      return XCTFail("Expected delayed zero pause")
    }
    XCTAssertEqual(delayed.transport.submissions.count, count)

    let absent = try Harness.running(stepDuration: 20)
    let absentAt = absent.orchestrator.state.lastEventTime.seconds
    absent.send(.tick(epoch: absent.epoch), monotonic: absentAt + 2.1)
    absent.send(.tick(epoch: absent.epoch), monotonic: absentAt + 10)
    XCTAssertEqual(absent.orchestrator.state.execution, .interrupted(.telemetryStreamTimedOut))
    XCTAssertEqual(absent.transport.submissions.count, count)
    XCTAssertEqual(
      absent.orchestrator.lastPersistedSummary?.outcome,
      .interrupted(reason: .init(rawValue: "telemetry-stream-timed-out"))
    )
  }

  func testStaleMalformedContradictoryAndDuplicateEventsCannotContinue() throws {
    let stale = try Harness.running(stepDuration: 20)
    let before = stale.orchestrator.state
    let recordCount = stale.history.recordCalls.count
    let result = stale.send(
      .telemetry(epoch: .init(rawValue: 0), stale.sample("5", "0"))
    )
    XCTAssertEqual(result.reducerDisposition, .ignored(.staleEpoch))
    XCTAssertEqual(stale.orchestrator.state, before)
    XCTAssertEqual(stale.history.recordCalls.count, recordCount)

    let malformed = try Harness.running(stepDuration: 20)
    malformed.send(.telemetry(epoch: malformed.epoch, .malformed("synthetic malformed")))
    XCTAssertEqual(
      malformed.orchestrator.lastPersistedSummary?.outcome,
      .failed(reason: .init(rawValue: "telemetry-malformed"))
    )

    let contradictory = try Harness.running(stepDuration: 20)
    contradictory.send(
      .humanConfirmsStationary(epoch: contradictory.epoch, note: "Synthetic operator evidence")
    )
    XCTAssertEqual(
      contradictory.orchestrator.lastPersistedSummary?.outcome,
      .failed(reason: .init(rawValue: "evidence-contradictory"))
    )

    let duplicate = Harness()
    try duplicate.prepare()
    let request = try duplicate.begin()
    try duplicate.acknowledgeCurrent()
    duplicate.send(.protocolAcknowledged(epoch: duplicate.epoch, procedureID: request.id))
    guard
      case .failed(.procedure(.duplicateOrLate(request.id))) =
        duplicate.orchestrator.state.execution
    else { return XCTFail("Expected duplicate callback failure") }
    XCTAssertEqual(duplicate.transport.submissions.count, 1)
  }

  func testConnectionControlAppInterruptionAndCancellationNeverResumeOrReconnect() throws {
    let cases: [(Harness) throws -> WorkoutOrchestrationResult] = [
      { h in
        h.send(.connectionLost(epoch: h.epoch, reason: "synthetic loss"))
      },
      { h in
        h.send(.controlPermissionLost(epoch: h.epoch, reason: "synthetic control loss"))
      },
      { h in
        h.send(.appBecameInactive(epoch: h.epoch, reason: "synthetic interruption"))
      },
      { h in h.orchestrator.cancelAttempt(epoch: h.epoch) },
    ]

    for apply in cases {
      let h = try Harness.running(stepDuration: 20)
      let before = h.transport.submissions.count
      let result = try apply(h)
      guard case .interrupted = result.state.execution else {
        return XCTFail("Expected interruption")
      }
      h.send(.tick(epoch: h.epoch))
      XCTAssertEqual(h.transport.submissions.count, before)
      XCTAssertFalse(
        h.transport.effects.contains {
          guard case .submit(let record) = $0 else { return false }
          return record.id.sequence > UInt64(before)
        }
      )
    }

    let pending = Harness()
    try pending.prepare()
    let request = try pending.begin()
    let cancelled = pending.orchestrator.cancelAttempt(epoch: pending.epoch)
    XCTAssertEqual(cancelled.transportEffects, [.cancelAwaitingCallback(request.id)])
    guard case .timedOutUnknown = pending.orchestrator.state.procedure else {
      return XCTFail("Cancellation must retain delivery uncertainty")
    }
  }

  func testHistoryCreationAndIncrementalFailuresPreventOrStopTransport() throws {
    let initial = Harness()
    try initial.prepare()
    initial.history.failure = .writeFailed(.stagingWrite)
    let begin = initial.send(
      .beginWorkout(epoch: initial.epoch, readiness: initial.readiness)
    )
    XCTAssertEqual(begin.historyCheckpoint, .failed(.writeFailed(.stagingWrite)))
    XCTAssertEqual(initial.orchestrator.state.execution, .preflight)
    XCTAssertTrue(initial.transport.effects.isEmpty)

    let progress = Harness()
    try progress.prepare()
    _ = try progress.begin()
    try progress.acknowledgeCurrent()
    progress.history.failure = .writeFailed(.atomicReplacement)
    let failed = progress.send(.telemetry(epoch: progress.epoch, progress.sample("0.5", "0")))
    XCTAssertEqual(failed.historyCheckpoint, .failed(.writeFailed(.atomicReplacement)))
    XCTAssertEqual(
      progress.orchestrator.state.execution,
      .failed(.localHistoryPersistence("Incremental history write failed"))
    )
    XCTAssertEqual(progress.transport.submissions.count, 1)
    guard
      case .failed(let unforwarded, .notSubmitted(let reason)) =
        progress.orchestrator.state.procedure
    else { return XCTFail("Expected definitely-not-submitted target evidence") }
    XCTAssertEqual(unforwarded.intent, .setTargetSpeed(progress.speed("5")))
    XCTAssertEqual(reason, "Execution ended before procedure submission")
  }

  func testRestartRecoveryConvertsOnlyInProgressRecordsWithoutAnyExecutionEffect() throws {
    let h = Harness()
    let inProgress = h.historySummary(
      id: h.uuid(1),
      outcome: .inProgress,
      stop: .notRequired
    )
    let completed = h.historySummary(
      id: h.uuid(2),
      outcome: .completed,
      stop: .humanConfirmed(at: Date(timeIntervalSince1970: 50))
    )
    h.history.records = [inProgress, completed]
    h.clock.set(monotonic: 20, wall: 100)

    let result = h.orchestrator.recoverInterruptedHistory()
    guard case .recovered(let recovered) = result else {
      return XCTFail("Expected recovery")
    }
    XCTAssertEqual(recovered.count, 1)
    XCTAssertEqual(
      recovered[0].outcome,
      .interrupted(reason: .init(rawValue: "app-continuity-lost"))
    )
    XCTAssertEqual(recovered[0].activeDuration, inProgress.activeDuration)
    XCTAssertEqual(recovered[0].distance, inProgress.distance)
    XCTAssertEqual(recovered[0].progress, inProgress.progress)
    XCTAssertEqual(recovered[0].physicalStopConfirmation, .unconfirmed)
    XCTAssertEqual(h.history.records[1], completed)
    XCTAssertTrue(h.transport.effects.isEmpty)
    XCTAssertEqual(h.orchestrator.state.execution, .idle)
  }
}

extension WorkoutExecutionOrchestratorTests {
  @MainActor
  fileprivate final class Harness {
    let epoch = ConnectionEpoch(rawValue: 1)
    let clock = TestClock()
    let transport = RecordingTargetTransport()
    let history = RecordingHistoryRepository()
    let attemptIDs: FixedAttemptIDSource
    let capability: FR30zCapabilitySnapshot
    let ceilings: WorkoutSessionCeilings
    let profile: FR30zExecutionProfile
    let plan: WorkoutPlanValidator.ValidatedPlan
    let readiness = WorkoutOperatorReadiness(
      deckClear: true,
      consoleImmediatelyReachable: true,
      safetyKeyImmediatelyReachable: true,
      physicallyStationary: true
    )
    let orchestrator: WorkoutExecutionOrchestrator

    init(stepDuration: Int = 5) {
      attemptIDs = .init(ids: [UUID(uuidString: "00000000-0000-0000-0000-000000000059")!])
      let capabilities = WorkoutPlanCapabilities(
        speed: .supported(
          .init(minimum: Self.speed("0.5"), maximum: Self.speed("20"), increment: Self.speed("0.1"))
        ),
        inclination: .supported(
          .init(
            minimum: Self.inclination("0"), maximum: Self.inclination("15"),
            increment: Self.inclination("1")
          )
        )
      )
      capability = .init(
        peripheralIdentity: "synthetic-local-peripheral",
        equipmentIdentity: "synthetic-operator-confirmed-fr30z",
        fitnessMachineServicePresent: true,
        requiredCharacteristicPropertiesMatch: true,
        fitnessMachineFeatureEvidence: .matched,
        supportedSpeedRangeEvidence: .matched,
        supportedInclinationRangeEvidence: .matched,
        treadmillDataNotificationsEnabled: true,
        controlPointIndicationsEnabled: true,
        optionalSubscriptionOutcomesResolved: true,
        planCapabilities: capabilities
      )
      ceilings = .init(
        maximumSpeed: Self.speed("10"),
        maximumInclination: Self.inclination("6"),
        maximumStepSpeedChange: Self.speed("3")
      )
      profile = .init(
        peripheralIdentity: capability.peripheralIdentity,
        equipmentIdentity: capability.equipmentIdentity
      )
      let raw = WorkoutPlan(
        schemaVersion: WorkoutPlanSchema.currentVersion,
        suggestedName: "Synthetic orchestration",
        activity: .indoorRunning,
        steps: [
          Self.step(.warmUp, "Warm up", stepDuration, "5", "0"),
          Self.step(.interval, "Run", stepDuration, "7", "1"),
          Self.step(.coolDown, "Cool down", stepDuration, "4", "0"),
        ]
      )
      plan = try! WorkoutPlanValidator.validate(raw, against: capabilities).get()
      orchestrator = .init(
        transport: transport,
        history: history,
        clock: clock,
        attemptIDs: attemptIDs
      )
    }

    static func running(stepDuration: Int) throws -> Harness {
      let h = Harness(stepDuration: stepDuration)
      try h.prepare()
      _ = try h.begin()
      try h.acknowledgeCurrent()
      h.send(.telemetry(epoch: h.epoch, h.sample("0.5", "0")))
      try h.acknowledgeCurrent()
      try h.acknowledgeCurrent()
      h.send(.telemetry(epoch: h.epoch, h.sample("5", "0")))
      return h
    }

    static func applyingInitialTarget() throws -> Harness {
      let h = Harness()
      try h.prepare()
      _ = try h.begin()
      try h.acknowledgeCurrent()
      h.send(.telemetry(epoch: h.epoch, h.sample("0.5", "0")))
      return h
    }

    func prepare(sourcePlanID: UUID? = nil) throws {
      assertAccepted(send(.userStartsConnection(epoch)))
      assertAccepted(
        send(.connectionBecomesReady(epoch: epoch, capability: capability))
      )
      let armed = orchestrator.arm(
        plan: plan,
        ceilings: ceilings,
        profile: profile,
        sourcePlanID: sourcePlanID
      )
      assertAccepted(armed)
      XCTAssertEqual(orchestrator.state.execution, .preflight)
    }

    func begin() throws -> WorkoutProcedureRecord {
      let result = send(.beginWorkout(epoch: epoch, readiness: readiness))
      assertAccepted(result)
      return try XCTUnwrap(transport.submissions.last)
    }

    func acknowledgeCurrent() throws {
      let record = try XCTUnwrap(orchestrator.state.procedure.unresolvedRecord)
      if case .intentCreated = orchestrator.state.procedure {
        assertAccepted(send(.intentSubmitted(epoch: epoch, procedureID: record.id)))
      }
      assertAccepted(send(.attAccepted(epoch: epoch, procedureID: record.id)))
      assertAccepted(send(.protocolAcknowledged(epoch: epoch, procedureID: record.id)))
    }

    func finishTargetSequenceAndObserve() throws {
      while orchestrator.state.procedure.unresolvedRecord != nil {
        try acknowledgeCurrent()
      }
      guard case .runningSegment = orchestrator.state.execution else {
        let target = try XCTUnwrap(orchestrator.targetEvidence.effective)
        assertAccepted(
          send(.telemetry(epoch: epoch, sample(target.speed, target.inclination)))
        )
        return
      }
    }

    func finishCurrentStep() throws {
      let segment = try XCTUnwrap(orchestrator.state.currentSegment)
      let startedAt = try XCTUnwrap(segment.activeStartedAt).seconds
      let duration = TimeInterval(plan.plan.steps[segment.stepIndex].duration.value)
      let target = try XCTUnwrap(orchestrator.targetEvidence.effective)
      assertAccepted(
        send(
          .telemetry(epoch: epoch, sample(target.speed, target.inclination)),
          monotonic: startedAt + duration - 0.1
        )
      )
      assertAccepted(
        send(.tick(epoch: epoch), monotonic: startedAt + duration)
      )
    }

    @discardableResult
    func send(
      _ event: WorkoutExecutionEvent,
      monotonic: TimeInterval? = nil
    ) -> WorkoutOrchestrationResult {
      if let monotonic {
        clock.set(monotonic: monotonic, wall: 1_000 + monotonic)
      } else {
        clock.advance(by: 0.1)
      }
      return orchestrator.handle(event)
    }

    func sample(
      _ speed: String,
      _ inclination: String,
      distance: String? = nil
    ) -> WorkoutTelemetryInput {
      .sample(
        speed: self.speed(speed),
        inclination: self.inclination(inclination),
        totalDistanceMetres: distance.map(decimal)
      )
    }

    func sample(
      _ speed: WorkoutSpeed,
      _ inclination: WorkoutInclination
    ) -> WorkoutTelemetryInput {
      .sample(speed: speed, inclination: inclination, totalDistanceMetres: nil)
    }

    func speed(_ value: String) -> WorkoutSpeed { Self.speed(value) }
    func inclination(_ value: String) -> WorkoutInclination { Self.inclination(value) }
    func decimal(_ value: String) -> Decimal { Self.decimal(value) }
    func uuid(_ suffix: Int) -> UUID {
      UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }

    func historySummary(
      id: UUID,
      outcome: WorkoutExecutionOutcome,
      stop: WorkoutPhysicalStopConfirmation
    ) -> WorkoutExecutionSummary {
      .init(
        id: id,
        schemaVersion: WorkoutExecutionSummarySchema.currentVersion,
        sourcePlanID: nil,
        planSnapshot: plan.plan,
        attemptedAt: Date(timeIntervalSince1970: 10),
        lastUpdatedAt: Date(timeIntervalSince1970: 20),
        outcome: outcome,
        activeDuration: .measured(seconds: 3),
        distance: .measured(metres: decimal("7")),
        progress: .init(completedStepCount: 0, currentStepIndex: 0, activeSecondsInCurrentStep: 3),
        physicalStopConfirmation: stop
      )
    }

    private func assertAccepted(
      _ result: WorkoutOrchestrationResult,
      file: StaticString = #filePath,
      line: UInt = #line
    ) {
      XCTAssertEqual(result.reducerDisposition, .accepted, file: file, line: line)
    }

    static func speed(_ value: String) -> WorkoutSpeed {
      .init(value: decimal(value), unit: .kilometresPerHour)
    }

    static func inclination(_ value: String) -> WorkoutInclination {
      .init(value: decimal(value), unit: .percent)
    }

    static func decimal(_ value: String) -> Decimal {
      Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    static func step(
      _ kind: WorkoutStepKind,
      _ label: String,
      _ duration: Int,
      _ speed: String,
      _ inclination: String
    ) -> WorkoutStep {
      .init(
        kind: kind,
        label: label,
        duration: .init(value: duration, unit: .seconds),
        targetSpeed: self.speed(speed),
        targetInclination: self.inclination(inclination)
      )
    }
  }
}

private final class TestClock: WorkoutOrchestrationClock {
  private var reading = WorkoutOrchestrationTime(
    monotonic: .init(seconds: 10),
    wallClock: Date(timeIntervalSince1970: 1_010)
  )

  func read() -> WorkoutOrchestrationTime { reading }

  func advance(by interval: TimeInterval) {
    set(
      monotonic: reading.monotonic.seconds + interval,
      wall: reading.wallClock.timeIntervalSince1970 + interval
    )
  }

  func set(monotonic: TimeInterval, wall: TimeInterval) {
    reading = .init(
      monotonic: .init(seconds: monotonic),
      wallClock: Date(timeIntervalSince1970: wall)
    )
  }
}

private final class FixedAttemptIDSource: WorkoutAttemptIDSource {
  private var ids: [UUID]
  init(ids: [UUID]) { self.ids = ids }
  func nextAttemptID() -> UUID { ids.removeFirst() }
}

private final class RecordingTargetTransport: WorkoutTargetControlTransport {
  private(set) var effects: [WorkoutTargetControlTransportEffect] = []
  var submissions: [WorkoutProcedureRecord] {
    effects.compactMap {
      guard case .submit(let record) = $0 else { return nil }
      return record
    }
  }
  func perform(_ effect: WorkoutTargetControlTransportEffect) { effects.append(effect) }
}

private final class RecordingHistoryRepository: WorkoutHistoryRepositoryProtocol {
  var records: [WorkoutExecutionSummary] = []
  var failure: WorkoutHistoryMutationFailure?
  private(set) var recordCalls: [WorkoutExecutionSummary] = []

  func list() -> WorkoutHistoryRepositoryStatus {
    .init(
      canonical: records.isEmpty ? .empty : .available(summaries: records),
      staging: .absent
    )
  }

  func record(_ summary: WorkoutExecutionSummary) throws {
    if let failure { throw failure }
    recordCalls.append(summary)
    if let index = records.firstIndex(where: { $0.id == summary.id }) {
      records[index] = summary
    } else {
      records.append(summary)
    }
  }
}
