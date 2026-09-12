#if DEBUG
  import SwiftUI

  enum WorkoutExerciseUITestScenario: String, CaseIterable {
    case waiting
    case applying
    case running
    case override
    case checking
    case paused
    case restoring
    case ending
    case failed
    case interrupted
  }

  struct WorkoutExerciseUITestConfiguration {
    let scenario: WorkoutExerciseUITestScenario
    let reduceMotion: Bool

    static var current: Self? {
      let process = ProcessInfo.processInfo
      guard process.arguments.contains("--paceprompt-exercise-ui-testing"),
        let value = process.environment["PACEPROMPT_EXERCISE_SCENARIO"],
        let scenario = WorkoutExerciseUITestScenario(rawValue: value)
      else {
        return nil
      }
      return .init(
        scenario: scenario,
        reduceMotion: process.environment["PACEPROMPT_EXERCISE_REDUCE_MOTION"] == "1"
      )
    }
  }

  struct WorkoutExerciseUITestHost: View {
    @State private var context: WorkoutExerciseContext
    private let now = MonotonicInstant(seconds: 100)
    private let reduceMotion: Bool

    init(configuration: WorkoutExerciseUITestConfiguration) {
      _context = State(
        initialValue: WorkoutExerciseFixtures.context(for: configuration.scenario)
      )
      reduceMotion = configuration.reduceMotion
    }

    var body: some View {
      WorkoutExerciseView(
        presentation: .init(
          context: context,
          at: now,
          locale: Locale(identifier: "en_GB")
        ),
        send: handle,
        reduceMotionOverride: reduceMotion
      )
    }

    private func handle(_ intent: WorkoutExerciseIntent) {
      var state = context.state
      switch intent {
      case .setSpeed(let target):
        guard var segment = state.currentSegment else { return }
        segment.speedOverride = target
        state.currentSegment = segment
        state.execution = .runningSegment
        state.telemetry = .fresh(
          WorkoutExerciseFixtures.sample(
            speed: target.value,
            inclination: WorkoutExerciseFixtures.effectiveInclination(state),
            at: 99.5
          )
        )
      case .setInclination(let target):
        guard var segment = state.currentSegment else { return }
        segment.inclinationOverride = target
        state.currentSegment = segment
        state.execution = .runningSegment
        state.telemetry = .fresh(
          WorkoutExerciseFixtures.sample(
            speed: WorkoutExerciseFixtures.effectiveSpeed(state),
            inclination: target.value,
            at: 99.5
          )
        )
      case .returnToPlan:
        guard var segment = state.currentSegment else { return }
        segment.speedOverride = nil
        segment.inclinationOverride = nil
        state.currentSegment = segment
        state.execution = .runningSegment
      case .confirmOperatorStationary:
        let evidence = WorkoutHumanStationaryEvidence(
          confirmedAt: now,
          note: "UI-test operator observation"
        )
        state.observedMachine = .humanConfirmedStationary(evidence)
        state.execution = .paused(.human(evidence))
      case .endWorkout:
        let evidence: WorkoutStationaryEvidence
        switch state.execution {
        case .paused(let stationary):
          evidence = stationary
        case .readyToEnd(let completion):
          evidence = completion.stationaryEvidence
        default:
          return
        }
        state.execution = .ending(
          .init(
            reason: .endedFromPause,
            stepIndex: state.currentSegment?.stepIndex ?? 0,
            totalActiveSeconds: state.completedActiveSeconds,
            stationaryEvidence: evidence
          )
        )
      }
      context = .init(
        state: state,
        frozenAttempt: context.frozenAttempt,
        latestSummary: context.latestSummary
      )
    }
  }

  enum WorkoutExerciseFixtures {
    static let now = MonotonicInstant(seconds: 100)

    static func context(
      for scenario: WorkoutExerciseUITestScenario
    ) -> WorkoutExerciseContext {
      let plan = validatedPlan()
      let capability = capabilitySnapshot()
      let ceilings = WorkoutSessionCeilings(
        maximumSpeed: .init(value: 10, unit: .kilometresPerHour),
        maximumInclination: .init(value: 6, unit: .percent),
        maximumStepSpeedChange: .init(value: 2, unit: .kilometresPerHour)
      )
      let profile = FR30zExecutionProfile(
        peripheralIdentity: "synthetic-peripheral",
        equipmentIdentity: "synthetic-fr30z"
      )
      let epoch = ConnectionEpoch(rawValue: 1)
      var state = WorkoutExecutionState()
      state.connection = .ready(epoch: epoch, capability: capability)
      state.controlPermission = .held(epoch: epoch, acknowledgedAt: .init(seconds: 2))
      state.armedWorkout = .init(
        plan: plan,
        capability: capability,
        ceilings: ceilings,
        profile: profile
      )
      state.currentSegment = .init(
        stepIndex: 1,
        accumulatedActiveSeconds: 21,
        activeStartedAt: .init(seconds: 90),
        speedOverride: nil,
        inclinationOverride: nil
      )
      state.completedActiveSeconds = 120
      state.motionPossible = true
      state.lastEventTime = now
      state.telemetry = .fresh(sample(speed: 7, inclination: 2, at: 99.5))
      state.observedMachine = .targetReported(
        stepIndex: 1,
        sample: sample(speed: 7, inclination: 2, at: 99.5)
      )

      switch scenario {
      case .waiting:
        state.currentSegment = .init(
          stepIndex: 0,
          accumulatedActiveSeconds: 0,
          activeStartedAt: nil,
          speedOverride: nil,
          inclinationOverride: nil
        )
        state.motionPossible = false
        state.telemetry = .fresh(sample(speed: 0, inclination: 0, at: 99.5))
        state.observedMachine = .reportedStationary(
          sample(speed: 0, inclination: 0, at: 99.5)
        )
        state.execution = .waitingForPhysicalStart
      case .applying:
        let record = procedure(
          intent: .setTargetInclination(.init(value: 2, unit: .percent))
        )
        state.procedure = .attAccepted(
          record: record,
          deadline: .init(seconds: 125)
        )
        state.targetSequence = .init(
          purpose: .initial,
          stepIndex: 1,
          startedAt: .init(seconds: 95),
          forceSpeed: true,
          forceInclination: true,
          acknowledgedSpeed: .init(value: 7, unit: .kilometresPerHour),
          acknowledgedInclination: nil,
          finalAcknowledgementAt: nil,
          observationDeadline: nil
        )
        state.execution = .applyingTargets(.initial)
      case .running:
        state.execution = .runningSegment
      case .override:
        state.currentSegment?.speedOverride = .init(
          value: Decimal(71) / 10,
          unit: .kilometresPerHour
        )
        state.telemetry = .fresh(sample(speed: Decimal(71) / 10, inclination: 2, at: 99.5))
        state.execution = .runningSegment
      case .checking:
        let stale = sample(speed: 7, inclination: 2, at: 96)
        state.telemetry = .stale(stale)
        state.observedMachine = .unknown
        state.currentSegment?.activeStartedAt = nil
        state.execution = .checkingTreadmill(
          .init(
            origin: .runningSegment,
            freshnessBoundary: .init(seconds: 98),
            interruptionDeadline: .init(seconds: 108)
          )
        )
      case .paused:
        let stationary = sample(speed: 0, inclination: 2, at: 99.5)
        state.telemetry = .fresh(stationary)
        state.observedMachine = .reportedStationary(stationary)
        state.currentSegment?.activeStartedAt = nil
        state.execution = .paused(.telemetry(stationary))
      case .restoring:
        let record = procedure(
          intent: .setTargetInclination(.init(value: 2, unit: .percent))
        )
        state.procedure = .submitted(record)
        state.targetSequence = .init(
          purpose: .resumeRestoration,
          stepIndex: 1,
          startedAt: .init(seconds: 98),
          forceSpeed: true,
          forceInclination: true,
          acknowledgedSpeed: .init(value: 7, unit: .kilometresPerHour),
          acknowledgedInclination: nil,
          finalAcknowledgementAt: nil,
          observationDeadline: nil
        )
        state.currentSegment?.activeStartedAt = nil
        state.execution = .restoringTargets
      case .ending:
        let stationary = sample(speed: 0, inclination: 2, at: 99.5)
        state.telemetry = .fresh(stationary)
        state.currentSegment?.activeStartedAt = nil
        state.execution = .ending(
          .init(
            reason: .endedFromPause,
            stepIndex: 1,
            totalActiveSeconds: 151,
            stationaryEvidence: .telemetry(stationary)
          )
        )
      case .failed:
        state.currentSegment?.activeStartedAt = nil
        state.execution = .failed(.targetObservationTimeout)
      case .interrupted:
        state.currentSegment?.activeStartedAt = nil
        state.telemetry = .stale(sample(speed: 7, inclination: 2, at: 85))
        state.observedMachine = .unknown
        state.execution = .interrupted(.telemetryStreamTimedOut)
      }

      let frozen = FrozenWorkoutAttemptInputs(
        attemptID: UUID(uuidString: "00000000-0000-0000-0000-000000000060")!,
        sourcePlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000061"),
        plan: plan,
        capability: capability,
        ceilings: ceilings,
        profile: profile,
        executionProfileIdentity: FR30zExecutionProfile.identity,
        attemptedAt: Date(timeIntervalSince1970: 1_789_120_000)
      )
      return .init(state: state, frozenAttempt: frozen, latestSummary: nil)
    }

    static func sample(
      speed: Decimal,
      inclination: Decimal,
      at receivedAt: TimeInterval
    ) -> WorkoutTelemetrySample {
      .init(
        speed: .init(value: speed, unit: .kilometresPerHour),
        inclination: .init(value: inclination, unit: .percent),
        totalDistanceMetres: 1_260,
        receivedAt: .init(seconds: receivedAt)
      )
    }

    static func effectiveSpeed(_ state: WorkoutExecutionState) -> Decimal {
      let index = state.currentSegment?.stepIndex ?? 0
      let step = state.armedWorkout!.plan.plan.steps[index]
      return state.currentSegment?.speedOverride?.value ?? step.targetSpeed.value
    }

    static func effectiveInclination(_ state: WorkoutExecutionState) -> Decimal {
      let index = state.currentSegment?.stepIndex ?? 0
      let step = state.armedWorkout!.plan.plan.steps[index]
      return state.currentSegment?.inclinationOverride?.value
        ?? step.targetInclination.value
    }

    private static func procedure(
      intent: WorkoutControlPointIntent
    ) -> WorkoutProcedureRecord {
      .init(
        id: .init(epoch: .init(rawValue: 1), sequence: 9),
        intent: intent,
        stepIndex: 1,
        createdAt: .init(seconds: 96),
        submittedAt: .init(seconds: 97),
        attAcceptedAt: nil,
        ftmsAcknowledgedAt: nil
      )
    }

    private static func validatedPlan() -> WorkoutPlanValidator.ValidatedPlan {
      let result = WorkoutPlanValidator.validate(
        .init(
          schemaVersion: WorkoutPlanSchema.currentVersion,
          suggestedName: "Synthetic Pyramid",
          activity: .indoorRunning,
          steps: [
            step(.warmUp, "Warm up", 120, 5, 0),
            step(.interval, "Run", 180, 7, 2),
            step(.coolDown, "Cool down", 120, 5, 0),
          ]
        ),
        against: capabilitySnapshot().planCapabilities
      )
      guard case .success(let plan) = result else {
        preconditionFailure("Synthetic Exercise plan must validate")
      }
      return plan
    }

    private static func capabilitySnapshot() -> FR30zCapabilitySnapshot {
      .init(
        peripheralIdentity: "synthetic-peripheral",
        equipmentIdentity: "synthetic-fr30z",
        fitnessMachineServicePresent: true,
        requiredCharacteristicPropertiesMatch: true,
        fitnessMachineFeatureEvidence: .matched,
        supportedSpeedRangeEvidence: .matched,
        supportedInclinationRangeEvidence: .matched,
        treadmillDataNotificationsEnabled: true,
        controlPointIndicationsEnabled: true,
        optionalSubscriptionOutcomesResolved: true,
        planCapabilities: .init(
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
              increment: .init(value: Decimal(5) / 10, unit: .percent)
            )
          )
        )
      )
    }

    private static func step(
      _ kind: WorkoutStepKind,
      _ label: String,
      _ seconds: Int,
      _ speed: Decimal,
      _ inclination: Decimal
    ) -> WorkoutStep {
      .init(
        kind: kind,
        label: label,
        duration: .init(value: seconds, unit: .seconds),
        targetSpeed: .init(value: speed, unit: .kilometresPerHour),
        targetInclination: .init(value: inclination, unit: .percent)
      )
    }
  }
#endif
