import Foundation
import XCTest

@testable import PacePrompt

final class WorkoutPreflightPresentationTests: XCTestCase {
    func testPlanIdentityTotalsCeilingsAndInitialTargetsRemainExact() {
        let harness = Harness()
        let presentation = harness.presentation(state: harness.preflightState())

        XCTAssertEqual(presentation.planName, "Synthetic progression")
        XCTAssertEqual(presentation.planTotals, "18:00 · 1.7 km est. · 3 segments")
        XCTAssertEqual(presentation.activity, "Indoor running")
        XCTAssertEqual(presentation.speedCeiling, "10.0 km/h")
        XCTAssertEqual(presentation.inclinationCeiling, "6.0 %")
        XCTAssertEqual(presentation.maximumStepSpeedChange, "2.0 km/h")
        XCTAssertEqual(presentation.initialStepLabel, "Warm-up")
        XCTAssertEqual(presentation.initialSpeed, "5.0 km/h")
        XCTAssertEqual(presentation.initialInclination, "0.0 %")
        XCTAssertEqual(presentation.confirmations.first?.title, "Confirm indoor running")
    }

    func testEveryRequiredReadinessStageHasDistinctPresentation() {
        let harness = Harness()
        let preflight = harness.preflightState()
        let requesting = harness.requestingState(from: preflight)
        let waiting = harness.waitingState(from: preflight)
        var locked = preflight
        locked.telemetry = .unavailable("Synthetic unavailable")
        let failed = harness.reduce(
            preflight,
            .connectionLost(epoch: harness.epoch, reason: "Synthetic loss"),
            at: 4.2
        ).state

        let presentations = [
            harness.presentation(state: WorkoutExecutionState(), now: 1),
            harness.presentation(state: harness.connectingState(), now: 1.1),
            harness.presentation(state: harness.unsupportedState(), now: 2.1),
            harness.presentation(state: preflight, now: 6.1),
            harness.presentation(state: locked, now: 4.2),
            harness.presentation(
                state: preflight,
                readiness: harness.unconfirmedReadiness,
                activityConfirmed: false
            ),
            harness.presentation(state: requesting, now: 4.2),
            harness.presentation(state: preflight),
            harness.presentation(state: waiting, now: 4.4),
            harness.presentation(state: failed, now: 4.3),
        ]

        XCTAssertEqual(
            presentations.map(\.stage),
            [
                .disconnected,
                .preparing,
                .unsupported,
                .stale,
                .lockedOrUnknown,
                .readyToRequestControl,
                .requestingControl,
                .readyToBegin,
                .waitingForPhysicalStart,
                .failed,
            ]
        )
        XCTAssertEqual(Set(presentations.map(\.status.title)).count, presentations.count)
        XCTAssertEqual(presentations.filter(\.canBeginWorkout).count, 1)
    }

    func testBeginRequiresActivityAndEveryReducerOperatorConfirmation() {
        let harness = Harness()
        let state = harness.preflightState()
        let missingReadiness = [
            WorkoutOperatorReadiness(
                deckClear: false,
                consoleImmediatelyReachable: true,
                safetyKeyImmediatelyReachable: true,
                physicallyStationary: true
            ),
            WorkoutOperatorReadiness(
                deckClear: true,
                consoleImmediatelyReachable: false,
                safetyKeyImmediatelyReachable: true,
                physicallyStationary: true
            ),
            WorkoutOperatorReadiness(
                deckClear: true,
                consoleImmediatelyReachable: true,
                safetyKeyImmediatelyReachable: false,
                physicallyStationary: true
            ),
            WorkoutOperatorReadiness(
                deckClear: true,
                consoleImmediatelyReachable: true,
                safetyKeyImmediatelyReachable: true,
                physicallyStationary: false
            ),
        ]

        XCTAssertFalse(
            harness.presentation(
                state: state,
                readiness: harness.confirmedReadiness,
                activityConfirmed: false
            ).canBeginWorkout
        )
        for readiness in missingReadiness {
            let presentation = harness.presentation(
                state: state,
                readiness: readiness,
                activityConfirmed: true
            )
            XCTAssertEqual(presentation.stage, .readyToRequestControl)
            XCTAssertFalse(presentation.canBeginWorkout)
        }
        XCTAssertTrue(harness.presentation(state: state).canBeginWorkout)
    }

    func testFreshStationaryEvidenceIsRequiredAndLastKnownValuesDoNotEnableBegin() {
        let harness = Harness()
        let preflight = harness.preflightState()

        XCTAssertTrue(harness.presentation(state: preflight, now: 4.1).canBeginWorkout)
        XCTAssertEqual(harness.presentation(state: preflight, now: 6.01).stage, .stale)

        var lastKnown = preflight
        if case .fresh(let sample) = lastKnown.telemetry {
            lastKnown.telemetry = .stale(sample)
        }
        XCTAssertEqual(harness.presentation(state: lastKnown, now: 4.1).stage, .stale)

        let moving = harness.reduce(
            preflight,
            .telemetry(
                epoch: harness.epoch,
                .sample(
                    speed: harness.speed(0.5),
                    inclination: harness.inclination(0),
                    totalDistanceMetres: 0
                )
            ),
            at: 4.1
        ).state
        XCTAssertEqual(harness.presentation(state: moving, now: 4.2).stage, .lockedOrUnknown)
        XCTAssertFalse(harness.presentation(state: moving, now: 4.2).canBeginWorkout)
    }

    func testCurrentPlanProfileForegroundControlProcedureAndCeilingsAllGateBegin() {
        let harness = Harness()
        let preflight = harness.preflightState()

        var background = preflight
        background.isForegroundActive = false

        var heldWithoutWaiting = preflight
        heldWithoutWaiting.controlPermission = .held(
            epoch: harness.epoch,
            acknowledgedAt: .init(seconds: 4)
        )

        var procedureBusy = preflight
        let record = WorkoutProcedureRecord(
            id: .init(epoch: harness.epoch, sequence: 99),
            intent: .requestControl,
            stepIndex: nil,
            createdAt: .init(seconds: 4)
        )
        procedureBusy.procedure = .intentCreated(record)

        let invalidCeilings = WorkoutSessionCeilings(
            maximumSpeed: harness.speed(4),
            maximumInclination: harness.inclination(6),
            maximumStepSpeedChange: harness.speed(2)
        )

        var wrongArmedPlan = preflight
        wrongArmedPlan.armedWorkout = nil

        let blocked = [
            harness.presentation(state: background),
            harness.presentation(state: heldWithoutWaiting),
            harness.presentation(state: procedureBusy),
            harness.presentation(state: wrongArmedPlan),
            harness.presentation(state: preflight, ceilings: invalidCeilings),
        ]
        for presentation in blocked {
            XCTAssertEqual(presentation.stage, .lockedOrUnknown)
            XCTAssertFalse(presentation.canBeginWorkout)
        }
    }

    func testControlClaimsRemainBoundToMatchingAcknowledgement() {
        let harness = Harness()
        let preflight = harness.preflightState()
        let requesting = harness.presentation(
            state: harness.requestingState(from: preflight),
            now: 4.2
        )
        let waiting = harness.presentation(
            state: harness.waitingState(from: preflight),
            now: 4.4
        )

        XCTAssertEqual(requesting.stage, .requestingControl)
        XCTAssertTrue(requesting.status.detail.contains("ATT acceptance alone is not control"))
        XCTAssertFalse(requesting.status.title.localizedCaseInsensitiveContains("confirmed"))

        XCTAssertEqual(waiting.stage, .waitingForPhysicalStart)
        XCTAssertTrue(waiting.status.detail.contains("matching FTMS Request Control success"))
        XCTAssertTrue(waiting.status.detail.contains("No speed or inclination target has been sent"))
        XCTAssertFalse(waiting.canBeginWorkout)
    }
}

private struct Harness {
    let reducer = WorkoutExecutionReducer()
    let epoch = ConnectionEpoch(rawValue: 58)

    let confirmedReadiness = WorkoutOperatorReadiness(
        deckClear: true,
        consoleImmediatelyReachable: true,
        safetyKeyImmediatelyReachable: true,
        physicallyStationary: true
    )
    let unconfirmedReadiness = WorkoutOperatorReadiness(
        deckClear: false,
        consoleImmediatelyReachable: false,
        safetyKeyImmediatelyReachable: false,
        physicallyStationary: false
    )

    var profile: FR30zExecutionProfile {
        .init(
            peripheralIdentity: "synthetic-local-peripheral",
            equipmentIdentity: "synthetic-fr30z-profile"
        )
    }

    var ceilings: WorkoutSessionCeilings {
        .init(
            maximumSpeed: speed(10),
            maximumInclination: inclination(6),
            maximumStepSpeedChange: speed(2)
        )
    }

    func presentation(
        state: WorkoutExecutionState,
        readiness: WorkoutOperatorReadiness? = nil,
        activityConfirmed: Bool = true,
        ceilings: WorkoutSessionCeilings? = nil,
        now: TimeInterval = 4.1
    ) -> WorkoutPreflightPresentation {
        .init(
            context: .init(
                validatedPlan: validatedPlan,
                ceilings: ceilings ?? self.ceilings,
                profile: profile,
                executionState: state,
                operatorReadiness: readiness ?? confirmedReadiness,
                activityConfirmed: activityConfirmed
            ),
            at: .init(seconds: now),
            locale: Locale(identifier: "en_GB")
        )
    }

    func connectingState() -> WorkoutExecutionState {
        reduce(
            WorkoutExecutionState(),
            .userStartsConnection(epoch),
            at: 1
        ).state
    }

    func unsupportedState() -> WorkoutExecutionState {
        var capability = matchingCapability
        capability = .init(
            peripheralIdentity: capability.peripheralIdentity,
            equipmentIdentity: capability.equipmentIdentity,
            fitnessMachineServicePresent: capability.fitnessMachineServicePresent,
            requiredCharacteristicPropertiesMatch: capability.requiredCharacteristicPropertiesMatch,
            fitnessMachineFeatureEvidence: .mismatch,
            supportedSpeedRangeEvidence: capability.supportedSpeedRangeEvidence,
            supportedInclinationRangeEvidence: capability.supportedInclinationRangeEvidence,
            treadmillDataNotificationsEnabled: capability.treadmillDataNotificationsEnabled,
            controlPointIndicationsEnabled: capability.controlPointIndicationsEnabled,
            optionalSubscriptionOutcomesResolved: capability.optionalSubscriptionOutcomesResolved,
            planCapabilities: capability.planCapabilities
        )
        return reduce(
            connectingState(),
            .connectionBecomesReady(epoch: epoch, capability: capability),
            at: 2
        ).state
    }

    func preflightState() -> WorkoutExecutionState {
        var state = reduce(
            connectingState(),
            .connectionBecomesReady(epoch: epoch, capability: matchingCapability),
            at: 2
        ).state
        state = reduce(
            state,
            .arm(plan: validatedPlan, ceilings: ceilings, profile: profile),
            at: 3
        ).state
        state = reduce(
            state,
            .telemetry(
                epoch: epoch,
                .sample(speed: speed(0), inclination: inclination(0), totalDistanceMetres: 0)
            ),
            at: 4
        ).state
        return state
    }

    func requestingState(from preflight: WorkoutExecutionState) -> WorkoutExecutionState {
        reduce(
            preflight,
            .beginWorkout(epoch: epoch, readiness: confirmedReadiness),
            at: 4.1
        ).state
    }

    func waitingState(from preflight: WorkoutExecutionState) -> WorkoutExecutionState {
        var transition = reduce(
            preflight,
            .beginWorkout(epoch: epoch, readiness: confirmedReadiness),
            at: 4.1
        )
        guard case .submit(let record) = transition.effects.first else {
            preconditionFailure("Expected Request Control intent")
        }
        transition = reduce(
            transition.state,
            .intentSubmitted(epoch: epoch, procedureID: record.id),
            at: 4.2
        )
        transition = reduce(
            transition.state,
            .attAccepted(epoch: epoch, procedureID: record.id),
            at: 4.3
        )
        transition = reduce(
            transition.state,
            .protocolAcknowledged(epoch: epoch, procedureID: record.id),
            at: 4.4
        )
        return transition.state
    }

    func reduce(
        _ state: WorkoutExecutionState,
        _ event: WorkoutExecutionEvent,
        at seconds: TimeInterval
    ) -> WorkoutExecutionTransition {
        reducer.reduce(state, event, at: .init(seconds: seconds))
    }

    var validatedPlan: WorkoutPlanValidator.ValidatedPlan {
        let plan = WorkoutPlan(
            schemaVersion: WorkoutPlanSchema.currentVersion,
            suggestedName: "Synthetic progression",
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
            against: matchingCapability.planCapabilities
        ) else {
            preconditionFailure("Synthetic plan must validate")
        }
        return validated
    }

    var matchingCapability: FR30zCapabilitySnapshot {
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

    func speed(_ value: Decimal) -> WorkoutSpeed {
        .init(value: value, unit: .kilometresPerHour)
    }

    func inclination(_ value: Decimal) -> WorkoutInclination {
        .init(value: value, unit: .percent)
    }
}
