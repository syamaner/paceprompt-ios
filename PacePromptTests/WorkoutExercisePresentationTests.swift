import XCTest

@testable import PacePrompt

final class WorkoutExercisePresentationTests: XCTestCase {
  private let now = MonotonicInstant(seconds: 100)
  private let locale = Locale(identifier: "en_GB")

  func testRequiredSyntheticScenariosRemainDistinct() {
    let expected: [(WorkoutExerciseUITestScenario, WorkoutExerciseStage, String)] = [
      (.waiting, .waiting, "Press Start on the treadmill"),
      (.applying, .applying, "Applying targets"),
      (.running, .running, "Running"),
      (.override, .override, "Manual override"),
      (.checking, .checking, "Checking treadmill"),
      (
        .paused,
        .paused,
        "Workout paused — press Start on the treadmill to resume"
      ),
      (.restoring, .restoring, "Restoring targets"),
      (.ending, .ending, "Ending workout"),
      (.failed, .failed, "Workout failed"),
      (.interrupted, .interrupted, "Workout interrupted"),
    ]

    for (scenario, stage, title) in expected {
      let presentation = makePresentation(scenario)
      XCTAssertEqual(presentation.stage, stage, scenario.rawValue)
      XCTAssertEqual(presentation.status.title, title, scenario.rawValue)
    }
  }

  func testProgressSnapshotKeepsIntervalCountdownNextElapsedAndDistanceSeparate() {
    let presentation = makePresentation(.running)

    XCTAssertEqual(presentation.planName, "Synthetic Pyramid")
    XCTAssertEqual(presentation.currentInterval, "Segment 2 of 3 - Run")
    XCTAssertEqual(presentation.countdown, "2:29")
    XCTAssertEqual(presentation.overallProgressLabel, "36 percent complete")
    XCTAssertEqual(presentation.nextInterval, "Next: Cool down, 2:00 at 5.0 km/h, 0.0 %")
    XCTAssertEqual(presentation.elapsedActiveTime, "2:31")
    XCTAssertEqual(presentation.distance, "1.26 km")
    XCTAssertEqual(presentation.distanceDetail, "Treadmill reported")
  }

  func testUnavailableDistanceIsNeverInvented() {
    var context = WorkoutExerciseFixtures.context(for: .running)
    var state = context.state
    state.telemetry = .fresh(
      .init(
        speed: .init(value: 7, unit: .kilometresPerHour),
        inclination: .init(value: 2, unit: .percent),
        totalDistanceMetres: nil,
        receivedAt: .init(seconds: 99.5)
      )
    )
    context = .init(state: state, frozenAttempt: context.frozenAttempt, latestSummary: nil)

    let presentation = makePresentation(context)

    XCTAssertEqual(presentation.distance, "Unavailable")
    XCTAssertEqual(
      presentation.distanceDetail,
      "No trustworthy treadmill distance is available"
    )
  }

  func testStaleDistanceRemainsExplicitlyLastReported() {
    let presentation = makePresentation(.checking)

    XCTAssertEqual(presentation.distance, "1.26 km")
    XCTAssertEqual(presentation.distanceDetail, "Last reported; telemetry is stale")
    XCTAssertTrue(presentation.status.detail.contains("does not mean the treadmill stopped"))
  }

  func testPlannedEffectiveActualAndOverrideRemainSeparate() {
    let presentation = makePresentation(.override)

    XCTAssertEqual(presentation.speed.planned, "7.0 km/h")
    XCTAssertEqual(presentation.speed.effective, "7.1 km/h")
    XCTAssertEqual(presentation.speed.actual, "7.1 km/h")
    XCTAssertTrue(presentation.speed.isOverridden)
    XCTAssertFalse(presentation.inclination.isOverridden)
    XCTAssertEqual(presentation.overrideLabel, "Current-segment speed override")
    XCTAssertTrue(presentation.canReturnToPlan)
  }

  func testMachineIncrementAndSessionCeilingProduceExactTypedAdjustmentTargets() {
    let presentation = makePresentation(.running)

    XCTAssertEqual(presentation.speed.decrementTarget, Decimal(69) / 10)
    XCTAssertEqual(presentation.speed.incrementTarget, Decimal(71) / 10)
    XCTAssertEqual(presentation.speed.decrementLabel, "Decrease by 0.1 km/h")
    XCTAssertEqual(presentation.inclination.decrementTarget, Decimal(15) / 10)
    XCTAssertEqual(presentation.inclination.incrementTarget, Decimal(25) / 10)
    XCTAssertEqual(presentation.inclination.incrementLabel, "Increase by 0.5 %")
  }

  func testControlsDisableOutsideAdjustmentPhases() {
    let presentation = makePresentation(.ending)

    XCTAssertNil(presentation.speed.decrementTarget)
    XCTAssertNil(presentation.speed.incrementTarget)
    XCTAssertNil(presentation.inclination.decrementTarget)
    XCTAssertNil(presentation.inclination.incrementTarget)
    XCTAssertFalse(presentation.canReturnToPlan)
  }

  func testAllEvidenceStagesAreProjectedWithoutCollapsingTheProcedureLifecycle() {
    XCTAssertEqual(evidence(.requested), .requested)
    XCTAssertEqual(evidence(.submitted), .submitted)
    XCTAssertEqual(evidence(.attAccepted), .attAccepted)
    XCTAssertEqual(evidence(.ftmsAcknowledged), .ftmsAcknowledged)
    XCTAssertEqual(evidence(.observing), .observing)
    XCTAssertEqual(evidence(.confirmed), .confirmed)
    XCTAssertEqual(evidence(.stale), .stale)
    XCTAssertEqual(evidence(.failed), .failed)
    XCTAssertEqual(evidence(.unknown), .unknown)
    XCTAssertEqual(Set(WorkoutExerciseEvidenceStage.allCases.map(\.label)).count, 9)
  }

  func testConfirmationRequiresLaterFreshJointExactObservation() {
    var preAcknowledgement = WorkoutExerciseFixtures.context(for: .applying)
    var preAcknowledgementState = preAcknowledgement.state
    preAcknowledgementState.procedure = .idle
    preAcknowledgementState.targetSequence?.acknowledgedInclination = .init(
      value: 2,
      unit: .percent
    )
    preAcknowledgementState.targetSequence?.finalAcknowledgementAt = .init(seconds: 99.75)
    preAcknowledgementState.targetSequence?.observationDeadline = .init(seconds: 129.75)
    preAcknowledgementState.telemetry = .fresh(
      WorkoutExerciseFixtures.sample(speed: 7, inclination: 2, at: 99.5)
    )
    preAcknowledgement = .init(
      state: preAcknowledgementState,
      frozenAttempt: preAcknowledgement.frozenAttempt,
      latestSummary: nil
    )

    let awaitingLaterObservation = makePresentation(preAcknowledgement)
    XCTAssertEqual(awaitingLaterObservation.speed.evidence, .observing)
    XCTAssertEqual(awaitingLaterObservation.inclination.evidence, .observing)

    var oneAxisOnly = WorkoutExerciseFixtures.context(for: .running)
    var oneAxisOnlyState = oneAxisOnly.state
    oneAxisOnlyState.telemetry = .fresh(
      WorkoutExerciseFixtures.sample(speed: 7, inclination: Decimal(15) / 10, at: 99.5)
    )
    oneAxisOnly = .init(
      state: oneAxisOnlyState,
      frozenAttempt: oneAxisOnly.frozenAttempt,
      latestSummary: nil
    )

    let mismatchedJointObservation = makePresentation(oneAxisOnly)
    XCTAssertEqual(mismatchedJointObservation.speed.evidence, .unknown)
    XCTAssertEqual(mismatchedJointObservation.inclination.evidence, .unknown)
  }

  func testResumeRestorationNamesEffectiveTargetsAndSequentialOrder() {
    let presentation = makePresentation(.restoring)

    XCTAssertEqual(
      presentation.restorationDetail,
      "Restoring effective speed 7.0 km/h, then inclination 2.0 %."
    )
    XCTAssertTrue(presentation.status.detail.contains("Speed is restored before inclination"))
  }

  func testEndWorkoutRequiresCurrentStationaryEvidenceAndNeverAppearsForChecking() {
    XCTAssertTrue(makePresentation(.paused).canEndWorkout)
    XCTAssertFalse(makePresentation(.checking).canEndWorkout)
    XCTAssertFalse(makePresentation(.running).canEndWorkout)
    XCTAssertFalse(makePresentation(.ending).canEndWorkout)
  }

  func testOperatorFallbackIsSeparateAndUnavailableWithoutPossibleMotion() {
    XCTAssertFalse(makePresentation(.running).canConfirmOperatorStationary)
    XCTAssertTrue(makePresentation(.checking).canConfirmOperatorStationary)
    XCTAssertFalse(makePresentation(.waiting).canConfirmOperatorStationary)
    XCTAssertFalse(makePresentation(.failed).canConfirmOperatorStationary)
  }

  func testNavigationCanDismissOnlyAfterTerminalOutcome() {
    XCTAssertFalse(makePresentation(.waiting).allowsDismissal)
    XCTAssertFalse(makePresentation(.running).allowsDismissal)
    XCTAssertFalse(makePresentation(.checking).allowsDismissal)
    XCTAssertFalse(makePresentation(.paused).allowsDismissal)
    XCTAssertFalse(makePresentation(.ending).allowsDismissal)
    XCTAssertFalse(makePresentation(.failed).allowsDismissal)
    XCTAssertFalse(makePresentation(.interrupted).allowsDismissal)

    var safeFailure = WorkoutExerciseFixtures.context(for: .failed)
    var safeFailureState = safeFailure.state
    safeFailureState.motionPossible = false
    safeFailure = .init(
      state: safeFailureState,
      frozenAttempt: safeFailure.frozenAttempt,
      latestSummary: nil
    )
    XCTAssertTrue(makePresentation(safeFailure).allowsDismissal)
  }

  func testCompletedFinalSegmentIsNotCountedTwiceAcrossCompletionPhases() {
    var context = WorkoutExerciseFixtures.context(for: .running)
    var state = context.state
    let stationary = WorkoutExerciseFixtures.sample(speed: 0, inclination: 0, at: 99.5)
    let completion = WorkoutCompletionContext(
      reason: .completedPlan,
      stepIndex: 2,
      totalActiveSeconds: 420,
      stationaryEvidence: .telemetry(stationary)
    )
    state.currentSegment = .init(
      stepIndex: 2,
      accumulatedActiveSeconds: 120,
      activeStartedAt: nil,
      speedOverride: nil,
      inclinationOverride: nil
    )
    state.completedActiveSeconds = 420

    let phases: [WorkoutExecutionPhase] = [
      .awaitingPhysicalStopForCompletion,
      .checkingTreadmill(
        .init(
          origin: .awaitingPhysicalStopForCompletion,
          freshnessBoundary: .init(seconds: 100),
          interruptionDeadline: .init(seconds: 130)
        )
      ),
      .readyToEnd(completion),
      .ending(completion),
      .finished(completion),
    ]
    for phase in phases {
      state.execution = phase
      context = .init(
        state: state,
        frozenAttempt: context.frozenAttempt,
        latestSummary: nil
      )
      XCTAssertEqual(makePresentation(context).elapsedActiveTime, "7:00")
    }
    XCTAssertTrue(makePresentation(context).allowsDismissal)
  }

  func testPausedSegmentAtItsDurationStillContributesToElapsedTotal() {
    var context = WorkoutExerciseFixtures.context(for: .paused)
    var state = context.state
    state.currentSegment = .init(
      stepIndex: 2,
      accumulatedActiveSeconds: 120,
      activeStartedAt: nil,
      speedOverride: nil,
      inclinationOverride: nil
    )
    state.completedActiveSeconds = 300
    context = .init(
      state: state,
      frozenAttempt: context.frozenAttempt,
      latestSummary: nil
    )

    XCTAssertEqual(makePresentation(context).elapsedActiveTime, "7:00")
  }

  func testFullPlanSnapshotMarksOnlyTheCurrentSegment() {
    let presentation = makePresentation(.running)

    XCTAssertEqual(presentation.plan.map(\.label), ["Warm up", "Run", "Cool down"])
    XCTAssertEqual(presentation.plan.map(\.isCurrent), [false, true, false])
    XCTAssertEqual(presentation.plan[1].duration, "3:00")
    XCTAssertEqual(presentation.plan[1].speed, "7.0 km/h")
    XCTAssertEqual(presentation.plan[1].inclination, "2.0 %")
  }

  private func makePresentation(
    _ scenario: WorkoutExerciseUITestScenario
  ) -> WorkoutExercisePresentation {
    makePresentation(WorkoutExerciseFixtures.context(for: scenario))
  }

  private func makePresentation(
    _ context: WorkoutExerciseContext
  ) -> WorkoutExercisePresentation {
    .init(context: context, at: now, locale: locale)
  }

  private enum EvidenceFixture: Equatable {
    case requested
    case submitted
    case attAccepted
    case ftmsAcknowledged
    case observing
    case confirmed
    case stale
    case failed
    case unknown
  }

  private func evidence(_ fixture: EvidenceFixture) -> WorkoutExerciseEvidenceStage {
    var context = WorkoutExerciseFixtures.context(for: .applying)
    var state = context.state
    let record = WorkoutProcedureRecord(
      id: .init(epoch: .init(rawValue: 1), sequence: 99),
      intent: .setTargetSpeed(.init(value: 7, unit: .kilometresPerHour)),
      stepIndex: 1,
      createdAt: .init(seconds: 95),
      submittedAt: fixture == .requested ? nil : .init(seconds: 96),
      attAcceptedAt: nil,
      ftmsAcknowledgedAt: nil
    )
    state.execution = .applyingTargets(.initial)
    state.procedure = .idle
    state.targetSequence = .init(
      purpose: .initial,
      stepIndex: 1,
      startedAt: .init(seconds: 95),
      forceSpeed: true,
      forceInclination: true,
      acknowledgedSpeed: nil,
      acknowledgedInclination: nil,
      finalAcknowledgementAt: nil,
      observationDeadline: nil
    )

    switch fixture {
    case .requested:
      state.procedure = .intentCreated(record)
    case .submitted:
      state.procedure = .submitted(record)
    case .attAccepted:
      state.procedure = .attAccepted(
        record: record,
        deadline: .init(seconds: 125)
      )
    case .ftmsAcknowledged:
      state.targetSequence?.acknowledgedSpeed = .init(
        value: 7,
        unit: .kilometresPerHour
      )
    case .observing:
      state.targetSequence?.acknowledgedSpeed = .init(
        value: 7,
        unit: .kilometresPerHour
      )
      state.targetSequence?.acknowledgedInclination = .init(
        value: 2,
        unit: .percent
      )
      state.targetSequence?.finalAcknowledgementAt = .init(seconds: 98)
      state.targetSequence?.observationDeadline = .init(seconds: 128)
      state.telemetry = .fresh(WorkoutExerciseFixtures.sample(speed: 6, inclination: 2, at: 99.5))
    case .confirmed:
      state.execution = .runningSegment
      state.targetSequence = nil
    case .stale:
      state.telemetry = .stale(
        WorkoutExerciseFixtures.sample(speed: 7, inclination: 2, at: 90)
      )
    case .failed:
      state.procedure = .failed(record: record, failure: .protocolRejected("synthetic"))
    case .unknown:
      state.telemetry = .unavailable("synthetic unavailable")
    }

    context = .init(
      state: state,
      frozenAttempt: context.frozenAttempt,
      latestSummary: context.latestSummary
    )
    return makePresentation(context).speed.evidence
  }
}
