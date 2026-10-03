import Foundation

enum WorkoutPreflightStage: Equatable {
    case disconnected
    case preparing
    case unsupported
    case stale
    case lockedOrUnknown
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

enum WorkoutPreflightIntent: Equatable {
    case beginWorkout
}

struct WorkoutPreflightContext: Equatable {
    let validatedPlan: WorkoutPlanValidator.ValidatedPlan
    let profile: FR30zExecutionProfile
    let executionState: WorkoutExecutionState
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
    let initialStepLabel: String
    let initialSpeed: String
    let initialInclination: String
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
        if let armed = context.executionState.armedWorkout,
          case .supported(let speed) = armed.capability.planCapabilities.speed,
          case .supported(let inclination) = armed.capability.planCapabilities.inclination {
          speedCeiling = Self.measurement(speed.maximum.value, unit: "km/h", locale: locale)
          inclinationCeiling = Self.measurement(inclination.maximum.value, unit: "%", locale: locale)
        } else {
          speedCeiling = "Unavailable"
          inclinationCeiling = "Unavailable"
        }
        initialStepLabel = initialStep.label
        initialSpeed = Self.measurement(initialStep.targetSpeed.value, unit: "km/h", locale: locale)
        initialInclination = Self.measurement(
            initialStep.targetInclination.value,
            unit: "%",
            locale: locale
        )

        stage = Self.stage(for: context, at: now)
    status = Self.status(for: stage, state: context.executionState)
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
    case .ready(let currentEpoch, let currentCapability):
            epoch = currentEpoch
            capability = currentCapability
        }

        guard context.profile.matches(capability) else { return .unsupported }

        switch state.execution {
        case .acquiringControl:
            return .requestingControl
        case .waitingForPhysicalStart:
      let permissionMatches: Bool
      switch state.controlPermission {
      case .notHeld:
        permissionMatches = true
      case .held(let heldEpoch, _):
        permissionMatches = heldEpoch == epoch
      case .requesting, .invalidated:
        permissionMatches = false
      }
      guard permissionMatches,
                  case .idle = state.procedure,
        armedWorkoutMatchesContext(context)
      else {
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
    case .stale, .unavailable:
      break
    case .fresh(let sample):
            let age = now.seconds - sample.receivedAt.seconds
      if age >= 0,
        age <= FR30zExecutionProfile.telemetryFreshnessInterval,
        sample.speed.value != 0
      {
        return .lockedOrUnknown
            }
    case .malformed, .contradictory:
            return .lockedOrUnknown
        }

        guard armedWorkoutMatchesContext(context),
              reducerAllowsArming(context, at: now),
              reducerAllowsBegin(state, epoch: epoch, at: now)
        else { return .lockedOrUnknown }
        return .readyToBegin
    }

    private static func armedWorkoutMatchesContext(_ context: WorkoutPreflightContext) -> Bool {
        guard let armed = context.executionState.armedWorkout,
      case .ready(_, let capability) = context.executionState.connection
    else {
            return false
        }
        return armed.plan == context.validatedPlan
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
                profile: context.profile
            ),
            at: now
        )
        return transition.disposition == .accepted && transition.state.execution == .preflight
    }

    private static func reducerAllowsBegin(
        _ state: WorkoutExecutionState,
        epoch: ConnectionEpoch,
        at now: MonotonicInstant
    ) -> Bool {
        let transition = WorkoutExecutionReducer().reduce(
            state,
            .beginWorkout(epoch: epoch),
            at: now
        )
        guard transition.disposition == .accepted,
      transition.effects.isEmpty,
      transition.state.execution == .waitingForPhysicalStart,
      transition.state.procedure == .idle,
      transition.state.controlPermission == .notHeld
    else {
            return false
        }
        return true
    }

    private static func status(
    for stage: WorkoutPreflightStage,
    state: WorkoutExecutionState
    ) -> WorkoutPreflightStatusPresentation {
        switch stage {
        case .disconnected:
            .init(
                title: "Disconnected",
        detail:
          "Connect your Reebok FR30z to check this workout. No control request has been sent.",
                symbol: "bolt.slash.fill",
                tone: .neutral
            )
        case .preparing:
            .init(
                title: "Preparing",
        detail:
          "Checking the treadmill settings and live updates. PacePrompt does not yet have control.",
                symbol: "ellipsis.circle.fill",
                tone: .neutral
            )
        case .unsupported:
            .init(
                title: "Treadmill not supported",
        detail:
          "This connection does not match the supported Reebok FR30z. PacePrompt cannot change its settings.",
                symbol: "xmark.shield.fill",
                tone: .failure
            )
        case .stale:
            .init(
                title: "Treadmill updates delayed",
        detail:
          "Speed and incline updates are delayed. Waiting for current readings before you can begin.",
                symbol: "clock.badge.exclamationmark.fill",
                tone: .warning
            )
        case .lockedOrUnknown:
            .init(
                title: "Workout not ready",
        detail:
          "Some treadmill checks are missing or did not pass. You cannot begin yet.",
                symbol: "lock.shield.fill",
                tone: .warning
            )
        case .requestingControl:
            .init(
                title: "Requesting control",
        detail:
          "Asking the treadmill to allow speed and incline changes. Waiting for its confirmation.",
                symbol: "arrow.triangle.2.circlepath.circle.fill",
                tone: .neutral
            )
        case .readyToBegin:
            .init(
                title: "Ready to begin",
        detail:
          "The checks have passed. Tap Begin workout, then use Start on the treadmill console.",
                symbol: "checkmark.circle.fill",
                tone: .ready
            )
        case .waitingForPhysicalStart:
      switch state.controlPermission {
      case .held:
            .init(
                title: "Control confirmed",
          detail:
            "The treadmill allows setting changes. Waiting for it to report movement before sending them.",
                symbol: "checkmark.shield.fill",
                tone: .ready
            )
      case .notHeld:
        .init(
          title: "Waiting for physical Start",
          detail:
            "No settings have been sent. PacePrompt will ask for control once the treadmill reports movement.",
          symbol: "figure.walk.motion",
          tone: .ready
        )
      case .requesting, .invalidated:
        .init(
          title: "Workout not ready",
          detail: "PacePrompt cannot proceed with this workout yet.",
          symbol: "lock.shield.fill",
          tone: .warning
        )
      }
        case .failed:
            .init(
                title: "Workout preparation failed",
        detail:
          "This attempt cannot continue. Use the physical console and safety key, then begin a new attempt.",
                symbol: "exclamationmark.triangle.fill",
                tone: .failure
            )
        }
    }

    private static func planTotals(preview: WorkoutPlanPreview, locale: Locale) -> String {
        let seconds = NSDecimalNumber(decimal: preview.totalDurationSeconds).intValue
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        let remainingSeconds = seconds % 60
    let duration =
      hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
        let distance = PlanValueFormatter.estimatedDistanceSummary(
            preview.estimatedDistanceKilometres,
            locale: locale
        )
        let count = preview.plan.steps.count
        return "\(duration) · \(distance) est. · \(count) \(count == 1 ? "segment" : "segments")"
    }

    private static func measurement(_ value: Decimal, unit: String, locale: Locale) -> String {
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

// A complete, explicit read from the current connection; never historical profile evidence.
enum LiveCapabilityRead: Equatable {
    case reading
    case unavailable(String)
    case complete(ConnectionEpoch, WorkoutPlanCapabilities)
}
struct LivePreflightFailure: Equatable {
    let plan: WorkoutPlan
    let reason: String
    let issues: [WorkoutPlanValidationIssue]
    let readComplete: Bool
    var isReading = false
    var title: String { isReading ? "Checking your treadmill" : "This workout cannot begin" }
    var readStatus: String { isReading ? "Checking…" : (readComplete ? "Checked" : "Unavailable") }
    static func review(_ plan: WorkoutPlan, read: LiveCapabilityRead, epoch: ConnectionEpoch?) -> Self? {
        switch read {
        case .reading: return .init(plan: plan, reason: "Checking supported treadmill settings. Please wait.", issues: [], readComplete: false, isReading: true)
        case .unavailable(let reason): return .init(plan: plan, reason: reason, issues: [], readComplete: false)
        case .complete(let observedEpoch, let capabilities):
            guard observedEpoch == epoch else { return .init(plan: plan, reason: "The connection changed during the check. Prepare the workout again.", issues: [], readComplete: false) }
            switch WorkoutPlanValidator.validate(plan, against: capabilities) {
            case .success: return nil
            case .failure(let failure): return .init(plan: plan, reason: "The current treadmill cannot satisfy this exact plan. Your saved plan has not been altered.", issues: failure.issues, readComplete: true)
            }
        }
    }
}
