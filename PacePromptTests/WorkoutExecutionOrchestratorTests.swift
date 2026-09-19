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
    try h.begin()

    XCTAssertTrue(h.transport.submissions.isEmpty)
    XCTAssertEqual(h.orchestrator.state.execution, .waitingForPhysicalStart)
    XCTAssertEqual(h.orchestrator.state.controlPermission, .notHeld)
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

    h.send(.telemetry(epoch: h.epoch, h.sample("0", "0", distance: "0")))
    XCTAssertTrue(h.transport.submissions.isEmpty)
    h.send(.telemetry(epoch: h.epoch, h.sample("0.5", "0", distance: "1")))
    let request = try XCTUnwrap(h.transport.submissions.last)
    XCTAssertEqual(request.intent, .requestControl)

    h.send(.intentSubmitted(epoch: h.epoch, procedureID: request.id))
    guard case .submitted = h.orchestrator.state.procedure else {
      return XCTFail("Submission must remain distinct")
    }
    h.send(.attAccepted(epoch: h.epoch, procedureID: request.id))
    guard case .attAccepted = h.orchestrator.state.procedure else {
      return XCTFail("ATT acceptance must remain distinct")
    }
    h.send(.protocolAcknowledged(epoch: h.epoch, procedureID: request.id))
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
    guard case let .measuredWithProvenance(metres, distanceProvenance) = final.distance else {
      return XCTFail("Expected current-attempt cumulative-distance delta")
    }
    XCTAssertEqual(metres, h.decimal("39"))
    XCTAssertEqual(distanceProvenance.method, .fr30zCumulativeDistanceDelta)
    XCTAssertEqual(distanceProvenance.startCumulativeMetres, h.decimal("3"))
    XCTAssertEqual(distanceProvenance.startObservedAt.timeIntervalSince1970, 1_011.5, accuracy: 0.000_001)
    XCTAssertEqual(distanceProvenance.finalCumulativeMetres, h.decimal("42"))
    XCTAssertEqual(distanceProvenance.finalObservedAt.timeIntervalSince1970, 1_029, accuracy: 0.000_001)
    guard case let .recorded(startedAt, endedAt, provenance, intervals) = final.activityTimeline else {
      return XCTFail("Expected a recorded execution-clock timeline")
    }
    XCTAssertEqual(provenance, .executionClock)
    XCTAssertEqual(startedAt, intervals.first?.startedAt)
    XCTAssertEqual(endedAt, intervals.last?.endedAt)
    XCTAssertEqual(intervals.count, 5)
    XCTAssertEqual(intervals[0].effectiveSpeed.source, .planned)
    XCTAssertEqual(intervals[1].effectiveSpeed.source, .manualOverride)
    XCTAssertEqual(intervals[1].effectiveInclination.source, .planned)
    XCTAssertEqual(intervals[1].settledObservation.speedKilometresPerHour, h.decimal("5.5"))
    XCTAssertEqual(intervals[1].settledObservation.inclinationPercent, h.decimal("0"))
    XCTAssertEqual(final.healthExport, .notRequested)
    XCTAssertEqual(final.physicalStopConfirmation, .notRequired)
    guard case let .eligible(healthPayload) = WorkoutHealthPayloadFactory.make(
      summary: final,
      syncVersion: 1
    ) else { return XCTFail("Completed orchestrator summary must be Health-export eligible") }
    XCTAssertEqual(healthPayload.intervals.count, intervals.count)
    XCTAssertEqual(healthPayload.distanceMetres, h.decimal("39"))

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
    XCTAssertEqual(
      h.orchestrator.lastPersistedSummary?.distance,
      .unavailable(reason: .init(rawValue: "distance-provenance-unavailable"))
    )
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
    XCTAssertEqual(h.orchestrator.state.currentSegment?.accumulatedActiveSeconds, 2)
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

  func testTerminalStationaryAcknowledgementPreservesInterruptionAndUpdatesHistory() throws {
    let h = try Harness.running(stepDuration: 20)
    let interruption = h.send(
      .userCancelsAttempt(epoch: h.epoch)
    )
    guard case .interrupted(let reason) = interruption.state.execution else {
      return XCTFail("Expected interruption")
    }
    let interruptedSummary = try XCTUnwrap(h.orchestrator.lastPersistedSummary)
    XCTAssertEqual(interruptedSummary.physicalStopConfirmation, .unconfirmed)

    let acknowledgement = h.send(
      .humanConfirmsStationary(
        epoch: h.epoch,
        note: "Synthetic direct observation"
      ),
      monotonic: h.orchestrator.state.lastEventTime.seconds + 3
    )

    XCTAssertEqual(acknowledgement.reducerDisposition, .accepted)
    XCTAssertEqual(h.orchestrator.state.execution, .interrupted(reason))
    XCTAssertFalse(h.orchestrator.state.motionPossible)
    XCTAssertTrue(acknowledgement.transportEffects.isEmpty)
    let updated = try XCTUnwrap(h.orchestrator.lastPersistedSummary)
    XCTAssertEqual(updated.outcome, interruptedSummary.outcome)
    XCTAssertEqual(updated.activityTimeline, interruptedSummary.activityTimeline)
    XCTAssertEqual(updated.distance, interruptedSummary.distance)
    XCTAssertEqual(updated.healthExport, interruptedSummary.healthExport)
    XCTAssertEqual(
      updated.physicalStopConfirmation,
      .humanConfirmed(at: Date(timeIntervalSince1970: 1_000 + h.clock.read().monotonic.seconds))
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

  func testLaterSegmentFailurePersistsOnlyClosedExecutedIntervalDuration() throws {
    let h = try Harness.running(stepDuration: 20)
    try h.finishCurrentStep()
    try h.finishTargetSequenceAndObserve()
    try h.finishCurrentStep()

    while h.orchestrator.state.procedure.unresolvedRecord != nil {
      try h.acknowledgeCurrent()
    }
    let deadline = try XCTUnwrap(h.orchestrator.state.targetSequence?.observationDeadline)
    h.send(.tick(epoch: h.epoch), monotonic: deadline.seconds)

    guard case .failed = h.orchestrator.state.execution else {
      return XCTFail("Expected the unsettled later target to fail closed")
    }
    let summary = try XCTUnwrap(h.orchestrator.lastPersistedSummary)
    guard case .failed = summary.outcome else {
      return XCTFail("Expected a stable failed history checkpoint")
    }
    guard case .recorded(_, _, _, let intervals) = summary.activityTimeline else {
      return XCTFail("Expected the two truthful closed intervals to remain recorded")
    }
    XCTAssertEqual(intervals.count, 2)
    let intervalSeconds = intervals.reduce(0.0) {
      $0 + $1.endedAt.timeIntervalSince($1.startedAt)
    }
    let measuredIntervalSeconds = Int(floor(intervalSeconds + 0.000_001))
    XCTAssertEqual(measuredIntervalSeconds, 40)
    XCTAssertEqual(summary.activeDuration, .measured(seconds: measuredIntervalSeconds))
  }

  func testDelayedZeroPausesAndAbsentTelemetryWaitsForOperatorWithoutRetry() throws {
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
    absent.send(.tick(epoch: absent.epoch), monotonic: absentAt + 60)
    guard case .checkingTreadmill = absent.orchestrator.state.execution else {
      return XCTFail("Expected absent telemetry to remain checking")
    }
    XCTAssertEqual(absent.transport.submissions.count, count)
    absent.send(
      .humanConfirmsStationary(epoch: absent.epoch, note: "Synthetic direct observation"),
      monotonic: absentAt + 61
    )
    guard case .paused(.human) = absent.orchestrator.state.execution else {
      return XCTFail("Expected operator-confirmed pause")
    }
    XCTAssertEqual(absent.transport.submissions.count, count)
    XCTAssertEqual(absent.orchestrator.lastPersistedSummary?.outcome, .inProgress)
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
    try duplicate.begin()
    duplicate.send(.telemetry(epoch: duplicate.epoch, duplicate.sample("0.5", "0")))
    let request = try XCTUnwrap(duplicate.transport.submissions.last)
    duplicate.send(.intentSubmitted(epoch: duplicate.epoch, procedureID: request.id))
    duplicate.send(.attAccepted(epoch: duplicate.epoch, procedureID: request.id))
    duplicate.send(
      .protocolAcknowledged(epoch: duplicate.epoch, procedureID: request.id),
      monotonic: duplicate.orchestrator.state.lastEventTime.seconds + 2.1
    )
    XCTAssertEqual(duplicate.orchestrator.state.execution, .waitingForPhysicalStart)
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
        h.send(.userCancelsAttempt(epoch: h.epoch))
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
    try pending.begin()
    pending.send(.telemetry(epoch: pending.epoch, pending.sample("0.5", "0")))
    let request = try XCTUnwrap(pending.transport.submissions.last)
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
    let begin = initial.send(.beginWorkout(epoch: initial.epoch))
    XCTAssertEqual(begin.historyCheckpoint, .failed(.writeFailed(.stagingWrite)))
    XCTAssertEqual(initial.orchestrator.state.execution, .preflight)
    XCTAssertTrue(initial.transport.effects.isEmpty)

    let progress = Harness()
    try progress.prepare()
    try progress.begin()
    progress.history.failure = .writeFailed(.atomicReplacement)
    let failed = progress.send(.telemetry(epoch: progress.epoch, progress.sample("0.5", "0")))
    XCTAssertEqual(failed.historyCheckpoint, .failed(.writeFailed(.atomicReplacement)))
    XCTAssertEqual(
      progress.orchestrator.state.execution,
      .failed(.localHistoryPersistence("Incremental history write failed"))
    )
    XCTAssertTrue(progress.transport.submissions.isEmpty)
    guard
      case .failed(let unforwarded, .notSubmitted(let reason)) =
        progress.orchestrator.state.procedure
    else { return XCTFail("Expected definitely-not-submitted control evidence") }
    XCTAssertEqual(unforwarded.intent, .requestControl)
    XCTAssertEqual(reason, "Execution ended before procedure submission")
  }

  func testRunningCheckpointAfterTargetChangeDoesNotPublishPartialTimeline() throws {
    let h = try Harness.running(stepDuration: 20)
    h.send(.setSpeedOverride(epoch: h.epoch, h.speed("5.5")))
    try h.acknowledgeCurrent()
    h.send(.telemetry(epoch: h.epoch, h.sample("5.5", "0")))
    let activeStartedAt = try XCTUnwrap(h.orchestrator.state.currentSegment?.activeStartedAt)

    let checkpoint = h.send(
      .tick(epoch: h.epoch),
      monotonic: activeStartedAt.seconds + 1.1
    )

    guard case let .recorded(summary) = checkpoint.historyCheckpoint else {
      return XCTFail("Expected a coherent running checkpoint")
    }
    guard case .unavailable = summary.activityTimeline else {
      return XCTFail("An open interval must not be published as a recorded timeline")
    }
    XCTAssertEqual(summary.outcome, .inProgress)
    if case .failed = checkpoint.state.execution {
      XCTFail("A coherent checkpoint must not fail the workout")
    }
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
      .interrupted(reason: .init(rawValue: "app-process-ended"))
    )
    XCTAssertEqual(recovered[0].activeDuration, inProgress.activeDuration)
    XCTAssertEqual(recovered[0].distance, inProgress.distance)
    XCTAssertEqual(recovered[0].progress, inProgress.progress)
    XCTAssertEqual(recovered[0].physicalStopConfirmation, .unconfirmed)
    XCTAssertEqual(h.history.records[1], completed)
    XCTAssertTrue(h.transport.effects.isEmpty)
    XCTAssertEqual(h.orchestrator.state.execution, .idle)
  }

  func testLifecycleCheckpointPreservesAttemptProgressOverrideIntentAndNeverResumes() throws {
    let h = try Harness.running(stepDuration: 20)
    let started = try XCTUnwrap(h.orchestrator.state.currentSegment?.activeStartedAt)
    h.send(
      .telemetry(epoch: h.epoch, h.sample("5", "0")),
      monotonic: started.seconds + 1
    )
    h.send(.setSpeedOverride(epoch: h.epoch, h.speed("5.5")))

    let checkpoint = try XCTUnwrap(h.lifecycleCheckpoints.checkpoint)
    let attemptID = try XCTUnwrap(h.orchestrator.frozenAttempt?.attemptID)
    XCTAssertEqual(checkpoint.historySummaryID, attemptID)
    XCTAssertEqual(checkpoint.currentStepIndex, 0)
    XCTAssertEqual(checkpoint.completedStepCount, 0)
    XCTAssertEqual(checkpoint.evidenceBackedActiveSeconds, 1.1, accuracy: 0.000_001)
    XCTAssertEqual(checkpoint.speedOverrideKilometresPerHour, h.decimal("5.5"))
    XCTAssertNil(checkpoint.inclinationOverridePercent)
    XCTAssertEqual(checkpoint.effectiveTargetSpeedKilometresPerHour, h.decimal("5.5"))
    XCTAssertEqual(checkpoint.lastConfirmedTargetSpeedKilometresPerHour, h.decimal("5"))
    XCTAssertEqual(checkpoint.pendingTargetIntent, .setTargetSpeed(h.decimal("5.5")))
    XCTAssertEqual(checkpoint.pendingProcedureID, 4)

    let encodedCheckpoint = try JSONEncoder().encode(checkpoint)
    XCTAssertEqual(
      try JSONDecoder().decode(WorkoutLifecycleCheckpoint.self, from: encodedCheckpoint),
      checkpoint
    )

    let recoveryTransport = RecordingTargetTransport()
    let recovery = WorkoutExecutionOrchestrator(
      transport: recoveryTransport,
      history: h.history,
      lifecycleCheckpoints: h.lifecycleCheckpoints,
      clock: h.clock,
      attemptIDs: FixedAttemptIDSource(ids: [h.uuid(90)])
    )
    let result = recovery.recoverInterruptedHistory()
    guard case .recovered(let recovered) = result else {
      return XCTFail("Expected process-death recovery")
    }
    XCTAssertEqual(
      recovered.single?.outcome,
      .interrupted(reason: .init(rawValue: "app-process-ended-with-checkpoint"))
    )
    XCTAssertTrue(recoveryTransport.effects.isEmpty)
    XCTAssertEqual(recovery.state.execution, .idle)
    XCTAssertNil(h.lifecycleCheckpoints.checkpoint)
  }

  func testBackgroundCheckpointDoesNotCountAnUnobservedSuspensionGap() throws {
    let h = try Harness.running(stepDuration: 20)
    let started = try XCTUnwrap(h.orchestrator.state.currentSegment?.activeStartedAt)
    h.send(
      .telemetry(epoch: h.epoch, h.sample("5", "0")),
      monotonic: started.seconds + 1
    )

    let background = h.send(
      .applicationLifecycleChanged(epoch: h.epoch, .background),
      monotonic: started.seconds + 60
    )

    guard case .recorded(let summary) = background.historyCheckpoint else {
      return XCTFail("Expected a lifecycle history checkpoint")
    }
    XCTAssertEqual(summary.activeDuration, .measured(seconds: 3))
    XCTAssertEqual(summary.progress.activeSecondsInCurrentStep, 3)
    XCTAssertEqual(
      try XCTUnwrap(h.lifecycleCheckpoints.checkpoint).evidenceBackedActiveSeconds,
      3,
      accuracy: 0.000_001
    )

    let interrupted = h.send(
      .connectionLost(epoch: h.epoch, reason: "Synthetic background disconnect"),
      monotonic: started.seconds + 61
    )
    guard case .recorded(let finalSummary) = interrupted.historyCheckpoint else {
      return XCTFail("Expected an interruption history checkpoint")
    }
    XCTAssertEqual(finalSummary.activeDuration, .measured(seconds: 3))
    guard case .recorded(_, _, _, let intervals) = finalSummary.activityTimeline else {
      return XCTFail("Expected the evidence-bounded interval to close")
    }
    XCTAssertEqual(
      intervals.reduce(0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) },
      3,
      accuracy: 0.000_001
    )
  }

  func testFreshTelemetryAfterLongGapSplitsRecordedExecutionIntervals() throws {
    let h = try Harness.running(stepDuration: 20)
    let started = try XCTUnwrap(h.orchestrator.state.currentSegment?.activeStartedAt)

    h.send(
      .telemetry(epoch: h.epoch, h.sample("5", "0")),
      monotonic: started.seconds + 10
    )
    let paused = h.send(
      .telemetry(epoch: h.epoch, h.sample("0", "0")),
      monotonic: started.seconds + 11
    )

    guard case .recorded(let summary) = paused.historyCheckpoint else {
      return XCTFail("Expected a pause history checkpoint")
    }
    XCTAssertEqual(summary.activeDuration, .measured(seconds: 3))
    guard case .recorded(_, _, _, let intervals) = summary.activityTimeline else {
      return XCTFail("Expected split execution intervals")
    }
    XCTAssertEqual(intervals.count, 2)
    XCTAssertEqual(
      intervals.reduce(0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) },
      3,
      accuracy: 0.000_001
    )
  }
}

extension WorkoutExecutionOrchestratorTests {
  @MainActor
  fileprivate final class Harness {
    let epoch = ConnectionEpoch(rawValue: 1)
    let clock = TestClock()
    let transport = RecordingTargetTransport()
    let history = RecordingHistoryRepository()
    let lifecycleCheckpoints = RecordingLifecycleCheckpointRepository()
    let attemptIDs: FixedAttemptIDSource
    let capability: FR30zCapabilitySnapshot
    let ceilings: WorkoutSessionCeilings
    let profile: FR30zExecutionProfile
    let plan: WorkoutPlanValidator.ValidatedPlan
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
        lifecycleCheckpoints: lifecycleCheckpoints,
        clock: clock,
        attemptIDs: attemptIDs
      )
    }

    static func running(stepDuration: Int) throws -> Harness {
      let h = Harness(stepDuration: stepDuration)
      try h.prepare()
      try h.begin()
      h.send(.telemetry(epoch: h.epoch, h.sample("0.5", "0")))
      try h.acknowledgeCurrent()
      try h.acknowledgeCurrent()
      try h.acknowledgeCurrent()
      h.send(.telemetry(epoch: h.epoch, h.sample("5", "0")))
      return h
    }

    static func applyingInitialTarget() throws -> Harness {
      let h = Harness()
      try h.prepare()
      try h.begin()
      h.send(.telemetry(epoch: h.epoch, h.sample("0.5", "0")))
      try h.acknowledgeCurrent()
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

    func begin() throws {
      let result = send(.beginWorkout(epoch: epoch))
      assertAccepted(result)
      XCTAssertTrue(result.reducerEffects.isEmpty)
      XCTAssertTrue(result.transportEffects.isEmpty)
      XCTAssertTrue(transport.submissions.isEmpty)
      XCTAssertEqual(orchestrator.state.execution, .waitingForPhysicalStart)
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
      var segment = try XCTUnwrap(orchestrator.state.currentSegment)
      let startedAt = try XCTUnwrap(segment.activeStartedAt).seconds
      let duration = TimeInterval(plan.plan.steps[segment.stepIndex].duration.value)
      let target = try XCTUnwrap(orchestrator.targetEvidence.effective)
      var elapsed: TimeInterval = 1
      while elapsed <= duration {
        assertAccepted(
          send(
            .telemetry(epoch: epoch, sample(target.speed, target.inclination)),
            monotonic: startedAt + elapsed
          )
        )
        elapsed += 1
      }
      segment = try XCTUnwrap(orchestrator.state.currentSegment)
      XCTAssertNil(segment.activeStartedAt)
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

private final class RecordingLifecycleCheckpointRepository:
  WorkoutLifecycleCheckpointRepositoryProtocol
{
  var checkpoint: WorkoutLifecycleCheckpoint?
  var failure: Error?

  func load() throws -> WorkoutLifecycleCheckpoint? {
    if let failure { throw failure }
    return checkpoint
  }

  func save(_ checkpoint: WorkoutLifecycleCheckpoint) throws {
    if let failure { throw failure }
    self.checkpoint = checkpoint
  }

  func remove() throws {
    if let failure { throw failure }
    checkpoint = nil
  }
}

private extension Collection {
  var single: Element? { count == 1 ? first : nil }
}
