import Foundation

enum WorkoutExerciseStage: String, Equatable {
  case waiting
  case applying
  case running
  case override
  case checking
  case paused
  case restoring
  case awaitingPhysicalStop
  case readyToEnd
  case ending
  case finished
  case failed
  case interrupted
}

enum WorkoutExerciseTone: Equatable {
  case neutral
  case active
  case warning
  case failure
}

enum WorkoutExerciseEvidenceStage: String, CaseIterable, Equatable {
  case requested
  case submitted
  case attAccepted
  case ftmsAcknowledged
  case observing
  case confirmed
  case stale
  case failed
  case unknown

  var label: String {
    switch self {
    case .requested: "Requested"
    case .submitted: "Submitted"
    case .attAccepted: "ATT accepted"
    case .ftmsAcknowledged: "FTMS acknowledged"
    case .observing: "Observing treadmill"
    case .confirmed: "Confirmed by treadmill"
    case .stale: "Stale treadmill report"
    case .failed: "Failed"
    case .unknown: "Unknown"
    }
  }

  var symbol: String {
    switch self {
    case .requested: "arrow.up.circle"
    case .submitted: "paperplane.circle"
    case .attAccepted: "antenna.radiowaves.left.and.right.circle"
    case .ftmsAcknowledged: "checkmark.circle"
    case .observing: "eye.circle"
    case .confirmed: "checkmark.circle.fill"
    case .stale: "clock.badge.exclamationmark"
    case .failed: "xmark.octagon.fill"
    case .unknown: "questionmark.circle"
    }
  }
}

struct WorkoutExerciseStatusPresentation: Equatable {
  let title: String
  let detail: String
  let symbol: String
  let tone: WorkoutExerciseTone
}

struct WorkoutExerciseAxisPresentation: Equatable {
  let title: String
  let unit: String
  let actual: String
  let planned: String
  let effective: String
  let evidence: WorkoutExerciseEvidenceStage
  let evidenceDetail: String
  let isOverridden: Bool
  let decrementLabel: String
  let incrementLabel: String
  let decrementTarget: Decimal?
  let incrementTarget: Decimal?
}

struct WorkoutExercisePlanStepPresentation: Equatable, Identifiable {
  let index: Int
  let label: String
  let duration: String
  let speed: String
  let inclination: String
  let isCurrent: Bool

  var id: Int { index }
}

struct WorkoutExerciseContext: Equatable {
  let state: WorkoutExecutionState
  let frozenAttempt: FrozenWorkoutAttemptInputs?
  let latestSummary: WorkoutExecutionSummary?

  @MainActor
  init(orchestrator: WorkoutExecutionOrchestrator) {
    state = orchestrator.state
    frozenAttempt = orchestrator.frozenAttempt
    latestSummary = orchestrator.lastPersistedSummary
  }

  init(
    state: WorkoutExecutionState,
    frozenAttempt: FrozenWorkoutAttemptInputs?,
    latestSummary: WorkoutExecutionSummary?
  ) {
    self.state = state
    self.frozenAttempt = frozenAttempt
    self.latestSummary = latestSummary
  }
}

enum WorkoutExerciseIntent: Equatable {
  case setSpeed(WorkoutSpeed)
  case setInclination(WorkoutInclination)
  case returnToPlan
  case confirmOperatorStationary
  case endWorkout
}

struct WorkoutExercisePresentation: Equatable {
  let stage: WorkoutExerciseStage
  let status: WorkoutExerciseStatusPresentation
  let planName: String
  let currentInterval: String
  let countdown: String
  let overallProgress: Double
  let overallProgressLabel: String
  let nextInterval: String
  let elapsedActiveTime: String
  let distance: String
  let distanceDetail: String
  let speed: WorkoutExerciseAxisPresentation
  let inclination: WorkoutExerciseAxisPresentation
  let overrideLabel: String?
  let restorationDetail: String?
  let plan: [WorkoutExercisePlanStepPresentation]
  let canReturnToPlan: Bool
  let canConfirmOperatorStationary: Bool
  let canEndWorkout: Bool
  let allowsDismissal: Bool

  init(
    context: WorkoutExerciseContext,
    at now: MonotonicInstant,
    locale: Locale = .autoupdatingCurrent
  ) {
    let state = context.state
    let plan = context.frozenAttempt?.plan.plan ?? state.armedWorkout?.plan.plan
    let steps = plan?.steps ?? []
    let currentIndex =
      state.currentSegment?.stepIndex ?? context.latestSummary?.progress.currentStepIndex
    let safeIndex = currentIndex.flatMap { steps.indices.contains($0) ? $0 : nil }
    let currentStep = safeIndex.map { steps[$0] }
    let elapsedInSegment = Self.elapsedInSegment(state: state, at: now)
    let elapsedTotal = Self.elapsedTotal(state: state, at: now)
    let totalDuration = steps.reduce(0) { $0 + $1.duration.value }

    stage = Self.stage(for: state)
    status = Self.status(for: stage, state: state)
    planName = plan?.suggestedName ?? "Workout"
    currentInterval = Self.currentInterval(
      step: currentStep,
      index: safeIndex,
      count: steps.count,
      stage: stage
    )
    countdown = Self.duration(max(0, (currentStep?.duration.value ?? 0) - elapsedInSegment))
    let completedBeforeCurrent =
      safeIndex.map { index in
        steps.prefix(index).reduce(0) { $0 + $1.duration.value }
      } ?? (stage == .finished ? totalDuration : 0)
    let progressed = min(totalDuration, completedBeforeCurrent + elapsedInSegment)
    overallProgress = totalDuration > 0 ? Double(progressed) / Double(totalDuration) : 0
    overallProgressLabel =
      totalDuration > 0
      ? "\(Int((overallProgress * 100).rounded())) percent complete"
      : "Progress unavailable"
    nextInterval = Self.nextInterval(after: safeIndex, steps: steps, locale: locale)
    elapsedActiveTime = Self.duration(elapsedTotal)

    let telemetry = Self.telemetrySample(state.telemetry)
    let summaryDistance = context.latestSummary.flatMap(Self.summaryDistance)
    let trustworthyDistance = telemetry?.totalDistanceMetres ?? summaryDistance
    if let trustworthyDistance, trustworthyDistance >= 0 {
      distance = Self.measurement(trustworthyDistance / 1_000, unit: "km", locale: locale)
      distanceDetail =
        Self.telemetryIsStale(state.telemetry, at: now)
        ? "Last reported; telemetry is stale"
        : "Treadmill reported"
    } else {
      distance = "Unavailable"
      distanceDetail = "No trustworthy treadmill distance is available"
    }

    let planned = currentStep.map {
      WorkoutTarget(speed: $0.targetSpeed, inclination: $0.targetInclination)
    }
    let effective =
      currentStep.flatMap { step -> WorkoutTarget? in
        guard let segment = state.currentSegment else { return planned }
        return .init(
          speed: segment.speedOverride ?? step.targetSpeed,
          inclination: segment.inclinationOverride ?? step.targetInclination
        )
      } ?? planned

    speed = Self.axis(
      title: "Speed",
      unit: "km/h",
      planned: planned?.speed.value,
      effective: effective?.speed.value,
      actual: telemetry?.speed.value,
      jointEffective: effective,
      isOverridden: state.currentSegment?.speedOverride != nil,
      state: state,
      at: now,
      locale: locale,
      isSpeed: true
    )
    inclination = Self.axis(
      title: "Inclination",
      unit: "%",
      planned: planned?.inclination.value,
      effective: effective?.inclination.value,
      actual: telemetry?.inclination.value,
      jointEffective: effective,
      isOverridden: state.currentSegment?.inclinationOverride != nil,
      state: state,
      at: now,
      locale: locale,
      isSpeed: false
    )

    let overriddenAxes = [
      speed.isOverridden ? "speed" : nil,
      inclination.isOverridden ? "inclination" : nil,
    ].compactMap { $0 }
    overrideLabel =
      overriddenAxes.isEmpty
      ? nil
      : "Current-segment \(overriddenAxes.joined(separator: " and ")) override"
    canReturnToPlan = !overriddenAxes.isEmpty && Self.adjustmentAllowed(state.execution)
    restorationDetail =
      stage == .restoring
      ? "Restoring effective speed \(speed.effective), then inclination \(inclination.effective)."
      : nil
    self.plan = steps.enumerated().map { index, step in
      .init(
        index: index,
        label: step.label,
        duration: Self.duration(step.duration.value),
        speed: Self.measurement(step.targetSpeed.value, unit: "km/h", locale: locale),
        inclination: Self.measurement(
          step.targetInclination.value,
          unit: "%",
          locale: locale
        ),
        isCurrent: index == safeIndex
      )
    }
    canConfirmOperatorStationary = Self.canConfirmOperatorStationary(state, at: now)
    canEndWorkout = Self.stationaryEvidenceIsCurrent(state.execution, at: now)
    allowsDismissal =
      stage == .finished
      || ([.failed, .interrupted].contains(stage) && !state.motionPossible)
  }

  private static func stage(for state: WorkoutExecutionState) -> WorkoutExerciseStage {
    switch state.execution {
    case .idle, .preflight, .acquiringControl, .waitingForPhysicalStart:
      return .waiting
    case .applyingTargets:
      return state.currentSegment.map {
        $0.speedOverride != nil || $0.inclinationOverride != nil
      } == true ? .override : .applying
    case .runningSegment:
      return state.currentSegment.map {
        $0.speedOverride != nil || $0.inclinationOverride != nil
      } == true ? .override : .running
    case .checkingTreadmill:
      return .checking
    case .paused:
      return .paused
    case .restoringTargets:
      return .restoring
    case .awaitingPhysicalStopForCompletion:
      return .awaitingPhysicalStop
    case .readyToEnd:
      return .readyToEnd
    case .ending:
      return .ending
    case .finished:
      return .finished
    case .interrupted:
      return .interrupted
    case .failed:
      return .failed
    }
  }

  private static func status(
    for stage: WorkoutExerciseStage,
    state: WorkoutExecutionState
  ) -> WorkoutExerciseStatusPresentation {
    switch stage {
    case .waiting:
      return .init(
        title: "Press Start on the treadmill",
        detail:
          "PacePrompt is waiting for fresh treadmill-reported movement. No target is confirmed.",
        symbol: "hand.tap.fill",
        tone: .neutral
      )
    case .applying:
      return .init(
        title: "Applying targets",
        detail:
          "Intent, submission, ATT, FTMS acknowledgement and treadmill observation remain separate.",
        symbol: "arrow.triangle.2.circlepath",
        tone: .warning
      )
    case .running:
      return .init(
        title: "Running",
        detail: "Fresh treadmill evidence confirms the current effective targets.",
        symbol: "figure.run",
        tone: .active
      )
    case .override:
      return .init(
        title: "Manual override",
        detail: "The effective target differs from the plan for this segment only.",
        symbol: "slider.horizontal.3",
        tone: .warning
      )
    case .checking:
      return .init(
        title: "Checking treadmill",
        detail:
          "Telemetry is delayed or stale. Belt state is unknown; this does not mean the treadmill stopped.",
        symbol: "clock.badge.exclamationmark.fill",
        tone: .warning
      )
    case .paused:
      return .init(
        title: "Workout paused — press Start on the treadmill to resume",
        detail:
          "The current segment and effective targets are preserved while active time is frozen.",
        symbol: "pause.circle.fill",
        tone: .warning
      )
    case .restoring:
      return .init(
        title: "Restoring targets",
        detail:
          "Speed is restored before inclination; timing resumes only after later joint observation.",
        symbol: "arrow.clockwise.circle.fill",
        tone: .warning
      )
    case .awaitingPhysicalStop:
      return .init(
        title: "Workout complete - press Stop on the treadmill",
        detail: "PacePrompt sends no Stop command. End workout appears after stationary evidence.",
        symbol: "flag.checkered",
        tone: .warning
      )
    case .readyToEnd:
      return .init(
        title: "Stationary confirmed",
        detail: "End workout saves the local app attempt and sends no FTMS Stop.",
        symbol: "checkmark.shield.fill",
        tone: .active
      )
    case .ending:
      return .init(
        title: "Ending workout",
        detail:
          "Saving the local app attempt. The treadmill remains under physical-console control.",
        symbol: "hourglass",
        tone: .neutral
      )
    case .finished:
      return .init(
        title: "Workout ended",
        detail: "The local app attempt is saved. No FTMS Stop was sent.",
        symbol: "checkmark.circle.fill",
        tone: .active
      )
    case .failed:
      return .init(
        title: "Workout failed",
        detail:
          "Use the physical console and safety key. PacePrompt will not retry or continue this attempt.",
        symbol: "xmark.octagon.fill",
        tone: .failure
      )
    case .interrupted:
      return .init(
        title: "Workout interrupted",
        detail:
          "Physical state is uncertain. Use the console and safety key; no automatic resume is available.",
        symbol: "exclamationmark.triangle.fill",
        tone: .failure
      )
    }
  }

  private static func axis(
    title: String,
    unit: String,
    planned: Decimal?,
    effective: Decimal?,
    actual: Decimal?,
    jointEffective: WorkoutTarget?,
    isOverridden: Bool,
    state: WorkoutExecutionState,
    at now: MonotonicInstant,
    locale: Locale,
    isSpeed: Bool
  ) -> WorkoutExerciseAxisPresentation {
    let limits = adjustmentLimits(state: state, isSpeed: isSpeed)
    let evidence = evidence(
      state: state,
      jointEffective: jointEffective,
      at: now,
      isSpeed: isSpeed
    )
    return .init(
      title: title,
      unit: unit,
      actual: actual.map { measurement($0, unit: unit, locale: locale) } ?? "Unavailable",
      planned: planned.map { measurement($0, unit: unit, locale: locale) } ?? "Unavailable",
      effective: effective.map { measurement($0, unit: unit, locale: locale) } ?? "Unavailable",
      evidence: evidence,
      evidenceDetail: evidenceDetail(evidence, isSpeed: isSpeed),
      isOverridden: isOverridden,
      decrementLabel: limits.map {
        "Decrease by \(measurement($0.increment, unit: unit, locale: locale))"
      } ?? "Decrease unavailable",
      incrementLabel: limits.map {
        "Increase by \(measurement($0.increment, unit: unit, locale: locale))"
      } ?? "Increase unavailable",
      decrementTarget: adjusted(
        effective,
        by: limits.map { -$0.increment },
        limits: limits,
        state: state
      ),
      incrementTarget: adjusted(
        effective,
        by: limits?.increment,
        limits: limits,
        state: state
      )
    )
  }

  private struct AdjustmentLimits {
    let minimum: Decimal
    let maximum: Decimal
    let increment: Decimal
  }

  private static func adjustmentLimits(
    state: WorkoutExecutionState,
    isSpeed: Bool
  ) -> AdjustmentLimits? {
    guard let armed = state.armedWorkout else { return nil }
    if isSpeed {
      guard case .supported(let range) = armed.capability.planCapabilities.speed else {
        return nil
      }
      return .init(
        minimum: range.minimum.value,
        maximum: min(range.maximum.value, armed.ceilings.maximumSpeed.value),
        increment: range.increment.value
      )
    }
    guard case .supported(let range) = armed.capability.planCapabilities.inclination else {
      return nil
    }
    return .init(
      minimum: range.minimum.value,
      maximum: min(range.maximum.value, armed.ceilings.maximumInclination.value),
      increment: range.increment.value
    )
  }

  private static func adjusted(
    _ value: Decimal?,
    by delta: Decimal?,
    limits: AdjustmentLimits?,
    state: WorkoutExecutionState
  ) -> Decimal? {
    guard adjustmentAllowed(state.execution), let value, let delta, let limits else {
      return nil
    }
    let candidate = value + delta
    guard candidate >= limits.minimum, candidate <= limits.maximum else { return nil }
    return candidate
  }

  private static func adjustmentAllowed(_ phase: WorkoutExecutionPhase) -> Bool {
    switch phase {
    case .waitingForPhysicalStart, .applyingTargets, .runningSegment,
      .checkingTreadmill, .paused, .restoringTargets:
      return true
    default:
      return false
    }
  }

  private static func evidence(
    state: WorkoutExecutionState,
    jointEffective: WorkoutTarget?,
    at now: MonotonicInstant,
    isSpeed: Bool
  ) -> WorkoutExerciseEvidenceStage {
    if telemetryIsStale(state.telemetry, at: now) { return .stale }
    if case .malformed = state.telemetry { return .failed }
    if case .contradictory = state.telemetry { return .failed }

    let record = state.procedure.activeRecord
    let recordMatchesAxis =
      record.map { record in
        switch record.intent {
        case .setTargetSpeed: isSpeed
        case .setTargetInclination: !isSpeed
        case .requestControl: false
        }
      } ?? false
    if recordMatchesAxis {
      switch state.procedure {
      case .intentCreated: return .requested
      case .submitted: return .submitted
      case .attAccepted: return .attAccepted
      case .failed: return .failed
      case .timedOutUnknown: return .unknown
      case .idle: break
      }
    }

    if let sequence = state.targetSequence {
      let acknowledged =
        isSpeed
        ? sequence.acknowledgedSpeed != nil
        : sequence.acknowledgedInclination != nil
      if acknowledged {
        if let jointEffective,
          sequence.acknowledgedSpeed == jointEffective.speed,
          sequence.acknowledgedInclination == jointEffective.inclination,
          sequence.finalAcknowledgementAt != nil,
          sequence.observationDeadline != nil
        {
          return .observing
        }
        return .ftmsAcknowledged
      }
    }

    if let jointEffective,
      let sample = telemetrySample(state.telemetry),
      sample.speed == jointEffective.speed,
      sample.inclination == jointEffective.inclination,
      state.telemetry.isFresh(at: now),
      [.running, .override, .paused, .readyToEnd, .finished].contains(stage(for: state))
    {
      return .confirmed
    }
    return .unknown
  }

  private static func evidenceDetail(
    _ evidence: WorkoutExerciseEvidenceStage,
    isSpeed: Bool
  ) -> String {
    let axis = isSpeed ? "speed" : "inclination"
    return switch evidence {
    case .requested: "A typed \(axis) intent exists; submission is not yet recorded."
    case .submitted: "The \(axis) procedure was submitted; ATT acceptance is not yet recorded."
    case .attAccepted: "ATT accepted the \(axis) write; FTMS has not yet acknowledged it."
    case .ftmsAcknowledged:
      "FTMS acknowledged \(axis); later treadmill observation is still required."
    case .observing: "Acknowledgements are complete; waiting for a later joint treadmill report."
    case .confirmed: "A later fresh treadmill report matches the effective \(axis) target."
    case .stale: "The last treadmill report is older than the accepted freshness window."
    case .failed: "Current \(axis) evidence is malformed, contradictory or procedurally failed."
    case .unknown: "No current evidence confirms the effective \(axis) target."
    }
  }

  private static func currentInterval(
    step: WorkoutStep?,
    index: Int?,
    count: Int,
    stage: WorkoutExerciseStage
  ) -> String {
    guard let step, let index else {
      return stage == .finished ? "Workout complete" : "Current interval unavailable"
    }
    return "Segment \(index + 1) of \(count) - \(step.label)"
  }

  private static func nextInterval(
    after index: Int?,
    steps: [WorkoutStep],
    locale: Locale
  ) -> String {
    guard let index, steps.indices.contains(index + 1) else { return "Final segment" }
    let step = steps[index + 1]
    return "Next: \(step.label), \(duration(step.duration.value)) at "
      + "\(measurement(step.targetSpeed.value, unit: "km/h", locale: locale)), "
      + measurement(step.targetInclination.value, unit: "%", locale: locale)
  }

  private static func elapsedInSegment(
    state: WorkoutExecutionState,
    at now: MonotonicInstant
  ) -> Int {
    guard let segment = state.currentSegment else { return 0 }
    var elapsed = segment.accumulatedActiveSeconds
    if let startedAt = segment.activeStartedAt {
      elapsed += max(0, now.seconds - startedAt.seconds)
    }
    return max(0, Int(floor(elapsed + 0.000_000_001)))
  }

  private static func elapsedTotal(
    state: WorkoutExecutionState,
    at now: MonotonicInstant
  ) -> Int {
    if currentSegmentIsIncludedInCompletedTotal(state) {
      return max(0, Int(floor(state.completedActiveSeconds + 0.000_000_001)))
    }
    return max(
      0, Int(floor(state.completedActiveSeconds + Double(elapsedInSegment(state: state, at: now)))))
  }

  private static func currentSegmentIsIncludedInCompletedTotal(
    _ state: WorkoutExecutionState
  ) -> Bool {
    switch state.execution {
    case .awaitingPhysicalStopForCompletion:
      return true
    case .checkingTreadmill(let checking):
      return checking.origin == .awaitingPhysicalStopForCompletion
    case .readyToEnd(let completion), .ending(let completion), .finished(let completion):
      return completion.reason == .completedPlan
    case .failed, .interrupted:
      guard let plan = state.armedWorkout?.plan.plan else { return false }
      let plannedTotal = plan.steps.reduce(0.0) {
        $0 + TimeInterval($1.duration.value)
      }
      return state.completedActiveSeconds >= plannedTotal
    default:
      return false
    }
  }

  private static func telemetrySample(
    _ telemetry: WorkoutTelemetryState
  ) -> WorkoutTelemetrySample? {
    switch telemetry {
    case .fresh(let sample), .stale(let sample): sample
    case .unavailable, .malformed, .contradictory: nil
    }
  }

  private static func telemetryIsStale(
    _ telemetry: WorkoutTelemetryState,
    at now: MonotonicInstant
  ) -> Bool {
    switch telemetry {
    case .stale:
      return true
    case .fresh(let sample):
      return now.seconds - sample.receivedAt.seconds
        > FR30zExecutionProfile.telemetryFreshnessInterval
    case .unavailable, .malformed, .contradictory:
      return false
    }
  }

  private static func summaryDistance(_ summary: WorkoutExecutionSummary) -> Decimal? {
    guard case .measured(let metres) = summary.distance else { return nil }
    return metres
  }

  private static func canConfirmOperatorStationary(
    _ state: WorkoutExecutionState,
    at now: MonotonicInstant
  ) -> Bool {
    guard state.motionPossible else { return false }
    if case .fresh(let sample) = state.telemetry,
      state.telemetry.isFresh(at: now),
      sample.speed.value > 0
    {
      return false
    }
    switch state.execution {
    case .applyingTargets, .runningSegment, .checkingTreadmill,
      .restoringTargets, .awaitingPhysicalStopForCompletion:
      return true
    default:
      return false
    }
  }

  private static func stationaryEvidenceIsCurrent(
    _ phase: WorkoutExecutionPhase,
    at now: MonotonicInstant
  ) -> Bool {
    let evidence: WorkoutStationaryEvidence
    switch phase {
    case .paused(let stationary):
      evidence = stationary
    case .readyToEnd(let completion):
      evidence = completion.stationaryEvidence
    default:
      return false
    }
    switch evidence {
    case .human:
      return true
    case .telemetry(let sample):
      return now.seconds - sample.receivedAt.seconds
        <= FR30zExecutionProfile.telemetryFreshnessInterval
    }
  }

  private static func duration(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = seconds % 3_600 / 60
    let remainder = seconds % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
      : String(format: "%d:%02d", minutes, remainder)
  }

  private static func measurement(
    _ value: Decimal,
    unit: String,
    locale: Locale
  ) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 2
    let text =
      formatter.string(from: NSDecimalNumber(decimal: value))
      ?? PlanValueFormatter.localizedText(value, locale: locale)
    return "\(text) \(unit)"
  }
}

extension WorkoutTelemetryState {
  fileprivate func isFresh(at now: MonotonicInstant) -> Bool {
    guard case .fresh(let sample) = self else { return false }
    let age = now.seconds - sample.receivedAt.seconds
    return age >= 0 && age <= FR30zExecutionProfile.telemetryFreshnessInterval
  }
}
