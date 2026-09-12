import Foundation

struct WorkoutOrchestrationTime: Equatable {
  let monotonic: MonotonicInstant
  let wallClock: Date
}

protocol WorkoutOrchestrationClock {
  func read() -> WorkoutOrchestrationTime
}

protocol WorkoutAttemptIDSource {
  func nextAttemptID() -> UUID
}

enum WorkoutTargetControlTransportEffect: Equatable {
  case submit(WorkoutProcedureRecord)
  /// Local cleanup only. It makes no claim that a submitted procedure was not delivered.
  case cancelAwaitingCallback(ProcedureID)
}

protocol WorkoutTargetControlTransport {
  func perform(_ effect: WorkoutTargetControlTransportEffect)
}

struct FrozenWorkoutAttemptInputs: Equatable {
  let attemptID: UUID
  let sourcePlanID: UUID?
  let plan: WorkoutPlanValidator.ValidatedPlan
  let capability: FR30zCapabilitySnapshot
  let ceilings: WorkoutSessionCeilings
  let profile: FR30zExecutionProfile
  let executionProfileIdentity: String
  let attemptedAt: Date
}

struct WorkoutOrchestrationTargetEvidence: Equatable {
  let planned: WorkoutTarget?
  let effective: WorkoutTarget?
  let latestReported: WorkoutTelemetrySample?
}

enum WorkoutHistoryCheckpointResult: Equatable {
  case notRequired
  case recorded(WorkoutExecutionSummary)
  case failed(WorkoutHistoryMutationFailure)
}

struct WorkoutOrchestrationResult: Equatable {
  let state: WorkoutExecutionState
  let reducerDisposition: WorkoutReductionDisposition
  let reducerEffects: [WorkoutExecutionEffect]
  let transportEffects: [WorkoutTargetControlTransportEffect]
  let historyCheckpoint: WorkoutHistoryCheckpointResult
}

enum WorkoutHistoryRecoveryResult: Equatable {
  case nothingToRecover
  case recovered([WorkoutExecutionSummary])
  case blocked(WorkoutHistoryRepositoryStatus)
  case failed(summaryID: UUID, failure: WorkoutHistoryMutationFailure)
}

/// Software-only issue #59 integration boundary. Time, identifiers, history and
/// target-control delivery are injected; this type owns no CoreBluetooth client,
/// timer, UI or physical-device route.
@MainActor
final class WorkoutExecutionOrchestrator {
  private enum CheckpointPhase: Equatable {
    case acquiringControl
    case waitingForPhysicalStart
    case applyingTargets
    case running
    case checking
    case paused
    case restoringTargets
    case awaitingPhysicalStop
    case readyToEnd
    case ending
    case finished
    case interrupted
    case failed
  }

  private struct CheckpointTrigger: Equatable {
    let outcome: WorkoutExecutionOutcome
    let activeDuration: WorkoutActiveDuration
    let progress: WorkoutExecutionProgress
    let physicalStopConfirmation: WorkoutPhysicalStopConfirmation
    let phase: CheckpointPhase
  }

  private struct PreparedInputs {
    let sourcePlanID: UUID?
  }

  private let reducer: WorkoutExecutionReducer
  private let transport: any WorkoutTargetControlTransport
  private let history: any WorkoutHistoryRepositoryProtocol
  private let clock: any WorkoutOrchestrationClock
  private let attemptIDs: any WorkoutAttemptIDSource

  private var preparedInputs: PreparedInputs?
  private var latestDistance: WorkoutDistance = .unavailable(
    reason: .init(rawValue: "distance-not-yet-measured"))
  private var humanStationaryDate: Date?
  private var lastCheckpointTrigger: CheckpointTrigger?
  private var forwardedProcedureIDs: Set<ProcedureID> = []

  private(set) var state = WorkoutExecutionState()
  private(set) var frozenAttempt: FrozenWorkoutAttemptInputs?
  private(set) var lastPersistedSummary: WorkoutExecutionSummary?

  init(
    reducer: WorkoutExecutionReducer = .init(),
    transport: any WorkoutTargetControlTransport,
    history: any WorkoutHistoryRepositoryProtocol,
    clock: any WorkoutOrchestrationClock,
    attemptIDs: any WorkoutAttemptIDSource
  ) {
    self.reducer = reducer
    self.transport = transport
    self.history = history
    self.clock = clock
    self.attemptIDs = attemptIDs
  }

  @discardableResult
  func arm(
    plan: WorkoutPlanValidator.ValidatedPlan,
    ceilings: WorkoutSessionCeilings,
    profile: FR30zExecutionProfile,
    sourcePlanID: UUID?
  ) -> WorkoutOrchestrationResult {
    process(
      .arm(plan: plan, ceilings: ceilings, profile: profile),
      preparedInputs: .init(sourcePlanID: sourcePlanID)
    )
  }

  @discardableResult
  func handle(_ event: WorkoutExecutionEvent) -> WorkoutOrchestrationResult {
    process(event, preparedInputs: nil)
  }

  @discardableResult
  func cancelAttempt(epoch: ConnectionEpoch) -> WorkoutOrchestrationResult {
    process(
      .appBecameInactive(epoch: epoch, reason: "User cancelled synthetic attempt"),
      preparedInputs: nil
    )
  }

  var targetEvidence: WorkoutOrchestrationTargetEvidence {
    let stepIndex = state.currentSegment?.stepIndex
    let step = stepIndex.flatMap { index in
      state.armedWorkout?.plan.plan.steps.indices.contains(index) == true
        ? state.armedWorkout?.plan.plan.steps[index] : nil
    }
    let planned = step.map {
      WorkoutTarget(speed: $0.targetSpeed, inclination: $0.targetInclination)
    }
    let effective: WorkoutTarget? = step.flatMap { step in
      guard let segment = state.currentSegment else { return nil }
      return WorkoutTarget(
        speed: segment.speedOverride ?? step.targetSpeed,
        inclination: segment.inclinationOverride ?? step.targetInclination
      )
    }
    return .init(planned: planned, effective: effective, latestReported: telemetrySample(state))
  }

  @discardableResult
  func recoverInterruptedHistory() -> WorkoutHistoryRecoveryResult {
    let status = history.list()
    let summaries: [WorkoutExecutionSummary]
    switch status.canonical {
    case .empty:
      return status.staging == .absent ? .nothingToRecover : .blocked(status)
    case .available(let available):
      guard status.staging == .absent else { return .blocked(status) }
      summaries = available
    case .protectedDataUnavailable, .readFailure, .corruptData, .partialWriteDetected,
      .unsupportedStoreVersion, .unsupportedSummaryVersion, .unsupportedPlanVersion:
      return .blocked(status)
    }

    let reading = clock.read()
    var recovered: [WorkoutExecutionSummary] = []
    for summary in summaries where summary.outcome == .inProgress {
      let updated = WorkoutExecutionSummary(
        id: summary.id,
        schemaVersion: summary.schemaVersion,
        sourcePlanID: summary.sourcePlanID,
        planSnapshot: summary.planSnapshot,
        attemptedAt: summary.attemptedAt,
        lastUpdatedAt: max(summary.lastUpdatedAt, reading.wallClock),
        outcome: .interrupted(reason: .init(rawValue: "app-continuity-lost")),
        activeDuration: summary.activeDuration,
        distance: summary.distance,
        progress: summary.progress,
        physicalStopConfirmation: recoveredStopConfirmation(
          summary.physicalStopConfirmation)
      )
      do {
        try history.record(updated)
        recovered.append(updated)
      } catch let failure as WorkoutHistoryMutationFailure {
        return .failed(summaryID: summary.id, failure: failure)
      } catch {
        return .failed(
          summaryID: summary.id,
          failure: .unexpectedRepositoryFailure
        )
      }
    }
    return recovered.isEmpty ? .nothingToRecover : .recovered(recovered)
  }

  private func process(
    _ event: WorkoutExecutionEvent,
    preparedInputs newPreparedInputs: PreparedInputs?
  ) -> WorkoutOrchestrationResult {
    let reading = clock.read()
    let original = state
    let transition = reducer.reduce(original, event, at: reading.monotonic)

    guard
      transition.disposition == .accepted
        || isFailedClosed(transition.disposition)
    else {
      return .init(
        state: state,
        reducerDisposition: transition.disposition,
        reducerEffects: transition.effects,
        transportEffects: [],
        historyCheckpoint: .notRequired
      )
    }

    if case .userStartsConnection = event, transition.disposition == .accepted {
      resetAttemptContext()
    }
    if case .arm = event, transition.disposition == .accepted {
      preparedInputs = newPreparedInputs ?? .init(sourcePlanID: nil)
    }

    if case .beginWorkout = event, transition.disposition == .accepted, frozenAttempt == nil {
      guard let armed = transition.state.armedWorkout else {
        return unchangedResult(
          original: original,
          transition: transition,
          failure: .unexpectedRepositoryFailure
        )
      }
      let attemptedAt = reading.wallClock
      frozenAttempt = .init(
        attemptID: attemptIDs.nextAttemptID(),
        sourcePlanID: preparedInputs?.sourcePlanID,
        plan: armed.plan,
        capability: armed.capability,
        ceilings: armed.ceilings,
        profile: armed.profile,
        executionProfileIdentity: FR30zExecutionProfile.identity,
        attemptedAt: attemptedAt
      )
      latestDistance = .unavailable(reason: .init(rawValue: "distance-not-yet-measured"))
      humanStationaryDate = nil
      let summary = makeSummary(from: transition.state, updatedAt: reading.wallClock)
      do {
        try history.record(summary)
      } catch let failure as WorkoutHistoryMutationFailure {
        frozenAttempt = nil
        return unchangedResult(original: original, transition: transition, failure: failure)
      } catch {
        frozenAttempt = nil
        return unchangedResult(
          original: original,
          transition: transition,
          failure: .unexpectedRepositoryFailure
        )
      }
      state = transition.state
      lastPersistedSummary = summary
      lastCheckpointTrigger = checkpointTrigger(for: summary, state: transition.state)
      let transportEffects = performTransportEffects(transition.effects)
      return .init(
        state: state,
        reducerDisposition: transition.disposition,
        reducerEffects: transition.effects,
        transportEffects: transportEffects,
        historyCheckpoint: .recorded(summary)
      )
    }

    updateEphemeralEvidence(event: event, transition: transition, reading: reading)

    if transition.effects.contains(where: isLocalFinalizationEffect) {
      return finalizeLocally(
        original: original,
        transition: transition,
        reading: reading
      )
    }

    var checkpoint: WorkoutHistoryCheckpointResult = .notRequired
    if frozenAttempt != nil {
      let summary = makeSummary(from: transition.state, updatedAt: reading.wallClock)
      let trigger = checkpointTrigger(for: summary, state: transition.state)
      if trigger != lastCheckpointTrigger {
        do {
          try history.record(summary)
          checkpoint = .recorded(summary)
          lastPersistedSummary = summary
          lastCheckpointTrigger = trigger
        } catch let failure as WorkoutHistoryMutationFailure {
          return failForHistoryWrite(
            from: transition,
            original: original,
            reading: reading,
            failure: failure
          )
        } catch {
          return failForHistoryWrite(
            from: transition,
            original: original,
            reading: reading,
            failure: .unexpectedRepositoryFailure
          )
        }
      }
    }

    state = transition.state
    let transportEffects = performTransportEffects(transition.effects)
    if isTerminal(state.execution),
      let procedureID = forwardedProcedureID(original),
      procedureBecameUnknown(state)
    {
      let cancellation = WorkoutTargetControlTransportEffect.cancelAwaitingCallback(procedureID)
      transport.perform(cancellation)
      return .init(
        state: state,
        reducerDisposition: transition.disposition,
        reducerEffects: transition.effects,
        transportEffects: transportEffects + [cancellation],
        historyCheckpoint: checkpoint
      )
    }
    return .init(
      state: state,
      reducerDisposition: transition.disposition,
      reducerEffects: transition.effects,
      transportEffects: transportEffects,
      historyCheckpoint: checkpoint
    )
  }

  private func finalizeLocally(
    original: WorkoutExecutionState,
    transition: WorkoutExecutionTransition,
    reading: WorkoutOrchestrationTime
  ) -> WorkoutOrchestrationResult {
    guard let epoch = transition.state.connection.epoch else {
      return unchangedResult(
        original: original,
        transition: transition,
        failure: .unexpectedRepositoryFailure
      )
    }
    let completed = reducer.reduce(
      transition.state,
      .localEndingSucceeded(epoch: epoch),
      at: reading.monotonic
    )
    guard completed.disposition == .accepted else {
      state = completed.state
      return .init(
        state: state,
        reducerDisposition: completed.disposition,
        reducerEffects: transition.effects + completed.effects,
        transportEffects: [],
        historyCheckpoint: .notRequired
      )
    }
    let summary = makeSummary(from: completed.state, updatedAt: reading.wallClock)
    do {
      try history.record(summary)
      state = completed.state
      lastPersistedSummary = summary
      lastCheckpointTrigger = checkpointTrigger(for: summary, state: completed.state)
      return .init(
        state: state,
        reducerDisposition: completed.disposition,
        reducerEffects: transition.effects + completed.effects,
        transportEffects: [],
        historyCheckpoint: .recorded(summary)
      )
    } catch let failure as WorkoutHistoryMutationFailure {
      return localFinalizationFailed(
        transition: transition,
        reading: reading,
        failure: failure
      )
    } catch {
      return localFinalizationFailed(
        transition: transition,
        reading: reading,
        failure: .unexpectedRepositoryFailure
      )
    }
  }

  private func localFinalizationFailed(
    transition: WorkoutExecutionTransition,
    reading: WorkoutOrchestrationTime,
    failure: WorkoutHistoryMutationFailure
  ) -> WorkoutOrchestrationResult {
    let epoch = transition.state.connection.epoch!
    let failed = reducer.reduce(
      transition.state,
      .localEndingFailed(epoch: epoch, reason: "History finalization failed"),
      at: reading.monotonic
    )
    state = failed.state
    return .init(
      state: state,
      reducerDisposition: failed.disposition,
      reducerEffects: transition.effects + failed.effects,
      transportEffects: [],
      historyCheckpoint: .failed(failure)
    )
  }

  private func failForHistoryWrite(
    from transition: WorkoutExecutionTransition,
    original: WorkoutExecutionState,
    reading: WorkoutOrchestrationTime,
    failure: WorkoutHistoryMutationFailure
  ) -> WorkoutOrchestrationResult {
    guard let epoch = transition.state.connection.epoch else {
      return unchangedResult(original: original, transition: transition, failure: failure)
    }
    let definitelyNotSubmittedProcedureID = transition.effects.lazy.compactMap {
      effect -> ProcedureID? in
      guard case .submit(let record) = effect else { return nil }
      return record.id
    }.first
    let failed = reducer.reduce(
      transition.state,
      .localHistoryPersistenceFailed(
        epoch: epoch,
        reason: "Incremental history write failed",
        definitelyNotSubmittedProcedureID: definitelyNotSubmittedProcedureID
      ),
      at: reading.monotonic
    )
    state = failed.state
    var transportEffects: [WorkoutTargetControlTransportEffect] = []
    if let procedureID = forwardedProcedureID(transition.state), procedureBecameUnknown(state) {
      let cancellation = WorkoutTargetControlTransportEffect.cancelAwaitingCallback(procedureID)
      transport.perform(cancellation)
      transportEffects.append(cancellation)
    }
    return .init(
      state: state,
      reducerDisposition: failed.disposition,
      reducerEffects: failed.effects,
      transportEffects: transportEffects,
      historyCheckpoint: .failed(failure)
    )
  }

  private func unchangedResult(
    original: WorkoutExecutionState,
    transition: WorkoutExecutionTransition,
    failure: WorkoutHistoryMutationFailure
  ) -> WorkoutOrchestrationResult {
    state = original
    return .init(
      state: state,
      reducerDisposition: transition.disposition,
      reducerEffects: [],
      transportEffects: [],
      historyCheckpoint: .failed(failure)
    )
  }

  private func updateEphemeralEvidence(
    event: WorkoutExecutionEvent,
    transition: WorkoutExecutionTransition,
    reading: WorkoutOrchestrationTime
  ) {
    switch transition.state.observedMachine {
    case .reportedMoving, .humanObservedMoving:
      humanStationaryDate = nil
    case .targetReported(_, let sample) where sample.speed.value > 0:
      humanStationaryDate = nil
    default:
      break
    }
    if transition.disposition == .accepted,
      case .humanConfirmsStationary = event,
      case .humanConfirmedStationary = transition.state.observedMachine
    {
      humanStationaryDate = reading.wallClock
    }
    if transition.disposition == .accepted,
      case .fresh(let sample) = transition.state.telemetry,
      let metres = sample.totalDistanceMetres,
      !metres.isNaN,
      metres >= 0
    {
      latestDistance = .measured(metres: metres)
    }
  }

  private func makeSummary(
    from state: WorkoutExecutionState,
    updatedAt: Date
  ) -> WorkoutExecutionSummary {
    let attempt = frozenAttempt!
    return .init(
      id: attempt.attemptID,
      schemaVersion: WorkoutExecutionSummarySchema.currentVersion,
      sourcePlanID: attempt.sourcePlanID,
      planSnapshot: attempt.plan.plan,
      attemptedAt: attempt.attemptedAt,
      lastUpdatedAt: max(attempt.attemptedAt, updatedAt),
      outcome: historyOutcome(state.execution),
      activeDuration: .measured(seconds: measuredTotalSeconds(state)),
      distance: latestDistance,
      progress: progress(state),
      physicalStopConfirmation: stopConfirmation(state.execution)
    )
  }

  private func historyOutcome(_ phase: WorkoutExecutionPhase) -> WorkoutExecutionOutcome {
    switch phase {
    case .finished(let context):
      switch context.reason {
      case .completedPlan:
        return .completed
      case .endedFromPause:
        return .stoppedByUser(reason: .init(rawValue: "ended-from-accepted-pause"))
      }
    case .interrupted(let reason):
      return .interrupted(reason: .init(rawValue: interruptionCode(reason)))
    case .failed(let reason):
      return .failed(reason: .init(rawValue: failureCode(reason)))
    default:
      return .inProgress
    }
  }

  private func interruptionCode(_ reason: WorkoutInterruption) -> String {
    switch reason {
    case .telemetryUnavailable: "telemetry-unavailable"
    case .telemetryStreamTimedOut: "telemetry-stream-timed-out"
    case .stationaryEvidenceExpired: "stationary-evidence-expired"
    case .connectionLost: "connection-lost"
    case .foregroundLost(let detail):
      detail == "User cancelled synthetic attempt" ? "attempt-cancelled" : "app-continuity-lost"
    case .controlPermissionLost: "control-permission-lost"
    case .profileChanged: "profile-changed"
    case .resumeGuardsFailed: "resume-guards-failed"
    }
  }

  private func failureCode(_ reason: WorkoutExecutionFailure) -> String {
    switch reason {
    case .procedure(let procedure): procedureFailureCode(procedure)
    case .malformedTelemetry: "telemetry-malformed"
    case .incompleteTelemetry: "telemetry-incomplete"
    case .contradictoryEvidence: "evidence-contradictory"
    case .targetObservationTimeout: "target-observation-timed-out"
    case .localHistoryPersistence: "history-persistence-failed"
    case .localFinalization: "history-finalization-failed"
    }
  }

  private func procedureFailureCode(_ failure: WorkoutProcedureFailure) -> String {
    switch failure {
    case .notSubmitted: "procedure-not-submitted"
    case .submissionRejected: "procedure-submission-rejected"
    case .attRejected: "procedure-att-rejected"
    case .protocolRejected: "procedure-ftms-rejected"
    case .protocolUnsupported: "procedure-ftms-unsupported"
    case .protocolMalformed: "procedure-ftms-malformed"
    case .protocolUnknown: "procedure-ftms-unknown"
    case .correlationFailure: "procedure-correlation-failed"
    case .duplicateOrLate: "procedure-duplicate-or-late"
    case .responseTimeout: "procedure-response-timed-out"
    }
  }

  private func measuredTotalSeconds(_ state: WorkoutExecutionState) -> Int {
    var total = state.completedActiveSeconds
    if let segment = state.currentSegment {
      total += segment.accumulatedActiveSeconds
      if let startedAt = segment.activeStartedAt {
        total += max(0, state.lastEventTime.seconds - startedAt.seconds)
      }
      if segment.accumulatedActiveSeconds > 0,
        state.completedActiveSeconds >= segment.accumulatedActiveSeconds,
        activePlanIsComplete(state)
      {
        total -= segment.accumulatedActiveSeconds
      }
    }
    return max(0, Int(floor(total + 0.000_000_001)))
  }

  private func progress(_ state: WorkoutExecutionState) -> WorkoutExecutionProgress {
    guard let attempt = frozenAttempt, let segment = state.currentSegment else {
      return .init(completedStepCount: 0, currentStepIndex: nil, activeSecondsInCurrentStep: 0)
    }
    if activePlanIsComplete(state) {
      return .init(
        completedStepCount: attempt.plan.plan.steps.count,
        currentStepIndex: nil,
        activeSecondsInCurrentStep: 0
      )
    }
    var active = segment.accumulatedActiveSeconds
    if let startedAt = segment.activeStartedAt {
      active += max(0, state.lastEventTime.seconds - startedAt.seconds)
    }
    return .init(
      completedStepCount: segment.stepIndex,
      currentStepIndex: segment.stepIndex,
      activeSecondsInCurrentStep: max(0, Int(floor(active + 0.000_000_001)))
    )
  }

  private func activePlanIsComplete(_ state: WorkoutExecutionState) -> Bool {
    guard let attempt = frozenAttempt else { return false }
    let plannedSeconds = attempt.plan.plan.steps.reduce(0.0) {
      $0 + TimeInterval($1.duration.value)
    }
    return state.completedActiveSeconds + 0.000_000_001 >= plannedSeconds
  }

  private func stopConfirmation(
    _ phase: WorkoutExecutionPhase
  ) -> WorkoutPhysicalStopConfirmation {
    if let date = humanStationaryDate { return .humanConfirmed(at: date) }
    switch phase {
    case .interrupted, .failed:
      return .unconfirmed
    default:
      return .notRequired
    }
  }

  private func checkpointTrigger(
    for summary: WorkoutExecutionSummary,
    state: WorkoutExecutionState
  ) -> CheckpointTrigger {
    .init(
      outcome: summary.outcome,
      activeDuration: summary.activeDuration,
      progress: summary.progress,
      physicalStopConfirmation: summary.physicalStopConfirmation,
      phase: checkpointPhase(state.execution)
    )
  }

  private func checkpointPhase(_ phase: WorkoutExecutionPhase) -> CheckpointPhase {
    switch phase {
    case .idle, .preflight: .acquiringControl
    case .acquiringControl: .acquiringControl
    case .waitingForPhysicalStart: .waitingForPhysicalStart
    case .applyingTargets: .applyingTargets
    case .runningSegment: .running
    case .checkingTreadmill: .checking
    case .paused: .paused
    case .restoringTargets: .restoringTargets
    case .awaitingPhysicalStopForCompletion: .awaitingPhysicalStop
    case .readyToEnd: .readyToEnd
    case .ending: .ending
    case .finished: .finished
    case .interrupted: .interrupted
    case .failed: .failed
    }
  }

  private func performTransportEffects(
    _ effects: [WorkoutExecutionEffect]
  ) -> [WorkoutTargetControlTransportEffect] {
    let transportEffects = effects.compactMap { effect -> WorkoutTargetControlTransportEffect? in
      guard case .submit(let record) = effect else { return nil }
      return .submit(record)
    }
    for effect in transportEffects {
      if case .submit(let record) = effect { forwardedProcedureIDs.insert(record.id) }
      transport.perform(effect)
    }
    return transportEffects
  }

  private func forwardedProcedureID(_ state: WorkoutExecutionState) -> ProcedureID? {
    guard let id = state.procedure.activeRecord?.id, forwardedProcedureIDs.contains(id) else {
      return nil
    }
    return id
  }

  private func procedureBecameUnknown(_ state: WorkoutExecutionState) -> Bool {
    if case .timedOutUnknown = state.procedure { return true }
    return false
  }

  private func telemetrySample(_ state: WorkoutExecutionState) -> WorkoutTelemetrySample? {
    switch state.telemetry {
    case .fresh(let sample), .stale(let sample): sample
    case .unavailable, .malformed, .contradictory: nil
    }
  }

  private func isLocalFinalizationEffect(_ effect: WorkoutExecutionEffect) -> Bool {
    if case .finalizeLocally = effect { return true }
    return false
  }

  private func isFailedClosed(_ disposition: WorkoutReductionDisposition) -> Bool {
    if case .failedClosed = disposition { return true }
    return false
  }

  private func isTerminal(_ phase: WorkoutExecutionPhase) -> Bool {
    switch phase {
    case .finished, .interrupted, .failed: true
    default: false
    }
  }

  private func resetAttemptContext() {
    preparedInputs = nil
    frozenAttempt = nil
    lastPersistedSummary = nil
    latestDistance = .unavailable(reason: .init(rawValue: "distance-not-yet-measured"))
    humanStationaryDate = nil
    lastCheckpointTrigger = nil
    forwardedProcedureIDs = []
  }

  private func recoveredStopConfirmation(
    _ confirmation: WorkoutPhysicalStopConfirmation
  ) -> WorkoutPhysicalStopConfirmation {
    switch confirmation {
    case .humanConfirmed:
      confirmation
    case .notRequired, .unconfirmed:
      .unconfirmed
    }
  }
}
