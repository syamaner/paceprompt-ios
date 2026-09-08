import Foundation

struct MonotonicInstant: Equatable, Comparable {
    let seconds: TimeInterval

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.seconds < rhs.seconds
    }

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

struct FR30zCapabilitySnapshot: Equatable {
    let identity: String
    let equipmentIdentity: String
    let planCapabilities: WorkoutPlanCapabilities
    let controlPointSupportsWrite: Bool
    let controlPointSupportsIndicate: Bool
    let controlPointIndicationsEnabled: Bool
    let passiveSubscriptionOutcomesResolved: Bool
}

struct WorkoutSessionCeilings: Equatable {
    let maximumSpeed: WorkoutSpeed
    let maximumInclination: WorkoutInclination
    let maximumStepSpeedChange: WorkoutSpeed
}

enum FR30zTargetOrder: Equatable {
    case speedThenInclination
    case inclinationThenSpeed
}

struct FR30zExecutionProfile: Equatable {
    let identity: String
    let equipmentIdentity: String
    let targetOrder: FR30zTargetOrder
    let requiresStartForFirstStep: Bool
    let permitsStop: Bool
    let telemetryFreshnessInterval: TimeInterval
    let targetObservationInterval: TimeInterval
    let procedureResponseInterval: TimeInterval
    let requestControlEvidenceAccepted: Bool
    let speedTargetEvidenceAccepted: Bool
    let inclinationTargetEvidenceAccepted: Bool
    let startEvidenceAccepted: Bool
    let stopEvidenceAccepted: Bool

    var isComplete: Bool {
        !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !equipmentIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && telemetryFreshnessInterval.isFinite
            && telemetryFreshnessInterval > 0
            && targetObservationInterval.isFinite
            && targetObservationInterval > 0
            && procedureResponseInterval == 30
            && requestControlEvidenceAccepted
            && speedTargetEvidenceAccepted
            && inclinationTargetEvidenceAccepted
            && (!requiresStartForFirstStep || startEvidenceAccepted)
            && (!permitsStop || stopEvidenceAccepted)
    }
}

struct WorkoutOperatorReadiness: Equatable {
    let deckClear: Bool
    let consoleImmediatelyReachable: Bool
    let safetyKeyImmediatelyReachable: Bool
    let physicallyStationary: Bool

    var isConfirmed: Bool {
        deckClear && consoleImmediatelyReachable && safetyKeyImmediatelyReachable && physicallyStationary
    }
}

enum WorkoutControlPointIntent: Equatable {
    case requestControl
    case setTargetSpeed(WorkoutSpeed)
    case setTargetInclination(WorkoutInclination)
    case start
    case stop

    var mayMakeMotionPossible: Bool {
        switch self {
        case .setTargetSpeed, .setTargetInclination, .start:
            true
        case .requestControl, .stop:
            false
        }
    }
}

struct WorkoutProcedureRecord: Equatable {
    let id: ProcedureID
    let intent: WorkoutControlPointIntent
    let stepIndex: Int?
    let createdAt: MonotonicInstant
    var submittedAt: MonotonicInstant?
    var attAcceptedAt: MonotonicInstant?
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
    case acknowledged(record: WorkoutProcedureRecord, at: MonotonicInstant)
    case failed(record: WorkoutProcedureRecord, failure: WorkoutProcedureFailure)
    case timedOutUnknown(record: WorkoutProcedureRecord)

    var activeRecord: WorkoutProcedureRecord? {
        switch self {
        case .idle:
            nil
        case let .intentCreated(record), let .submitted(record), let .attAccepted(record, _),
             let .acknowledged(record, _), let .failed(record, _), let .timedOutUnknown(record):
            record
        }
    }

    var unresolvedRecord: WorkoutProcedureRecord? {
        switch self {
        case let .intentCreated(record), let .submitted(record), let .attAccepted(record, _):
            record
        case .idle, .acknowledged, .failed, .timedOutUnknown:
            nil
        }
    }
}

enum WorkoutProcedureOutcome: Equatable {
    case acknowledged(WorkoutProcedureRecord, at: MonotonicInstant)
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
        case let .connecting(epoch), let .ready(epoch, _), let .lost(epoch, _),
             let .invalidated(epoch, _):
            epoch
        }
    }

    var readyCapability: FR30zCapabilitySnapshot? {
        guard case let .ready(_, capability) = self else { return nil }
        return capability
    }
}

struct WorkoutTelemetrySample: Equatable {
    let speed: WorkoutSpeed?
    let inclination: WorkoutInclination?
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

enum WorkoutObservedMachineState: Equatable {
    case unknown
    case reported(WorkoutTelemetrySample)
    case stepTargetReported(stepIndex: Int, sample: WorkoutTelemetrySample)
    case humanConfirmedStopped(WorkoutHumanStopEvidence)
}

struct WorkoutHumanStopEvidence: Equatable {
    let confirmedAt: MonotonicInstant
    let note: String
}

struct ArmedWorkout: Equatable {
    let plan: WorkoutPlanValidator.ValidatedPlan
    let capability: FR30zCapabilitySnapshot
    let ceilings: WorkoutSessionCeilings
    let profile: FR30zExecutionProfile
}

struct WorkoutStepApplication: Equatable {
    let stepIndex: Int
    var remainingIntents: [WorkoutControlPointIntent]
    var speedAcknowledgedAt: MonotonicInstant?
    var inclinationAcknowledgedAt: MonotonicInstant?
    var startAcknowledgedAt: MonotonicInstant?
    var observationDeadline: MonotonicInstant?
}

struct WorkoutRunningStep: Equatable {
    let stepIndex: Int
    let accumulatedActiveSeconds: TimeInterval
    let segmentStartedAt: MonotonicInstant
}

enum WorkoutStopReason: Equatable {
    case userRequested
    case completedPlan
    case cancelled
}

struct WorkoutStopRequest: Equatable {
    let reason: WorkoutStopReason
    let requestedAt: MonotonicInstant
    let resumablePhase: WorkoutExecutionPhase
    let frozenRunningStep: WorkoutRunningStep?
}

enum WorkoutStopCommandOutcome: Equatable {
    case notSent
    case intentCreated(ProcedureID)
    case submitted(ProcedureID)
    case attAccepted(ProcedureID)
    case protocolAcknowledged(ProcedureID)
    case failed(ProcedureID, WorkoutProcedureFailure)
    case timedOutUnknown(ProcedureID)
}

struct WorkoutAwaitingHumanStop: Equatable {
    let reason: WorkoutStopReason
    var commandOutcome: WorkoutStopCommandOutcome
    let requestedAt: MonotonicInstant
}

enum WorkoutExecutionFailure: Equatable {
    case procedure(WorkoutProcedureFailure)
    case telemetry(String)
    case observationTimeout
    case connectionLost(String)
    case foregroundLost(String)
    case capabilityChanged
    case controlPermissionLost(String)
}

enum WorkoutEndOutcome: Equatable {
    case cancelledBeforeActuation
    case failedBeforeActuation(WorkoutExecutionFailure)
    case stopped(reason: WorkoutStopReason, command: WorkoutStopCommandOutcome, evidence: WorkoutHumanStopEvidence)
    case failedAfterPossibleMotion(WorkoutExecutionFailure, evidence: WorkoutHumanStopEvidence)
}

indirect enum WorkoutExecutionPhase: Equatable {
    case idle
    case armed
    case acquiringControl
    case readyToBegin
    case applyingStep(WorkoutStepApplication)
    case runningStep(WorkoutRunningStep)
    case stopConfirmationRequested(WorkoutStopRequest)
    case awaitingHumanStop(WorkoutAwaitingHumanStop)
    case failedAwaitingHumanStop(WorkoutExecutionFailure)
    case ended(WorkoutEndOutcome)
}

struct WorkoutExecutionState: Equatable {
    var connection: WorkoutConnectionState = .disconnected
    var controlPermission: WorkoutControlPermission = .notHeld
    var procedure: WorkoutProcedureState = .idle
    var telemetry: WorkoutTelemetryState = .unavailable("No current telemetry")
    var observedMachine: WorkoutObservedMachineState = .unknown
    var execution: WorkoutExecutionPhase = .idle
    var motionPossible = false
    var isForegroundActive = true
    var armedWorkout: ArmedWorkout?
    var procedureHistory: [WorkoutProcedureOutcome] = []
    var nextProcedureSequence: UInt64 = 1
    var completedActiveSeconds: TimeInterval = 0
    var frozenActiveSeconds: TimeInterval?
    var presentationStepIndex: Int?
    var lastEventTime = MonotonicInstant(seconds: 0)
}

enum WorkoutExecutionEvent: Equatable {
    case userStartsConnection(ConnectionEpoch)
    case connectionBecomesReady(epoch: ConnectionEpoch, capability: FR30zCapabilitySnapshot)
    case arm(plan: WorkoutPlanValidator.ValidatedPlan, ceilings: WorkoutSessionCeilings, profile: FR30zExecutionProfile)
    case userRequestsControl(epoch: ConnectionEpoch, readiness: WorkoutOperatorReadiness)
    case userBegins(epoch: ConnectionEpoch, readiness: WorkoutOperatorReadiness)
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
    case userRequestsStop(epoch: ConnectionEpoch, reason: WorkoutStopReason)
    case userCancelsStop(epoch: ConnectionEpoch)
    case userConfirmsStop(epoch: ConnectionEpoch)
    case humanConfirmsStopped(epoch: ConnectionEpoch, note: String)
    case humanObservesMotion(epoch: ConnectionEpoch)
    case connectionLost(epoch: ConnectionEpoch, reason: String)
    case capabilityChanged(epoch: ConnectionEpoch, capability: FR30zCapabilitySnapshot)
    case controlPermissionLost(epoch: ConnectionEpoch, reason: String)
    case appBecameInactive(epoch: ConnectionEpoch, reason: String)
}

enum WorkoutExecutionEffect: Equatable {
    case submit(WorkoutProcedureRecord)
    case directUserToConsoleAndSafetyKey
}

enum WorkoutGuardRejection: Equatable, Hashable, CaseIterable {
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
    case telemetryNotFresh
    case treadmillNotReportedStationary
    case appNotForeground
    case duplicateOrLateProcedure
    case stopAlreadyRequested
}

enum WorkoutReductionDisposition: Equatable {
    case accepted
    case rejected(WorkoutGuardRejection)
    case ignored(WorkoutGuardRejection)
    case failedClosed(WorkoutExecutionFailure)
}

struct WorkoutExecutionTransition: Equatable {
    let state: WorkoutExecutionState
    let effects: [WorkoutExecutionEffect]
    let disposition: WorkoutReductionDisposition
}

struct WorkoutExecutionReducer {
    let clock: () -> MonotonicInstant

    func reduce(_ original: WorkoutExecutionState, _ event: WorkoutExecutionEvent) -> WorkoutExecutionTransition {
        let now = clock()
        guard now.seconds.isFinite, now >= original.lastEventTime else {
            return .init(state: original, effects: [], disposition: .rejected(.nonMonotonicTime))
        }

        var state = original
        guard epochDisposition(for: event, state: state) == nil else {
            return .init(state: original, effects: [], disposition: epochDisposition(for: event, state: state)!)
        }
        if isTerminal(state.execution) {
            switch event {
            case .userStartsConnection, .connectionLost, .capabilityChanged:
                break
            default:
                let reason: WorkoutGuardRejection = isProcedureLifecycleEvent(event) ? .duplicateOrLateProcedure : .wrongState
                return .init(state: original, effects: [], disposition: .ignored(reason))
            }
        }
        state.lastEventTime = now

        var effects: [WorkoutExecutionEffect] = []
        var disposition: WorkoutReductionDisposition = .accepted

        if let responseID = protocolResponseProcedureID(event),
           case let .attAccepted(record, deadline) = state.procedure,
           now >= deadline {
            if responseID != record.id {
                return failCorrelation(state, received: responseID, now: now)
            }
            disposition = timeOutProcedure(record, state: &state, effects: &effects)
            return .init(state: state, effects: effects, disposition: disposition)
        }

        switch event {
        case let .userStartsConnection(epoch):
            guard canStartConnection(state) else { return rejected(original, .wrongState) }
            if let previousEpoch = state.connection.epoch, epoch.rawValue <= previousEpoch.rawValue {
                return rejected(original, .wrongEpoch)
            }
            state.connection = .connecting(epoch)
            state.controlPermission = .notHeld
            state.procedure = .idle
            state.telemetry = .unavailable("Awaiting current-epoch telemetry")
            state.observedMachine = .unknown
            state.isForegroundActive = true
            state.execution = .idle
            state.motionPossible = false
            state.armedWorkout = nil
            state.procedureHistory = []
            state.nextProcedureSequence = 1
            state.completedActiveSeconds = 0
            state.frozenActiveSeconds = nil
            state.presentationStepIndex = nil

        case let .connectionBecomesReady(epoch, capability):
            guard case .connecting(epoch) = state.connection else { return rejected(original, .wrongState) }
            guard capabilityIsComplete(capability) else { return rejected(original, .incompleteCapabilityEvidence) }
            state.connection = .ready(epoch: epoch, capability: capability)

        case let .arm(plan, ceilings, profile):
            guard case let .ready(_, capability) = state.connection, case .idle = state.execution else {
                return rejected(original, .connectionNotReady)
            }
            guard planAndCeilingsAreValid(plan, capability: capability, ceilings: ceilings) else {
                return rejected(original, .invalidPlanOrCeilings)
            }
            guard profile.isComplete, profile.equipmentIdentity == capability.equipmentIdentity else {
                return rejected(original, .incompleteOrMismatchedProfile)
            }
            state.armedWorkout = .init(plan: plan, capability: capability, ceilings: ceilings, profile: profile)
            state.telemetry = .unavailable("Awaiting telemetry matched to frozen execution bounds")
            state.observedMachine = .unknown
            state.execution = .armed

        case let .userRequestsControl(_, readiness):
            guard case .armed = state.execution,
                  case let .ready(epoch, capability) = state.connection,
                  state.isForegroundActive,
                  case .notHeld = state.controlPermission,
                  case .idle = state.procedure,
                  let armed = state.armedWorkout,
                  armed.capability == capability,
                  armed.profile.isComplete,
                  readiness.isConfirmed
            else {
                return rejected(original, requestControlRejection(state, readiness: readiness))
            }
            let record = makeProcedure(.requestControl, epoch: epoch, stepIndex: nil, now: now, state: &state)
            state.procedure = .intentCreated(record)
            state.controlPermission = .requesting(record.id)
            state.execution = .acquiringControl
            effects.append(.submit(record))

        case let .userBegins(_, readiness):
            guard case .readyToBegin = state.execution,
                  case let .ready(epoch, capability) = state.connection,
                  case .held(epoch, _) = state.controlPermission,
                  case .idle = state.procedure,
                  state.isForegroundActive,
                  readiness.isConfirmed,
                  let armed = state.armedWorkout,
                  armed.capability == capability,
                  telemetryIsFreshAndStationary(state.telemetry, now: now, profile: armed.profile)
            else {
                return rejected(original, beginRejection(state, readiness: readiness, now: now))
            }
            var application = newApplication(stepIndex: 0, armed: armed)
            guard let intent = application.remainingIntents.first else { return rejected(original, .incompleteOrMismatchedProfile) }
            application.remainingIntents.removeFirst()
            let record = makeProcedure(intent, epoch: epoch, stepIndex: 0, now: now, state: &state)
            state.procedure = .intentCreated(record)
            state.execution = .applyingStep(application)
            state.motionPossible = true
            state.presentationStepIndex = 0
            effects.append(.submit(record))

        case let .intentSubmitted(_, procedureID):
            guard case var .intentCreated(record) = state.procedure else {
                return lateOrWrongProcedure(original, procedureID: procedureID, now: now)
            }
            guard record.id == procedureID else {
                return failCorrelation(state, received: procedureID, now: now)
            }
            record.submittedAt = now
            state.procedure = .submitted(record)
            if record.intent == .stop { updateStopOutcome(&state, .submitted(record.id)) }

        case let .attAccepted(_, procedureID):
            guard case var .submitted(record) = state.procedure else {
                return lateOrWrongProcedure(original, procedureID: procedureID, now: now)
            }
            guard record.id == procedureID else { return failCorrelation(state, received: procedureID, now: now) }
            record.attAcceptedAt = now
            let deadline = now.advanced(by: state.armedWorkout?.profile.procedureResponseInterval ?? 30)
            state.procedure = .attAccepted(record: record, deadline: deadline)
            if record.intent == .stop { updateStopOutcome(&state, .attAccepted(record.id)) }

        case let .protocolAcknowledged(_, procedureID):
            guard case let .attAccepted(record, _) = state.procedure else {
                return lateOrWrongProcedure(original, procedureID: procedureID, now: now)
            }
            guard record.id == procedureID else { return failCorrelation(state, received: procedureID, now: now) }
            disposition = consumeAcknowledgement(record, at: now, state: &state, effects: &effects)

        case let .intentSubmissionRejected(_, procedureID, reason):
            disposition = failProcedure(procedureID, failure: .submissionRejected(reason), now: now, state: &state, effects: &effects)

        case let .attRejected(_, procedureID, reason):
            disposition = failProcedure(procedureID, failure: .attRejected(reason), now: now, state: &state, effects: &effects)

        case let .protocolRejected(_, procedureID, reason):
            disposition = failProcedure(procedureID, failure: .protocolRejected(reason), now: now, state: &state, effects: &effects)

        case let .protocolUnsupported(_, procedureID):
            disposition = failProcedure(procedureID, failure: .protocolUnsupported, now: now, state: &state, effects: &effects)

        case let .protocolMalformed(_, procedureID):
            disposition = failProcedure(procedureID, failure: .protocolMalformed, now: now, state: &state, effects: &effects)

        case let .protocolUnknown(_, procedureID):
            disposition = failProcedure(procedureID, failure: .protocolUnknown, now: now, state: &state, effects: &effects)

        case let .telemetry(_, input):
            disposition = consumeTelemetry(input, now: now, state: &state, effects: &effects)

        case .tick:
            disposition = consumeTick(now: now, state: &state, effects: &effects)

        case let .userRequestsStop(_, reason):
            guard !isTerminal(state.execution) else { return rejected(original, .wrongState) }
            switch state.execution {
            case .stopConfirmationRequested, .awaitingHumanStop, .failedAwaitingHumanStop:
                return rejected(original, .stopAlreadyRequested)
            default:
                break
            }
            let frozen = frozenRunningStep(from: state.execution, now: now)
            state.frozenActiveSeconds = state.completedActiveSeconds + (frozen?.accumulatedActiveSeconds ?? 0)
            state.execution = .stopConfirmationRequested(
                .init(reason: reason, requestedAt: now, resumablePhase: state.execution, frozenRunningStep: frozen)
            )

        case .userCancelsStop:
            guard case let .stopConfirmationRequested(request) = state.execution else { return rejected(original, .wrongState) }
            state.execution = restoredPhase(from: request, now: now)
            state.frozenActiveSeconds = nil

        case .userConfirmsStop:
            guard case let .stopConfirmationRequested(request) = state.execution else { return rejected(original, .wrongState) }
            guard state.motionPossible else {
                state.execution = .ended(.cancelledBeforeActuation)
                state.controlPermission = .invalidated("Execution ended before actuation")
                break
            }
            var waiting = WorkoutAwaitingHumanStop(reason: request.reason, commandOutcome: .notSent, requestedAt: request.requestedAt)
            if case let .ready(epoch, _) = state.connection,
               case .held(epoch, _) = state.controlPermission,
               case .idle = state.procedure,
               let profile = state.armedWorkout?.profile,
               profile.permitsStop,
               profile.stopEvidenceAccepted {
                let record = makeProcedure(.stop, epoch: epoch, stepIndex: nil, now: now, state: &state)
                state.procedure = .intentCreated(record)
                waiting.commandOutcome = .intentCreated(record.id)
                effects.append(.submit(record))
            } else {
                effects.append(.directUserToConsoleAndSafetyKey)
            }
            state.execution = .awaitingHumanStop(waiting)

        case let .humanConfirmsStopped(_, note):
            let evidence = WorkoutHumanStopEvidence(confirmedAt: now, note: note)
            let outcome: WorkoutEndOutcome
            switch state.execution {
            case let .awaitingHumanStop(waiting):
                outcome = .stopped(reason: waiting.reason, command: waiting.commandOutcome, evidence: evidence)
            case let .failedAwaitingHumanStop(failure):
                outcome = .failedAfterPossibleMotion(failure, evidence: evidence)
            default:
                return rejected(original, .wrongState)
            }
            state.motionPossible = false
            state.observedMachine = .humanConfirmedStopped(evidence)
            state.execution = .ended(outcome)
            state.controlPermission = .invalidated("Human stop confirmation ended execution")

        case .humanObservesMotion:
            state.motionPossible = true
            switch state.execution {
            case .applyingStep, .runningStep, .stopConfirmationRequested, .awaitingHumanStop, .failedAwaitingHumanStop:
                break
            default:
                disposition = failExecution(.telemetry("Unexpected human observation of motion"), state: &state, effects: &effects)
            }

        case let .connectionLost(_, reason):
            let epoch = state.connection.epoch!
            let terminal = isTerminal(state.execution)
            state.connection = .lost(previousEpoch: epoch, reason: reason)
            if terminal {
                state.controlPermission = .invalidated("Connection lost after execution ended")
                state.telemetry = .unavailable("Connection lost")
                break
            }
            if let record = state.procedure.unresolvedRecord {
                state.procedure = .timedOutUnknown(record: record)
                state.procedureHistory.append(.timedOutUnknown(record))
                if record.intent == .stop { updateStopOutcome(&state, .timedOutUnknown(record.id)) }
            }
            state.controlPermission = .invalidated("Connection lost")
            state.telemetry = .unavailable("Connection lost")
            state.observedMachine = .unknown
            if case .awaitingHumanStop = state.execution {
                effects.append(.directUserToConsoleAndSafetyKey)
                disposition = .failedClosed(.connectionLost(reason))
            } else {
                disposition = failExecution(.connectionLost(reason), state: &state, effects: &effects)
            }

        case let .capabilityChanged(_, capability):
            guard capability != state.connection.readyCapability else { break }
            let epoch = state.connection.epoch!
            state.connection = .invalidated(previousEpoch: epoch, reason: "Capability evidence changed")
            state.controlPermission = .invalidated("Capability evidence changed")
            if isTerminal(state.execution) { break }
            state.observedMachine = .unknown
            disposition = failExecutionPreservingStopOutcome(.capabilityChanged, state: &state, effects: &effects)

        case let .controlPermissionLost(_, reason):
            state.controlPermission = .invalidated(reason)
            disposition = failExecutionPreservingStopOutcome(.controlPermissionLost(reason), state: &state, effects: &effects)

        case let .appBecameInactive(_, reason):
            state.isForegroundActive = false
            state.controlPermission = .invalidated("App is not foreground-active")
            state.observedMachine = .unknown
            if let record = state.procedure.unresolvedRecord {
                state.procedure = .timedOutUnknown(record: record)
                state.procedureHistory.append(.timedOutUnknown(record))
                if record.intent == .stop { updateStopOutcome(&state, .timedOutUnknown(record.id)) }
            }
            if case .awaitingHumanStop = state.execution {
                effects.append(.directUserToConsoleAndSafetyKey)
                disposition = .failedClosed(.foregroundLost(reason))
            } else {
                disposition = failExecution(.foregroundLost(reason), state: &state, effects: &effects)
            }
        }

        return .init(state: state, effects: effects, disposition: disposition)
    }
}

private extension WorkoutExecutionReducer {
    func rejected(_ state: WorkoutExecutionState, _ reason: WorkoutGuardRejection) -> WorkoutExecutionTransition {
        .init(state: state, effects: [], disposition: .rejected(reason))
    }

    func eventEpoch(_ event: WorkoutExecutionEvent) -> ConnectionEpoch? {
        switch event {
        case .userStartsConnection, .arm:
            nil
        case let .connectionBecomesReady(epoch, _), let .userRequestsControl(epoch, _),
             let .userBegins(epoch, _), let .intentSubmitted(epoch, _),
             let .intentSubmissionRejected(epoch, _, _), let .attAccepted(epoch, _),
             let .attRejected(epoch, _, _), let .protocolAcknowledged(epoch, _),
             let .protocolRejected(epoch, _, _), let .protocolUnsupported(epoch, _),
             let .protocolMalformed(epoch, _), let .protocolUnknown(epoch, _),
             let .telemetry(epoch, _), let .tick(epoch),
             let .userRequestsStop(epoch, _), let .userCancelsStop(epoch),
             let .userConfirmsStop(epoch), let .humanConfirmsStopped(epoch, _),
             let .humanObservesMotion(epoch), let .connectionLost(epoch, _),
             let .capabilityChanged(epoch, _), let .controlPermissionLost(epoch, _),
             let .appBecameInactive(epoch, _):
            epoch
        }
    }

    func epochDisposition(for event: WorkoutExecutionEvent, state: WorkoutExecutionState) -> WorkoutReductionDisposition? {
        guard let supplied = eventEpoch(event) else { return nil }
        guard let current = state.connection.epoch else { return .rejected(.wrongEpoch) }
        if supplied.rawValue < current.rawValue { return .ignored(.staleEpoch) }
        if supplied != current { return .rejected(.wrongEpoch) }
        return nil
    }

    func canStartConnection(_ state: WorkoutExecutionState) -> Bool {
        switch (state.connection, state.execution) {
        case (.disconnected, .idle), (.lost, .idle), (.lost, .ended),
             (.invalidated, .idle), (.invalidated, .ended):
            true
        default:
            false
        }
    }

    func protocolResponseProcedureID(_ event: WorkoutExecutionEvent) -> ProcedureID? {
        switch event {
        case let .protocolAcknowledged(_, id), let .protocolRejected(_, id, _),
             let .protocolUnsupported(_, id), let .protocolMalformed(_, id),
             let .protocolUnknown(_, id):
            id
        default:
            nil
        }
    }

    func isProcedureLifecycleEvent(_ event: WorkoutExecutionEvent) -> Bool {
        switch event {
        case .intentSubmitted, .intentSubmissionRejected, .attAccepted, .attRejected,
             .protocolAcknowledged, .protocolRejected, .protocolUnsupported,
             .protocolMalformed, .protocolUnknown:
            true
        default:
            false
        }
    }

    func capabilityIsComplete(_ capability: FR30zCapabilitySnapshot) -> Bool {
        !capability.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !capability.equipmentIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && capability.controlPointSupportsWrite
            && capability.controlPointSupportsIndicate
            && capability.controlPointIndicationsEnabled
            && capability.passiveSubscriptionOutcomesResolved
    }

    func planAndCeilingsAreValid(
        _ validated: WorkoutPlanValidator.ValidatedPlan,
        capability: FR30zCapabilitySnapshot,
        ceilings: WorkoutSessionCeilings
    ) -> Bool {
        guard case let .success(revalidated) = WorkoutPlanValidator.validate(validated.plan, against: capability.planCapabilities),
              revalidated == validated,
              case let .supported(speedRange) = capability.planCapabilities.speed,
              case let .supported(inclinationRange) = capability.planCapabilities.inclination,
              ceilings.maximumSpeed.value.isFinite,
              ceilings.maximumInclination.value.isFinite,
              ceilings.maximumStepSpeedChange.value.isFinite,
              ceilings.maximumSpeed.value >= speedRange.minimum.value,
              ceilings.maximumSpeed.value <= speedRange.maximum.value,
              ceilings.maximumInclination.value >= inclinationRange.minimum.value,
              ceilings.maximumInclination.value <= inclinationRange.maximum.value,
              ceilings.maximumStepSpeedChange.value > 0,
              ceilings.maximumStepSpeedChange.value <= speedRange.maximum.value - speedRange.minimum.value
        else { return false }

        for (index, step) in validated.plan.steps.enumerated() {
            if step.targetSpeed.value > ceilings.maximumSpeed.value
                || step.targetInclination.value > ceilings.maximumInclination.value {
                return false
            }
            if index > 0 {
                let prior = validated.plan.steps[index - 1].targetSpeed.value
                if absDecimal(step.targetSpeed.value - prior) > ceilings.maximumStepSpeedChange.value {
                    return false
                }
            }
        }
        return true
    }

    func requestControlRejection(_ state: WorkoutExecutionState, readiness: WorkoutOperatorReadiness) -> WorkoutGuardRejection {
        guard state.isForegroundActive else { return .appNotForeground }
        guard readiness.isConfirmed else { return .operatorReadinessMissing }
        guard case .idle = state.procedure else { return .procedureBusy }
        guard case .ready = state.connection else { return .connectionNotReady }
        return .wrongState
    }

    func beginRejection(
        _ state: WorkoutExecutionState,
        readiness: WorkoutOperatorReadiness,
        now: MonotonicInstant
    ) -> WorkoutGuardRejection {
        guard state.isForegroundActive else { return .appNotForeground }
        guard readiness.isConfirmed else { return .operatorReadinessMissing }
        guard case .idle = state.procedure else { return .procedureBusy }
        guard case .held = state.controlPermission else { return .controlNotHeld }
        guard case .fresh(let sample) = state.telemetry else { return .telemetryNotFresh }
        guard let speed = sample.speed, sample.inclination != nil else { return .telemetryNotFresh }
        guard let profile = state.armedWorkout?.profile,
              now.seconds - sample.receivedAt.seconds <= profile.telemetryFreshnessInterval
        else { return .telemetryNotFresh }
        guard speed.value == 0 else { return .treadmillNotReportedStationary }
        return .wrongState
    }

    func telemetryIsFreshAndStationary(
        _ telemetry: WorkoutTelemetryState,
        now: MonotonicInstant,
        profile: FR30zExecutionProfile
    ) -> Bool {
        guard case let .fresh(sample) = telemetry,
              let speed = sample.speed,
              sample.inclination != nil
        else { return false }
        return speed.value == 0 && now.seconds - sample.receivedAt.seconds <= profile.telemetryFreshnessInterval
    }

    func telemetryIsFreshAndComplete(
        _ telemetry: WorkoutTelemetryState,
        now: MonotonicInstant,
        profile: FR30zExecutionProfile
    ) -> Bool {
        guard case let .fresh(sample) = telemetry,
              sample.speed != nil,
              sample.inclination != nil
        else { return false }
        return now.seconds - sample.receivedAt.seconds <= profile.telemetryFreshnessInterval
    }

    func makeProcedure(
        _ intent: WorkoutControlPointIntent,
        epoch: ConnectionEpoch,
        stepIndex: Int?,
        now: MonotonicInstant,
        state: inout WorkoutExecutionState
    ) -> WorkoutProcedureRecord {
        let id = ProcedureID(epoch: epoch, sequence: state.nextProcedureSequence)
        state.nextProcedureSequence += 1
        return .init(id: id, intent: intent, stepIndex: stepIndex, createdAt: now)
    }

    func newApplication(stepIndex: Int, armed: ArmedWorkout) -> WorkoutStepApplication {
        let step = armed.plan.plan.steps[stepIndex]
        var intents: [WorkoutControlPointIntent]
        switch armed.profile.targetOrder {
        case .speedThenInclination:
            intents = [.setTargetSpeed(step.targetSpeed), .setTargetInclination(step.targetInclination)]
        case .inclinationThenSpeed:
            intents = [.setTargetInclination(step.targetInclination), .setTargetSpeed(step.targetSpeed)]
        }
        if stepIndex == 0, armed.profile.requiresStartForFirstStep { intents.append(.start) }
        return .init(
            stepIndex: stepIndex,
            remainingIntents: intents,
            speedAcknowledgedAt: nil,
            inclinationAcknowledgedAt: nil,
            startAcknowledgedAt: nil,
            observationDeadline: nil
        )
    }

    func consumeAcknowledgement(
        _ record: WorkoutProcedureRecord,
        at now: MonotonicInstant,
        state: inout WorkoutExecutionState,
        effects: inout [WorkoutExecutionEffect]
    ) -> WorkoutReductionDisposition {
        switch record.intent {
        case .requestControl:
            guard case .acquiringControl = state.execution else {
                return recordLateAcknowledgement(record, at: now, state: &state, effects: &effects)
            }
            state.procedureHistory.append(.acknowledged(record, at: now))
            state.procedure = .idle
            state.controlPermission = .held(epoch: record.id.epoch, acknowledgedAt: now)
            state.execution = .readyToBegin
        case .setTargetSpeed, .setTargetInclination, .start:
            guard case var .applyingStep(application) = state.execution,
                  let armed = state.armedWorkout,
                  case let .ready(epoch, _) = state.connection
            else {
                return recordLateAcknowledgement(record, at: now, state: &state, effects: &effects)
            }
            state.procedureHistory.append(.acknowledged(record, at: now))
            switch record.intent {
            case .setTargetSpeed: application.speedAcknowledgedAt = now
            case .setTargetInclination: application.inclinationAcknowledgedAt = now
            case .start: application.startAcknowledgedAt = now
            default: break
            }
            if let next = application.remainingIntents.first {
                guard telemetryIsFreshAndComplete(state.telemetry, now: now, profile: armed.profile) else {
                    if case let .fresh(sample) = state.telemetry {
                        state.telemetry = .stale(sample)
                    }
                    state.observedMachine = .unknown
                    return failExecution(.telemetry("Telemetry is not fresh during command progression"), state: &state, effects: &effects)
                }
                application.remainingIntents.removeFirst()
                let nextRecord = makeProcedure(next, epoch: epoch, stepIndex: application.stepIndex, now: now, state: &state)
                state.procedure = .intentCreated(nextRecord)
                state.execution = .applyingStep(application)
                state.motionPossible = state.motionPossible || next.mayMakeMotionPossible
                effects.append(.submit(nextRecord))
            } else {
                application.observationDeadline = now.advanced(by: armed.profile.targetObservationInterval)
                state.procedure = .idle
                state.execution = .applyingStep(application)
            }
        case .stop:
            guard case .awaitingHumanStop = state.execution else {
                return recordLateAcknowledgement(record, at: now, state: &state, effects: &effects)
            }
            state.procedureHistory.append(.acknowledged(record, at: now))
            state.procedure = .acknowledged(record: record, at: now)
            updateStopOutcome(&state, .protocolAcknowledged(record.id))
        }
        return .accepted
    }

    func recordLateAcknowledgement(
        _ record: WorkoutProcedureRecord,
        at now: MonotonicInstant,
        state: inout WorkoutExecutionState,
        effects: inout [WorkoutExecutionEffect]
    ) -> WorkoutReductionDisposition {
        let failure = WorkoutProcedureFailure.duplicateOrLate(record.id)
        state.procedureHistory.append(.acknowledged(record, at: now))
        state.procedure = .acknowledged(record: record, at: now)
        state.controlPermission = .invalidated("Late procedure acknowledgement")
        return failExecutionPreservingStopOutcome(.procedure(failure), state: &state, effects: &effects)
    }

    func lateOrWrongProcedure(
        _ state: WorkoutExecutionState,
        procedureID: ProcedureID,
        now: MonotonicInstant
    ) -> WorkoutExecutionTransition {
        guard let active = state.procedure.activeRecord else {
            var failedState = state
            var effects: [WorkoutExecutionEffect] = []
            let failure = WorkoutProcedureFailure.duplicateOrLate(procedureID)
            failedState.controlPermission = .invalidated("Duplicate or late procedure evidence")
            let disposition = failExecution(.procedure(failure), state: &failedState, effects: &effects)
            failedState.lastEventTime = now
            return .init(state: failedState, effects: effects, disposition: disposition)
        }
        if active.id != procedureID { return failCorrelation(state, received: procedureID, now: now) }
        var failedState = state
        var effects: [WorkoutExecutionEffect] = []
        let failure = WorkoutProcedureFailure.duplicateOrLate(procedureID)
        _ = failProcedure(procedureID, failure: failure, now: now, state: &failedState, effects: &effects)
        failedState.lastEventTime = now
        return .init(state: failedState, effects: effects, disposition: .failedClosed(.procedure(failure)))
    }

    func failCorrelation(
        _ original: WorkoutExecutionState,
        received: ProcedureID,
        now: MonotonicInstant
    ) -> WorkoutExecutionTransition {
        var state = original
        var effects: [WorkoutExecutionEffect] = []
        let expected = state.procedure.activeRecord!.id
        let failure = WorkoutProcedureFailure.correlationFailure(expected: expected, received: received)
        _ = failProcedure(expected, failure: failure, now: now, state: &state, effects: &effects)
        state.lastEventTime = now
        return .init(state: state, effects: effects, disposition: .failedClosed(.procedure(failure)))
    }

    func failProcedure(
        _ procedureID: ProcedureID,
        failure: WorkoutProcedureFailure,
        now: MonotonicInstant,
        state: inout WorkoutExecutionState,
        effects: inout [WorkoutExecutionEffect]
    ) -> WorkoutReductionDisposition {
        guard let record = state.procedure.activeRecord else { return .ignored(.duplicateOrLateProcedure) }
        guard record.id == procedureID else {
            let mismatch = WorkoutProcedureFailure.correlationFailure(expected: record.id, received: procedureID)
            state.procedure = .failed(record: record, failure: mismatch)
            state.procedureHistory.append(.failed(record, mismatch))
            state.controlPermission = .invalidated("Procedure correlation failed")
            return failExecution(.procedure(mismatch), state: &state, effects: &effects)
        }
        state.procedure = .failed(record: record, failure: failure)
        state.procedureHistory.append(.failed(record, failure))
        state.controlPermission = .invalidated("Procedure failed")
        if record.intent == .stop {
            updateStopOutcome(&state, .failed(record.id, failure))
            effects.append(.directUserToConsoleAndSafetyKey)
            return .failedClosed(.procedure(failure))
        }
        return failExecutionPreservingStopOutcome(.procedure(failure), state: &state, effects: &effects)
    }

    func consumeTelemetry(
        _ input: WorkoutTelemetryInput,
        now: MonotonicInstant,
        state: inout WorkoutExecutionState,
        effects: inout [WorkoutExecutionEffect]
    ) -> WorkoutReductionDisposition {
        if case let .applyingStep(application) = state.execution,
           let deadline = application.observationDeadline,
           now >= deadline {
            return failExecution(.observationTimeout, state: &state, effects: &effects)
        }
        switch input {
        case let .unavailable(reason):
            state.telemetry = .unavailable(reason)
            state.observedMachine = .unknown
            if isApplyingOrRunning(state.execution) {
                return failExecution(.telemetry(reason), state: &state, effects: &effects)
            }
        case let .malformed(reason):
            state.telemetry = .malformed(reason)
            state.observedMachine = .unknown
            if isApplyingOrRunning(state.execution) {
                return failExecution(.telemetry(reason), state: &state, effects: &effects)
            }
        case let .sample(speed, inclination, distance):
            let sample = WorkoutTelemetrySample(
                speed: speed,
                inclination: inclination,
                totalDistanceMetres: distance,
                receivedAt: now
            )
            guard speed != nil, inclination != nil else {
                state.telemetry = .unavailable("Required speed or inclination field missing")
                state.observedMachine = .unknown
                if isApplyingOrRunning(state.execution) {
                    return failExecution(.telemetry("Required field missing"), state: &state, effects: &effects)
                }
                return .accepted
            }
            if speed!.value > 0 { state.motionPossible = true }
            guard sampleIsInsideFrozenBounds(sample, state: state) else {
                state.telemetry = .contradictory("Telemetry lies outside frozen capabilities or session ceilings")
                state.observedMachine = .unknown
                return failExecutionPreservingStopOutcome(
                    .telemetry("Contradictory telemetry"),
                    state: &state,
                    effects: &effects
                )
            }
            state.telemetry = .fresh(sample)
            state.observedMachine = .reported(sample)
            switch state.execution {
            case let .applyingStep(application):
                if sampleConfirms(application: application, sample: sample, state: state) {
                    state.observedMachine = .stepTargetReported(stepIndex: application.stepIndex, sample: sample)
                    state.execution = .runningStep(
                        .init(stepIndex: application.stepIndex, accumulatedActiveSeconds: 0, segmentStartedAt: now)
                    )
                }
            case let .runningStep(running):
                if !sampleMatchesStep(sample, stepIndex: running.stepIndex, state: state) {
                    state.telemetry = .contradictory("A confirmed step target changed")
                    state.observedMachine = .unknown
                    return failExecution(.telemetry("Contradictory confirmed target"), state: &state, effects: &effects)
                }
                state.observedMachine = .stepTargetReported(stepIndex: running.stepIndex, sample: sample)
            default:
                break
            }
        }
        return .accepted
    }

    func consumeTick(
        now: MonotonicInstant,
        state: inout WorkoutExecutionState,
        effects: inout [WorkoutExecutionEffect]
    ) -> WorkoutReductionDisposition {
        if case let .attAccepted(record, deadline) = state.procedure, now >= deadline {
            return timeOutProcedure(record, state: &state, effects: &effects)
        }
        if case let .fresh(sample) = state.telemetry,
           let profile = state.armedWorkout?.profile,
           now.seconds - sample.receivedAt.seconds > profile.telemetryFreshnessInterval {
            state.telemetry = .stale(sample)
            state.observedMachine = .unknown
            if isApplyingOrRunning(state.execution) {
                return failExecution(.telemetry("Telemetry became stale"), state: &state, effects: &effects)
            }
        }
        if case let .applyingStep(application) = state.execution,
           let deadline = application.observationDeadline,
           now >= deadline {
            return failExecution(.observationTimeout, state: &state, effects: &effects)
        }
        if case let .runningStep(running) = state.execution,
           let armed = state.armedWorkout {
            let active = running.accumulatedActiveSeconds + now.seconds - running.segmentStartedAt.seconds
            let required = TimeInterval(armed.plan.plan.steps[running.stepIndex].duration.value)
            if active >= required {
                if running.stepIndex + 1 < armed.plan.plan.steps.count {
                    state.completedActiveSeconds += required
                    var next = newApplication(stepIndex: running.stepIndex + 1, armed: armed)
                    let intent = next.remainingIntents.removeFirst()
                    guard case let .ready(epoch, _) = state.connection,
                          case .held(epoch, _) = state.controlPermission,
                          case .idle = state.procedure,
                          state.isForegroundActive
                    else {
                        return failExecution(.controlPermissionLost("Step transition guards failed"), state: &state, effects: &effects)
                    }
                    let record = makeProcedure(intent, epoch: epoch, stepIndex: next.stepIndex, now: now, state: &state)
                    state.procedure = .intentCreated(record)
                    state.execution = .applyingStep(next)
                    state.presentationStepIndex = next.stepIndex
                    if case let .fresh(sample) = state.telemetry {
                        state.observedMachine = .reported(sample)
                    } else {
                        state.observedMachine = .unknown
                    }
                    effects.append(.submit(record))
                } else {
                    let frozen = WorkoutRunningStep(
                        stepIndex: running.stepIndex,
                        accumulatedActiveSeconds: required,
                        segmentStartedAt: now
                    )
                    state.frozenActiveSeconds = state.completedActiveSeconds + required
                    state.execution = .stopConfirmationRequested(
                        .init(reason: .completedPlan, requestedAt: now, resumablePhase: .runningStep(frozen), frozenRunningStep: frozen)
                    )
                }
            }
        }
        return .accepted
    }

    func timeOutProcedure(
        _ record: WorkoutProcedureRecord,
        state: inout WorkoutExecutionState,
        effects: inout [WorkoutExecutionEffect]
    ) -> WorkoutReductionDisposition {
        state.procedure = .timedOutUnknown(record: record)
        state.procedureHistory.append(.timedOutUnknown(record))
        state.controlPermission = .invalidated("Procedure response timed out")
        updateStopOutcome(&state, .timedOutUnknown(record.id))
        if record.intent == .stop {
            effects.append(.directUserToConsoleAndSafetyKey)
            return .failedClosed(.procedure(.responseTimeout))
        }
        return failExecutionPreservingStopOutcome(.procedure(.responseTimeout), state: &state, effects: &effects)
    }

    func sampleIsInsideFrozenBounds(_ sample: WorkoutTelemetrySample, state: WorkoutExecutionState) -> Bool {
        guard let armed = state.armedWorkout,
              let speed = sample.speed,
              let inclination = sample.inclination,
              case let .supported(speedRange) = armed.capability.planCapabilities.speed,
              case let .supported(inclinationRange) = armed.capability.planCapabilities.inclination
        else { return state.armedWorkout == nil }
        return speed.value >= speedRange.minimum.value
            && speed.value <= speedRange.maximum.value
            && inclination.value >= inclinationRange.minimum.value
            && inclination.value <= inclinationRange.maximum.value
            && speed.value <= armed.ceilings.maximumSpeed.value
            && inclination.value <= armed.ceilings.maximumInclination.value
    }

    func sampleConfirms(
        application: WorkoutStepApplication,
        sample: WorkoutTelemetrySample,
        state: WorkoutExecutionState
    ) -> Bool {
        guard application.remainingIntents.isEmpty,
              let speedAt = application.speedAcknowledgedAt,
              let inclineAt = application.inclinationAcknowledgedAt,
              sample.receivedAt > speedAt,
              sample.receivedAt > inclineAt,
              application.observationDeadline != nil
        else { return false }
        return sampleMatchesStep(sample, stepIndex: application.stepIndex, state: state)
    }

    func sampleMatchesStep(_ sample: WorkoutTelemetrySample, stepIndex: Int, state: WorkoutExecutionState) -> Bool {
        guard let step = state.armedWorkout?.plan.plan.steps[stepIndex] else { return false }
        return sample.speed == step.targetSpeed && sample.inclination == step.targetInclination
    }

    func failExecution(
        _ failure: WorkoutExecutionFailure,
        state: inout WorkoutExecutionState,
        effects: inout [WorkoutExecutionEffect]
    ) -> WorkoutReductionDisposition {
        guard !isTerminal(state.execution) else { return .failedClosed(failure) }
        state.observedMachine = .unknown
        if state.motionPossible {
            state.frozenActiveSeconds = state.completedActiveSeconds + activeSeconds(in: state.execution, at: state.lastEventTime)
            state.execution = .failedAwaitingHumanStop(failure)
            effects.append(.directUserToConsoleAndSafetyKey)
        } else {
            state.execution = .ended(.failedBeforeActuation(failure))
        }
        return .failedClosed(failure)
    }

    func failExecutionPreservingStopOutcome(
        _ failure: WorkoutExecutionFailure,
        state: inout WorkoutExecutionState,
        effects: inout [WorkoutExecutionEffect]
    ) -> WorkoutReductionDisposition {
        guard case .awaitingHumanStop = state.execution else {
            return failExecution(failure, state: &state, effects: &effects)
        }
        state.observedMachine = .unknown
        if !effects.contains(.directUserToConsoleAndSafetyKey) {
            effects.append(.directUserToConsoleAndSafetyKey)
        }
        return .failedClosed(failure)
    }

    func updateStopOutcome(_ state: inout WorkoutExecutionState, _ outcome: WorkoutStopCommandOutcome) {
        guard case var .awaitingHumanStop(waiting) = state.execution else { return }
        waiting.commandOutcome = outcome
        state.execution = .awaitingHumanStop(waiting)
    }

    func frozenRunningStep(from phase: WorkoutExecutionPhase, now: MonotonicInstant) -> WorkoutRunningStep? {
        guard case let .runningStep(running) = phase else { return nil }
        return .init(
            stepIndex: running.stepIndex,
            accumulatedActiveSeconds: running.accumulatedActiveSeconds + now.seconds - running.segmentStartedAt.seconds,
            segmentStartedAt: now
        )
    }

    func activeSeconds(in phase: WorkoutExecutionPhase, at now: MonotonicInstant) -> TimeInterval {
        switch phase {
        case let .runningStep(running):
            running.accumulatedActiveSeconds + now.seconds - running.segmentStartedAt.seconds
        case let .stopConfirmationRequested(request):
            request.frozenRunningStep?.accumulatedActiveSeconds ?? 0
        default:
            0
        }
    }

    func restoredPhase(from request: WorkoutStopRequest, now: MonotonicInstant) -> WorkoutExecutionPhase {
        guard let frozen = request.frozenRunningStep else { return request.resumablePhase }
        return .runningStep(
            .init(stepIndex: frozen.stepIndex, accumulatedActiveSeconds: frozen.accumulatedActiveSeconds, segmentStartedAt: now)
        )
    }

    func isApplyingOrRunning(_ phase: WorkoutExecutionPhase) -> Bool {
        switch phase {
        case .applyingStep, .runningStep: true
        default: false
        }
    }

    func isTerminal(_ phase: WorkoutExecutionPhase) -> Bool {
        if case .ended = phase { return true }
        return false
    }

    func absDecimal(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}

enum WorkoutPreflightBlocker: Equatable {
    case connectionNotReady
    case planNotArmed
    case controlNotHeld
    case telemetryNotFresh
    case treadmillNotReportedStationary
    case appNotForeground
}

enum WorkoutCommandPresentationState: Equatable {
    case notRequested
    case intentCreated
    case submitted
    case attAccepted
    case protocolAcknowledged
    case targetObserved
    case failed
}

enum WorkoutStopPresentationState: Equatable {
    case available
    case confirmationRequired
    case notSentUsePhysicalControls
    case intentCreated
    case submitted
    case attAccepted
    case sentUnconfirmed
    case failedUsePhysicalControls
    case humanConfirmed
    case endedWithoutPhysicalStopClaim
}

enum WorkoutDistancePresentation: Equatable {
    case trustworthy(metres: Decimal, sampledAt: MonotonicInstant)
    case unavailable
}

struct WorkoutStepPresentation: Equatable {
    let index: Int
    let label: String
    let requestedSpeed: WorkoutSpeed
    let requestedInclination: WorkoutInclination
    let remainingSeconds: Int
}

struct WorkoutExecutionPresentation: Equatable {
    let preflightBlockers: [WorkoutPreflightBlocker]
    let activity: WorkoutActivity?
    let currentStep: WorkoutStepPresentation?
    let nextStep: WorkoutStepPresentation?
    let requestedSpeed: WorkoutSpeed?
    let actualSpeed: WorkoutSpeed?
    let speedCommandState: WorkoutCommandPresentationState
    let requestedInclination: WorkoutInclination?
    let actualInclination: WorkoutInclination?
    let inclinationCommandState: WorkoutCommandPresentationState
    let elapsedActiveSeconds: Int
    let distance: WorkoutDistancePresentation
    let stopState: WorkoutStopPresentationState
    let frozenCeilings: WorkoutSessionCeilings?
    let executionProfileIdentity: String?

    init(state: WorkoutExecutionState) {
        var blockers: [WorkoutPreflightBlocker] = []
        if state.connection.readyCapability == nil { blockers.append(.connectionNotReady) }
        if state.armedWorkout == nil { blockers.append(.planNotArmed) }
        if case .held = state.controlPermission {} else { blockers.append(.controlNotHeld) }
        if case let .fresh(sample) = state.telemetry,
           let profile = state.armedWorkout?.profile,
           state.lastEventTime.seconds - sample.receivedAt.seconds <= profile.telemetryFreshnessInterval {
            if let speed = sample.speed, sample.inclination != nil {
                if speed.value != 0, Self.isAwaitingBegin(state.execution) {
                    blockers.append(.treadmillNotReportedStationary)
                }
            } else {
                blockers.append(.telemetryNotFresh)
            }
        } else {
            blockers.append(.telemetryNotFresh)
        }
        if !state.isForegroundActive { blockers.append(.appNotForeground) }
        preflightBlockers = blockers
        activity = state.armedWorkout?.plan.plan.activity

        let stepIndex: Int?
        let remaining: Int
        switch state.execution {
        case let .applyingStep(application):
            stepIndex = application.stepIndex
            remaining = state.armedWorkout?.plan.plan.steps[application.stepIndex].duration.value ?? 0
        case let .runningStep(running):
            stepIndex = running.stepIndex
            let duration = state.armedWorkout?.plan.plan.steps[running.stepIndex].duration.value ?? 0
            let elapsed = running.accumulatedActiveSeconds + state.lastEventTime.seconds - running.segmentStartedAt.seconds
            remaining = max(0, duration - Int(elapsed.rounded(.down)))
        case let .stopConfirmationRequested(request):
            if let frozen = request.frozenRunningStep {
                stepIndex = frozen.stepIndex
                let duration = state.armedWorkout?.plan.plan.steps[frozen.stepIndex].duration.value ?? 0
                remaining = max(0, duration - Int(frozen.accumulatedActiveSeconds.rounded(.down)))
            } else {
                stepIndex = nil
                remaining = 0
            }
        default:
            stepIndex = state.presentationStepIndex
            if let stepIndex,
               let frozenTotal = state.frozenActiveSeconds {
                let currentActive = max(0, frozenTotal - state.completedActiveSeconds)
                let duration = state.armedWorkout?.plan.plan.steps[stepIndex].duration.value ?? 0
                remaining = max(0, duration - Int(currentActive.rounded(.down)))
            } else {
                remaining = 0
            }
        }

        if let stepIndex, let plan = state.armedWorkout?.plan.plan {
            let step = plan.steps[stepIndex]
            currentStep = .init(index: stepIndex, label: step.label, requestedSpeed: step.targetSpeed, requestedInclination: step.targetInclination, remainingSeconds: remaining)
            if stepIndex + 1 < plan.steps.count {
                let next = plan.steps[stepIndex + 1]
                nextStep = .init(index: stepIndex + 1, label: next.label, requestedSpeed: next.targetSpeed, requestedInclination: next.targetInclination, remainingSeconds: next.duration.value)
            } else {
                nextStep = nil
            }
            requestedSpeed = step.targetSpeed
            requestedInclination = step.targetInclination
        } else {
            currentStep = nil
            nextStep = nil
            requestedSpeed = nil
            requestedInclination = nil
        }

        if case let .fresh(sample) = state.telemetry,
           let profile = state.armedWorkout?.profile,
           state.lastEventTime.seconds - sample.receivedAt.seconds <= profile.telemetryFreshnessInterval {
            actualSpeed = sample.speed
            actualInclination = sample.inclination
            if let metres = sample.totalDistanceMetres {
                distance = .trustworthy(metres: metres, sampledAt: sample.receivedAt)
            } else {
                distance = .unavailable
            }
        } else {
            actualSpeed = nil
            actualInclination = nil
            distance = .unavailable
        }

        speedCommandState = Self.commandState(for: .speed, state: state)
        inclinationCommandState = Self.commandState(for: .inclination, state: state)
        elapsedActiveSeconds = Int((state.frozenActiveSeconds ?? (state.completedActiveSeconds + Self.currentActiveSeconds(state))).rounded(.down))
        stopState = Self.stopState(state)
        frozenCeilings = state.armedWorkout?.ceilings
        executionProfileIdentity = state.armedWorkout?.profile.identity
    }

    private enum Axis { case speed, inclination }

    private static func isAwaitingBegin(_ phase: WorkoutExecutionPhase) -> Bool {
        switch phase {
        case .armed, .acquiringControl, .readyToBegin:
            true
        default:
            false
        }
    }

    private static func commandState(for axis: Axis, state: WorkoutExecutionState) -> WorkoutCommandPresentationState {
        if case .stepTargetReported = state.observedMachine { return .targetObserved }
        let currentStepIndex = state.presentationStepIndex
        let matches: (WorkoutControlPointIntent) -> Bool = { intent in
            switch (axis, intent) {
            case (.speed, .setTargetSpeed), (.inclination, .setTargetInclination): true
            default: false
            }
        }
        if let record = state.procedure.activeRecord,
           record.stepIndex == currentStepIndex,
           matches(record.intent) {
            switch state.procedure {
            case .intentCreated: return .intentCreated
            case .submitted: return .submitted
            case .attAccepted: return .attAccepted
            case .acknowledged: return .protocolAcknowledged
            case .failed, .timedOutUnknown: return .failed
            case .idle: break
            }
        }
        for outcome in state.procedureHistory.reversed() {
            switch outcome {
            case let .acknowledged(record, _) where record.stepIndex == currentStepIndex && matches(record.intent):
                return .protocolAcknowledged
            case let .failed(record, _) where record.stepIndex == currentStepIndex && matches(record.intent):
                return .failed
            case let .timedOutUnknown(record) where record.stepIndex == currentStepIndex && matches(record.intent):
                return .failed
            default: continue
            }
        }
        return .notRequested
    }

    private static func currentActiveSeconds(_ state: WorkoutExecutionState) -> TimeInterval {
        switch state.execution {
        case let .runningStep(running):
            running.accumulatedActiveSeconds + state.lastEventTime.seconds - running.segmentStartedAt.seconds
        case let .stopConfirmationRequested(request):
            request.frozenRunningStep?.accumulatedActiveSeconds ?? 0
        default:
            0
        }
    }

    private static func stopState(_ state: WorkoutExecutionState) -> WorkoutStopPresentationState {
        if case .humanConfirmedStopped = state.observedMachine { return .humanConfirmed }
        switch state.execution {
        case .stopConfirmationRequested:
            return .confirmationRequired
        case let .awaitingHumanStop(waiting):
            switch waiting.commandOutcome {
            case .notSent: return .notSentUsePhysicalControls
            case .intentCreated: return .intentCreated
            case .submitted: return .submitted
            case .attAccepted: return .attAccepted
            case .protocolAcknowledged, .timedOutUnknown: return .sentUnconfirmed
            case .failed: return .failedUsePhysicalControls
            }
        case .failedAwaitingHumanStop:
            return .failedUsePhysicalControls
        case let .ended(outcome):
            switch outcome {
            case .stopped, .failedAfterPossibleMotion:
                return .humanConfirmed
            case .cancelledBeforeActuation, .failedBeforeActuation:
                return .endedWithoutPhysicalStopClaim
            }
        default:
            return .available
        }
    }
}

private extension Decimal {
    var isFinite: Bool { !isNaN }
}
