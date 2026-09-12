#if DEBUG
import SwiftUI

enum WorkoutPreflightUITestScenario: String {
    case disconnected
    case preparing
    case unsupported
    case stale
    case locked
    case readyToRequestControl = "ready-to-request-control"
    case requesting = "requesting"
    case readyToBegin = "ready-to-begin"
    case waitingForPhysicalStart = "waiting-for-physical-start"
    case failed
}

struct WorkoutPreflightUITestConfiguration {
    let scenario: WorkoutPreflightUITestScenario
    let reduceMotion: Bool

    static var current: Self? {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--paceprompt-preflight-ui-testing"),
              let value = process.environment["PACEPROMPT_PREFLIGHT_SCENARIO"],
              let scenario = WorkoutPreflightUITestScenario(rawValue: value) else {
            return nil
        }
        return .init(
            scenario: scenario,
            reduceMotion: process.environment["PACEPROMPT_PREFLIGHT_REDUCE_MOTION"] == "1"
        )
    }
}

struct WorkoutPreflightUITestHost: View {
    @State private var context: WorkoutPreflightContext
    @State private var now: MonotonicInstant
    private let reduceMotion: Bool

    init(configuration: WorkoutPreflightUITestConfiguration) {
        let fixture = WorkoutPreflightFixtures.fixture(for: configuration.scenario)
        _context = State(initialValue: fixture.context)
        _now = State(initialValue: fixture.now)
        reduceMotion = configuration.reduceMotion
    }

    var body: some View {
        WorkoutPreflightView(
            presentation: .init(context: context, at: now, locale: Locale(identifier: "en_GB")),
            send: handle,
            reduceMotionOverride: reduceMotion
        )
    }

    private func handle(_ intent: WorkoutPreflightIntent) {
        switch intent {
        case let .setConfirmation(kind, isConfirmed):
            setConfirmation(kind, isConfirmed: isConfirmed)
        case .beginWorkout:
            beginWorkout()
        }
    }

    private func setConfirmation(
        _ kind: WorkoutPreflightConfirmationKind,
        isConfirmed: Bool
    ) {
        var readiness = context.operatorReadiness
        var activityConfirmed = context.activityConfirmed
        switch kind {
        case .activity:
            activityConfirmed = isConfirmed
        case .deckClear:
            readiness = .init(
                deckClear: isConfirmed,
                consoleImmediatelyReachable: readiness.consoleImmediatelyReachable,
                safetyKeyImmediatelyReachable: readiness.safetyKeyImmediatelyReachable,
                physicallyStationary: readiness.physicallyStationary
            )
        case .consoleReachable:
            readiness = .init(
                deckClear: readiness.deckClear,
                consoleImmediatelyReachable: isConfirmed,
                safetyKeyImmediatelyReachable: readiness.safetyKeyImmediatelyReachable,
                physicallyStationary: readiness.physicallyStationary
            )
        case .safetyKeyReachable:
            readiness = .init(
                deckClear: readiness.deckClear,
                consoleImmediatelyReachable: readiness.consoleImmediatelyReachable,
                safetyKeyImmediatelyReachable: isConfirmed,
                physicallyStationary: readiness.physicallyStationary
            )
        case .physicallyStationary:
            readiness = .init(
                deckClear: readiness.deckClear,
                consoleImmediatelyReachable: readiness.consoleImmediatelyReachable,
                safetyKeyImmediatelyReachable: readiness.safetyKeyImmediatelyReachable,
                physicallyStationary: isConfirmed
            )
        }
        context = .init(
            validatedPlan: context.validatedPlan,
            ceilings: context.ceilings,
            profile: context.profile,
            executionState: context.executionState,
            operatorReadiness: readiness,
            activityConfirmed: activityConfirmed
        )
    }

    private func beginWorkout() {
        let presentation = WorkoutPreflightPresentation(
            context: context,
            at: now,
            locale: Locale(identifier: "en_GB")
        )
        guard presentation.canBeginWorkout,
              let epoch = context.executionState.connection.epoch else { return }

        let reducer = WorkoutExecutionReducer()
        var transition = reducer.reduce(
            context.executionState,
            .beginWorkout(epoch: epoch, readiness: context.operatorReadiness),
            at: now.advanced(by: 0.1)
        )
        guard transition.disposition == .accepted,
              case .submit(let record) = transition.effects.first else { return }

        transition = reducer.reduce(
            transition.state,
            .intentSubmitted(epoch: epoch, procedureID: record.id),
            at: now.advanced(by: 0.2)
        )
        transition = reducer.reduce(
            transition.state,
            .attAccepted(epoch: epoch, procedureID: record.id),
            at: now.advanced(by: 0.3)
        )
        transition = reducer.reduce(
            transition.state,
            .protocolAcknowledged(epoch: epoch, procedureID: record.id),
            at: now.advanced(by: 0.4)
        )
        guard transition.disposition == .accepted,
              transition.state.execution == .waitingForPhysicalStart else { return }

        now = now.advanced(by: 0.4)
        context = .init(
            validatedPlan: context.validatedPlan,
            ceilings: context.ceilings,
            profile: context.profile,
            executionState: transition.state,
            operatorReadiness: context.operatorReadiness,
            activityConfirmed: context.activityConfirmed
        )
    }
}

private enum WorkoutPreflightFixtures {
    struct Fixture {
        let context: WorkoutPreflightContext
        let now: MonotonicInstant
    }

    static func fixture(for scenario: WorkoutPreflightUITestScenario) -> Fixture {
        let plan = validatedPlan()
        let profile = FR30zExecutionProfile(
            peripheralIdentity: "synthetic-local-peripheral",
            equipmentIdentity: "synthetic-fr30z-profile"
        )
        let ceilings = WorkoutSessionCeilings(
            maximumSpeed: speed(10),
            maximumInclination: inclination(6),
            maximumStepSpeedChange: speed(2)
        )
        let confirmed = WorkoutOperatorReadiness(
            deckClear: true,
            consoleImmediatelyReachable: true,
            safetyKeyImmediatelyReachable: true,
            physicallyStationary: true
        )
        let unconfirmed = WorkoutOperatorReadiness(
            deckClear: false,
            consoleImmediatelyReachable: false,
            safetyKeyImmediatelyReachable: false,
            physicallyStationary: false
        )
        let capability = matchingCapability()

        var state = WorkoutExecutionState()
        let reducer = WorkoutExecutionReducer()
        let epoch = ConnectionEpoch(rawValue: 58)
        state = reducer.reduce(
            state,
            .userStartsConnection(epoch),
            at: .init(seconds: 1)
        ).state

        if scenario == .disconnected {
            state = WorkoutExecutionState()
            return make(
                plan: plan,
                ceilings: ceilings,
                profile: profile,
                state: state,
                readiness: unconfirmed,
                activityConfirmed: false,
                now: 1
            )
        }
        if scenario == .preparing {
            return make(
                plan: plan,
                ceilings: ceilings,
                profile: profile,
                state: state,
                readiness: unconfirmed,
                activityConfirmed: false,
                now: 1.1
            )
        }

        let connectedCapability = scenario == .unsupported
            ? capabilityReplacingFeatureEvidence(capability, evidence: .mismatch)
            : capability
        state = reducer.reduce(
            state,
            .connectionBecomesReady(epoch: epoch, capability: connectedCapability),
            at: .init(seconds: 2)
        ).state

        if scenario == .unsupported {
            return make(
                plan: plan,
                ceilings: ceilings,
                profile: profile,
                state: state,
                readiness: unconfirmed,
                activityConfirmed: false,
                now: 2.1
            )
        }

        state = reducer.reduce(
            state,
            .arm(plan: plan, ceilings: ceilings, profile: profile),
            at: .init(seconds: 3)
        ).state
        state = reducer.reduce(
            state,
            .telemetry(
                epoch: epoch,
                .sample(speed: speed(0), inclination: inclination(0), totalDistanceMetres: 0)
            ),
            at: .init(seconds: 4)
        ).state

        switch scenario {
        case .stale:
            return make(
                plan: plan,
                ceilings: ceilings,
                profile: profile,
                state: state,
                readiness: confirmed,
                activityConfirmed: true,
                now: 6.1
            )
        case .locked:
            state = reducer.reduce(
                state,
                .telemetry(epoch: epoch, .unavailable("Synthetic current sample unavailable")),
                at: .init(seconds: 4.1)
            ).state
            return make(
                plan: plan,
                ceilings: ceilings,
                profile: profile,
                state: state,
                readiness: confirmed,
                activityConfirmed: true,
                now: 4.2
            )
        case .readyToRequestControl:
            return make(
                plan: plan,
                ceilings: ceilings,
                profile: profile,
                state: state,
                readiness: unconfirmed,
                activityConfirmed: false,
                now: 4.1
            )
        case .readyToBegin:
            return make(
                plan: plan,
                ceilings: ceilings,
                profile: profile,
                state: state,
                readiness: confirmed,
                activityConfirmed: true,
                now: 4.1
            )
        case .requesting, .waitingForPhysicalStart:
            var transition = reducer.reduce(
                state,
                .beginWorkout(epoch: epoch, readiness: confirmed),
                at: .init(seconds: 4.1)
            )
            guard case .submit(let record) = transition.effects.first else {
                preconditionFailure("Synthetic Begin workout did not create Request Control")
            }
            if scenario == .requesting {
                return make(
                    plan: plan,
                    ceilings: ceilings,
                    profile: profile,
                    state: transition.state,
                    readiness: confirmed,
                    activityConfirmed: true,
                    now: 4.2
                )
            }
            transition = reducer.reduce(
                transition.state,
                .intentSubmitted(epoch: epoch, procedureID: record.id),
                at: .init(seconds: 4.2)
            )
            transition = reducer.reduce(
                transition.state,
                .attAccepted(epoch: epoch, procedureID: record.id),
                at: .init(seconds: 4.3)
            )
            transition = reducer.reduce(
                transition.state,
                .protocolAcknowledged(epoch: epoch, procedureID: record.id),
                at: .init(seconds: 4.4)
            )
            return make(
                plan: plan,
                ceilings: ceilings,
                profile: profile,
                state: transition.state,
                readiness: confirmed,
                activityConfirmed: true,
                now: 4.4
            )
        case .failed:
            state = reducer.reduce(
                state,
                .connectionLost(epoch: epoch, reason: "Synthetic connection loss"),
                at: .init(seconds: 4.1)
            ).state
            return make(
                plan: plan,
                ceilings: ceilings,
                profile: profile,
                state: state,
                readiness: confirmed,
                activityConfirmed: true,
                now: 4.2
            )
        case .disconnected, .preparing, .unsupported:
            preconditionFailure("Scenario returned before canonical preflight")
        }
    }

    private static func make(
        plan: WorkoutPlanValidator.ValidatedPlan,
        ceilings: WorkoutSessionCeilings,
        profile: FR30zExecutionProfile,
        state: WorkoutExecutionState,
        readiness: WorkoutOperatorReadiness,
        activityConfirmed: Bool,
        now: TimeInterval
    ) -> Fixture {
        .init(
            context: .init(
                validatedPlan: plan,
                ceilings: ceilings,
                profile: profile,
                executionState: state,
                operatorReadiness: readiness,
                activityConfirmed: activityConfirmed
            ),
            now: .init(seconds: now)
        )
    }

    private static func validatedPlan() -> WorkoutPlanValidator.ValidatedPlan {
        let plan = WorkoutPlan(
            schemaVersion: WorkoutPlanSchema.currentVersion,
            suggestedName: "Pyramid 5 x 3",
            activity: .indoorRunning,
            steps: [
                .init(
                    kind: .warmUp,
                    label: "Warm-up",
                    duration: .init(value: 360, unit: .seconds),
                    targetSpeed: speed(5),
                    targetInclination: inclination(0)
                ),
                .init(
                    kind: .interval,
                    label: "First climb",
                    duration: .init(value: 360, unit: .seconds),
                    targetSpeed: speed(7),
                    targetInclination: inclination(2)
                ),
                .init(
                    kind: .coolDown,
                    label: "Cool-down",
                    duration: .init(value: 360, unit: .seconds),
                    targetSpeed: speed(5),
                    targetInclination: inclination(0)
                ),
            ]
        )
        guard case .success(let validated) = WorkoutPlanValidator.validate(
            plan,
            against: matchingCapability().planCapabilities
        ) else {
            preconditionFailure("Synthetic preflight plan must validate")
        }
        return validated
    }

    private static func matchingCapability() -> FR30zCapabilitySnapshot {
        .init(
            peripheralIdentity: "synthetic-local-peripheral",
            equipmentIdentity: "synthetic-fr30z-profile",
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
                    .init(minimum: speed(0.5), maximum: speed(20), increment: speed(0.1))
                ),
                inclination: .supported(
                    .init(
                        minimum: inclination(0),
                        maximum: inclination(15),
                        increment: inclination(1)
                    )
                )
            )
        )
    }

    private static func capabilityReplacingFeatureEvidence(
        _ capability: FR30zCapabilitySnapshot,
        evidence: FR30zProfileEvidence
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

    private static func speed(_ value: Decimal) -> WorkoutSpeed {
        .init(value: value, unit: .kilometresPerHour)
    }

    private static func inclination(_ value: Decimal) -> WorkoutInclination {
        .init(value: value, unit: .percent)
    }
}
#endif
