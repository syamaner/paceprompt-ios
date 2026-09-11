import XCTest

@testable import PacePrompt

final class WorkoutExecutionReducerTests: XCTestCase {
  func testExactProfileAndCeilingsGatePreflight() throws {
    let h = Harness()
    var state = h.connectingState()
    let mismatch = h.capabilityReplacingFeatureEvidence(.mismatch)
    state =
      h.accept(h.send(state, .connectionBecomesReady(epoch: h.epoch, capability: mismatch))).state
    let rejected = h.send(state, .arm(plan: h.plan, ceilings: h.ceilings, profile: h.profile))
    XCTAssertEqual(rejected.disposition, .rejected(.incompleteOrMismatchedProfile))
    XCTAssertEqual(rejected.state, state)

    XCTAssertEqual(try Harness().preflightState().execution, .preflight)
    XCTAssertEqual(FR30zExecutionProfile.telemetryFreshnessInterval, 2)
    XCTAssertEqual(FR30zExecutionProfile.telemetryCheckingInterval, 10)
    XCTAssertEqual(FR30zExecutionProfile.targetObservationInterval, 30)
  }

  func testBeginCreatesOnlyRequestControlIntentAndRequiresReadiness() throws {
    let h = Harness()
    let state = try h.preflightState()
    let missing = WorkoutOperatorReadiness(
      deckClear: true,
      consoleImmediatelyReachable: false,
      safetyKeyImmediatelyReachable: true,
      physicallyStationary: true
    )
    let rejected = h.send(state, .beginWorkout(epoch: h.epoch, readiness: missing))
    XCTAssertEqual(rejected.disposition, .rejected(.operatorReadinessMissing))
    XCTAssertEqual(rejected.state, state)

    let accepted = h.accept(h.send(state, .beginWorkout(epoch: h.epoch, readiness: h.readiness)))
    XCTAssertEqual(accepted.state.execution, .acquiringControl)
    XCTAssertEqual(accepted.record?.intent, .requestControl)
    XCTAssertFalse(accepted.state.motionPossible)
    XCTAssertFalse(accepted.effects.containsTargetSubmission)
  }

  func testIntentSubmissionATTAndFTMSAcknowledgementRemainDistinct() throws {
    let h = Harness()
    var t = h.accept(
      h.send(try h.preflightState(), .beginWorkout(epoch: h.epoch, readiness: h.readiness)))
    let record = try XCTUnwrap(t.record)
    t = h.accept(h.send(t.state, .intentSubmitted(epoch: h.epoch, procedureID: record.id)))
    guard case .submitted = t.state.procedure else { return XCTFail("Expected submitted") }
    XCTAssertEqual(t.state.execution, .acquiringControl)
    t = h.accept(h.send(t.state, .attAccepted(epoch: h.epoch, procedureID: record.id)))
    guard case .attAccepted = t.state.procedure else { return XCTFail("Expected ATT accepted") }
    XCTAssertEqual(t.state.execution, .acquiringControl)
    t = h.accept(h.send(t.state, .protocolAcknowledged(epoch: h.epoch, procedureID: record.id)))
    XCTAssertEqual(t.state.execution, .waitingForPhysicalStart)
    guard case .held(h.epoch, _) = t.state.controlPermission else {
      return XCTFail("Expected control")
    }
  }

  func testEarlyFTMSAcknowledgementRemainsProvisionalUntilATT() throws {
    let h = Harness()
    var t = h.accept(
      h.send(try h.preflightState(), .beginWorkout(epoch: h.epoch, readiness: h.readiness)))
    let record = try XCTUnwrap(t.record)
    t = h.accept(h.send(t.state, .intentSubmitted(epoch: h.epoch, procedureID: record.id)))
    t = h.accept(h.send(t.state, .protocolAcknowledged(epoch: h.epoch, procedureID: record.id)))
    guard case .submitted(let provisional) = t.state.procedure else {
      return XCTFail("Expected provisional")
    }
    XCTAssertNotNil(provisional.ftmsAcknowledgedAt)
    XCTAssertEqual(t.state.execution, .acquiringControl)
    t = h.accept(h.send(t.state, .attAccepted(epoch: h.epoch, procedureID: record.id)))
    XCTAssertEqual(t.state.execution, .waitingForPhysicalStart)
  }

  func testPhysicalStartNeedsFreshNonzeroTelemetryAndAppliesSpeedThenInclination() throws {
    let h = Harness()
    var state = try h.waitingState()
    var t = h.accept(h.send(state, .telemetry(epoch: h.epoch, h.sample("0", "0"))))
    state = t.state
    XCTAssertEqual(state.execution, .waitingForPhysicalStart)
    XCTAssertTrue(t.effects.isEmpty)

    t = h.accept(h.send(state, .telemetry(epoch: h.epoch, h.sample("0.5", "0"))))
    XCTAssertEqual(t.state.execution, .applyingTargets(.initial))
    XCTAssertEqual(t.record?.intent, .setTargetSpeed(Harness.speed("5")))
    t = try h.acknowledgeCurrent(t)
    XCTAssertEqual(t.record?.intent, .setTargetInclination(Harness.inclination("0")))
    t = try h.acknowledgeCurrent(t)
    XCTAssertEqual(t.state.execution, .applyingTargets(.initial))
    XCTAssertNil(t.state.currentSegment?.activeStartedAt)
    t = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("4.9", "0"))))
    XCTAssertEqual(t.state.execution, .applyingTargets(.initial))
    t = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("5", "0"))))
    XCTAssertEqual(t.state.execution, .runningSegment)
  }

  func testWaitingForPhysicalStartAdjustmentsStayPendingAndBecomeInitialTargets() throws {
    let h = Harness()
    var t = h.accept(
      h.send(try h.waitingState(), .setSpeedOverride(epoch: h.epoch, Harness.speed("5.5"))))
    XCTAssertTrue(t.effects.isEmpty)
    XCTAssertEqual(t.state.currentSegment?.speedOverride, Harness.speed("5.5"))
    t = h.accept(
      h.send(t.state, .setInclinationOverride(epoch: h.epoch, Harness.inclination("1"))))
    XCTAssertTrue(t.effects.isEmpty)
    XCTAssertEqual(t.state.currentSegment?.inclinationOverride, Harness.inclination("1"))

    t = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("0.5", "0"))))
    XCTAssertEqual(t.record?.intent, .setTargetSpeed(Harness.speed("5.5")))
    t = try h.acknowledgeCurrent(t)
    XCTAssertEqual(t.record?.intent, .setTargetInclination(Harness.inclination("1")))
  }

  func testStaleTelemetryChecksAtTwoSecondsAndExcludesUncertainGap() throws {
    let h = Harness(stepDuration: 20)
    var state = try h.runningState()
    let sampleAt = state.lastEventTime.seconds
    var t = h.accept(h.send(at: sampleAt + 2, state, .tick(epoch: h.epoch)))
    XCTAssertEqual(t.state.execution, .runningSegment)
    t = h.accept(h.send(at: sampleAt + 2.1, t.state, .tick(epoch: h.epoch)))
    guard case .checkingTreadmill(let checking) = t.state.execution else {
      return XCTFail("Expected checking")
    }
    XCTAssertEqual(checking.freshnessBoundary.seconds, sampleAt + 2, accuracy: 0.0001)
    XCTAssertEqual(t.state.currentSegment?.accumulatedActiveSeconds ?? -1, 2, accuracy: 0.0001)
    t = h.accept(
      h.send(at: sampleAt + 8, t.state, .telemetry(epoch: h.epoch, h.sample("4.8", "0"))))
    state = t.state
    XCTAssertEqual(state.execution, .runningSegment)
    XCTAssertEqual(state.currentSegment?.accumulatedActiveSeconds ?? -1, 2, accuracy: 0.0001)
    XCTAssertEqual(
      state.currentSegment?.activeStartedAt?.seconds ?? -1, sampleAt + 8, accuracy: 0.0001)
    XCTAssertTrue(t.effects.isEmpty)
  }

  func testDelayedZeroPausesButSilenceOrDeadlineTelemetryInterrupts() throws {
    let h = Harness(stepDuration: 20)
    var state = try h.runningState()
    let sampleAt = state.lastEventTime.seconds
    state = h.accept(h.send(at: sampleAt + 3, state, .tick(epoch: h.epoch))).state
    let paused = h.accept(
      h.send(at: sampleAt + 8.01, state, .telemetry(epoch: h.epoch, h.sample("0", "0")))
    )
    guard case .paused(.telemetry) = paused.state.execution else {
      return XCTFail("Expected pause")
    }
    XCTAssertEqual(paused.state.currentSegment?.accumulatedActiveSeconds ?? -1, 2, accuracy: 0.0001)

    let silence = Harness(stepDuration: 20)
    var other = try silence.runningState()
    let otherSampleAt = other.lastEventTime.seconds
    other =
      silence.accept(silence.send(at: otherSampleAt + 3, other, .tick(epoch: silence.epoch))).state
    let interrupted = silence.send(at: otherSampleAt + 10, other, .tick(epoch: silence.epoch))
    XCTAssertEqual(interrupted.state.execution, .interrupted(.telemetryStreamTimedOut))
    XCTAssertEqual(interrupted.effects, [.directUserToConsoleAndSafetyKey])
    XCTAssertFalse(interrupted.effects.containsTargetSubmission)

    let boundary = Harness(stepDuration: 20)
    var boundaryState = try boundary.runningState()
    let boundaryAt = boundaryState.lastEventTime.seconds
    boundaryState =
      boundary.accept(
        boundary.send(at: boundaryAt + 3, boundaryState, .tick(epoch: boundary.epoch))
      ).state
    let late = boundary.send(
      at: boundaryAt + 10,
      boundaryState,
      .telemetry(epoch: boundary.epoch, boundary.sample("5", "0"))
    )
    XCTAssertEqual(late.state.execution, .interrupted(.telemetryStreamTimedOut))
  }

  func testDirectPausePreservesSegmentAndPhysicalResumeRestoresBothTargets() throws {
    let h = Harness(stepDuration: 20)
    var state = try h.pausedState(activeSeconds: 3)
    guard case .paused(.telemetry) = state.execution else { return XCTFail("Expected pause") }
    XCTAssertEqual(state.currentSegment?.accumulatedActiveSeconds ?? -1, 3, accuracy: 0.0001)
    XCTAssertTrue(state.motionPossible)

    var t = h.accept(h.send(state, .telemetry(epoch: h.epoch, h.sample("0.5", "0"))))
    XCTAssertEqual(t.state.execution, .restoringTargets)
    XCTAssertEqual(t.record?.intent, .setTargetSpeed(Harness.speed("5")))
    t = try h.acknowledgeCurrent(t)
    XCTAssertEqual(t.record?.intent, .setTargetInclination(Harness.inclination("0")))
    t = try h.acknowledgeCurrent(t)
    XCTAssertNil(t.state.currentSegment?.activeStartedAt)
    t = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("5", "0"))))
    state = t.state
    XCTAssertEqual(state.execution, .runningSegment)
    XCTAssertEqual(state.currentSegment?.accumulatedActiveSeconds ?? -1, 3, accuracy: 0.0001)
  }

  func testPausedAdjustmentsArePendingAndRestoreLatestEffectiveTargets() throws {
    let h = Harness(stepDuration: 20)
    var state = try h.pausedState(activeSeconds: 3)
    var t = h.accept(h.send(state, .setSpeedOverride(epoch: h.epoch, Harness.speed("5.5"))))
    XCTAssertTrue(t.effects.isEmpty)
    t = h.accept(h.send(t.state, .setInclinationOverride(epoch: h.epoch, Harness.inclination("1"))))
    XCTAssertTrue(t.effects.isEmpty)
    t = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("0.5", "0"))))
    XCTAssertEqual(t.record?.intent, .setTargetSpeed(Harness.speed("5.5")))
    t = try h.acknowledgeCurrent(t)
    XCTAssertEqual(t.record?.intent, .setTargetInclination(Harness.inclination("1")))
    state = t.state
    XCTAssertEqual(state.currentSegment?.speedOverride, Harness.speed("5.5"))
    XCTAssertEqual(state.currentSegment?.inclinationOverride, Harness.inclination("1"))
  }

  func testCurrentSegmentOverridesAreIndependentAndInflightChangesDoNotCompete() throws {
    let h = Harness(stepDuration: 20)
    var t = h.accept(
      h.send(try h.runningState(), .setSpeedOverride(epoch: h.epoch, Harness.speed("5.5"))))
    let speedRecord = try XCTUnwrap(t.record)
    let frozen = t.state.currentSegment!.accumulatedActiveSeconds
    t = h.accept(h.send(t.state, .setInclinationOverride(epoch: h.epoch, Harness.inclination("1"))))
    XCTAssertTrue(t.effects.isEmpty)
    XCTAssertEqual(t.state.procedure.activeRecord?.id, speedRecord.id)
    t = try h.acknowledgeCurrent(t)
    XCTAssertEqual(t.record?.intent, .setTargetInclination(Harness.inclination("1")))
    t = try h.acknowledgeCurrent(t)
    t = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("5.5", "1"))))
    XCTAssertEqual(t.state.execution, .runningSegment)
    XCTAssertEqual(t.state.currentSegment?.accumulatedActiveSeconds ?? -1, frozen, accuracy: 0.0001)
  }

  func testReturnToPlanReappliesChangedAxis() throws {
    let h = Harness(stepDuration: 20)
    var t = h.accept(
      h.send(try h.runningState(), .setSpeedOverride(epoch: h.epoch, Harness.speed("5.5"))))
    t = try h.acknowledgeCurrent(t)
    t = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("5.5", "0"))))
    t = h.accept(h.send(t.state, .returnToPlan(epoch: h.epoch)))
    XCTAssertNil(t.state.currentSegment?.speedOverride)
    XCTAssertEqual(t.record?.intent, .setTargetSpeed(Harness.speed("5")))
  }

  func testSegmentBoundaryClearsOverridesAndNoChangeBoundaryEmitsNothing() throws {
    let h = Harness(stepDuration: 5)
    var t = h.accept(
      h.send(try h.runningState(), .setSpeedOverride(epoch: h.epoch, Harness.speed("5.5"))))
    t = try h.acknowledgeCurrent(t)
    t = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("5.5", "0"))))
    let started = t.state.currentSegment!.activeStartedAt!.seconds
    var state = h.accept(
      h.send(at: started + 4.5, t.state, .telemetry(epoch: h.epoch, h.sample("5.5", "0")))
    ).state
    t = h.accept(h.send(at: started + 5, state, .tick(epoch: h.epoch)))
    state = t.state
    XCTAssertEqual(state.currentSegment?.stepIndex, 1)
    XCTAssertNil(state.currentSegment?.speedOverride)
    XCTAssertNil(state.currentSegment?.inclinationOverride)
    XCTAssertEqual(t.record?.intent, .setTargetSpeed(Harness.speed("7")))

    let same = Harness(stepDuration: 5, repeatedTargets: true)
    var sameState = try same.runningState()
    let sameStarted = sameState.currentSegment!.activeStartedAt!.seconds
    sameState =
      same.accept(
        same.send(
          at: sameStarted + 4.5, sameState, .telemetry(epoch: same.epoch, same.sample("5", "0")))
      ).state
    let noChange = same.accept(same.send(at: sameStarted + 5, sameState, .tick(epoch: same.epoch)))
    XCTAssertEqual(noChange.state.execution, .runningSegment)
    XCTAssertEqual(noChange.state.currentSegment?.stepIndex, 1)
    XCTAssertTrue(noChange.effects.isEmpty)
  }

  func testAdjustmentsWhileCheckingStayPendingAndInvalidValuesAreRejected() throws {
    let h = Harness(stepDuration: 20)
    var state = try h.runningState()
    let sampleAt = state.lastEventTime.seconds
    state = h.accept(h.send(at: sampleAt + 3, state, .tick(epoch: h.epoch))).state
    let pending = h.accept(h.send(state, .setSpeedOverride(epoch: h.epoch, Harness.speed("5.5"))))
    XCTAssertTrue(pending.effects.isEmpty)
    guard case .checkingTreadmill = pending.state.execution else {
      return XCTFail("Expected checking")
    }

    let invalidHarness = Harness(stepDuration: 20)
    let invalidState = try invalidHarness.runningState()
    for event in [
      WorkoutExecutionEvent.setSpeedOverride(epoch: invalidHarness.epoch, Harness.speed("5.55")),
      .setSpeedOverride(epoch: invalidHarness.epoch, Harness.speed("10.1")),
      .setInclinationOverride(epoch: invalidHarness.epoch, Harness.inclination("1.5")),
      .setInclinationOverride(epoch: invalidHarness.epoch, Harness.inclination("7")),
    ] {
      let rejected = invalidHarness.send(invalidState, event)
      XCTAssertEqual(rejected.disposition, .rejected(.invalidAdjustment))
      XCTAssertEqual(rejected.state, invalidState)
    }
  }

  func testTargetFailuresAndDeadlinesInvalidateWithoutRetry() throws {
    let rejectedHarness = Harness()
    let initial = try rejectedHarness.initialSpeedTransition()
    let record = try XCTUnwrap(initial.record)
    let rejected = rejectedHarness.send(
      initial.state,
      .intentSubmissionRejected(
        epoch: rejectedHarness.epoch, procedureID: record.id, reason: "not delivered")
    )
    XCTAssertEqual(
      rejected.state.execution, .failed(.procedure(.submissionRejected("not delivered"))))
    XCTAssertEqual(rejected.effects, [.directUserToConsoleAndSafetyKey])
    XCTAssertFalse(rejected.effects.containsTargetSubmission)

    let negativeAcknowledgementHarness = Harness()
    var negativeAcknowledgement = try negativeAcknowledgementHarness.initialSpeedTransition()
    let negativeAcknowledgementRecord = try XCTUnwrap(negativeAcknowledgement.record)
    negativeAcknowledgement = negativeAcknowledgementHarness.accept(
      negativeAcknowledgementHarness.send(
        negativeAcknowledgement.state,
        .intentSubmitted(
          epoch: negativeAcknowledgementHarness.epoch,
          procedureID: negativeAcknowledgementRecord.id)
      )
    )
    negativeAcknowledgement = negativeAcknowledgementHarness.accept(
      negativeAcknowledgementHarness.send(
        negativeAcknowledgement.state,
        .attAccepted(
          epoch: negativeAcknowledgementHarness.epoch,
          procedureID: negativeAcknowledgementRecord.id)
      )
    )
    let negativelyAcknowledged = negativeAcknowledgementHarness.send(
      negativeAcknowledgement.state,
      .protocolRejected(
        epoch: negativeAcknowledgementHarness.epoch,
        procedureID: negativeAcknowledgementRecord.id,
        reason: "not permitted")
    )
    XCTAssertEqual(
      negativelyAcknowledged.state.execution,
      .failed(.procedure(.protocolRejected("not permitted")))
    )
    XCTAssertEqual(negativelyAcknowledged.effects, [.directUserToConsoleAndSafetyKey])
    XCTAssertFalse(negativelyAcknowledged.effects.containsTargetSubmission)

    let responseHarness = Harness()
    var response = try responseHarness.initialSpeedTransition()
    let responseRecord = try XCTUnwrap(response.record)
    response = responseHarness.accept(
      responseHarness.send(
        response.state,
        .intentSubmitted(epoch: responseHarness.epoch, procedureID: responseRecord.id))
    )
    response = responseHarness.accept(
      responseHarness.send(
        response.state, .attAccepted(epoch: responseHarness.epoch, procedureID: responseRecord.id))
    )
    guard case .attAccepted(_, let deadline) = response.state.procedure else {
      return XCTFail("Expected deadline")
    }
    let timedOut = responseHarness.send(
      at: deadline.seconds,
      response.state,
      .protocolAcknowledged(epoch: responseHarness.epoch, procedureID: responseRecord.id)
    )
    XCTAssertEqual(timedOut.state.execution, .failed(.procedure(.responseTimeout)))

    let observationHarness = Harness()
    var observation = try observationHarness.initialSpeedTransition()
    observation = try observationHarness.acknowledgeCurrent(observation)
    observation = try observationHarness.acknowledgeCurrent(observation)
    let observationDeadline = try XCTUnwrap(observation.state.targetSequence?.observationDeadline)
    let targetTimedOut = observationHarness.send(
      at: observationDeadline.seconds,
      observation.state,
      .telemetry(epoch: observationHarness.epoch, observationHarness.sample("5", "0"))
    )
    XCTAssertEqual(targetTimedOut.state.execution, .failed(.targetObservationTimeout))
  }

  func testMalformedIncompleteAndUnavailableTelemetryFailClosed() throws {
    let malformedHarness = Harness(stepDuration: 20)
    let malformed = malformedHarness.send(
      try malformedHarness.runningState(),
      .telemetry(epoch: malformedHarness.epoch, .malformed("short"))
    )
    XCTAssertEqual(malformed.state.execution, .failed(.malformedTelemetry("short")))

    let incompleteHarness = Harness(stepDuration: 20)
    let incomplete = incompleteHarness.send(
      try incompleteHarness.runningState(),
      .telemetry(
        epoch: incompleteHarness.epoch,
        .sample(speed: Harness.speed("5"), inclination: nil, totalDistanceMetres: nil)
      )
    )
    XCTAssertEqual(incomplete.state.execution, .failed(.incompleteTelemetry))

    let unavailableHarness = Harness(stepDuration: 20)
    let unavailable = unavailableHarness.send(
      try unavailableHarness.runningState(),
      .telemetry(epoch: unavailableHarness.epoch, .unavailable("subscription ended"))
    )
    XCTAssertEqual(
      unavailable.state.execution, .interrupted(.telemetryUnavailable("subscription ended")))
  }

  func testConnectionControlForegroundAndCapabilityChangesInterruptWithoutContinuation() throws {
    let makers: [(Harness) throws -> WorkoutExecutionTransition] = [
      { h in h.send(try h.runningState(), .connectionLost(epoch: h.epoch, reason: "link")) },
      { h in h.send(try h.runningState(), .controlPermissionLost(epoch: h.epoch, reason: "control"))
      },
      { h in h.send(try h.runningState(), .appBecameInactive(epoch: h.epoch, reason: "background"))
      },
      { h in
        h.send(
          try h.runningState(),
          .capabilityChanged(
            epoch: h.epoch,
            capability: h.capabilityReplacingFeatureEvidence(.mismatch)
          )
        )
      },
    ]
    for make in makers {
      let transition = try make(Harness(stepDuration: 20))
      guard case .interrupted = transition.state.execution else {
        return XCTFail("Expected interruption")
      }
      XCTAssertEqual(transition.effects, [.directUserToConsoleAndSafetyKey])
      XCTAssertFalse(transition.effects.containsTargetSubmission)
    }
  }

  func testHumanStationaryEvidencePausesAfterMissingZeroAndContradictionFails() throws {
    let h = Harness(stepDuration: 20)
    var state = try h.runningState()
    let sampleAt = state.lastEventTime.seconds
    state = h.accept(h.send(at: sampleAt + 3, state, .tick(epoch: h.epoch))).state
    let paused = h.accept(
      h.send(
        at: sampleAt + 4, state, .humanConfirmsStationary(epoch: h.epoch, note: "Console stopped"))
    )
    guard case .paused(.human) = paused.state.execution else {
      return XCTFail("Expected human pause")
    }

    let contradictionHarness = Harness(stepDuration: 20)
    let contradiction = contradictionHarness.send(
      try contradictionHarness.runningState(),
      .humanConfirmsStationary(epoch: contradictionHarness.epoch, note: "Stopped")
    )
    guard case .failed(.contradictoryEvidence) = contradiction.state.execution else {
      return XCTFail("Expected contradiction")
    }
  }

  func testEndFromPauseUsesOnlyLocalEndingEffect() throws {
    let h = Harness(stepDuration: 20)
    var t = h.accept(h.send(try h.pausedState(activeSeconds: 3), .userEndsWorkout(epoch: h.epoch)))
    guard case .ending = t.state.execution else { return XCTFail("Expected ending") }
    XCTAssertNotNil(t.finalization)
    XCTAssertFalse(t.effects.containsTargetSubmission)
    t = h.accept(h.send(t.state, .localEndingSucceeded(epoch: h.epoch)))
    guard case .finished(let context) = t.state.execution else {
      return XCTFail("Expected finished")
    }
    XCTAssertEqual(context.reason, .endedFromPause)
    XCTAssertFalse(t.state.motionPossible)
  }

  func testEndRequiresCurrentStationaryEvidenceAndMovementRevokesEligibility() throws {
    let pausedHarness = Harness(stepDuration: 20)
    var paused = try pausedHarness.pausedState(activeSeconds: 3)
    guard case .paused(.telemetry(let pausedSample)) = paused.execution else {
      return XCTFail("Expected telemetry pause")
    }
    paused =
      pausedHarness.accept(
        pausedHarness.send(
          at: pausedSample.receivedAt.seconds + 2.1,
          paused,
          .tick(epoch: pausedHarness.epoch)
        )
      ).state
    guard case .checkingTreadmill(let checking) = paused.execution,
      case .paused = checking.origin
    else { return XCTFail("Expected stale pause to enter checking") }
    XCTAssertEqual(
      pausedHarness.send(paused, .userEndsWorkout(epoch: pausedHarness.epoch)).disposition,
      .rejected(.endNotAvailable)
    )
    let resumed = pausedHarness.accept(
      pausedHarness.send(
        paused, .telemetry(epoch: pausedHarness.epoch, pausedHarness.sample("0.5", "0"))))
    XCTAssertEqual(resumed.state.execution, .restoringTargets)

    let completedHarness = Harness(stepDuration: 3)
    let ready = try completedHarness.readyToEndState()
    let moving = completedHarness.accept(
      completedHarness.send(
        ready, .telemetry(epoch: completedHarness.epoch, completedHarness.sample("0.5", "0"))))
    XCTAssertEqual(moving.state.execution, .awaitingPhysicalStopForCompletion)
    XCTAssertEqual(
      completedHarness.send(moving.state, .userEndsWorkout(epoch: completedHarness.epoch))
        .disposition,
      .rejected(.endNotAvailable)
    )

    let staleCompletedHarness = Harness(stepDuration: 3)
    var staleReady = try staleCompletedHarness.readyToEndState()
    guard case .readyToEnd(let staleContext) = staleReady.execution,
      case .telemetry(let staleSample) = staleContext.stationaryEvidence
    else { return XCTFail("Expected telemetry-backed End eligibility") }
    staleReady =
      staleCompletedHarness.accept(
        staleCompletedHarness.send(
          at: staleSample.receivedAt.seconds + 2.1,
          staleReady,
          .tick(epoch: staleCompletedHarness.epoch)
        )
      ).state
    guard case .checkingTreadmill(let staleChecking) = staleReady.execution else {
      return XCTFail("Expected stale End eligibility to enter checking")
    }
    XCTAssertEqual(staleChecking.origin, .awaitingPhysicalStopForCompletion)
    XCTAssertEqual(
      staleCompletedHarness.send(
        staleReady, .userEndsWorkout(epoch: staleCompletedHarness.epoch)
      ).disposition,
      .rejected(.endNotAvailable)
    )
  }

  func testNewerFreshStationaryTelemetryRefreshesReadyToEndAndEndingEvidence() throws {
    let readyHarness = Harness(stepDuration: 3)
    let ready = try readyHarness.readyToEndState()
    guard case .readyToEnd(let initialReadyContext) = ready.execution,
      case .telemetry(let initialReadySample) = initialReadyContext.stationaryEvidence
    else { return XCTFail("Expected telemetry-backed End eligibility") }
    let refreshedReady = readyHarness.accept(
      readyHarness.send(
        at: initialReadySample.receivedAt.seconds + 1,
        ready,
        .telemetry(epoch: readyHarness.epoch, readyHarness.sample("0", "0"))
      )
    )
    guard case .readyToEnd(let refreshedReadyContext) = refreshedReady.state.execution,
      case .telemetry(let refreshedReadySample) = refreshedReadyContext.stationaryEvidence
    else { return XCTFail("Expected refreshed End eligibility") }
    XCTAssertNotEqual(refreshedReadySample, initialReadySample)
    XCTAssertEqual(
      readyHarness.send(
        refreshedReady.state, .userEndsWorkout(epoch: readyHarness.epoch)
      ).disposition,
      .accepted
    )

    let endingHarness = Harness(stepDuration: 20)
    var ending = endingHarness.accept(
      endingHarness.send(
        try endingHarness.pausedState(activeSeconds: 3),
        .userEndsWorkout(epoch: endingHarness.epoch)
      )
    )
    guard case .ending(let initialEndingContext) = ending.state.execution,
      case .telemetry(let initialEndingSample) = initialEndingContext.stationaryEvidence
    else { return XCTFail("Expected telemetry-backed ending") }
    ending = endingHarness.accept(
      endingHarness.send(
        at: initialEndingSample.receivedAt.seconds + 1,
        ending.state,
        .telemetry(epoch: endingHarness.epoch, endingHarness.sample("0", "0"))
      )
    )
    guard case .ending(let refreshedEndingContext) = ending.state.execution,
      case .telemetry(let refreshedEndingSample) = refreshedEndingContext.stationaryEvidence
    else { return XCTFail("Expected refreshed ending evidence") }
    XCTAssertNotEqual(refreshedEndingSample, initialEndingSample)
    ending = endingHarness.accept(
      endingHarness.send(ending.state, .localEndingSucceeded(epoch: endingHarness.epoch))
    )
    guard case .finished = ending.state.execution else { return XCTFail("Expected finished") }
  }

  func testEndRejectsUnresolvedTargetProcedureAndEndingFailsClosedOnUncertainty() throws {
    for stage in 0...2 {
      let h = Harness()
      var t = try h.initialSpeedTransition()
      let record = try XCTUnwrap(t.record)
      if stage >= 1 {
        t = h.accept(h.send(t.state, .intentSubmitted(epoch: h.epoch, procedureID: record.id)))
      }
      if stage == 2 {
        t = h.accept(h.send(t.state, .attAccepted(epoch: h.epoch, procedureID: record.id)))
      }
      let paused = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("0", "0"))))
      let rejected = h.send(paused.state, .userEndsWorkout(epoch: h.epoch))
      XCTAssertEqual(rejected.disposition, .rejected(.procedureBusy))
      XCTAssertEqual(rejected.state, paused.state)
    }

    let movingHarness = Harness(stepDuration: 20)
    var moving = movingHarness.accept(
      movingHarness.send(
        try movingHarness.pausedState(activeSeconds: 3),
        .userEndsWorkout(epoch: movingHarness.epoch)))
    moving = movingHarness.send(
      moving.state,
      .telemetry(epoch: movingHarness.epoch, movingHarness.sample("0.5", "0"))
    )
    XCTAssertEqual(
      moving.state.execution,
      .failed(.contradictoryEvidence("Treadmill reported movement while ending"))
    )

    let staleHarness = Harness(stepDuration: 20)
    var stale = staleHarness.accept(
      staleHarness.send(
        try staleHarness.pausedState(activeSeconds: 3),
        .userEndsWorkout(epoch: staleHarness.epoch)))
    guard case .ending(let context) = stale.state.execution,
      case .telemetry(let sample) = context.stationaryEvidence
    else { return XCTFail("Expected telemetry-backed ending") }
    stale = staleHarness.send(
      at: sample.receivedAt.seconds + 2.1,
      stale.state,
      .localEndingSucceeded(epoch: staleHarness.epoch)
    )
    XCTAssertEqual(stale.state.execution, .interrupted(.stationaryEvidenceExpired))
    guard case .stale = stale.state.telemetry else { return XCTFail("Expected stale telemetry") }
    XCTAssertEqual(stale.effects, [.directUserToConsoleAndSafetyKey])
  }

  func testFinalCompletionWaitsForPhysicalStopAndNeverEmitsStop() throws {
    let h = Harness(stepDuration: 3)
    var state = try h.runningState()
    state = try h.advanceToNextSegment(state)
    state = try h.advanceToNextSegment(state)
    let started = state.currentSegment!.activeStartedAt!.seconds
    state =
      h.accept(
        h.send(at: started + 2.5, state, .telemetry(epoch: h.epoch, h.sample("4", "0")))
      ).state
    var t = h.accept(h.send(at: started + 3, state, .tick(epoch: h.epoch)))
    XCTAssertEqual(t.state.execution, .awaitingPhysicalStopForCompletion)
    XCTAssertTrue(t.effects.isEmpty)
    t = h.accept(h.send(t.state, .telemetry(epoch: h.epoch, h.sample("0", "0"))))
    guard case .readyToEnd = t.state.execution else { return XCTFail("Expected End gate") }
    t = h.accept(h.send(t.state, .userEndsWorkout(epoch: h.epoch)))
    XCTAssertNotNil(t.finalization)
    XCTAssertFalse(t.effects.containsTargetSubmission)
  }

  func testStopStartGapWithoutPauseEvidenceContinuesWithoutRestoration() throws {
    let h = Harness(stepDuration: 20)
    var state = try h.runningState()
    let sampleAt = state.lastEventTime.seconds
    state = h.accept(h.send(at: sampleAt + 3, state, .tick(epoch: h.epoch))).state
    let resumed = h.accept(
      h.send(at: sampleAt + 8, state, .telemetry(epoch: h.epoch, h.sample("0.5", "0")))
    )
    XCTAssertEqual(resumed.state.execution, .runningSegment)
    XCTAssertNil(resumed.state.targetSequence)
    XCTAssertTrue(resumed.effects.isEmpty)
  }

  func testEpochTimeAndTerminalGuardsPreventImplicitRecovery() throws {
    let h = Harness(epochValue: 3, stepDuration: 20)
    let state = try h.runningState()
    let stale = h.send(state, .tick(epoch: .init(rawValue: 2)))
    XCTAssertEqual(stale.disposition, .ignored(.staleEpoch))
    let future = h.send(state, .tick(epoch: .init(rawValue: 4)))
    XCTAssertEqual(future.disposition, .rejected(.wrongEpoch))
    let backward = h.send(at: state.lastEventTime.seconds - 0.1, state, .tick(epoch: h.epoch))
    XCTAssertEqual(backward.disposition, .rejected(.nonMonotonicTime))

    let interrupted = h.send(state, .controlPermissionLost(epoch: h.epoch, reason: "lost"))
    let late = h.send(interrupted.state, .telemetry(epoch: h.epoch, h.sample("5", "0")))
    XCTAssertEqual(late.state, interrupted.state)
    XCTAssertEqual(late.disposition, .ignored(.wrongState))
    XCTAssertEqual(
      h.send(interrupted.state, .userStartsConnection(h.epoch)).disposition, .rejected(.wrongEpoch))
    let next = ConnectionEpoch(rawValue: 4)
    let restarted = h.accept(h.send(interrupted.state, .userStartsConnection(next)))
    XCTAssertEqual(restarted.state.connection, .connecting(next))
    XCTAssertEqual(restarted.state.execution, .idle)
    XCTAssertTrue(restarted.effects.isEmpty)
  }

  func testWrongCorrelationAndDuplicateProcedureEvidenceFailClosed() throws {
    let correlationHarness = Harness()
    let current = try correlationHarness.initialSpeedTransition()
    let record = try XCTUnwrap(current.record)
    let wrongID = ProcedureID(epoch: correlationHarness.epoch, sequence: record.id.sequence + 1)
    let mismatched = correlationHarness.send(
      current.state,
      .intentSubmitted(epoch: correlationHarness.epoch, procedureID: wrongID)
    )
    XCTAssertEqual(
      mismatched.state.execution,
      .failed(.procedure(.correlationFailure(expected: record.id, received: wrongID)))
    )
    XCTAssertTrue(mismatched.state.motionPossible)
    XCTAssertEqual(mismatched.effects, [.directUserToConsoleAndSafetyKey])

    let duplicateHarness = Harness()
    var completed = duplicateHarness.accept(
      duplicateHarness.send(
        try duplicateHarness.preflightState(),
        .beginWorkout(epoch: duplicateHarness.epoch, readiness: duplicateHarness.readiness)))
    let completedRecord = try XCTUnwrap(completed.record)
    completed = try duplicateHarness.acknowledgeCurrent(completed)
    let duplicate = duplicateHarness.send(
      completed.state,
      .protocolAcknowledged(
        epoch: duplicateHarness.epoch,
        procedureID: completedRecord.id)
    )
    XCTAssertEqual(
      duplicate.state.execution,
      .failed(.procedure(.duplicateOrLate(completedRecord.id)))
    )
    XCTAssertFalse(duplicate.state.motionPossible)
    XCTAssertTrue(duplicate.effects.isEmpty)
  }
}

extension WorkoutExecutionReducerTests {
  fileprivate final class Harness {
    let reducer = WorkoutExecutionReducer()
    let epoch: ConnectionEpoch
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
    private(set) var now: TimeInterval = 10

    init(epochValue: UInt64 = 1, stepDuration: Int = 5, repeatedTargets: Bool = false) {
      epoch = .init(rawValue: epochValue)
      let capabilities = WorkoutPlanCapabilities(
        speed: .supported(
          .init(minimum: Self.speed("0.5"), maximum: Self.speed("20"), increment: Self.speed("0.1"))
        ),
        inclination: .supported(
          .init(
            minimum: Self.inclination("0"), maximum: Self.inclination("15"),
            increment: Self.inclination("1"))
        )
      )
      capability = .init(
        peripheralIdentity: "local-peripheral",
        equipmentIdentity: "operator-confirmed-fr30z",
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
        equipmentIdentity: capability.equipmentIdentity)
      let steps =
        repeatedTargets
        ? [
          Self.step(.warmUp, "Warm up", stepDuration, "5", "0"),
          Self.step(.interval, "Run", stepDuration, "5", "0"),
          Self.step(.coolDown, "Cool down", stepDuration, "5", "0"),
        ]
        : [
          Self.step(.warmUp, "Warm up", stepDuration, "5", "0"),
          Self.step(.interval, "Run", stepDuration, "7", "1"),
          Self.step(.coolDown, "Cool down", stepDuration, "4", "0"),
        ]
      let raw = WorkoutPlan(
        schemaVersion: WorkoutPlanSchema.currentVersion,
        suggestedName: "Synthetic",
        activity: .indoorRunning,
        steps: steps
      )
      plan = try! WorkoutPlanValidator.validate(raw, against: capabilities).get()
    }

    func send(
      at explicitTime: TimeInterval? = nil,
      _ state: WorkoutExecutionState,
      _ event: WorkoutExecutionEvent
    ) -> WorkoutExecutionTransition {
      if let explicitTime {
        now = explicitTime
      } else {
        now = max(now, state.lastEventTime.seconds) + 0.1
      }
      return reducer.reduce(state, event, at: .init(seconds: now))
    }

    func accept(
      _ transition: WorkoutExecutionTransition,
      file: StaticString = #filePath,
      line: UInt = #line
    ) -> WorkoutExecutionTransition {
      XCTAssertEqual(transition.disposition, .accepted, file: file, line: line)
      return transition
    }

    func connectingState() -> WorkoutExecutionState {
      accept(send(WorkoutExecutionState(), .userStartsConnection(epoch))).state
    }

    func preflightState() throws -> WorkoutExecutionState {
      var state = connectingState()
      state =
        accept(send(state, .connectionBecomesReady(epoch: epoch, capability: capability))).state
      return accept(send(state, .arm(plan: plan, ceilings: ceilings, profile: profile))).state
    }

    func waitingState() throws -> WorkoutExecutionState {
      var t = accept(send(try preflightState(), .beginWorkout(epoch: epoch, readiness: readiness)))
      t = try acknowledgeCurrent(t)
      return t.state
    }

    func initialSpeedTransition() throws -> WorkoutExecutionTransition {
      accept(send(try waitingState(), .telemetry(epoch: epoch, sample("0.5", "0"))))
    }

    func runningState() throws -> WorkoutExecutionState {
      var t = try initialSpeedTransition()
      t = try acknowledgeCurrent(t)
      t = try acknowledgeCurrent(t)
      return accept(send(t.state, .telemetry(epoch: epoch, sample("5", "0")))).state
    }

    func pausedState(activeSeconds: TimeInterval) throws -> WorkoutExecutionState {
      let state = try runningState()
      let started = state.currentSegment!.activeStartedAt!.seconds
      return accept(
        send(at: started + activeSeconds, state, .telemetry(epoch: epoch, sample("0", "0")))
      ).state
    }

    func readyToEndState() throws -> WorkoutExecutionState {
      var state = try runningState()
      state = try advanceToNextSegment(state)
      state = try advanceToNextSegment(state)
      let started = state.currentSegment!.activeStartedAt!.seconds
      let target = effectiveTarget(state)
      state =
        accept(
          send(
            at: started + TimeInterval(plan.plan.steps[2].duration.value) - 0.5,
            state,
            .telemetry(epoch: epoch, sample(target.speed, target.inclination))
          )
        ).state
      state =
        accept(
          send(
            at: started + TimeInterval(plan.plan.steps[2].duration.value),
            state,
            .tick(epoch: epoch)
          )
        ).state
      XCTAssertEqual(state.execution, .awaitingPhysicalStopForCompletion)
      return accept(send(state, .telemetry(epoch: epoch, sample("0", "0")))).state
    }

    func acknowledgeCurrent(_ initial: WorkoutExecutionTransition) throws
      -> WorkoutExecutionTransition
    {
      var t = initial
      let record = try XCTUnwrap(t.state.procedure.unresolvedRecord)
      if case .intentCreated = t.state.procedure {
        t = accept(send(t.state, .intentSubmitted(epoch: epoch, procedureID: record.id)))
      }
      t = accept(send(t.state, .attAccepted(epoch: epoch, procedureID: record.id)))
      return accept(send(t.state, .protocolAcknowledged(epoch: epoch, procedureID: record.id)))
    }

    func advanceToNextSegment(_ original: WorkoutExecutionState) throws -> WorkoutExecutionState {
      var state = original
      let segment = try XCTUnwrap(state.currentSegment)
      let started = try XCTUnwrap(segment.activeStartedAt).seconds
      let duration = TimeInterval(plan.plan.steps[segment.stepIndex].duration.value)
      let target = effectiveTarget(state)
      state =
        accept(
          send(
            at: started + duration - 0.5,
            state,
            .telemetry(epoch: epoch, sample(target.speed, target.inclination))
          )
        ).state
      var t = accept(send(at: started + duration, state, .tick(epoch: epoch)))
      while t.record != nil { t = try acknowledgeCurrent(t) }
      if case .runningSegment = t.state.execution { return t.state }
      let next = effectiveTarget(t.state)
      return accept(send(t.state, .telemetry(epoch: epoch, sample(next.speed, next.inclination))))
        .state
    }

    func sample(_ speed: String, _ inclination: String) -> WorkoutTelemetryInput {
      sample(Self.speed(speed), Self.inclination(inclination))
    }

    func sample(_ speed: WorkoutSpeed, _ inclination: WorkoutInclination) -> WorkoutTelemetryInput {
      .sample(speed: speed, inclination: inclination, totalDistanceMetres: nil)
    }

    func effectiveTarget(_ state: WorkoutExecutionState) -> WorkoutTarget {
      let segment = state.currentSegment!
      let step = plan.plan.steps[segment.stepIndex]
      return .init(
        speed: segment.speedOverride ?? step.targetSpeed,
        inclination: segment.inclinationOverride ?? step.targetInclination
      )
    }

    func capabilityReplacingFeatureEvidence(
      _ evidence: FR30zProfileEvidence
    ) -> FR30zCapabilitySnapshot {
      .init(
        peripheralIdentity: capability.peripheralIdentity,
        equipmentIdentity: capability.equipmentIdentity,
        fitnessMachineServicePresent: capability.fitnessMachineServicePresent,
        requiredCharacteristicPropertiesMatch: capability.requiredCharacteristicPropertiesMatch,
        fitnessMachineFeatureEvidence: evidence,
        supportedSpeedRangeEvidence: capability.supportedSpeedRangeEvidence,
        supportedInclinationRangeEvidence: capability.supportedInclinationRangeEvidence,
        treadmillDataNotificationsEnabled: capability.treadmillDataNotificationsEnabled,
        controlPointIndicationsEnabled: capability.controlPointIndicationsEnabled,
        optionalSubscriptionOutcomesResolved: capability.optionalSubscriptionOutcomesResolved,
        planCapabilities: capability.planCapabilities
      )
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

extension WorkoutExecutionTransition {
  fileprivate var record: WorkoutProcedureRecord? {
    effects.compactMap {
      guard case .submit(let record) = $0 else { return nil }
      return record
    }.first
  }

  fileprivate var finalization: WorkoutCompletionContext? {
    effects.compactMap {
      guard case .finalizeLocally(let context) = $0 else { return nil }
      return context
    }.first
  }
}

extension Array where Element == WorkoutExecutionEffect {
  fileprivate var containsTargetSubmission: Bool {
    contains {
      guard case .submit(let record) = $0 else { return false }
      switch record.intent {
      case .setTargetSpeed, .setTargetInclination: return true
      case .requestControl: return false
      }
    }
  }
}
