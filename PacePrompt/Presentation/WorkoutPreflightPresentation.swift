import Foundation

enum WorkoutPreflightStage: Equatable {
    case disconnected
    case preparing
    case unsupported
    case stale
    case lockedOrUnknown
    case readyToRequestControl
    case requestingControl
    case readyToBegin
    case waitingForPhysicalStart
    case failed
}

enum WorkoutPreflightTone: Equatable {
    case neutral
    case warning
    case ready
    case failure
}

struct WorkoutPreflightStatusPresentation: Equatable {
    let title: String
    let detail: String
    let symbol: String
    let tone: WorkoutPreflightTone
}

enum WorkoutPreflightConfirmationKind: String, CaseIterable, Equatable {
    case activity
    case deckClear
    case consoleReachable
    case safetyKeyReachable
    case physicallyStationary
}

struct WorkoutPreflightConfirmationPresentation: Equatable, Identifiable {
    let kind: WorkoutPreflightConfirmationKind
    let title: String
    let detail: String
    let isConfirmed: Bool

    var id: WorkoutPreflightConfirmationKind { kind }
}

enum WorkoutPreflightIntent: Equatable {
    case setConfirmation(WorkoutPreflightConfirmationKind, Bool)
    case beginWorkout
}

struct WorkoutPreflightContext: Equatable {
    let validatedPlan: WorkoutPlanValidator.ValidatedPlan
    let ceilings: WorkoutSessionCeilings
    let profile: FR30zExecutionProfile
    let executionState: WorkoutExecutionState
    let operatorReadiness: WorkoutOperatorReadiness
    let activityConfirmed: Bool
}

struct WorkoutPreflightPresentation: Equatable {
    let stage: WorkoutPreflightStage
    let status: WorkoutPreflightStatusPresentation
    let planName: String
    let planTotals: String
    let activity: String
    let activitySymbol: String
    let speedCeiling: String
    let inclinationCeiling: String
    let maximumStepSpeedChange: String
    let initialStepLabel: String
    let initialSpeed: String
    let initialInclination: String
    let confirmations: [WorkoutPreflightConfirmationPresentation]
    let canEditConfirmations: Bool
    let canBeginWorkout: Bool

    var isWaitingForPhysicalStart: Bool {
        stage == .waitingForPhysicalStart
    }

    init(
        context: WorkoutPreflightContext,
        at now: MonotonicInstant,
        locale: Locale = .autoupdatingCurrent
    ) {
        let plan = context.validatedPlan.plan
        precondition(!plan.steps.isEmpty, "A validated plan must contain at least one step")
        let preview = WorkoutPlanPreview(validatedPlan: context.validatedPlan)
        let initialStep = plan.steps[0]

        planName = plan.suggestedName
        planTotals = Self.planTotals(preview: preview, locale: locale)
        switch plan.activity {
        case .indoorWalking:
            activity = "Indoor walking"
            activitySymbol = "figure.walk"
        case .indoorRunning:
            activity = "Indoor running"
            activitySymbol = "figure.run"
        }
        speedCeiling = Self.measurement(
            context.ceilings.maximumSpeed.value,
            unit: "km/h",
            locale: locale
        )
        inclinationCeiling = Self.measurement(
            context.ceilings.maximumInclination.value,
            unit: "%",
            locale: locale
        )
        maximumStepSpeedChange = Self.measurement(
            context.ceilings.maximumStepSpeedChange.value,
            unit: "km/h",
            locale: locale
        )
        initialStepLabel = initialStep.label
        initialSpeed = Self.measurement(initialStep.targetSpeed.value, unit: "km/h", locale: locale)
        initialInclination = Self.measurement(
            initialStep.targetInclination.value,
            unit: "%",
            locale: locale
        )

        stage = Self.stage(for: context, at: now)
        status = Self.status(for: stage)
        confirmations = Self.confirmations(for: context, activity: activity)
        canEditConfirmations = stage == .readyToRequestControl || stage == .readyToBegin
        canBeginWorkout = stage == .readyToBegin
    }

    private static func stage(
        for context: WorkoutPreflightContext,
        at now: MonotonicInstant
    ) -> WorkoutPreflightStage {
        let state = context.executionState

        switch state.execution {
        case .failed, .interrupted:
            return .failed
        default:
            break
        }

        let epoch: ConnectionEpoch
        let capability: FR30zCapabilitySnapshot
        switch state.connection {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .preparing
        case .lost, .invalidated:
            return .failed
        case let .ready(currentEpoch, currentCapability):
            epoch = currentEpoch
            capability = currentCapability
        }

        guard context.profile.matches(capability) else { return .unsupported }

        switch state.execution {
        case .acquiringControl:
            return .requestingControl
        case .waitingForPhysicalStart:
            guard case .held(let heldEpoch, _) = state.controlPermission,
                  heldEpoch == epoch,
                  case .idle = state.procedure,
                  armedWorkoutMatchesContext(context) else {
                return .lockedOrUnknown
            }
            return .waitingForPhysicalStart
        case .checkingTreadmill(let checking)
            where checking.origin == .waitingForPhysicalStart:
            return .stale
        default:
            break
        }

        switch state.telemetry {
        case .stale:
            return .stale
        case let .fresh(sample):
            let age = now.seconds - sample.receivedAt.seconds
            guard age >= 0,
                  age <= FR30zExecutionProfile.telemetryFreshnessInterval else {
                return .stale
            }
            guard sample.speed.value == 0 else { return .lockedOrUnknown }
        case .unavailable, .malformed, .contradictory:
            return .lockedOrUnknown
        }

        guard armedWorkoutMatchesContext(context),
              reducerAllowsArming(context, at: now),
              reducerAllowsBegin(
            state,
            epoch: epoch,
            readiness: fullyConfirmedReadiness,
            at: now
              ) else {
            return .lockedOrUnknown
        }

        guard context.activityConfirmed,
              reducerAllowsBegin(
                state,
                epoch: epoch,
                readiness: context.operatorReadiness,
                at: now
              ) else {
            return .readyToRequestControl
        }
        return .readyToBegin
    }

    private static func armedWorkoutMatchesContext(_ context: WorkoutPreflightContext) -> Bool {
        guard let armed = context.executionState.armedWorkout,
              case .ready(_, let capability) = context.executionState.connection else {
            return false
        }
        return armed.plan == context.validatedPlan
            && armed.ceilings == context.ceilings
            && armed.profile == context.profile
            && armed.capability == capability
    }

    private static func reducerAllowsArming(
        _ context: WorkoutPreflightContext,
        at now: MonotonicInstant
    ) -> Bool {
        var state = WorkoutExecutionState()
        state.connection = context.executionState.connection
        state.isForegroundActive = context.executionState.isForegroundActive
        state.lastEventTime = context.executionState.lastEventTime
        let transition = WorkoutExecutionReducer().reduce(
            state,
            .arm(
                plan: context.validatedPlan,
                ceilings: context.ceilings,
                profile: context.profile
            ),
            at: now
        )
        return transition.disposition == .accepted && transition.state.execution == .preflight
    }

    private static func reducerAllowsBegin(
        _ state: WorkoutExecutionState,
        epoch: ConnectionEpoch,
        readiness: WorkoutOperatorReadiness,
        at now: MonotonicInstant
    ) -> Bool {
        let transition = WorkoutExecutionReducer().reduce(
            state,
            .beginWorkout(epoch: epoch, readiness: readiness),
            at: now
        )
        guard transition.disposition == .accepted,
              transition.effects.count == 1,
              case .submit(let record) = transition.effects[0],
              record.intent == .requestControl else {
            return false
        }
        return true
    }

    private static let fullyConfirmedReadiness = WorkoutOperatorReadiness(
        deckClear: true,
        consoleImmediatelyReachable: true,
        safetyKeyImmediatelyReachable: true,
        physicallyStationary: true
    )

    private static func status(
        for stage: WorkoutPreflightStage
    ) -> WorkoutPreflightStatusPresentation {
        switch stage {
        case .disconnected:
            .init(
                title: "Disconnected",
                detail: "Connect the accepted FR30z before preflight can continue. No control request has been made.",
                symbol: "bolt.slash.fill",
                tone: .neutral
            )
        case .preparing:
            .init(
                title: "Preparing",
                detail: "Reading current capabilities, subscriptions and profile evidence. Control is not held.",
                symbol: "ellipsis.circle.fill",
                tone: .neutral
            )
        case .unsupported:
            .init(
                title: "Unsupported profile",
                detail: "This connection does not exactly match the accepted FR30z profile. Control remains unavailable.",
                symbol: "xmark.shield.fill",
                tone: .failure
            )
        case .stale:
            .init(
                title: "Treadmill data stale",
                detail: "Current speed and inclination evidence is older than 2 seconds. Last-known values are not readiness.",
                symbol: "clock.badge.exclamationmark.fill",
                tone: .warning
            )
        case .lockedOrUnknown:
            .init(
                title: "Readiness locked",
                detail: "A required current fact is unknown, invalid or unsafe. Begin workout remains unavailable.",
                symbol: "lock.shield.fill",
                tone: .warning
            )
        case .readyToRequestControl:
            .init(
                title: "Ready to request control",
                detail: "Current system checks pass. Complete every confirmation before Begin workout can request control.",
                symbol: "checkmark.shield.fill",
                tone: .ready
            )
        case .requestingControl:
            .init(
                title: "Requesting control",
                detail: "A Request Control procedure is in progress. Intent, submission or ATT acceptance alone is not control.",
                symbol: "arrow.triangle.2.circlepath.circle.fill",
                tone: .neutral
            )
        case .readyToBegin:
            .init(
                title: "Ready to begin",
                detail: "All current guards and confirmations pass. Begin workout requests control; it does not start the belt.",
                symbol: "checkmark.circle.fill",
                tone: .ready
            )
        case .waitingForPhysicalStart:
            .init(
                title: "Control confirmed",
                detail: "A matching FTMS Request Control success is held for this connection. No speed or inclination target has been sent.",
                symbol: "checkmark.shield.fill",
                tone: .ready
            )
        case .failed:
            .init(
                title: "Preflight failed",
                detail: "This attempt cannot continue. Use the physical console and safety key, then begin a new attempt.",
                symbol: "exclamationmark.triangle.fill",
                tone: .failure
            )
        }
    }

    private static func confirmations(
        for context: WorkoutPreflightContext,
        activity: String
    ) -> [WorkoutPreflightConfirmationPresentation] {
        [
            .init(
                kind: .activity,
                title: "Confirm \(activity.lowercased())",
                detail: "This activity type will be offered to the later Apple Health save flow.",
                isConfirmed: context.activityConfirmed
            ),
            .init(
                kind: .deckClear,
                title: "Treadmill deck is clear",
                detail: "Nothing can catch underfoot or obstruct the belt.",
                isConfirmed: context.operatorReadiness.deckClear
            ),
            .init(
                kind: .consoleReachable,
                title: "Physical console is within reach",
                detail: "You will start and stop the belt using the treadmill console.",
                isConfirmed: context.operatorReadiness.consoleImmediatelyReachable
            ),
            .init(
                kind: .safetyKeyReachable,
                title: "Safety key is within reach",
                detail: "The treadmill safety key remains authoritative.",
                isConfirmed: context.operatorReadiness.safetyKeyImmediatelyReachable
            ),
            .init(
                kind: .physicallyStationary,
                title: "Treadmill is physically stationary",
                detail: "Confirm the belt is stopped before PacePrompt requests control.",
                isConfirmed: context.operatorReadiness.physicallyStationary
            ),
        ]
    }

    private static func planTotals(preview: WorkoutPlanPreview, locale: Locale) -> String {
        let seconds = NSDecimalNumber(decimal: preview.totalDurationSeconds).intValue
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        let remainingSeconds = seconds % 60
        let duration = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
        let distance = PlanValueFormatter.estimatedDistanceText(
            preview.estimatedDistanceKilometres,
            locale: locale
        )
        let count = preview.plan.steps.count
        return "\(duration) · \(distance) km est. · \(count) \(count == 1 ? "segment" : "segments")"
    }

    private static func measurement(_ value: Decimal, unit: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        let text = formatter.string(from: NSDecimalNumber(decimal: value))
            ?? PlanValueFormatter.localizedText(value, locale: locale)
        return "\(text) \(unit)"
    }
}
