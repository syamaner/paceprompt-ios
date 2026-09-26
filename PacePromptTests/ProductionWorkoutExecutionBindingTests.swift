import Foundation
import XCTest

@testable import PacePrompt

@MainActor
final class ProductionWorkoutExecutionBindingTests: XCTestCase {
  func testExactProductionProfileEnablesControlReadinessWithoutProofAuthority() {
    let h = Harness()
    h.publishExactProfile()

    XCTAssertEqual(h.link.enableIndicationsCount, 1)
    XCTAssertFalse(h.binding.canExposeArming)
    XCTAssertTrue(h.link.writes.isEmpty)
    h.link.send(.indicationsEnabled)
    XCTAssertTrue(h.binding.canExposeArming)
    XCTAssertNotNil(h.binding.currentCapability)
  }

  func testExplicitlySelectedConnectionIdentityBecomesTheAttemptProfileIdentity() {
    let h = Harness()
    let selectedID = UUID(
      uuidString: "00000000-0000-0000-0000-000000000999"
    )!
    h.client.connectedPeripheralIdentifier = selectedID
    h.publishExactProfile()
    h.link.send(.indicationsEnabled)

    XCTAssertTrue(h.binding.canExposeArming)
    XCTAssertEqual(h.binding.executionProfile?.peripheralIdentity, selectedID.uuidString.lowercased())
    XCTAssertEqual(h.link.enableIndicationsCount, 1)
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testMismatchedCapabilityBytesOrControlPointPropertiesRemainPassive() {
    let bytes = Harness()
    bytes.publishExactProfile(
      featureData: Data([0x0C, 0x16, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
    )
    XCTAssertEqual(bytes.link.enableIndicationsCount, 0)
    XCTAssertFalse(bytes.binding.canExposeArming)

    let properties = Harness()
    let withoutIndicate = Harness.characteristics.map { info in
      info.uuid == FTMSUUID.fitnessMachineControlPoint
        ? .init(uuid: info.uuid, properties: ["Write"])
        : info
    }
    properties.publishExactProfile(characteristics: withoutIndicate)
    XCTAssertEqual(properties.link.enableIndicationsCount, 0)
    XCTAssertFalse(properties.binding.canExposeArming)
  }

  func testChangedConnectedIdentityInvalidatesTheEstablishedControlLink() {
    let h = Harness()
    h.makeReadyWithFreshStationaryTelemetry()

    h.client.connectedPeripheralName = "Different synthetic treadmill"
    h.binding.tick()

    XCTAssertFalse(h.binding.canExposeArming)
    XCTAssertNil(h.binding.currentCapability)
    XCTAssertEqual(h.link.invalidateCount, 1)
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testExactCurrentProfileRequiresControlIndicationButNotAStationaryPacket() {
    let h = Harness()
    h.publishExactProfile()

    XCTAssertEqual(h.link.enableIndicationsCount, 1)
    XCTAssertFalse(h.binding.canExposeArming)
    h.link.send(.indicationsEnabled)
    XCTAssertTrue(h.binding.canExposeArming)

    h.binding.receive(
      .value(
        uuid: FTMSUUID.treadmillData,
        data: Data([0x09, 0x00, 0x00, 0x00, 0x00, 0x00]),
        source: .notification
      )
    )
    XCTAssertTrue(h.binding.canExposeArming)

    h.publishTelemetry(speedRaw: 0)
    XCTAssertTrue(h.binding.canExposeArming)
    XCTAssertEqual(h.binding.currentCapability?.fitnessMachineFeatureEvidence, .matched)

    h.clock.advance(by: 2.001)
    XCTAssertTrue(h.binding.canExposeArming)
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testEndToEndPhysicalStartThenRequestControlSequencesOnlySpeedAndInclination() throws {
    let h = Harness()
    h.makeReadyWithFreshStationaryTelemetry()
    XCTAssertNotNil(h.binding.arm(plan: h.plan, ceilings: h.ceilings, sourcePlanID: nil))

    XCTAssertNotNil(h.binding.beginWorkout())
    XCTAssertTrue(h.link.writes.isEmpty)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .waitingForPhysicalStart)

    h.publishTelemetry(speedRaw: 0)
    XCTAssertTrue(h.link.writes.isEmpty, "Accepted zero speed is not Start evidence")
    h.publishTelemetry(speedRaw: 50)
    XCTAssertEqual(h.link.writes, [Data([0x00])])
    guard case .submitted = h.binding.orchestrator.state.procedure else {
      return XCTFail("Intent and submission must remain separate from ATT acceptance")
    }

    h.link.send(.writeAccepted)
    guard case .attAccepted = h.binding.orchestrator.state.procedure else {
      return XCTFail("ATT acceptance must remain separate from the FTMS result")
    }
    h.link.send(.indication(Data([0x80, 0x00, 0x01])))
    XCTAssertEqual(h.link.writes.last, Data([0x02, 0xF4, 0x01]))
    XCTAssertEqual(h.link.writes.map(\.first), [0x00, 0x02])

    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x02, 0x01])))
    XCTAssertEqual(h.link.writes.last, Data([0x03, 0x00, 0x00]))
    XCTAssertEqual(h.link.writes.map(\.first), [0x00, 0x02, 0x03])

    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x03, 0x01])))
    guard case .applyingTargets(.initial) = h.binding.orchestrator.state.execution else {
      return XCTFail("Acknowledged targets still require later matching telemetry")
    }
    h.clock.advance(by: 0.001)
    h.publishTelemetry(speedRaw: 500)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .runningSegment)
  }

  func testPhysicalStartRampBelowMinimumTargetPermitsRequestControl() throws {
    let h = Harness()
    h.makeReadyWithFreshStationaryTelemetry()
    XCTAssertNotNil(h.binding.arm(plan: h.plan, ceilings: h.ceilings, sourcePlanID: nil))
    XCTAssertNotNil(h.binding.beginWorkout())

    h.publishTelemetry(speedRaw: 10)

    XCTAssertEqual(h.binding.orchestrator.state.execution, .acquiringControl)
    XCTAssertEqual(h.link.writes, [Data([0x00])])
  }

  func testProtocolScaledTelemetryCanonicalizesFloatingTailBeforeTargetObservation() throws {
    let h = Harness()
    h.reachRunning()
    let epoch = try XCTUnwrap(h.binding.epoch)

    let adjustment = try XCTUnwrap(
      h.binding.handle(
        .setSpeedOverride(
          epoch: epoch,
          .init(value: Decimal(7) / 10, unit: .kilometresPerHour)
        )
      )
    )
    XCTAssertEqual(adjustment.reducerDisposition, .accepted)
    XCTAssertEqual(h.link.writes.last, Data([0x02, 0x46, 0x00]))
    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x02, 0x01])))

    h.clock.advance(by: 0.001)
    h.publishTelemetry(speedRaw: 70)

    XCTAssertEqual(h.binding.orchestrator.state.execution, .runningSegment)
    guard case .fresh(let sample) = h.binding.orchestrator.state.telemetry else {
      return XCTFail("Expected canonical fresh telemetry")
    }
    XCTAssertEqual(sample.speed.value, Decimal(7) / 10)
  }

  func testInactiveBackgroundAndScreenLockLifecyclePreserveSameAttemptAndLink() throws {
    let h = Harness()
    h.makeReadyWithFreshStationaryTelemetry()
    XCTAssertNotNil(h.binding.arm(plan: h.plan, ceilings: h.ceilings, sourcePlanID: nil))
    _ = h.binding.beginWorkout()
    let attemptID = h.binding.orchestrator.frozenAttempt?.attemptID
    XCTAssertTrue(h.link.writes.isEmpty)

    h.binding.setApplicationActivity(.inactive)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .waitingForPhysicalStart)
    h.binding.setApplicationActivity(.background)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .waitingForPhysicalStart)
    XCTAssertEqual(h.link.invalidateCount, 0)
    XCTAssertTrue(h.link.writes.isEmpty)

    h.binding.setApplicationActivity(.active)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .waitingForPhysicalStart)
    XCTAssertEqual(h.binding.orchestrator.frozenAttempt?.attemptID, attemptID)
    XCTAssertEqual(h.link.enableIndicationsCount, 1, "Lifecycle changes must not recreate the link")
    XCTAssertTrue(h.link.writes.isEmpty)

    h.binding.setProtectedDataAvailable(false)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .waitingForPhysicalStart)
    h.binding.setProtectedDataAvailable(true)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .waitingForPhysicalStart)
    XCTAssertEqual(h.binding.orchestrator.frozenAttempt?.attemptID, attemptID)
    XCTAssertEqual(h.link.invalidateCount, 0)
  }

  func testFreshBackgroundTelemetryContinuesOneAttemptWithoutInteractiveControl() {
    let h = Harness()
    h.reachRunning()
    let attemptID = h.binding.orchestrator.frozenAttempt?.attemptID
    let writeCount = h.link.writes.count

    h.binding.setApplicationActivity(.background)
    h.clock.advance(by: 1)
    h.publishTelemetry(speedRaw: 500)

    XCTAssertEqual(h.binding.orchestrator.state.execution, .runningSegment)
    XCTAssertEqual(h.binding.orchestrator.frozenAttempt?.attemptID, attemptID)
    XCTAssertEqual(h.binding.orchestrator.state.currentSegment?.accumulatedActiveSeconds, 1)
    XCTAssertEqual(h.link.writes.count, writeCount)
    XCTAssertFalse(h.binding.canExposeArming)

    h.binding.setApplicationActivity(.active)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .runningSegment)
  }

  func testBackgroundBoundaryUsesFreshTelemetryForOnePlannedWriteAtATime() {
    let h = Harness()
    h.reachRunning()
    h.binding.setApplicationActivity(.background)
    let initialWriteCount = h.link.writes.count

    for _ in 1...60 {
      h.clock.advance(by: 1)
      h.publishTelemetry(speedRaw: 500)
    }

    XCTAssertEqual(h.binding.orchestrator.state.currentSegment?.stepIndex, 1)
    XCTAssertEqual(h.link.writes.count, initialWriteCount + 1)
    XCTAssertEqual(h.link.writes.last?.first, 0x02)

    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x02, 0x01])))
    XCTAssertEqual(
      h.link.writes.count,
      initialWriteCount + 1,
      "An acknowledgement wake must not submit the next planned axis"
    )

    h.clock.advance(by: 0.5)
    h.publishTelemetry(speedRaw: 500)
    XCTAssertEqual(h.link.writes.count, initialWriteCount + 2)
    XCTAssertEqual(h.link.writes.last?.first, 0x03)
  }

  func testStaleBackgroundGapFreezesProgressAndForegroundReconcilesToChecking() {
    let h = Harness()
    h.reachRunning()
    let writeCount = h.link.writes.count

    h.binding.setApplicationActivity(.background)
    h.clock.advance(by: 5)
    h.binding.setApplicationActivity(.active)

    guard case .checkingTreadmill = h.binding.orchestrator.state.execution else {
      return XCTFail("Foreground return with stale telemetry must reconcile to Checking treadmill")
    }
    XCTAssertEqual(h.binding.orchestrator.state.currentSegment?.accumulatedActiveSeconds, 2)
    XCTAssertEqual(h.link.writes.count, writeCount)

    h.publishTelemetry(speedRaw: 500)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .runningSegment)
    XCTAssertEqual(h.binding.orchestrator.state.currentSegment?.accumulatedActiveSeconds, 2)
    XCTAssertEqual(h.link.writes.count, writeCount)
  }

  func testEpochReplacementWhileBackgroundedEndsAttemptWithoutAutomaticRecovery() {
    let h = Harness()
    h.reachRunning()
    let oldEpoch = h.binding.epoch
    let writeCount = h.link.writes.count
    h.binding.setApplicationActivity(.background)

    h.binding.receive(.connection(.connecting(name: Harness.equipment)))

    XCTAssertNotEqual(h.binding.epoch, oldEpoch)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .idle)
    XCTAssertNil(h.binding.orchestrator.frozenAttempt)
    XCTAssertNil(h.lifecycleCheckpoints.checkpoint)
    XCTAssertEqual(h.link.writes.count, writeCount)
    XCTAssertFalse(h.binding.canExposeArming)
  }

  func testExplicitReconnectCanPrepareAnotherSequence() {
    let h = Harness()
    h.makeReadyWithFreshStationaryTelemetry()
    XCTAssertNotNil(h.binding.arm(plan: h.plan, ceilings: h.ceilings, sourcePlanID: nil))

    h.binding.receive(.connection(.disconnected(message: "Synthetic explicit disconnect")))
    guard case .interrupted = h.binding.orchestrator.state.execution else {
      return XCTFail("The first sequence must terminate before another connection")
    }

    h.makeReadyWithFreshStationaryTelemetry()

    XCTAssertTrue(h.binding.canExposeArming)
    XCTAssertNotNil(h.binding.arm(plan: h.plan, ceilings: h.ceilings, sourcePlanID: nil))
    XCTAssertEqual(h.binding.orchestrator.state.execution, .preflight)
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testNormalSessionCoordinatorUsesSelectedPlanWithoutProofConfirmations() throws {
    let h = Harness()
    h.makeReadyWithFreshStationaryTelemetry()
    let planID = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!
    let record = SavedPlanRecord(
      id: planID,
      createdAt: Date(timeIntervalSince1970: 100),
      modifiedAt: Date(timeIntervalSince1970: 200),
      plan: h.plan.plan
    )
    let displayWake = RecordingWorkoutDisplayWakeController()
    let coordinator = WorkoutSessionCoordinator(
      binding: h.binding,
      displayWakeController: displayWake
    )

    XCTAssertEqual(displayWake.values, [false])

    coordinator.begin(record)
    coordinator.limits = .init(
      maximumSpeed: "10.0",
      maximumInclination: "6",
      maximumStepSpeedChange: "3.0"
    )
    coordinator.prepareWorkout()

    XCTAssertEqual(coordinator.stage, .preflight)
    let preflight = try XCTUnwrap(coordinator.preflightPresentation)
    XCTAssertTrue(preflight.canBeginWorkout)
    XCTAssertTrue(h.link.writes.isEmpty)

    coordinator.handlePreflight(.beginWorkout)

    XCTAssertEqual(coordinator.stage, .exercise)
    XCTAssertEqual(displayWake.values.last, true)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .waitingForPhysicalStart)
    XCTAssertEqual(h.binding.orchestrator.frozenAttempt?.sourcePlanID, planID)
    XCTAssertEqual(h.binding.orchestrator.lastPersistedSummary?.schemaVersion, 2)
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testNormalSessionCoordinatorCanCancelPreparedWorkoutAndPrepareAgain() {
    let h = Harness()
    h.makeReadyWithFreshStationaryTelemetry()
    let record = SavedPlanRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000108")!,
      createdAt: Date(timeIntervalSince1970: 100),
      modifiedAt: Date(timeIntervalSince1970: 200),
      plan: h.plan.plan
    )
    let displayWake = RecordingWorkoutDisplayWakeController()
    let coordinator = WorkoutSessionCoordinator(
      binding: h.binding,
      displayWakeController: displayWake
    )

    coordinator.begin(record)
    coordinator.limits = .init(
      maximumSpeed: "10", maximumInclination: "6", maximumStepSpeedChange: "3"
    )
    coordinator.prepareWorkout()
    coordinator.cancelBeforeExercise()

    XCTAssertEqual(coordinator.stage, .inactive)
    XCTAssertEqual(displayWake.values.last, false)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .idle)
    XCTAssertNil(h.binding.orchestrator.frozenAttempt)
    XCTAssertNil(h.binding.orchestrator.lastPersistedSummary)
    XCTAssertTrue(h.link.writes.isEmpty)

    coordinator.begin(record)
    coordinator.limits = .init(
      maximumSpeed: "10", maximumInclination: "6", maximumStepSpeedChange: "3"
    )
    coordinator.prepareWorkout()
    XCTAssertEqual(coordinator.stage, .preflight)
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testSessionCoordinatorReleasesDisplayWakeAfterInterruption() {
    let h = Harness()
    h.makeReadyWithFreshStationaryTelemetry()
    let record = SavedPlanRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000109")!,
      createdAt: Date(timeIntervalSince1970: 100),
      modifiedAt: Date(timeIntervalSince1970: 200),
      plan: h.plan.plan
    )
    let displayWake = RecordingWorkoutDisplayWakeController()
    let coordinator = WorkoutSessionCoordinator(
      binding: h.binding,
      displayWakeController: displayWake
    )
    coordinator.begin(record)
    coordinator.limits = .init(
      maximumSpeed: "10", maximumInclination: "6", maximumStepSpeedChange: "3"
    )
    coordinator.prepareWorkout()
    coordinator.handlePreflight(.beginWorkout)

    XCTAssertEqual(displayWake.values, [false, true])

    h.binding.receive(.connection(.disconnected(message: "Synthetic interruption")))

    XCTAssertEqual(coordinator.exercisePresentation.stage, .interrupted)
    XCTAssertEqual(displayWake.values, [false, true, false])
    XCTAssertTrue(h.link.writes.isEmpty)
  }

  func testSessionLimitDraftParsesExactLocaleDecimalWithoutInventingDefaults() {
    XCTAssertNil(WorkoutSessionLimitDraft().ceilings())
    let parsed = WorkoutSessionLimitDraft(
      maximumSpeed: "0,70",
      maximumInclination: "1",
      maximumStepSpeedChange: "0,10"
    ).ceilings(locale: Locale(identifier: "de_DE"))

    XCTAssertEqual(parsed?.maximumSpeed.value, Decimal(string: "0.70"))
    XCTAssertEqual(parsed?.maximumInclination.value, 1)
    XCTAssertEqual(parsed?.maximumStepSpeedChange.value, Decimal(string: "0.10"))
  }

  func testDisplayWakePolicyKeepsOnlyNonterminalExerciseStagesAwake() {
    let activeStages: [WorkoutExerciseStage] = [
      .waiting, .applying, .running, .override, .checking, .paused, .restoring,
      .awaitingPhysicalStop, .readyToEnd, .ending,
    ]
    let terminalStages: [WorkoutExerciseStage] = [.finished, .failed, .interrupted]

    for stage in activeStages {
      XCTAssertTrue(
        WorkoutDisplayWakePolicy.shouldKeepScreenAwake(
          sessionStage: .exercise,
          exerciseStage: stage
        ),
        "Expected \(stage) to keep the display awake"
      )
    }
    for stage in terminalStages {
      XCTAssertFalse(
        WorkoutDisplayWakePolicy.shouldKeepScreenAwake(
          sessionStage: .exercise,
          exerciseStage: stage
        ),
        "Expected \(stage) to release the display wake request"
      )
    }
    for stage in [WorkoutSessionStage.inactive, .preparation, .preflight] {
      XCTAssertFalse(
        WorkoutDisplayWakePolicy.shouldKeepScreenAwake(
          sessionStage: stage,
          exerciseStage: .running
        )
      )
    }
  }

  func testAcceptedPhysicalResumeRestoresEffectiveSpeedThenInclination() throws {
    let h = Harness()
    h.reachRunning()
    h.publishTelemetry(speedRaw: 0)
    guard case .paused = h.binding.orchestrator.state.execution else {
      return XCTFail("Accepted zero-speed telemetry must establish a pause")
    }
    let writeCount = h.link.writes.count

    let epoch = try XCTUnwrap(h.binding.epoch)
    _ = h.binding.handle(
      .setSpeedOverride(
        epoch: epoch,
        .init(value: Decimal(string: "5.5")!, unit: .kilometresPerHour)
      )
    )
    _ = h.binding.handle(
      .setInclinationOverride(
        epoch: epoch,
        .init(value: 1, unit: .percent)
      )
    )
    XCTAssertEqual(h.link.writes.count, writeCount)

    h.publishTelemetry(speedRaw: 50)
    XCTAssertEqual(h.link.writes.last, Data([0x02, 0x26, 0x02]))
    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x02, 0x01])))
    XCTAssertEqual(h.link.writes.last, Data([0x03, 0x0A, 0x00]))
    h.link.send(.writeAccepted)
    h.link.send(.indication(Data([0x80, 0x03, 0x01])))
    guard case .restoringTargets = h.binding.orchestrator.state.execution else {
      return XCTFail("Restored commands still require later telemetry evidence")
    }
    h.clock.advance(by: 0.001)
    h.publishTelemetry(speedRaw: 550, inclinationRaw: 10)
    XCTAssertEqual(h.binding.orchestrator.state.execution, .runningSegment)
  }

  func testEveryTransmissionRechecksEpochForegroundProfileProcedureAndFreshness() throws {
    let h = Harness()
    h.makeReadyWithFreshStationaryTelemetry()
    let capability = try XCTUnwrap(h.binding.currentCapability)
    let profile = try XCTUnwrap(h.binding.executionProfile)
    let epoch = try XCTUnwrap(h.binding.epoch)
    let procedureID = ProcedureID(epoch: epoch, sequence: 41)
    let record = WorkoutProcedureRecord(
      id: procedureID,
      intent: .requestControl,
      stepIndex: nil,
      createdAt: h.clock.read().monotonic
    )
    let frozen = FrozenWorkoutAttemptInputs(
      attemptID: UUID(),
      sourcePlanID: nil,
      plan: h.plan,
      capability: capability,
      ceilings: h.ceilings,
      profile: profile,
      executionProfileIdentity: FR30zExecutionProfile.identity,
      attemptedAt: h.clock.read().wallClock
    )

    let valid = ProductionTransmissionContext(
      epoch: epoch,
      foreground: true,
      capability: capability,
      profile: profile,
      frozenAttempt: frozen,
      expectedProcedureID: procedureID,
      latestTelemetryAt: h.clock.read().monotonic,
      now: h.clock.read().monotonic
    )
    var wrongEpoch = valid
    wrongEpoch.epoch = .init(rawValue: epoch.rawValue + 1)
    var background = valid
    background.foreground = false
    var noCapability = valid
    noCapability.capability = nil
    var noProfile = valid
    noProfile.profile = nil
    var noFrozenAttempt = valid
    noFrozenAttempt.frozenAttempt = nil
    var wrongProcedure = valid
    wrongProcedure.expectedProcedureID = nil
    var staleTelemetry = valid
    staleTelemetry.latestTelemetryAt = h.clock.read().monotonic.advanced(by: -2.001)
    let cases: [(String, ProductionTransmissionContext)] = [
      ("connection epoch", wrongEpoch),
      ("foreground", background),
      ("capability", noCapability),
      ("profile", noProfile),
      ("frozen attempt", noFrozenAttempt),
      ("current reducer procedure", wrongProcedure),
      ("telemetry freshness", staleTelemetry),
    ]

    for (name, suppliedContext) in cases {
      let raw = BindingRawTransport(epoch: epoch)
      let adapter = ProductionWorkoutTargetControlTransport(transport: raw)
      adapter.contextProvider = { suppliedContext }
      adapter.perform(.submit(record))
      XCTAssertTrue(raw.submissions.isEmpty, "Expected \(name) to fail closed")
    }

    let busyRaw = BindingRawTransport(epoch: epoch)
    busyRaw.state.inFlight = .init(
      id: .init(epoch: epoch, sequence: 99),
      intent: .requestControl,
      exactRequestBytes: Data([0x00]),
      submittedAt: h.clock.read().monotonic,
      attOutcome: nil
    )
    let busyAdapter = ProductionWorkoutTargetControlTransport(transport: busyRaw)
    busyAdapter.contextProvider = { valid }
    busyAdapter.perform(.submit(record))
    XCTAssertTrue(busyRaw.submissions.isEmpty, "One-procedure state must be rechecked")

    let targetID = ProcedureID(epoch: epoch, sequence: 42)
    let targetRecord = WorkoutProcedureRecord(
      id: targetID,
      intent: .setTargetSpeed(.init(value: 11, unit: .kilometresPerHour)),
      stepIndex: 0,
      createdAt: h.clock.read().monotonic
    )
    let ceilingRaw = BindingRawTransport(epoch: epoch, permissionHeld: true)
    let ceilingAdapter = ProductionWorkoutTargetControlTransport(transport: ceilingRaw)
    var ceilingContext = valid
    ceilingContext.expectedProcedureID = targetID
    ceilingAdapter.contextProvider = { ceilingContext }
    ceilingAdapter.perform(.submit(targetRecord))
    XCTAssertTrue(ceilingRaw.submissions.isEmpty, "Frozen ceilings must be rechecked")

    let permittedTarget = WorkoutProcedureRecord(
      id: targetID,
      intent: .setTargetSpeed(.init(value: 7, unit: .kilometresPerHour)),
      stepIndex: 1,
      createdAt: h.clock.read().monotonic
    )
    let backgroundRaw = BindingRawTransport(epoch: epoch, permissionHeld: true)
    let backgroundAdapter = ProductionWorkoutTargetControlTransport(transport: backgroundRaw)
    var backgroundTelemetryContext = valid
    backgroundTelemetryContext.foreground = false
    backgroundTelemetryContext.backgroundTelemetryWake = true
    backgroundTelemetryContext.targetSequencePurpose = .plannedTransition
    backgroundTelemetryContext.expectedProcedureID = targetID
    backgroundAdapter.contextProvider = { backgroundTelemetryContext }
    backgroundAdapter.perform(.submit(permittedTarget))
    XCTAssertEqual(
      backgroundRaw.submissions,
      [.setTargetSpeed(kilometresPerHour: 7)],
      "Only a fresh background telemetry wake may carry one planned target"
    )
  }
}

@MainActor
extension ProductionWorkoutExecutionBindingTests {
  @MainActor
  fileprivate final class Harness {
    static let peripheralID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
    static let equipment = "Synthetic FR30z"

    let client = BindingClient()
    let link = BindingControlPointLink()
    let clock = BindingClock()
    let scheduler = BindingScheduler()
    let history = BindingHistory()
    let lifecycleCheckpoints = BindingLifecycleCheckpoints()
    let binding: ProductionWorkoutExecutionBinding
    let plan: WorkoutPlanValidator.ValidatedPlan
    let ceilings = WorkoutSessionCeilings(
      maximumSpeed: .init(value: 10, unit: .kilometresPerHour),
      maximumInclination: .init(value: 6, unit: .percent),
      maximumStepSpeedChange: .init(value: 3, unit: .kilometresPerHour)
    )

    init() {
      client.connectedPeripheralIdentifier = Self.peripheralID
      client.connectedPeripheralName = Self.equipment
      client.controlPointLink = link
      let capabilities = Self.capabilities
      let rawPlan = WorkoutPlan(
        schemaVersion: WorkoutPlanSchema.currentVersion,
        suggestedName: "Synthetic binding",
        activity: .indoorRunning,
        steps: [
          Self.step(.warmUp, "Warm up", speed: 5, incline: 0),
          Self.step(.interval, "Run", speed: 7, incline: 1),
          Self.step(.coolDown, "Cool down", speed: 4, incline: 0),
        ]
      )
      plan = try! WorkoutPlanValidator.validate(rawPlan, against: capabilities).get()
      let rawTransport = FTMSSingleProcedureTransport(
        clock: { [clock] in clock.read().monotonic },
        scheduler: scheduler
      )
      binding = ProductionWorkoutExecutionBinding(
        client: client,
        controlTransport: rawTransport,
        history: history,
        lifecycleCheckpoints: lifecycleCheckpoints,
        clock: clock,
        attemptIDs: BindingAttemptIDs(),
        automaticTicks: false
      )
      binding.setApplicationActivity(.active)
    }

    func publishExactProfile(
      featureData: Data = Data([0x0C, 0x16, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00]),
      characteristics suppliedCharacteristics: [FTMSCharacteristicInfo]? = nil
    ) {
      binding.receive(.connection(.connecting(name: Self.equipment)))
      binding.receive(.connection(.connected(name: Self.equipment)))
      binding.receive(.characteristics(suppliedCharacteristics ?? Self.characteristics))
      for uuid in [FTMSUUID.treadmillData, FTMSUUID.trainingStatus, FTMSUUID.fitnessMachineStatus] {
        binding.receive(.subscription(uuid: uuid, state: .subscribed))
      }
      binding.receive(
        .value(
          uuid: FTMSUUID.fitnessMachineFeature,
          data: featureData,
          source: .initialRead
        )
      )
      binding.receive(
        .value(
          uuid: FTMSUUID.supportedSpeedRange,
          data: Data([0x32, 0x00, 0xD0, 0x07, 0x0A, 0x00]),
          source: .initialRead
        )
      )
      binding.receive(
        .value(
          uuid: FTMSUUID.supportedInclinationRange,
          data: Data([0x00, 0x00, 0x96, 0x00, 0x0A, 0x00]),
          source: .initialRead
        )
      )
    }

    func makeReadyWithFreshStationaryTelemetry() {
      publishExactProfile()
      link.send(.indicationsEnabled)
      publishTelemetry(speedRaw: 0)
      XCTAssertTrue(binding.canExposeArming)
    }

    func reachRunning() {
      makeReadyWithFreshStationaryTelemetry()
      XCTAssertNotNil(binding.arm(plan: plan, ceilings: ceilings, sourcePlanID: nil))
      _ = binding.beginWorkout()
      publishTelemetry(speedRaw: 50)
      link.send(.writeAccepted)
      link.send(.indication(Data([0x80, 0x00, 0x01])))
      link.send(.writeAccepted)
      link.send(.indication(Data([0x80, 0x02, 0x01])))
      link.send(.writeAccepted)
      link.send(.indication(Data([0x80, 0x03, 0x01])))
      clock.advance(by: 0.001)
      publishTelemetry(speedRaw: 500)
      XCTAssertEqual(binding.orchestrator.state.execution, .runningSegment)
    }

    func publishTelemetry(speedRaw: UInt16, inclinationRaw: Int16 = 0) {
      let incline = UInt16(bitPattern: inclinationRaw)
      let bytes = Data([
        0x08, 0x00,
        UInt8(speedRaw & 0x00FF), UInt8(speedRaw >> 8),
        UInt8(incline & 0x00FF), UInt8(incline >> 8),
        0x00, 0x00,
      ])
      binding.receive(.value(uuid: FTMSUUID.treadmillData, data: bytes, source: .notification))
    }

    static let capabilities = WorkoutPlanCapabilities(
      speed: .supported(
        .init(
          minimum: .init(value: Decimal(5) / 10, unit: .kilometresPerHour),
          maximum: .init(value: 20, unit: .kilometresPerHour),
          increment: .init(value: Decimal(1) / 10, unit: .kilometresPerHour)
        )
      ),
      inclination: .supported(
        .init(
          minimum: .init(value: 0, unit: .percent),
          maximum: .init(value: 15, unit: .percent),
          increment: .init(value: 1, unit: .percent)
        )
      )
    )

    static let characteristics: [FTMSCharacteristicInfo] = [
      .init(uuid: FTMSUUID.fitnessMachineFeature, properties: ["Read"]),
      .init(uuid: FTMSUUID.treadmillData, properties: ["Notify"]),
      .init(uuid: FTMSUUID.trainingStatus, properties: ["Read", "Notify"]),
      .init(uuid: FTMSUUID.supportedSpeedRange, properties: ["Read"]),
      .init(uuid: FTMSUUID.supportedInclinationRange, properties: ["Read"]),
      .init(uuid: FTMSUUID.fitnessMachineControlPoint, properties: ["Write", "Indicate"]),
      .init(uuid: FTMSUUID.fitnessMachineStatus, properties: ["Notify"]),
    ]

    static func step(
      _ kind: WorkoutStepKind,
      _ label: String,
      speed: Decimal,
      incline: Decimal
    ) -> WorkoutStep {
      .init(
        kind: kind,
        label: label,
        duration: .init(value: 60, unit: .seconds),
        targetSpeed: .init(value: speed, unit: .kilometresPerHour),
        targetInclination: .init(value: incline, unit: .percent)
      )
    }
  }
}

@MainActor
private final class BindingClient: FTMSClientProtocol {
  weak var delegate: (any FTMSClientDelegate)?
  var connectedPeripheralIdentifier: UUID?
  var connectedPeripheralName: String?
  var controlPointLink: (any FTMSControlPointLink)?
  func startScan() {}
  func stopScan() {}
  func connect(to identifier: UUID) {}
  func disconnect() {}
}

@MainActor
private final class BindingControlPointLink: FTMSControlPointLink {
  let supportsWriteWithResponse = true
  let supportsIndications = true
  var eventHandler: ((FTMSControlPointLinkEvent) -> Void)?
  private(set) var enableIndicationsCount = 0
  private(set) var writes: [Data] = []
  private(set) var invalidateCount = 0

  func enableIndications() { enableIndicationsCount += 1 }
  func writeWithResponse(_ data: Data) { writes.append(data) }
  func invalidate() {
    invalidateCount += 1
    eventHandler = nil
  }
  func send(_ event: FTMSControlPointLinkEvent) { eventHandler?(event) }
}

private final class BindingClock: WorkoutOrchestrationClock {
  private var value = WorkoutOrchestrationTime(
    monotonic: .init(seconds: 10),
    wallClock: Date(timeIntervalSince1970: 10)
  )
  func read() -> WorkoutOrchestrationTime { value }
  func advance(by interval: TimeInterval) {
    value = .init(
      monotonic: value.monotonic.advanced(by: interval),
      wallClock: value.wallClock.addingTimeInterval(interval)
    )
  }
}

private final class BindingAttemptIDs: WorkoutAttemptIDSource {
  func nextAttemptID() -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000063")!
  }
}

@MainActor
private final class RecordingWorkoutDisplayWakeController: WorkoutDisplayWakeControlling {
  private(set) var values: [Bool] = []

  func setWorkoutKeepsScreenAwake(_ enabled: Bool) {
    values.append(enabled)
  }
}

private final class BindingHistory: WorkoutHistoryRepositoryProtocol {
  private var summaries: [WorkoutExecutionSummary] = []
  func list() -> WorkoutHistoryRepositoryStatus {
    .init(
      canonical: summaries.isEmpty ? .empty : .available(summaries: summaries),
      staging: .absent
    )
  }
  func record(_ summary: WorkoutExecutionSummary) throws {
    if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
      summaries[index] = summary
    } else {
      summaries.append(summary)
    }
  }
}

private final class BindingLifecycleCheckpoints: WorkoutLifecycleCheckpointRepositoryProtocol {
  var checkpoint: WorkoutLifecycleCheckpoint?
  func load() throws -> WorkoutLifecycleCheckpoint? { checkpoint }
  func save(_ checkpoint: WorkoutLifecycleCheckpoint) throws { self.checkpoint = checkpoint }
  func remove() throws { checkpoint = nil }
}

@MainActor
private final class BindingScheduler: FTMSDeadlineScheduling {
  func schedule(
    after interval: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any FTMSDeadlineCancellation {
    BindingCancellation()
  }
}

@MainActor
private final class BindingCancellation: FTMSDeadlineCancellation {
  func cancel() {}
}

@MainActor
private final class BindingRawTransport: FitnessMachineControlTransport {
  var state: FTMSControlPointTransportState
  var stateHandler: ((FTMSControlPointTransportState) -> Void)?
  private(set) var submissions: [FitnessMachineControlIntent] = []

  init(epoch: ConnectionEpoch, permissionHeld: Bool = false) {
    state = .init(
      link: .ready(epoch),
      permission: permissionHeld ? .held(epoch, acknowledgedAt: .init(seconds: 1)) : .notHeld
    )
  }

  func establishLink(
    epoch: ConnectionEpoch,
    eligibility: FTMSControlPointEligibility,
    link: any FTMSControlPointLink
  ) throws {}
  func enableIndications() throws {}
  func submit(_ intent: FitnessMachineControlIntent) throws -> ProcedureID {
    submissions.append(intent)
    return .init(epoch: state.link.epoch!, sequence: UInt64(submissions.count))
  }
  func disconnect() { state.link = .disconnected }
}
