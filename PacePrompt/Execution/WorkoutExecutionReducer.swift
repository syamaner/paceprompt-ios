import Foundation

struct MonotonicInstant: Equatable, Comparable {
  let seconds: TimeInterval

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.seconds < rhs.seconds }

  func advanced(by interval: TimeInterval) -> Self {
    .init(seconds: seconds + interval)
  }
}

struct ConnectionEpoch: Equatable, Hashable {
  let rawValue: UInt64
}

struct ProcedureID: Equatable, Hashable {
  let epoch: ConnectionEpoch
  let sequence: UInt64
}

enum FR30zProfileEvidence: Equatable {
  case unavailable
  case mismatch
  case matched
}

struct FR30zCapabilitySnapshot: Equatable {
  let peripheralIdentity: String
  let equipmentIdentity: String
  let fitnessMachineServicePresent: Bool
  let requiredCharacteristicPropertiesMatch: Bool
  let fitnessMachineFeatureEvidence: FR30zProfileEvidence
  let supportedSpeedRangeEvidence: FR30zProfileEvidence
  let supportedInclinationRangeEvidence: FR30zProfileEvidence
  let treadmillDataNotificationsEnabled: Bool
  let controlPointIndicationsEnabled: Bool
  let optionalSubscriptionOutcomesResolved: Bool
  let planCapabilities: WorkoutPlanCapabilities
}

struct WorkoutSessionCeilings: Equatable {
  let maximumSpeed: WorkoutSpeed
  let maximumInclination: WorkoutInclination
  let maximumStepSpeedChange: WorkoutSpeed
}

/// The immutable issue #57 product policy. It deliberately has no Start, Stop,
/// Pause, retry, reconnect, or control-reacquisition option.
struct FR30zExecutionProfile: Equatable {
  static let identity = "fr30z-physical-console-v1"
  static let telemetryFreshnessInterval: TimeInterval = 2
  static let telemetryCheckingInterval: TimeInterval = 10
  static let targetObservationInterval: TimeInterval = 30
  static let procedureResponseInterval: TimeInterval = 30

  let peripheralIdentity: String
  let equipmentIdentity: String

  var isComplete: Bool {
    !peripheralIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !equipmentIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func matches(_ capability: FR30zCapabilitySnapshot) -> Bool {
    isComplete
      && capability.peripheralIdentity == peripheralIdentity
      && capability.equipmentIdentity == equipmentIdentity
      && capability.fitnessMachineServicePresent
      && capability.requiredCharacteristicPropertiesMatch
      && capability.fitnessMachineFeatureEvidence == .matched
      && capability.supportedSpeedRangeEvidence == .matched
      && capability.supportedInclinationRangeEvidence == .matched
      && capability.treadmillDataNotificationsEnabled
      && capability.controlPointIndicationsEnabled
      && capability.optionalSubscriptionOutcomesResolved
      && capability.planCapabilities == Self.acceptedPlanCapabilities
  }

  private static var acceptedPlanCapabilities: WorkoutPlanCapabilities {
    .init(
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
  }
}

struct WorkoutOperatorReadiness: Equatable {
  let deckClear: Bool
  let consoleImmediatelyReachable: Bool
  let safetyKeyImmediatelyReachable: Bool
  let physicallyStationary: Bool

  var isConfirmed: Bool {
    deckClear && consoleImmediatelyReachable && safetyKeyImmediatelyReachable
      && physicallyStationary
  }
}

struct WorkoutTarget: Equatable {
  let speed: WorkoutSpeed
  let inclination: WorkoutInclination
}

enum WorkoutControlPointIntent: Equatable {
  case requestControl
  case setTargetSpeed(WorkoutSpeed)
  case setTargetInclination(WorkoutInclination)
}

struct WorkoutProcedureRecord: Equatable {
  let id: ProcedureID
  let intent: WorkoutControlPointIntent
  let stepIndex: Int?
  let createdAt: MonotonicInstant
  var submittedAt: MonotonicInstant?
  var attAcceptedAt: MonotonicInstant?
  var ftmsAcknowledgedAt: MonotonicInstant?
}

enum WorkoutProcedureFailure: Equatable {
  case submissionRejected(String)
  case attRejected(String)
  case protocolRejected(String)
  case protocolUnsupported
  case protocolMalformed
  case protocolUnknown
  case correlationFailure(expected: ProcedureID, received: ProcedureID)
  case duplicateOrLate(ProcedureID)
  case responseTimeout
}

enum WorkoutProcedureState: Equatable {
  case idle
  case intentCreated(WorkoutProcedureRecord)
  case submitted(WorkoutProcedureRecord)
  case attAccepted(record: WorkoutProcedureRecord, deadline: MonotonicInstant)
  case failed(record: WorkoutProcedureRecord, failure: WorkoutProcedureFailure)
  case timedOutUnknown(record: WorkoutProcedureRecord)

  var activeRecord: WorkoutProcedureRecord? {
    switch self {
    case .idle:
      nil
    case .intentCreated(let record), .submitted(let record), .attAccepted(let record, _),
      .failed(let record, _), .timedOutUnknown(let record):
      record
    }
  }

  var unresolvedRecord: WorkoutProcedureRecord? {
    switch self {
    case .intentCreated(let record), .submitted(let record), .attAccepted(let record, _):
      record
    case .idle, .failed, .timedOutUnknown:
      nil
    }
  }
}

enum WorkoutProcedureOutcome: Equatable {
  case acknowledged(
    record: WorkoutProcedureRecord,
    attAcceptedAt: MonotonicInstant,
    ftmsAcknowledgedAt: MonotonicInstant
  )
  case failed(WorkoutProcedureRecord, WorkoutProcedureFailure)
  case timedOutUnknown(WorkoutProcedureRecord)
}

enum WorkoutControlPermission: Equatable {
  case notHeld
  case requesting(ProcedureID)
  case held(epoch: ConnectionEpoch, acknowledgedAt: MonotonicInstant)
  case invalidated(String)
}

enum WorkoutConnectionState: Equatable {
  case disconnected
  case connecting(ConnectionEpoch)
  case ready(epoch: ConnectionEpoch, capability: FR30zCapabilitySnapshot)
  case lost(previousEpoch: ConnectionEpoch, reason: String)
  case invalidated(previousEpoch: ConnectionEpoch, reason: String)

  var epoch: ConnectionEpoch? {
    switch self {
    case .disconnected:
      nil
    case .connecting(let epoch), .ready(let epoch, _), .lost(let epoch, _),
      .invalidated(let epoch, _):
      epoch
    }
  }

  var readyCapability: FR30zCapabilitySnapshot? {
    guard case .ready(_, let capability) = self else { return nil }
    return capability
  }
}

struct WorkoutTelemetrySample: Equatable {
  let speed: WorkoutSpeed
  let inclination: WorkoutInclination
  let totalDistanceMetres: Decimal?
  let receivedAt: MonotonicInstant
}

enum WorkoutTelemetryInput: Equatable {
  case sample(speed: WorkoutSpeed?, inclination: WorkoutInclination?, totalDistanceMetres: Decimal?)
  case unavailable(String)
  case malformed(String)
}

enum WorkoutTelemetryState: Equatable {
  case unavailable(String)
  case fresh(WorkoutTelemetrySample)
  case stale(WorkoutTelemetrySample)
  case malformed(String)
  case contradictory(String)
}

struct WorkoutHumanStationaryEvidence: Equatable {
  let confirmedAt: MonotonicInstant
  let note: String
}

struct WorkoutHumanMotionEvidence: Equatable {
  let observedAt: MonotonicInstant
  let note: String
}

enum WorkoutStationaryEvidence: Equatable {
  case telemetry(WorkoutTelemetrySample)
  case human(WorkoutHumanStationaryEvidence)
}

enum WorkoutObservedMachineState: Equatable {
  case unknown
  case reportedStationary(WorkoutTelemetrySample)
  case reportedMoving(WorkoutTelemetrySample)
  case targetReported(stepIndex: Int, sample: WorkoutTelemetrySample)
  case humanConfirmedStationary(WorkoutHumanStationaryEvidence)
  case humanObservedMoving(WorkoutHumanMotionEvidence)
}

struct ArmedWorkout: Equatable {
  let plan: WorkoutPlanValidator.ValidatedPlan
  let capability: FR30zCapabilitySnapshot
  let ceilings: WorkoutSessionCeilings
  let profile: FR30zExecutionProfile
}

struct WorkoutCurrentSegment: Equatable {
  let stepIndex: Int
  var accumulatedActiveSeconds: TimeInterval
  var activeStartedAt: MonotonicInstant?
  var speedOverride: WorkoutSpeed?
  var inclinationOverride: WorkoutInclination?
}

enum WorkoutTargetSequencePurpose: Equatable {
  case initial
  case plannedTransition
  case manualAdjustment
  case returnToPlan
  case resumeRestoration
}

struct WorkoutTargetSequence: Equatable {
  let purpose: WorkoutTargetSequencePurpose
  let stepIndex: Int
  let startedAt: MonotonicInstant
  var forceSpeed: Bool
  var forceInclination: Bool
  var acknowledgedSpeed: WorkoutSpeed?
  var acknowledgedInclination: WorkoutInclination?
  var finalAcknowledgementAt: MonotonicInstant?
  var observationDeadline: MonotonicInstant?
}

enum WorkoutCheckingOrigin: Equatable {
  case waitingForPhysicalStart
  case applyingTargets(WorkoutTargetSequencePurpose)
  case runningSegment
  case paused(WorkoutStationaryEvidence)
  case restoringTargets
  case awaitingPhysicalStopForCompletion
}

struct WorkoutCheckingState: Equatable {
  let origin: WorkoutCheckingOrigin
  let freshnessBoundary: MonotonicInstant
  let interruptionDeadline: MonotonicInstant
}

enum WorkoutCompletionReason: Equatable {
  case completedPlan
  case endedFromPause
}

struct WorkoutCompletionContext: Equatable {
  let reason: WorkoutCompletionReason
  let stepIndex: Int
  let totalActiveSeconds: TimeInterval
  let stationaryEvidence: WorkoutStationaryEvidence

  func replacingStationaryEvidence(
    with evidence: WorkoutStationaryEvidence
  ) -> WorkoutCompletionContext {
    .init(
      reason: reason,
      stepIndex: stepIndex,
      totalActiveSeconds: totalActiveSeconds,
      stationaryEvidence: evidence
    )
  }
}

enum WorkoutInterruption: Equatable {
  case telemetryUnavailable(String)
  case telemetryStreamTimedOut
  case stationaryEvidenceExpired
  case connectionLost(String)
  case foregroundLost(String)
  case controlPermissionLost(String)
  case profileChanged
  case resumeGuardsFailed
}

enum WorkoutExecutionFailure: Equatable {
  case procedure(WorkoutProcedureFailure)
  case malformedTelemetry(String)
  case incompleteTelemetry
  case contradictoryEvidence(String)
  case targetObservationTimeout
  case localFinalization(String)
}

enum WorkoutTerminalReason: Equatable {
  case interrupted(WorkoutInterruption)
  case failed(WorkoutExecutionFailure)
}

enum WorkoutExecutionPhase: Equatable {
  case idle
  case preflight
  case acquiringControl
  case waitingForPhysicalStart
  case applyingTargets(WorkoutTargetSequencePurpose)
  case runningSegment
  case checkingTreadmill(WorkoutCheckingState)
  case paused(WorkoutStationaryEvidence)
  case restoringTargets
  case awaitingPhysicalStopForCompletion
  case readyToEnd(WorkoutCompletionContext)
  case ending(WorkoutCompletionContext)
  case finished(WorkoutCompletionContext)
  case interrupted(WorkoutInterruption)
  case failed(WorkoutExecutionFailure)
}

struct WorkoutExecutionState: Equatable {
  var connection: WorkoutConnectionState = .disconnected
  var controlPermission: WorkoutControlPermission = .notHeld
  var procedure: WorkoutProcedureState = .idle
  var procedureHistory: [WorkoutProcedureOutcome] = []
  var telemetry: WorkoutTelemetryState = .unavailable("No current telemetry")
  var observedMachine: WorkoutObservedMachineState = .unknown
  var execution: WorkoutExecutionPhase = .idle
  var armedWorkout: ArmedWorkout?
  var currentSegment: WorkoutCurrentSegment?
  var targetSequence: WorkoutTargetSequence?
  var lastConfirmedTarget: WorkoutTarget?
  var completedActiveSeconds: TimeInterval = 0
  var motionPossible = false
  var isForegroundActive = true
  var nextProcedureSequence: UInt64 = 1
  var lastEventTime = MonotonicInstant(seconds: 0)
}

enum WorkoutExecutionEvent: Equatable {
  case userStartsConnection(ConnectionEpoch)
  case connectionBecomesReady(epoch: ConnectionEpoch, capability: FR30zCapabilitySnapshot)
  case arm(
    plan: WorkoutPlanValidator.ValidatedPlan, ceilings: WorkoutSessionCeilings,
    profile: FR30zExecutionProfile)
  case beginWorkout(epoch: ConnectionEpoch, readiness: WorkoutOperatorReadiness)
  case intentSubmitted(epoch: ConnectionEpoch, procedureID: ProcedureID)
  case intentSubmissionRejected(epoch: ConnectionEpoch, procedureID: ProcedureID, reason: String)
  case attAccepted(epoch: ConnectionEpoch, procedureID: ProcedureID)
  case attRejected(epoch: ConnectionEpoch, procedureID: ProcedureID, reason: String)
  case protocolAcknowledged(epoch: ConnectionEpoch, procedureID: ProcedureID)
  case protocolRejected(epoch: ConnectionEpoch, procedureID: ProcedureID, reason: String)
  case protocolUnsupported(epoch: ConnectionEpoch, procedureID: ProcedureID)
  case protocolMalformed(epoch: ConnectionEpoch, procedureID: ProcedureID)
  case protocolUnknown(epoch: ConnectionEpoch, procedureID: ProcedureID)
  case telemetry(epoch: ConnectionEpoch, WorkoutTelemetryInput)
  case tick(epoch: ConnectionEpoch)
  case setSpeedOverride(epoch: ConnectionEpoch, WorkoutSpeed)
  case setInclinationOverride(epoch: ConnectionEpoch, WorkoutInclination)
  case returnToPlan(epoch: ConnectionEpoch)
  case humanConfirmsStationary(epoch: ConnectionEpoch, note: String)
  case humanObservesMotion(epoch: ConnectionEpoch, note: String)
  case userEndsWorkout(epoch: ConnectionEpoch)
  case localEndingSucceeded(epoch: ConnectionEpoch)
  case localEndingFailed(epoch: ConnectionEpoch, reason: String)
  case connectionLost(epoch: ConnectionEpoch, reason: String)
  case capabilityChanged(epoch: ConnectionEpoch, capability: FR30zCapabilitySnapshot)
  case controlPermissionLost(epoch: ConnectionEpoch, reason: String)
  case appBecameInactive(epoch: ConnectionEpoch, reason: String)
}

enum WorkoutExecutionEffect: Equatable {
  case submit(WorkoutProcedureRecord)
  case finalizeLocally(WorkoutCompletionContext)
  case directUserToConsoleAndSafetyKey
}

enum WorkoutGuardRejection: Equatable {
  case nonMonotonicTime
  case wrongState
  case wrongEpoch
  case staleEpoch
  case connectionNotReady
  case incompleteCapabilityEvidence
  case invalidPlanOrCeilings
  case incompleteOrMismatchedProfile
  case operatorReadinessMissing
  case controlNotHeld
  case procedureBusy
  case invalidAdjustment
  case noCurrentSegment
  case endNotAvailable
  case duplicateOrLateProcedure
}

enum WorkoutReductionDisposition: Equatable {
  case accepted
  case rejected(WorkoutGuardRejection)
  case ignored(WorkoutGuardRejection)
  case failedClosed(WorkoutTerminalReason)
}

struct WorkoutExecutionTransition: Equatable {
  let state: WorkoutExecutionState
  let effects: [WorkoutExecutionEffect]
  let disposition: WorkoutReductionDisposition
}

struct WorkoutExecutionReducer {
  func reduce(
    _ original: WorkoutExecutionState,
    _ event: WorkoutExecutionEvent,
    at now: MonotonicInstant
  ) -> WorkoutExecutionTransition {
    guard now.seconds.isFinite, now >= original.lastEventTime else {
      return rejected(original, .nonMonotonicTime)
    }
    if isTerminal(original.execution), !isNewAttempt(event) {
      let reason: WorkoutGuardRejection =
        isProcedureLifecycleEvent(event) ? .duplicateOrLateProcedure : .wrongState
      return .init(state: original, effects: [], disposition: .ignored(reason))
    }
    if let epochDisposition = epochDisposition(for: event, state: original) {
      return .init(state: original, effects: [], disposition: epochDisposition)
    }

    var state = original
    state.lastEventTime = now
    var effects: [WorkoutExecutionEffect] = []
    var disposition: WorkoutReductionDisposition = .accepted

    if let responseID = protocolResponseProcedureID(event),
      case .attAccepted(let record, let deadline) = state.procedure,
      now >= deadline
    {
      if responseID != record.id { return failCorrelation(state, received: responseID, at: now) }
      disposition = timeOutProcedure(record, state: &state, effects: &effects)
      return .init(state: state, effects: effects, disposition: disposition)
    }

    switch event {
    case .userStartsConnection(let epoch):
      guard canStartNewAttempt(state) else { return rejected(original, .wrongState) }
      if let previous = state.connection.epoch, epoch.rawValue <= previous.rawValue {
        return rejected(original, .wrongEpoch)
      }
      state = WorkoutExecutionState(
        connection: .connecting(epoch),
        telemetry: .unavailable("Awaiting current-epoch telemetry"),
        lastEventTime: now
      )

    case .connectionBecomesReady(let epoch, let capability):
      guard case .connecting(epoch) = state.connection else {
        return rejected(original, .wrongState)
      }
      guard capabilityIsComplete(capability) else {
        return rejected(original, .incompleteCapabilityEvidence)
      }
      state.connection = .ready(epoch: epoch, capability: capability)

    case .arm(let plan, let ceilings, let profile):
      guard case .ready(_, let capability) = state.connection,
        case .idle = state.execution,
        state.isForegroundActive
      else { return rejected(original, .connectionNotReady) }
      guard profile.matches(capability) else {
        return rejected(original, .incompleteOrMismatchedProfile)
      }
      guard planAndCeilingsAreValid(plan, capability: capability, ceilings: ceilings) else {
        return rejected(original, .invalidPlanOrCeilings)
      }
      state.armedWorkout = .init(
        plan: plan, capability: capability, ceilings: ceilings, profile: profile)
      state.telemetry = .unavailable("Awaiting current attempt telemetry")
      state.observedMachine = .unknown
      state.execution = .preflight

    case .beginWorkout(_, let readiness):
      guard case .preflight = state.execution,
        case .ready(let epoch, let capability) = state.connection,
        case .notHeld = state.controlPermission,
        case .idle = state.procedure,
        state.isForegroundActive,
        readiness.isConfirmed,
        let armed = state.armedWorkout,
        armed.capability == capability,
        armed.profile.matches(capability)
      else { return rejected(original, beginRejection(state, readiness: readiness)) }
      let record = makeProcedure(
        .requestControl, epoch: epoch, stepIndex: nil, at: now, state: &state)
      state.procedure = .intentCreated(record)
      state.controlPermission = .requesting(record.id)
      state.execution = .acquiringControl
      effects.append(.submit(record))

    case .intentSubmitted(_, let procedureID):
      guard case .intentCreated(var record) = state.procedure else {
        return lateOrWrongProcedure(original, procedureID: procedureID, at: now)
      }
      guard record.id == procedureID else {
        return failCorrelation(state, received: procedureID, at: now)
      }
      record.submittedAt = now
      state.procedure = .submitted(record)

    case .intentSubmissionRejected(_, let procedureID, let reason):
      disposition = failProcedure(
        procedureID, failure: .submissionRejected(reason), state: &state, effects: &effects)

    case .attAccepted(_, let procedureID):
      guard case .submitted(var record) = state.procedure else {
        return lateOrWrongProcedure(original, procedureID: procedureID, at: now)
      }
      guard record.id == procedureID else {
        return failCorrelation(state, received: procedureID, at: now)
      }
      record.attAcceptedAt = now
      if let acknowledgedAt = record.ftmsAcknowledgedAt {
        disposition = completeAcknowledgedProcedure(
          record,
          attAcceptedAt: now,
          ftmsAcknowledgedAt: acknowledgedAt,
          state: &state,
          effects: &effects
        )
      } else {
        state.procedure = .attAccepted(
          record: record,
          deadline: now.advanced(by: FR30zExecutionProfile.procedureResponseInterval)
        )
      }

    case .attRejected(_, let procedureID, let reason):
      disposition = failProcedure(
        procedureID, failure: .attRejected(reason), state: &state, effects: &effects)

    case .protocolAcknowledged(_, let procedureID):
      switch state.procedure {
      case .submitted(var record):
        guard record.id == procedureID else {
          return failCorrelation(state, received: procedureID, at: now)
        }
        guard record.ftmsAcknowledgedAt == nil else {
          return lateOrWrongProcedure(original, procedureID: procedureID, at: now)
        }
        record.ftmsAcknowledgedAt = now
        state.procedure = .submitted(record)
      case .attAccepted(var record, _):
        guard record.id == procedureID else {
          return failCorrelation(state, received: procedureID, at: now)
        }
        record.ftmsAcknowledgedAt = now
        disposition = completeAcknowledgedProcedure(
          record,
          attAcceptedAt: record.attAcceptedAt!,
          ftmsAcknowledgedAt: now,
          state: &state,
          effects: &effects
        )
      default:
        return lateOrWrongProcedure(original, procedureID: procedureID, at: now)
      }

    case .protocolRejected(_, let procedureID, let reason):
      disposition = failProcedure(
        procedureID, failure: .protocolRejected(reason), state: &state, effects: &effects)
    case .protocolUnsupported(_, let procedureID):
      disposition = failProcedure(
        procedureID, failure: .protocolUnsupported, state: &state, effects: &effects)
    case .protocolMalformed(_, let procedureID):
      disposition = failProcedure(
        procedureID, failure: .protocolMalformed, state: &state, effects: &effects)
    case .protocolUnknown(_, let procedureID):
      disposition = failProcedure(
        procedureID, failure: .protocolUnknown, state: &state, effects: &effects)

    case .telemetry(_, let input):
      disposition = consumeTelemetry(input, at: now, state: &state, effects: &effects)
    case .tick:
      disposition = consumeTick(at: now, state: &state, effects: &effects)
    case .setSpeedOverride(_, let target):
      disposition = setOverride(
        speed: target, inclination: nil, at: now, state: &state, effects: &effects)
    case .setInclinationOverride(_, let target):
      disposition = setOverride(
        speed: nil, inclination: target, at: now, state: &state, effects: &effects)
    case .returnToPlan:
      disposition = returnToPlan(at: now, state: &state, effects: &effects)
    case .humanConfirmsStationary(_, let note):
      disposition = consumeHumanStationary(note: note, at: now, state: &state, effects: &effects)
    case .humanObservesMotion(_, let note):
      disposition = consumeHumanMotion(note: note, at: now, state: &state, effects: &effects)

    case .userEndsWorkout:
      guard case .idle = state.procedure else { return rejected(original, .procedureBusy) }
      guard let context = endContext(state, at: now) else {
        return rejected(original, .endNotAvailable)
      }
      state.execution = .ending(context)
      state.targetSequence = nil
      effects.append(.finalizeLocally(context))
    case .localEndingSucceeded:
      guard case .ending(let context) = state.execution, case .idle = state.procedure else {
        return rejected(original, .wrongState)
      }
      guard stationaryEvidenceIsAccepted(context.stationaryEvidence, state: state, at: now) else {
        if case .telemetry(let sample) = context.stationaryEvidence {
          state.telemetry = .stale(sample)
          state.observedMachine = .unknown
        }
        disposition = interrupt(.stationaryEvidenceExpired, state: &state, effects: &effects)
        break
      }
      state.execution = .finished(context)
      state.controlPermission = .invalidated("Workout ended locally")
      state.procedure = .idle
      state.motionPossible = false
    case .localEndingFailed(_, let reason):
      guard case .ending = state.execution else { return rejected(original, .wrongState) }
      disposition = fail(.localFinalization(reason), state: &state, effects: &effects)

    case .connectionLost(_, let reason):
      let epoch = state.connection.epoch!
      state.connection = .lost(previousEpoch: epoch, reason: reason)
      state.telemetry = .unavailable("Connection lost")
      state.observedMachine = .unknown
      disposition = interrupt(.connectionLost(reason), state: &state, effects: &effects)
    case .capabilityChanged(_, let capability):
      guard capability != state.connection.readyCapability else { break }
      let epoch = state.connection.epoch!
      state.connection = .invalidated(
        previousEpoch: epoch, reason: "Capability/profile evidence changed")
      disposition = interrupt(.profileChanged, state: &state, effects: &effects)
    case .controlPermissionLost(_, let reason):
      disposition = interrupt(.controlPermissionLost(reason), state: &state, effects: &effects)
    case .appBecameInactive(_, let reason):
      state.isForegroundActive = false
      disposition = interrupt(.foregroundLost(reason), state: &state, effects: &effects)
    }

    if case .rejected(let reason) = disposition {
      return rejected(original, reason)
    }
    return .init(state: state, effects: effects, disposition: disposition)
  }
}

extension WorkoutExecutionReducer {
  fileprivate func rejected(_ state: WorkoutExecutionState, _ reason: WorkoutGuardRejection)
    -> WorkoutExecutionTransition
  {
    .init(state: state, effects: [], disposition: .rejected(reason))
  }

  fileprivate func isNewAttempt(_ event: WorkoutExecutionEvent) -> Bool {
    if case .userStartsConnection = event { return true }
    return false
  }

  fileprivate func isTerminal(_ phase: WorkoutExecutionPhase) -> Bool {
    switch phase {
    case .finished, .interrupted, .failed: true
    default: false
    }
  }

  fileprivate func canStartNewAttempt(_ state: WorkoutExecutionState) -> Bool {
    switch state.execution {
    case .idle, .finished, .interrupted, .failed: true
    default: false
    }
  }

  fileprivate func eventEpoch(_ event: WorkoutExecutionEvent) -> ConnectionEpoch? {
    switch event {
    case .userStartsConnection, .arm:
      nil
    case .connectionBecomesReady(let epoch, _), .beginWorkout(let epoch, _),
      .intentSubmitted(let epoch, _), .intentSubmissionRejected(let epoch, _, _),
      .attAccepted(let epoch, _), .attRejected(let epoch, _, _),
      .protocolAcknowledged(let epoch, _), .protocolRejected(let epoch, _, _),
      .protocolUnsupported(let epoch, _), .protocolMalformed(let epoch, _),
      .protocolUnknown(let epoch, _), .telemetry(let epoch, _), .tick(let epoch),
      .setSpeedOverride(let epoch, _), .setInclinationOverride(let epoch, _),
      .returnToPlan(let epoch), .humanConfirmsStationary(let epoch, _),
      .humanObservesMotion(let epoch, _), .userEndsWorkout(let epoch),
      .localEndingSucceeded(let epoch), .localEndingFailed(let epoch, _),
      .connectionLost(let epoch, _), .capabilityChanged(let epoch, _),
      .controlPermissionLost(let epoch, _), .appBecameInactive(let epoch, _):
      epoch
    }
  }

  fileprivate func epochDisposition(for event: WorkoutExecutionEvent, state: WorkoutExecutionState)
    -> WorkoutReductionDisposition?
  {
    guard let supplied = eventEpoch(event) else { return nil }
    guard let current = state.connection.epoch else { return .rejected(.wrongEpoch) }
    if supplied.rawValue < current.rawValue { return .ignored(.staleEpoch) }
    if supplied != current { return .rejected(.wrongEpoch) }
    return nil
  }

  fileprivate func isProcedureLifecycleEvent(_ event: WorkoutExecutionEvent) -> Bool {
    switch event {
    case .intentSubmitted, .intentSubmissionRejected, .attAccepted, .attRejected,
      .protocolAcknowledged, .protocolRejected, .protocolUnsupported,
      .protocolMalformed, .protocolUnknown:
      true
    default:
      false
    }
  }

  fileprivate func protocolResponseProcedureID(_ event: WorkoutExecutionEvent) -> ProcedureID? {
    switch event {
    case .protocolAcknowledged(_, let id), .protocolRejected(_, let id, _),
      .protocolUnsupported(_, let id), .protocolMalformed(_, let id), .protocolUnknown(_, let id):
      id
    default:
      nil
    }
  }

  fileprivate func capabilityIsComplete(_ capability: FR30zCapabilitySnapshot) -> Bool {
    !capability.peripheralIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !capability.equipmentIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && capability.fitnessMachineServicePresent
      && capability.requiredCharacteristicPropertiesMatch
      && capability.fitnessMachineFeatureEvidence != .unavailable
      && capability.supportedSpeedRangeEvidence != .unavailable
      && capability.supportedInclinationRangeEvidence != .unavailable
  }

  fileprivate func planAndCeilingsAreValid(
    _ validated: WorkoutPlanValidator.ValidatedPlan,
    capability: FR30zCapabilitySnapshot,
    ceilings: WorkoutSessionCeilings
  ) -> Bool {
    guard
      case .success(let revalidated) = WorkoutPlanValidator.validate(
        validated.plan, against: capability.planCapabilities),
      revalidated == validated,
      case .supported(let speedRange) = capability.planCapabilities.speed,
      case .supported(let inclinationRange) = capability.planCapabilities.inclination,
      value(ceilings.maximumSpeed, isWithin: speedRange, ceiling: speedRange.maximum),
      value(
        ceilings.maximumInclination, isWithin: inclinationRange, ceiling: inclinationRange.maximum),
      ceilings.maximumStepSpeedChange.value > 0,
      ceilings.maximumStepSpeedChange.value <= speedRange.maximum.value - speedRange.minimum.value,
      isAligned(
        ceilings.maximumStepSpeedChange.value, minimum: 0, increment: speedRange.increment.value)
    else { return false }

    for (index, step) in validated.plan.steps.enumerated() {
      guard step.targetSpeed.value <= ceilings.maximumSpeed.value,
        step.targetInclination.value <= ceilings.maximumInclination.value
      else { return false }
      if index > 0 {
        let previous = validated.plan.steps[index - 1].targetSpeed.value
        guard absolute(step.targetSpeed.value - previous) <= ceilings.maximumStepSpeedChange.value
        else {
          return false
        }
      }
    }
    return true
  }

  fileprivate func value(
    _ value: WorkoutSpeed, isWithin range: WorkoutSpeedRange, ceiling: WorkoutSpeed
  ) -> Bool {
    value.value.isFinite
      && value.unit == range.minimum.unit
      && value.value >= range.minimum.value
      && value.value <= ceiling.value
      && isAligned(value.value, minimum: range.minimum.value, increment: range.increment.value)
  }

  fileprivate func value(
    _ value: WorkoutInclination, isWithin range: WorkoutInclinationRange,
    ceiling: WorkoutInclination
  ) -> Bool {
    value.value.isFinite
      && value.unit == range.minimum.unit
      && value.value >= range.minimum.value
      && value.value <= ceiling.value
      && isAligned(value.value, minimum: range.minimum.value, increment: range.increment.value)
  }

  fileprivate func beginRejection(
    _ state: WorkoutExecutionState, readiness: WorkoutOperatorReadiness
  ) -> WorkoutGuardRejection {
    guard state.isForegroundActive else { return .wrongState }
    guard readiness.isConfirmed else { return .operatorReadinessMissing }
    guard case .idle = state.procedure else { return .procedureBusy }
    guard case .ready = state.connection else { return .connectionNotReady }
    return .wrongState
  }

  fileprivate func makeProcedure(
    _ intent: WorkoutControlPointIntent,
    epoch: ConnectionEpoch,
    stepIndex: Int?,
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState
  ) -> WorkoutProcedureRecord {
    let id = ProcedureID(epoch: epoch, sequence: state.nextProcedureSequence)
    state.nextProcedureSequence += 1
    return .init(id: id, intent: intent, stepIndex: stepIndex, createdAt: now)
  }

  fileprivate func completeAcknowledgedProcedure(
    _ record: WorkoutProcedureRecord,
    attAcceptedAt: MonotonicInstant,
    ftmsAcknowledgedAt: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    state.procedureHistory.append(
      .acknowledged(
        record: record, attAcceptedAt: attAcceptedAt, ftmsAcknowledgedAt: ftmsAcknowledgedAt)
    )
    state.procedure = .idle

    switch record.intent {
    case .requestControl:
      guard case .acquiringControl = state.execution else {
        return fail(.procedure(.duplicateOrLate(record.id)), state: &state, effects: &effects)
      }
      state.currentSegment = .init(
        stepIndex: 0,
        accumulatedActiveSeconds: 0,
        activeStartedAt: nil,
        speedOverride: nil,
        inclinationOverride: nil
      )
      state.controlPermission = .held(
        epoch: record.id.epoch, acknowledgedAt: max(attAcceptedAt, ftmsAcknowledgedAt))
      state.execution = .waitingForPhysicalStart
    case .setTargetSpeed(let target):
      guard var sequence = state.targetSequence, sequence.stepIndex == record.stepIndex else {
        return fail(.procedure(.duplicateOrLate(record.id)), state: &state, effects: &effects)
      }
      sequence.acknowledgedSpeed = target
      sequence.forceSpeed = false
      sequence.finalAcknowledgementAt = max(attAcceptedAt, ftmsAcknowledgedAt)
      sequence.observationDeadline = nil
      state.targetSequence = sequence
      if isActivelyApplyingTargets(state.execution) {
        return advanceTargetSequence(at: state.lastEventTime, state: &state, effects: &effects)
      }
    case .setTargetInclination(let target):
      guard var sequence = state.targetSequence, sequence.stepIndex == record.stepIndex else {
        return fail(.procedure(.duplicateOrLate(record.id)), state: &state, effects: &effects)
      }
      sequence.acknowledgedInclination = target
      sequence.forceInclination = false
      sequence.finalAcknowledgementAt = max(attAcceptedAt, ftmsAcknowledgedAt)
      sequence.observationDeadline = nil
      state.targetSequence = sequence
      if isActivelyApplyingTargets(state.execution) {
        return advanceTargetSequence(at: state.lastEventTime, state: &state, effects: &effects)
      }
    }
    return .accepted
  }

  fileprivate func advanceTargetSequence(
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    guard var sequence = state.targetSequence,
      let target = effectiveTarget(state),
      case .idle = state.procedure,
      case .ready(let epoch, let capability) = state.connection,
      case .held(epoch, _) = state.controlPermission,
      state.isForegroundActive,
      let armed = state.armedWorkout,
      armed.capability == capability,
      armed.profile.matches(capability)
    else { return interrupt(.resumeGuardsFailed, state: &state, effects: &effects) }

    let intent: WorkoutControlPointIntent?
    if sequence.forceSpeed || sequence.acknowledgedSpeed != target.speed {
      intent = .setTargetSpeed(target.speed)
    } else if sequence.forceInclination || sequence.acknowledgedInclination != target.inclination {
      intent = .setTargetInclination(target.inclination)
    } else {
      intent = nil
    }

    if let intent {
      sequence.observationDeadline = nil
      state.targetSequence = sequence
      let record = makeProcedure(
        intent, epoch: epoch, stepIndex: sequence.stepIndex, at: now, state: &state)
      state.procedure = .intentCreated(record)
      state.motionPossible = true
      effects.append(.submit(record))
      return .accepted
    }

    if let acknowledgedAt = sequence.finalAcknowledgementAt {
      sequence.observationDeadline = acknowledgedAt.advanced(
        by: FR30zExecutionProfile.targetObservationInterval)
      state.targetSequence = sequence
      if let sample = freshSample(state, at: now),
        sample.receivedAt > acknowledgedAt,
        sampleMatches(sample, target: target)
      {
        completeTargetObservation(sample, at: now, state: &state)
      }
      return .accepted
    }

    guard let sample = freshSample(state, at: now), sampleMatches(sample, target: target) else {
      return fail(
        .contradictoryEvidence("Current exact telemetry is required when no target changes"),
        state: &state,
        effects: &effects
      )
    }
    completeTargetObservation(sample, at: now, state: &state)
    return .accepted
  }

  fileprivate func startTargetSequence(
    purpose: WorkoutTargetSequencePurpose,
    forceBothAxes: Bool,
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    guard let segment = state.currentSegment else { return .rejected(.noCurrentSegment) }
    state.targetSequence = .init(
      purpose: purpose,
      stepIndex: segment.stepIndex,
      startedAt: now,
      forceSpeed: forceBothAxes,
      forceInclination: forceBothAxes,
      acknowledgedSpeed: forceBothAxes ? nil : state.lastConfirmedTarget?.speed,
      acknowledgedInclination: forceBothAxes ? nil : state.lastConfirmedTarget?.inclination,
      finalAcknowledgementAt: nil,
      observationDeadline: nil
    )
    state.execution = purpose == .resumeRestoration ? .restoringTargets : .applyingTargets(purpose)
    return advanceTargetSequence(at: now, state: &state, effects: &effects)
  }

  fileprivate func completeTargetObservation(
    _ sample: WorkoutTelemetrySample, at now: MonotonicInstant, state: inout WorkoutExecutionState
  ) {
    guard var segment = state.currentSegment else { return }
    state.lastConfirmedTarget = .init(speed: sample.speed, inclination: sample.inclination)
    state.targetSequence = nil
    segment.activeStartedAt = now
    state.currentSegment = segment
    state.execution = .runningSegment
    state.observedMachine = .targetReported(stepIndex: segment.stepIndex, sample: sample)
  }

  fileprivate func consumeTelemetry(
    _ input: WorkoutTelemetryInput,
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    if case .checkingTreadmill(let checking) = state.execution, now >= checking.interruptionDeadline
    {
      return interrupt(.telemetryStreamTimedOut, state: &state, effects: &effects)
    }
    if let deadline = state.targetSequence?.observationDeadline,
      now >= deadline,
      isTargetObservationRelevant(state.execution)
    {
      return fail(.targetObservationTimeout, state: &state, effects: &effects)
    }

    switch input {
    case .unavailable(let reason):
      state.telemetry = .unavailable(reason)
      state.observedMachine = .unknown
      if attemptNeedsTelemetry(state.execution) {
        return interrupt(.telemetryUnavailable(reason), state: &state, effects: &effects)
      }
      return .accepted
    case .malformed(let reason):
      state.telemetry = .malformed(reason)
      state.observedMachine = .unknown
      if attemptNeedsTelemetry(state.execution) {
        return fail(.malformedTelemetry(reason), state: &state, effects: &effects)
      }
      return .accepted
    case .sample(let speed, let inclination, let distance):
      guard let speed, let inclination else {
        state.telemetry = .unavailable("Required speed or inclination field missing")
        state.observedMachine = .unknown
        if attemptNeedsTelemetry(state.execution) {
          return fail(.incompleteTelemetry, state: &state, effects: &effects)
        }
        return .accepted
      }
      let sample = WorkoutTelemetrySample(
        speed: speed,
        inclination: inclination,
        totalDistanceMetres: distance,
        receivedAt: now
      )
      guard sampleIsInsideCapability(sample, state: state) else {
        state.telemetry = .contradictory("Telemetry lies outside the accepted capability range")
        state.observedMachine = .unknown
        return fail(
          .contradictoryEvidence("Telemetry lies outside the accepted capability range"),
          state: &state,
          effects: &effects
        )
      }
      state.telemetry = .fresh(sample)
      if speed.value == 0 {
        state.observedMachine = .reportedStationary(sample)
        return consumeReportedStationary(sample, at: now, state: &state)
      }
      state.motionPossible = true
      state.observedMachine = .reportedMoving(sample)
      return consumeReportedMoving(sample, at: now, state: &state, effects: &effects)
    }
  }

  fileprivate func consumeReportedStationary(
    _ sample: WorkoutTelemetrySample,
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState
  ) -> WorkoutReductionDisposition {
    let evidence = WorkoutStationaryEvidence.telemetry(sample)
    switch state.execution {
    case .applyingTargets, .runningSegment, .restoringTargets:
      guard state.motionPossible else { return .accepted }
      enterPaused(evidence, at: now, state: &state)
    case .checkingTreadmill(let checking):
      if checking.origin == .awaitingPhysicalStopForCompletion {
        state.execution = .readyToEnd(
          completionContext(.completedPlan, evidence: evidence, state: state))
      } else if state.motionPossible {
        enterPaused(evidence, at: now, state: &state)
      }
    case .awaitingPhysicalStopForCompletion:
      state.execution = .readyToEnd(
        completionContext(.completedPlan, evidence: evidence, state: state))
    case .paused:
      state.execution = .paused(evidence)
    case .readyToEnd(let context):
      state.execution = .readyToEnd(context.replacingStationaryEvidence(with: evidence))
    case .ending(let context):
      state.execution = .ending(context.replacingStationaryEvidence(with: evidence))
    default:
      break
    }
    return .accepted
  }

  fileprivate func consumeReportedMoving(
    _ sample: WorkoutTelemetrySample,
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    switch state.execution {
    case .waitingForPhysicalStart:
      guard state.currentSegment != nil else { return .rejected(.noCurrentSegment) }
      return startTargetSequence(
        purpose: .initial, forceBothAxes: true, at: now, state: &state, effects: &effects)
    case .paused:
      guard case .idle = state.procedure else {
        return interrupt(.resumeGuardsFailed, state: &state, effects: &effects)
      }
      state.targetSequence = nil
      return startTargetSequence(
        purpose: .resumeRestoration,
        forceBothAxes: true,
        at: now,
        state: &state,
        effects: &effects
      )
    case .checkingTreadmill(let checking):
      return resolveCheckingWithMoving(
        checking, sample: sample, at: now, state: &state, effects: &effects)
    case .applyingTargets, .restoringTargets:
      if targetObservationIsSatisfied(sample, state: state) {
        completeTargetObservation(sample, at: now, state: &state)
      }
    case .runningSegment:
      if let target = effectiveTarget(state), sampleMatches(sample, target: target),
        let segment = state.currentSegment
      {
        state.observedMachine = .targetReported(stepIndex: segment.stepIndex, sample: sample)
      }
    case .readyToEnd:
      state.execution = .awaitingPhysicalStopForCompletion
    case .ending:
      return fail(
        .contradictoryEvidence("Treadmill reported movement while ending"),
        state: &state,
        effects: &effects
      )
    default:
      break
    }
    return .accepted
  }

  fileprivate func resolveCheckingWithMoving(
    _ checking: WorkoutCheckingState,
    sample: WorkoutTelemetrySample,
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    switch checking.origin {
    case .waitingForPhysicalStart:
      state.execution = .waitingForPhysicalStart
      return consumeReportedMoving(sample, at: now, state: &state, effects: &effects)
    case .applyingTargets(let purpose):
      state.execution = .applyingTargets(purpose)
      if targetObservationIsSatisfied(sample, state: state) {
        completeTargetObservation(sample, at: now, state: &state)
        return .accepted
      }
      if case .idle = state.procedure {
        return advanceTargetSequence(at: now, state: &state, effects: &effects)
      }
    case .restoringTargets:
      state.execution = .restoringTargets
      if targetObservationIsSatisfied(sample, state: state) {
        completeTargetObservation(sample, at: now, state: &state)
        return .accepted
      }
      if case .idle = state.procedure {
        return advanceTargetSequence(at: now, state: &state, effects: &effects)
      }
    case .runningSegment:
      state.execution = .runningSegment
      if var segment = state.currentSegment {
        segment.activeStartedAt = now
        state.currentSegment = segment
      }
    case .paused(let evidence):
      state.execution = .paused(evidence)
      return consumeReportedMoving(sample, at: now, state: &state, effects: &effects)
    case .awaitingPhysicalStopForCompletion:
      state.execution = .awaitingPhysicalStopForCompletion
    }
    return .accepted
  }

  fileprivate func consumeTick(
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    if case .attAccepted(let record, let deadline) = state.procedure, now >= deadline {
      return timeOutProcedure(record, state: &state, effects: &effects)
    }
    if let deadline = state.targetSequence?.observationDeadline,
      now >= deadline,
      isTargetObservationRelevant(state.execution)
    {
      return fail(.targetObservationTimeout, state: &state, effects: &effects)
    }
    if case .checkingTreadmill(let checking) = state.execution {
      if now >= checking.interruptionDeadline {
        return interrupt(.telemetryStreamTimedOut, state: &state, effects: &effects)
      }
      return .accepted
    }
    if let sample = currentTelemetrySample(state.telemetry),
      phaseRequiresFreshTelemetry(state.execution),
      now.seconds - sample.receivedAt.seconds > FR30zExecutionProfile.telemetryFreshnessInterval
    {
      let freshnessBoundary = sample.receivedAt.advanced(
        by: FR30zExecutionProfile.telemetryFreshnessInterval)
      freezeSegment(at: freshnessBoundary, state: &state)
      state.telemetry = .stale(sample)
      state.observedMachine = .unknown
      let checking = WorkoutCheckingState(
        origin: checkingOrigin(state.execution),
        freshnessBoundary: freshnessBoundary,
        interruptionDeadline: sample.receivedAt.advanced(
          by: FR30zExecutionProfile.telemetryCheckingInterval)
      )
      state.execution = .checkingTreadmill(checking)
      if now >= checking.interruptionDeadline {
        return interrupt(.telemetryStreamTimedOut, state: &state, effects: &effects)
      }
      return .accepted
    }
    if case .runningSegment = state.execution {
      return progressRunningSegment(at: now, state: &state, effects: &effects)
    }
    return .accepted
  }

  fileprivate func progressRunningSegment(
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    guard var segment = state.currentSegment,
      let startedAt = segment.activeStartedAt,
      let armed = state.armedWorkout
    else { return .rejected(.noCurrentSegment) }
    let duration = TimeInterval(armed.plan.plan.steps[segment.stepIndex].duration.value)
    let active = segment.accumulatedActiveSeconds + now.seconds - startedAt.seconds
    guard active + 0.000_000_001 >= duration else { return .accepted }

    segment.accumulatedActiveSeconds = duration
    segment.activeStartedAt = nil
    state.currentSegment = segment
    state.completedActiveSeconds += duration
    if segment.stepIndex + 1 >= armed.plan.plan.steps.count {
      state.targetSequence = nil
      state.execution = .awaitingPhysicalStopForCompletion
      return .accepted
    }
    state.currentSegment = .init(
      stepIndex: segment.stepIndex + 1,
      accumulatedActiveSeconds: 0,
      activeStartedAt: nil,
      speedOverride: nil,
      inclinationOverride: nil
    )
    return startTargetSequence(
      purpose: .plannedTransition,
      forceBothAxes: false,
      at: now,
      state: &state,
      effects: &effects
    )
  }

  fileprivate func setOverride(
    speed: WorkoutSpeed?,
    inclination: WorkoutInclination?,
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    guard var segment = state.currentSegment else { return .rejected(.noCurrentSegment) }
    guard adjustmentStateAllowsChange(state.execution) else { return .rejected(.wrongState) }
    if let speed, !validSpeedAdjustment(speed, state: state) {
      return .rejected(.invalidAdjustment)
    }
    if let inclination, !validInclinationAdjustment(inclination, state: state) {
      return .rejected(.invalidAdjustment)
    }
    if let speed { segment.speedOverride = speed }
    if let inclination { segment.inclinationOverride = inclination }
    state.currentSegment = segment
    switch state.execution {
    case .runningSegment:
      freezeSegment(at: now, state: &state)
      return startTargetSequence(
        purpose: .manualAdjustment,
        forceBothAxes: false,
        at: now,
        state: &state,
        effects: &effects
      )
    case .applyingTargets, .restoringTargets:
      if case .idle = state.procedure {
        return advanceTargetSequence(at: now, state: &state, effects: &effects)
      }
    case .waitingForPhysicalStart, .checkingTreadmill, .paused:
      break
    default:
      return .rejected(.wrongState)
    }
    return .accepted
  }

  fileprivate func returnToPlan(
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    guard var segment = state.currentSegment else { return .rejected(.noCurrentSegment) }
    guard adjustmentStateAllowsChange(state.execution) else { return .rejected(.wrongState) }
    segment.speedOverride = nil
    segment.inclinationOverride = nil
    state.currentSegment = segment
    switch state.execution {
    case .runningSegment:
      freezeSegment(at: now, state: &state)
      return startTargetSequence(
        purpose: .returnToPlan,
        forceBothAxes: false,
        at: now,
        state: &state,
        effects: &effects
      )
    case .applyingTargets, .restoringTargets:
      if case .idle = state.procedure {
        return advanceTargetSequence(at: now, state: &state, effects: &effects)
      }
    case .waitingForPhysicalStart, .checkingTreadmill, .paused:
      break
    default:
      return .rejected(.wrongState)
    }
    return .accepted
  }

  fileprivate func consumeHumanStationary(
    note: String,
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    if let sample = freshSample(state, at: now), sample.speed.value > 0 {
      state.telemetry = .contradictory(
        "Human stationary observation conflicts with fresh moving telemetry")
      return fail(
        .contradictoryEvidence(
          "Human stationary observation conflicts with fresh moving telemetry"),
        state: &state,
        effects: &effects
      )
    }
    let human = WorkoutHumanStationaryEvidence(confirmedAt: now, note: note)
    let evidence = WorkoutStationaryEvidence.human(human)
    state.observedMachine = .humanConfirmedStationary(human)
    switch state.execution {
    case .awaitingPhysicalStopForCompletion:
      state.execution = .readyToEnd(
        completionContext(.completedPlan, evidence: evidence, state: state))
    case .checkingTreadmill(let checking)
    where checking.origin == .awaitingPhysicalStopForCompletion:
      state.execution = .readyToEnd(
        completionContext(.completedPlan, evidence: evidence, state: state))
    case .applyingTargets, .runningSegment, .checkingTreadmill, .restoringTargets:
      guard state.motionPossible else { return .rejected(.wrongState) }
      enterPaused(evidence, at: now, state: &state)
    case .paused:
      state.execution = .paused(evidence)
    default:
      return .rejected(.wrongState)
    }
    return .accepted
  }

  fileprivate func consumeHumanMotion(
    note: String,
    at now: MonotonicInstant,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    if let sample = freshSample(state, at: now), sample.speed.value == 0 {
      state.telemetry = .contradictory(
        "Human motion observation conflicts with fresh zero telemetry")
      return fail(
        .contradictoryEvidence("Human motion observation conflicts with fresh zero telemetry"),
        state: &state,
        effects: &effects
      )
    }
    state.motionPossible = true
    state.observedMachine = .humanObservedMoving(.init(observedAt: now, note: note))
    return .accepted
  }

  fileprivate func enterPaused(
    _ evidence: WorkoutStationaryEvidence, at now: MonotonicInstant,
    state: inout WorkoutExecutionState
  ) {
    freezeSegment(at: now, state: &state)
    if var sequence = state.targetSequence {
      sequence.observationDeadline = nil
      state.targetSequence = state.procedure.unresolvedRecord == nil ? nil : sequence
    }
    state.execution = .paused(evidence)
  }

  fileprivate func freezeSegment(at boundary: MonotonicInstant, state: inout WorkoutExecutionState)
  {
    guard var segment = state.currentSegment, let startedAt = segment.activeStartedAt else {
      return
    }
    segment.accumulatedActiveSeconds += max(0, boundary.seconds - startedAt.seconds)
    segment.activeStartedAt = nil
    state.currentSegment = segment
  }

  fileprivate func timeOutProcedure(
    _ record: WorkoutProcedureRecord,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    state.procedure = .timedOutUnknown(record: record)
    state.procedureHistory.append(.timedOutUnknown(record))
    return fail(.procedure(.responseTimeout), state: &state, effects: &effects)
  }

  fileprivate func failProcedure(
    _ procedureID: ProcedureID,
    failure: WorkoutProcedureFailure,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    guard let record = state.procedure.unresolvedRecord else {
      return .ignored(.duplicateOrLateProcedure)
    }
    guard record.id == procedureID else {
      let mismatch = WorkoutProcedureFailure.correlationFailure(
        expected: record.id, received: procedureID)
      state.procedure = .failed(record: record, failure: mismatch)
      state.procedureHistory.append(.failed(record, mismatch))
      return fail(.procedure(mismatch), state: &state, effects: &effects)
    }
    state.procedure = .failed(record: record, failure: failure)
    state.procedureHistory.append(.failed(record, failure))
    return fail(.procedure(failure), state: &state, effects: &effects)
  }

  fileprivate func failCorrelation(
    _ original: WorkoutExecutionState,
    received: ProcedureID,
    at now: MonotonicInstant
  ) -> WorkoutExecutionTransition {
    var state = original
    state.lastEventTime = now
    var effects: [WorkoutExecutionEffect] = []
    guard let expected = state.procedure.unresolvedRecord?.id else {
      let failure = WorkoutProcedureFailure.duplicateOrLate(received)
      let disposition = fail(.procedure(failure), state: &state, effects: &effects)
      return .init(state: state, effects: effects, disposition: disposition)
    }
    let failure = WorkoutProcedureFailure.correlationFailure(expected: expected, received: received)
    _ = failProcedure(expected, failure: failure, state: &state, effects: &effects)
    return .init(
      state: state, effects: effects, disposition: .failedClosed(.failed(.procedure(failure))))
  }

  fileprivate func lateOrWrongProcedure(
    _ original: WorkoutExecutionState,
    procedureID: ProcedureID,
    at now: MonotonicInstant
  ) -> WorkoutExecutionTransition {
    var state = original
    state.lastEventTime = now
    var effects: [WorkoutExecutionEffect] = []
    if let active = state.procedure.unresolvedRecord, active.id != procedureID {
      return failCorrelation(original, received: procedureID, at: now)
    }
    let failure = WorkoutProcedureFailure.duplicateOrLate(procedureID)
    if let record = state.procedure.unresolvedRecord {
      state.procedure = .failed(record: record, failure: failure)
      state.procedureHistory.append(.failed(record, failure))
    }
    let disposition = fail(.procedure(failure), state: &state, effects: &effects)
    return .init(state: state, effects: effects, disposition: disposition)
  }

  fileprivate func fail(
    _ failure: WorkoutExecutionFailure,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    freezeSegment(at: state.lastEventTime, state: &state)
    invalidateOutstandingProcedure(state: &state)
    state.controlPermission = .invalidated("Execution failed")
    state.targetSequence = nil
    state.execution = .failed(failure)
    if state.motionPossible, !effects.contains(.directUserToConsoleAndSafetyKey) {
      effects.append(.directUserToConsoleAndSafetyKey)
    }
    return .failedClosed(.failed(failure))
  }

  fileprivate func interrupt(
    _ interruption: WorkoutInterruption,
    state: inout WorkoutExecutionState,
    effects: inout [WorkoutExecutionEffect]
  ) -> WorkoutReductionDisposition {
    freezeSegment(at: state.lastEventTime, state: &state)
    invalidateOutstandingProcedure(state: &state)
    state.controlPermission = .invalidated("Execution interrupted")
    state.targetSequence = nil
    state.execution = .interrupted(interruption)
    if state.motionPossible, !effects.contains(.directUserToConsoleAndSafetyKey) {
      effects.append(.directUserToConsoleAndSafetyKey)
    }
    return .failedClosed(.interrupted(interruption))
  }

  fileprivate func invalidateOutstandingProcedure(state: inout WorkoutExecutionState) {
    guard let record = state.procedure.unresolvedRecord else { return }
    state.procedure = .timedOutUnknown(record: record)
    if !state.procedureHistory.contains(.timedOutUnknown(record)) {
      state.procedureHistory.append(.timedOutUnknown(record))
    }
  }

  fileprivate func effectiveTarget(_ state: WorkoutExecutionState) -> WorkoutTarget? {
    guard let segment = state.currentSegment,
      let plan = state.armedWorkout?.plan.plan,
      plan.steps.indices.contains(segment.stepIndex)
    else { return nil }
    let step = plan.steps[segment.stepIndex]
    return .init(
      speed: segment.speedOverride ?? step.targetSpeed,
      inclination: segment.inclinationOverride ?? step.targetInclination
    )
  }

  fileprivate func targetObservationIsSatisfied(
    _ sample: WorkoutTelemetrySample, state: WorkoutExecutionState
  ) -> Bool {
    guard let sequence = state.targetSequence,
      let target = effectiveTarget(state),
      let acknowledgedAt = sequence.finalAcknowledgementAt,
      sequence.observationDeadline != nil,
      sample.receivedAt > acknowledgedAt
    else { return false }
    return sampleMatches(sample, target: target)
  }

  fileprivate func sampleMatches(_ sample: WorkoutTelemetrySample, target: WorkoutTarget) -> Bool {
    sample.speed == target.speed && sample.inclination == target.inclination
  }

  fileprivate func sampleIsInsideCapability(
    _ sample: WorkoutTelemetrySample, state: WorkoutExecutionState
  ) -> Bool {
    guard let armed = state.armedWorkout,
      case .supported(let speedRange) = armed.capability.planCapabilities.speed,
      case .supported(let inclinationRange) = armed.capability.planCapabilities.inclination
    else { return true }
    let speedIsValid =
      sample.speed.value == 0
      || (sample.speed.value >= speedRange.minimum.value
        && sample.speed.value <= speedRange.maximum.value)
    return speedIsValid
      && sample.inclination.value >= inclinationRange.minimum.value
      && sample.inclination.value <= inclinationRange.maximum.value
  }

  fileprivate func freshSample(_ state: WorkoutExecutionState, at now: MonotonicInstant)
    -> WorkoutTelemetrySample?
  {
    guard case .fresh(let sample) = state.telemetry,
      now.seconds - sample.receivedAt.seconds <= FR30zExecutionProfile.telemetryFreshnessInterval
    else { return nil }
    return sample
  }

  fileprivate func currentTelemetrySample(_ telemetry: WorkoutTelemetryState)
    -> WorkoutTelemetrySample?
  {
    switch telemetry {
    case .fresh(let sample), .stale(let sample): sample
    default: nil
    }
  }

  fileprivate func phaseRequiresFreshTelemetry(_ phase: WorkoutExecutionPhase) -> Bool {
    switch phase {
    case .waitingForPhysicalStart, .applyingTargets, .runningSegment,
      .restoringTargets, .awaitingPhysicalStopForCompletion:
      true
    case .paused(let evidence):
      if case .telemetry = evidence { true } else { false }
    case .readyToEnd(let context):
      if case .telemetry = context.stationaryEvidence { true } else { false }
    default:
      false
    }
  }

  fileprivate func attemptNeedsTelemetry(_ phase: WorkoutExecutionPhase) -> Bool {
    switch phase {
    case .waitingForPhysicalStart, .applyingTargets, .runningSegment,
      .checkingTreadmill, .paused, .restoringTargets,
      .awaitingPhysicalStopForCompletion, .readyToEnd, .ending:
      true
    default:
      false
    }
  }

  fileprivate func checkingOrigin(_ phase: WorkoutExecutionPhase) -> WorkoutCheckingOrigin {
    switch phase {
    case .waitingForPhysicalStart: .waitingForPhysicalStart
    case .applyingTargets(let purpose): .applyingTargets(purpose)
    case .runningSegment: .runningSegment
    case .paused(let evidence): .paused(evidence)
    case .restoringTargets: .restoringTargets
    case .awaitingPhysicalStopForCompletion, .readyToEnd: .awaitingPhysicalStopForCompletion
    default: preconditionFailure("Only telemetry-dependent phases enter checking")
    }
  }

  fileprivate func isActivelyApplyingTargets(_ phase: WorkoutExecutionPhase) -> Bool {
    switch phase {
    case .applyingTargets, .restoringTargets: true
    default: false
    }
  }

  fileprivate func isTargetObservationRelevant(_ phase: WorkoutExecutionPhase) -> Bool {
    switch phase {
    case .applyingTargets, .restoringTargets, .checkingTreadmill: true
    default: false
    }
  }

  fileprivate func adjustmentStateAllowsChange(_ phase: WorkoutExecutionPhase) -> Bool {
    switch phase {
    case .waitingForPhysicalStart, .applyingTargets, .runningSegment,
      .checkingTreadmill, .paused, .restoringTargets:
      true
    default:
      false
    }
  }

  fileprivate func validSpeedAdjustment(_ speed: WorkoutSpeed, state: WorkoutExecutionState) -> Bool
  {
    guard let armed = state.armedWorkout,
      case .supported(let range) = armed.capability.planCapabilities.speed
    else { return false }
    return value(speed, isWithin: range, ceiling: armed.ceilings.maximumSpeed)
  }

  fileprivate func validInclinationAdjustment(
    _ inclination: WorkoutInclination, state: WorkoutExecutionState
  ) -> Bool {
    guard let armed = state.armedWorkout,
      case .supported(let range) = armed.capability.planCapabilities.inclination
    else { return false }
    return value(inclination, isWithin: range, ceiling: armed.ceilings.maximumInclination)
  }

  fileprivate func completionContext(
    _ reason: WorkoutCompletionReason,
    evidence: WorkoutStationaryEvidence,
    state: WorkoutExecutionState
  ) -> WorkoutCompletionContext {
    .init(
      reason: reason,
      stepIndex: state.currentSegment?.stepIndex ?? 0,
      totalActiveSeconds: totalActiveSeconds(state),
      stationaryEvidence: evidence
    )
  }

  fileprivate func endContext(
    _ state: WorkoutExecutionState, at now: MonotonicInstant
  ) -> WorkoutCompletionContext? {
    switch state.execution {
    case .readyToEnd(let context):
      stationaryEvidenceIsAccepted(context.stationaryEvidence, state: state, at: now)
        ? context : nil
    case .paused(let evidence):
      stationaryEvidenceIsAccepted(evidence, state: state, at: now)
        ? completionContext(.endedFromPause, evidence: evidence, state: state) : nil
    default: nil
    }
  }

  fileprivate func stationaryEvidenceIsAccepted(
    _ evidence: WorkoutStationaryEvidence,
    state: WorkoutExecutionState,
    at now: MonotonicInstant
  ) -> Bool {
    switch evidence {
    case .telemetry(let evidenceSample):
      guard case .fresh(let latestSample) = state.telemetry else { return false }
      return latestSample == evidenceSample
        && latestSample.speed.value == 0
        && now.seconds - latestSample.receivedAt.seconds
          <= FR30zExecutionProfile.telemetryFreshnessInterval
    case .human:
      guard let sample = freshSample(state, at: now) else { return true }
      return sample.speed.value == 0
    }
  }

  fileprivate func totalActiveSeconds(_ state: WorkoutExecutionState) -> TimeInterval {
    guard let segment = state.currentSegment else { return state.completedActiveSeconds }
    var current = segment.accumulatedActiveSeconds
    if let started = segment.activeStartedAt {
      current += max(0, state.lastEventTime.seconds - started.seconds)
    }
    let duration = state.armedWorkout.map {
      TimeInterval($0.plan.plan.steps[segment.stepIndex].duration.value)
    }
    if duration == segment.accumulatedActiveSeconds,
      state.completedActiveSeconds >= segment.accumulatedActiveSeconds
    {
      return state.completedActiveSeconds
    }
    return state.completedActiveSeconds + current
  }

  fileprivate func isAligned(_ value: Decimal, minimum: Decimal, increment: Decimal) -> Bool {
    guard value.isFinite, minimum.isFinite, increment.isFinite, increment > 0 else { return false }
    var quotient = (value - minimum) / increment
    var rounded = Decimal()
    NSDecimalRound(&rounded, &quotient, 0, .plain)
    return quotient == rounded
  }

  fileprivate func absolute(_ value: Decimal) -> Decimal { value < 0 ? -value : value }
}

extension Decimal {
  fileprivate var isFinite: Bool { !isNaN }
}
