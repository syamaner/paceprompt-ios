import Foundation
import XCTest
@testable import PacePrompt

final class WorkoutExecutionReducerTests: XCTestCase {
    func testConnectionPreparationArmingAndFrozenInputsAreExplicitAndEffectFree() throws {
        let h = Harness()
        var state = WorkoutExecutionState()

        state = accepted(h.reduce(state, .userStartsConnection(h.epoch))).state
        XCTAssertEqual(state.connection, .connecting(h.epoch))
        state = accepted(h.reduce(state, .connectionBecomesReady(epoch: h.epoch, capability: h.capability))).state
        let transition = accepted(h.reduce(state, .arm(plan: h.plan, ceilings: h.ceilings, profile: h.profile)))

        XCTAssertTrue(transition.effects.isEmpty)
        XCTAssertEqual(transition.state.execution, .armed)
        XCTAssertEqual(transition.state.armedWorkout?.plan, h.plan)
        XCTAssertEqual(transition.state.armedWorkout?.capability, h.capability)
        XCTAssertEqual(transition.state.armedWorkout?.ceilings, h.ceilings)
        XCTAssertEqual(transition.state.armedWorkout?.profile, h.profile)
    }

    func testArmingInvalidatesPreArmTelemetryBeforeAnyActuationIntent() throws {
        let h = Harness()
        var state = WorkoutExecutionState()
        state = accepted(h.reduce(state, .userStartsConnection(h.epoch))).state
        state = accepted(h.reduce(state, .connectionBecomesReady(epoch: h.epoch, capability: h.capability))).state
        state = accepted(
            h.reduce(state, .telemetry(epoch: h.epoch, h.telemetry(speed: "0", inclination: "99")))
        ).state
        state = accepted(h.reduce(state, .arm(plan: h.plan, ceilings: h.ceilings, profile: h.profile))).state
        var control = accepted(h.reduce(state, .userRequestsControl(epoch: h.epoch, readiness: h.readiness)))
        control = try h.acknowledgeCurrent(control)
        state = control.state

        XCTAssertRejected(
            h.reduce(state, .userBegins(epoch: h.epoch, readiness: h.readiness)),
            .telemetryNotFresh
        )
        XCTAssertEqual(state.telemetry, .unavailable("Awaiting telemetry matched to frozen execution bounds"))
    }

    func testConnectionAndArmingRejectEveryIncompleteGuardWithoutMutation() throws {
        let h = Harness()
        let initial = WorkoutExecutionState()
        XCTAssertRejected(h.reduce(initial, .connectionBecomesReady(epoch: h.epoch, capability: h.capability)), .wrongEpoch)

        var connecting = accepted(h.reduce(initial, .userStartsConnection(h.epoch))).state
        var incomplete = h.capability
        incomplete = .init(
            identity: incomplete.identity,
            equipmentIdentity: incomplete.equipmentIdentity,
            planCapabilities: incomplete.planCapabilities,
            controlPointSupportsWrite: true,
            controlPointSupportsIndicate: true,
            controlPointIndicationsEnabled: false,
            passiveSubscriptionOutcomesResolved: true
        )
        XCTAssertRejected(h.reduce(connecting, .connectionBecomesReady(epoch: h.epoch, capability: incomplete)), .incompleteCapabilityEvidence)

        connecting = accepted(h.reduce(connecting, .connectionBecomesReady(epoch: h.epoch, capability: h.capability))).state
        let tooLow = WorkoutSessionCeilings(
            maximumSpeed: speed("4"),
            maximumInclination: h.ceilings.maximumInclination,
            maximumStepSpeedChange: h.ceilings.maximumStepSpeedChange
        )
        XCTAssertRejected(h.reduce(connecting, .arm(plan: h.plan, ceilings: tooLow, profile: h.profile)), .invalidPlanOrCeilings)

        let beyondCapability = WorkoutSessionCeilings(
            maximumSpeed: speed("100"),
            maximumInclination: inclination("100"),
            maximumStepSpeedChange: speed("100")
        )
        XCTAssertRejected(
            h.reduce(connecting, .arm(plan: h.plan, ceilings: beyondCapability, profile: h.profile)),
            .invalidPlanOrCeilings
        )

        let wrongProfile = FR30zExecutionProfile(
            identity: h.profile.identity,
            equipmentIdentity: "different treadmill",
            targetOrder: h.profile.targetOrder,
            requiresStartForFirstStep: h.profile.requiresStartForFirstStep,
            permitsStop: h.profile.permitsStop,
            telemetryFreshnessInterval: h.profile.telemetryFreshnessInterval,
            targetObservationInterval: h.profile.targetObservationInterval,
            procedureResponseInterval: h.profile.procedureResponseInterval,
            requestControlEvidenceAccepted: true,
            speedTargetEvidenceAccepted: true,
            inclinationTargetEvidenceAccepted: true,
            startEvidenceAccepted: true,
            stopEvidenceAccepted: true
        )
        XCTAssertRejected(h.reduce(connecting, .arm(plan: h.plan, ceilings: h.ceilings, profile: wrongProfile)), .incompleteOrMismatchedProfile)
    }

    func testProfileRejectsNonFiniteEvidenceIntervals() throws {
        for h in [Harness(freshness: .infinity), Harness(observation: .infinity)] {
            var state = WorkoutExecutionState()
            state = accepted(h.reduce(state, .userStartsConnection(h.epoch))).state
            h.advance()
            state = accepted(h.reduce(state, .connectionBecomesReady(epoch: h.epoch, capability: h.capability))).state
            h.advance()

            XCTAssertRejected(
                h.reduce(state, .arm(plan: h.plan, ceilings: h.ceilings, profile: h.profile)),
                .incompleteOrMismatchedProfile
            )
        }
    }

    func testRequestControlRequiresFreshExplicitHumanReadinessAndDoesNotSetMotionLatch() throws {
        let h = Harness()
        var state = try h.armedState()
        let missing = WorkoutOperatorReadiness(
            deckClear: true,
            consoleImmediatelyReachable: true,
            safetyKeyImmediatelyReachable: true,
            physicallyStationary: false
        )

        XCTAssertRejected(h.reduce(state, .userRequestsControl(epoch: h.epoch, readiness: missing)), .operatorReadinessMissing)
        let transition = accepted(h.reduce(state, .userRequestsControl(epoch: h.epoch, readiness: h.readiness)))
        state = transition.state

        XCTAssertEqual(transition.effects.count, 1)
        XCTAssertEqual(transition.effects.first?.intent, .requestControl)
        XCTAssertFalse(state.motionPossible)
        XCTAssertEqual(state.controlPermission, .requesting(try XCTUnwrap(transition.effects.first?.record).id))
        XCTAssertEqual(state.execution, .acquiringControl)
    }

    func testIntentSubmissionATTAndProtocolAcknowledgementRemainDistinct() throws {
        let h = Harness()
        var transition = accepted(h.reduce(try h.armedState(), .userRequestsControl(epoch: h.epoch, readiness: h.readiness)))
        let record = try XCTUnwrap(transition.effects.first?.record)

        h.advance()
        transition = accepted(h.reduce(transition.state, .intentSubmitted(epoch: h.epoch, procedureID: record.id)))
        guard case let .submitted(submitted) = transition.state.procedure else { return XCTFail("Expected submitted") }
        XCTAssertEqual(submitted.submittedAt, h.now)

        h.advance()
        transition = accepted(h.reduce(transition.state, .attAccepted(epoch: h.epoch, procedureID: record.id)))
        guard case let .attAccepted(attRecord, deadline) = transition.state.procedure else { return XCTFail("Expected ATT accepted") }
        XCTAssertEqual(attRecord.attAcceptedAt, h.now)
        XCTAssertEqual(deadline, h.now.advanced(by: 30))
        XCTAssertEqual(transition.state.execution, .acquiringControl)

        h.advance()
        transition = accepted(h.reduce(transition.state, .protocolAcknowledged(epoch: h.epoch, procedureID: record.id)))
        XCTAssertEqual(transition.state.execution, .readyToBegin)
        XCTAssertEqual(transition.state.controlPermission, .held(epoch: h.epoch, acknowledgedAt: h.now))
        XCTAssertEqual(transition.state.procedureHistory.last, .acknowledged(attRecord, at: h.now))
    }

    func testBeginRequiresCurrentTelemetryControlForegroundAndRepeatedReadiness() throws {
        let h = Harness()
        var state = try h.readyToBeginState()
        let noTelemetry = h.reduce(state, .userBegins(epoch: h.epoch, readiness: h.readiness))
        XCTAssertRejected(noTelemetry, .telemetryNotFresh)

        state = accepted(h.reduce(state, .telemetry(epoch: h.epoch, h.telemetry(speed: "0", inclination: "0")))).state
        let missing = WorkoutOperatorReadiness(deckClear: false, consoleImmediatelyReachable: true, safetyKeyImmediatelyReachable: true, physicallyStationary: true)
        XCTAssertRejected(h.reduce(state, .userBegins(epoch: h.epoch, readiness: missing)), .operatorReadinessMissing)

        h.advance()
        state = accepted(h.reduce(state, .telemetry(epoch: h.epoch, h.telemetry(speed: "0.1", inclination: "0")))).state
        XCTAssertRejected(h.reduce(state, .userBegins(epoch: h.epoch, readiness: h.readiness)), .treadmillNotReportedStationary)
        XCTAssertTrue(
            WorkoutExecutionPresentation(state: state).preflightBlockers.contains(.treadmillNotReportedStationary)
        )
        h.advance()
        state = accepted(h.reduce(state, .telemetry(epoch: h.epoch, h.telemetry(speed: "0", inclination: "0")))).state

        let transition = accepted(h.reduce(state, .userBegins(epoch: h.epoch, readiness: h.readiness)))
        XCTAssertEqual(transition.effects.first?.intent, .setTargetSpeed(speed("5")))
        XCTAssertTrue(transition.state.motionPossible)
        guard case let .applyingStep(application) = transition.state.execution else { return XCTFail("Expected applying") }
        XCTAssertEqual(application.stepIndex, 0)
        XCTAssertEqual(application.remainingIntents, [.setTargetInclination(inclination("0")), .start])
    }

    func testProfileOrderingIsDeterministic() throws {
        let h = Harness(targetOrder: .inclinationThenSpeed, requiresStart: false)
        var state = try h.readyToBeginState()
        state = accepted(h.reduce(state, .telemetry(epoch: h.epoch, h.telemetry(speed: "0", inclination: "0")))).state

        let begin = accepted(h.reduce(state, .userBegins(epoch: h.epoch, readiness: h.readiness)))

        XCTAssertEqual(begin.effects.first?.intent, .setTargetInclination(inclination("0")))
        guard case let .applyingStep(application) = begin.state.execution else { return XCTFail("Expected applying") }
        XCTAssertEqual(application.remainingIntents, [.setTargetSpeed(speed("5"))])
    }

    func testStepTimerStartsOnlyAfterAllAcknowledgementsAndOneLaterJointExactObservation() throws {
        let h = Harness()
        var transition = try h.beginTransition()

        transition = try h.acknowledgeCurrent(transition)
        XCTAssertEqual(transition.effects.first?.intent, .setTargetInclination(inclination("0")))
        transition = try h.acknowledgeCurrent(transition)
        XCTAssertEqual(transition.effects.first?.intent, .start)
        transition = try h.acknowledgeCurrent(transition)
        XCTAssertTrue(transition.effects.isEmpty)
        guard case let .applyingStep(application) = transition.state.execution else { return XCTFail("Expected observation pending") }
        XCTAssertNotNil(application.speedAcknowledgedAt)
        XCTAssertNotNil(application.inclinationAcknowledgedAt)
        XCTAssertNotNil(application.startAcknowledgedAt)

        h.advance()
        transition = accepted(h.reduce(transition.state, .telemetry(epoch: h.epoch, h.telemetry(speed: "4.9", inclination: "0"))))
        guard case .applyingStep = transition.state.execution else { return XCTFail("Ramp sample must remain pending") }

        h.advance()
        transition = accepted(h.reduce(transition.state, .telemetry(epoch: h.epoch, h.telemetry(speed: "5", inclination: "0", distance: "12.5"))))
        guard case let .runningStep(running) = transition.state.execution else { return XCTFail("Expected running") }
        XCTAssertEqual(running.segmentStartedAt, h.now)
        XCTAssertEqual(running.accumulatedActiveSeconds, 0)
        XCTAssertEqual(transition.state.observedMachine, .stepTargetReported(stepIndex: 0, sample: try XCTUnwrap(transition.state.telemetry.sample)))
    }

    func testCommandProgressionStopsIfTelemetryExpiresBeforeAcknowledgement() throws {
        let h = Harness(freshness: 2)
        let begin = try h.beginTransition()
        let transition = try h.acknowledgeCurrentAllowingFailure(begin)

        XCTAssertFailedClosed(transition, .telemetry("Telemetry is not fresh during command progression"))
        XCTAssertTrue(transition.effects.filter { $0.record != nil }.isEmpty)
        guard case .stale = transition.state.telemetry else { return XCTFail("Expected stale evidence") }
    }

    func testUnavailableMalformedStaleAndObservationTimeoutTelemetryFailClosed() throws {
        let unavailableHarness = Harness()
        var pending = try unavailableHarness.observationPendingTransition().state
        unavailableHarness.advance()
        var result = unavailableHarness.reduce(pending, .telemetry(epoch: unavailableHarness.epoch, .unavailable("field absent")))
        XCTAssertFailedClosed(result, .telemetry("field absent"))
        XCTAssertTrue(result.effects.contains(.directUserToConsoleAndSafetyKey))

        let malformedHarness = Harness()
        pending = try malformedHarness.observationPendingTransition().state
        malformedHarness.advance()
        result = malformedHarness.reduce(pending, .telemetry(epoch: malformedHarness.epoch, .malformed("short packet")))
        XCTAssertFailedClosed(result, .telemetry("short packet"))

        let staleHarness = Harness(freshness: 50)
        let running = try staleHarness.runningTransition().state
        staleHarness.advance(by: 51)
        result = staleHarness.reduce(running, .tick(epoch: staleHarness.epoch))
        XCTAssertFailedClosed(result, .telemetry("Telemetry became stale"))
        guard case .stale = result.state.telemetry else { return XCTFail("Expected stale telemetry") }

        let timeoutHarness = Harness(freshness: 50, observation: 4)
        pending = try timeoutHarness.observationPendingTransition().state
        timeoutHarness.advance(by: 4)
        result = timeoutHarness.reduce(pending, .tick(epoch: timeoutHarness.epoch))
        XCTAssertFailedClosed(result, .observationTimeout)

        let missingHarness = Harness()
        pending = try missingHarness.observationPendingTransition().state
        missingHarness.advance()
        result = missingHarness.reduce(
            pending,
            .telemetry(epoch: missingHarness.epoch, .sample(speed: speed("5"), inclination: nil, totalDistanceMetres: nil))
        )
        XCTAssertFailedClosed(result, .telemetry("Required field missing"))
    }

    func testContradictoryObservationAfterConfirmationFailsButRampBeforeConfirmationDoesNot() throws {
        let h = Harness()
        var transition = try h.runningTransition()
        h.advance()
        transition = h.reduce(transition.state, .telemetry(epoch: h.epoch, h.telemetry(speed: "5.1", inclination: "0")))

        XCTAssertFailedClosed(transition, .telemetry("Contradictory confirmed target"))
        guard case .contradictory = transition.state.telemetry else { return XCTFail("Expected contradiction") }
        XCTAssertTrue(transition.state.motionPossible)
    }

    func testWrongEpochIsIgnoredAndFutureEpochRejected() throws {
        let h = Harness(epochValue: 7)
        let state = try h.armedState()
        let old = ConnectionEpoch(rawValue: 6)
        let future = ConnectionEpoch(rawValue: 8)

        let ignored = h.reduce(state, .telemetry(epoch: old, h.telemetry(speed: "0", inclination: "0")))
        XCTAssertEqual(ignored.state, state)
        XCTAssertEqual(ignored.disposition, .ignored(.staleEpoch))
        XCTAssertRejected(h.reduce(state, .tick(epoch: future)), .wrongEpoch)
    }

    func testWrongProcedureFailsClosedAndDuplicateOrLateEvidenceCannotProgress() throws {
        let h = Harness()
        var transition = accepted(h.reduce(try h.armedState(), .userRequestsControl(epoch: h.epoch, readiness: h.readiness)))
        let current = try XCTUnwrap(transition.effects.first?.record).id
        let wrong = ProcedureID(epoch: h.epoch, sequence: current.sequence + 99)
        h.advance()
        transition = h.reduce(transition.state, .intentSubmitted(epoch: h.epoch, procedureID: wrong))
        XCTAssertFailedClosed(transition, .procedure(.correlationFailure(expected: current, received: wrong)))
        XCTAssertTrue(transition.effects.isEmpty)

        let lateHarness = Harness()
        let ready = try lateHarness.readyToBeginState()
        let prior = try XCTUnwrap(ready.procedureHistory.last?.record).id
        lateHarness.advance()
        let late = lateHarness.reduce(ready, .protocolAcknowledged(epoch: lateHarness.epoch, procedureID: prior))
        XCTAssertFailedClosed(late, .procedure(.duplicateOrLate(prior)))
        XCTAssertEqual(late.state.execution, .ended(.failedBeforeActuation(.procedure(.duplicateOrLate(prior)))))
    }

    func testEveryExposedGuardHasAStateEventRejectionPath() throws {
        var seen: Set<WorkoutGuardRejection> = []
        func capture(_ transition: WorkoutExecutionTransition) {
            switch transition.disposition {
            case let .rejected(reason), let .ignored(reason): seen.insert(reason)
            case .accepted, .failedClosed: break
            }
        }

        let h = Harness(epochValue: 7)
        var connecting = accepted(h.reduce(WorkoutExecutionState(), .userStartsConnection(h.epoch))).state
        capture(h.reduce(connecting, .userStartsConnection(h.epoch)))
        capture(h.reduce(connecting, .connectionBecomesReady(epoch: .init(rawValue: 8), capability: h.capability)))
        capture(h.reduce(connecting, .connectionBecomesReady(epoch: .init(rawValue: 6), capability: h.capability)))
        capture(h.reduce(WorkoutExecutionState(), .arm(plan: h.plan, ceilings: h.ceilings, profile: h.profile)))

        let incompleteCapability = FR30zCapabilitySnapshot(
            identity: h.capability.identity,
            equipmentIdentity: h.capability.equipmentIdentity,
            planCapabilities: h.capability.planCapabilities,
            controlPointSupportsWrite: true,
            controlPointSupportsIndicate: true,
            controlPointIndicationsEnabled: false,
            passiveSubscriptionOutcomesResolved: true
        )
        capture(h.reduce(connecting, .connectionBecomesReady(epoch: h.epoch, capability: incompleteCapability)))
        connecting = accepted(h.reduce(connecting, .connectionBecomesReady(epoch: h.epoch, capability: h.capability))).state
        let restrictive = WorkoutSessionCeilings(
            maximumSpeed: speed("4"),
            maximumInclination: h.ceilings.maximumInclination,
            maximumStepSpeedChange: h.ceilings.maximumStepSpeedChange
        )
        capture(h.reduce(connecting, .arm(plan: h.plan, ceilings: restrictive, profile: h.profile)))

        let invalidProfileHarness = Harness(freshness: .infinity)
        var invalidProfileConnection = accepted(
            invalidProfileHarness.reduce(WorkoutExecutionState(), .userStartsConnection(invalidProfileHarness.epoch))
        ).state
        invalidProfileConnection = accepted(
            invalidProfileHarness.reduce(
                invalidProfileConnection,
                .connectionBecomesReady(epoch: invalidProfileHarness.epoch, capability: invalidProfileHarness.capability)
            )
        ).state
        capture(
            invalidProfileHarness.reduce(
                invalidProfileConnection,
                .arm(
                    plan: invalidProfileHarness.plan,
                    ceilings: invalidProfileHarness.ceilings,
                    profile: invalidProfileHarness.profile
                )
            )
        )

        let readinessHarness = Harness()
        let armed = try readinessHarness.armedState()
        let missingReadiness = WorkoutOperatorReadiness(
            deckClear: false,
            consoleImmediatelyReachable: true,
            safetyKeyImmediatelyReachable: true,
            physicallyStationary: true
        )
        capture(
            readinessHarness.reduce(
                armed,
                .userRequestsControl(epoch: readinessHarness.epoch, readiness: missingReadiness)
            )
        )
        let busy = accepted(
            readinessHarness.reduce(
                armed,
                .userRequestsControl(epoch: readinessHarness.epoch, readiness: readinessHarness.readiness)
            )
        ).state
        capture(
            readinessHarness.reduce(
                busy,
                .userRequestsControl(epoch: readinessHarness.epoch, readiness: readinessHarness.readiness)
            )
        )

        let beginHarness = Harness()
        var ready = try beginHarness.readyToBeginState()
        capture(beginHarness.reduce(ready, .userBegins(epoch: beginHarness.epoch, readiness: beginHarness.readiness)))
        ready.controlPermission = .notHeld
        capture(beginHarness.reduce(ready, .userBegins(epoch: beginHarness.epoch, readiness: beginHarness.readiness)))
        ready = try beginHarness.readyToBeginState()
        ready.isForegroundActive = false
        capture(beginHarness.reduce(ready, .userBegins(epoch: beginHarness.epoch, readiness: beginHarness.readiness)))
        ready = try beginHarness.readyToBeginState()
        ready.procedure = busy.procedure
        capture(beginHarness.reduce(ready, .userBegins(epoch: beginHarness.epoch, readiness: beginHarness.readiness)))
        ready = try beginHarness.readyToBeginState()
        beginHarness.advance()
        ready = accepted(
            beginHarness.reduce(
                ready,
                .telemetry(epoch: beginHarness.epoch, beginHarness.telemetry(speed: "0.1", inclination: "0"))
            )
        ).state
        capture(beginHarness.reduce(ready, .userBegins(epoch: beginHarness.epoch, readiness: beginHarness.readiness)))

        let lateHarness = Harness()
        let lateReady = try lateHarness.readyToBeginState()
        let prior = try XCTUnwrap(lateReady.procedureHistory.last?.record).id
        capture(
            lateHarness.reduce(
                lateReady,
                .intentSubmissionRejected(epoch: lateHarness.epoch, procedureID: prior, reason: "late")
            )
        )

        let stopHarness = Harness(freshness: 50)
        var stopping = try stopHarness.runningTransition().state
        stopHarness.advance()
        stopping = accepted(
            stopHarness.reduce(stopping, .userRequestsStop(epoch: stopHarness.epoch, reason: .userRequested))
        ).state
        capture(stopHarness.reduce(stopping, .userRequestsStop(epoch: stopHarness.epoch, reason: .userRequested)))

        let clockHarness = Harness()
        let clockState = try clockHarness.armedState()
        clockHarness.setTime(clockState.lastEventTime.seconds - 1)
        capture(clockHarness.reduce(clockState, .tick(epoch: clockHarness.epoch)))

        XCTAssertEqual(seen, Set(WorkoutGuardRejection.allCases))
    }

    func testBenignNonRunningEvidenceUpdatesRemainEffectFree() throws {
        let h = Harness()
        var state = try h.armedState()
        h.advance()
        var transition = accepted(
            h.reduce(state, .telemetry(epoch: h.epoch, .sample(speed: nil, inclination: nil, totalDistanceMetres: nil)))
        )
        XCTAssertTrue(transition.effects.isEmpty)
        guard case .unavailable = transition.state.telemetry else { return XCTFail("Expected unavailable telemetry") }

        state = transition.state
        h.advance()
        transition = accepted(h.reduce(state, .capabilityChanged(epoch: h.epoch, capability: h.capability)))
        XCTAssertTrue(transition.effects.isEmpty)
        XCTAssertEqual(transition.state.connection.readyCapability, h.capability)
    }

    func testDuplicateAcknowledgementDuringNextProcedureFailsClosed() throws {
        let h = Harness()
        var transition = try h.beginTransition()
        let speedProcedure = try XCTUnwrap(transition.effects.first?.record).id
        transition = try h.acknowledgeCurrent(transition)
        h.advance()

        transition = h.reduce(transition.state, .protocolAcknowledged(epoch: h.epoch, procedureID: speedProcedure))

        guard case let .failedAwaitingHumanStop(.procedure(.correlationFailure(expected, received))) = transition.state.execution else {
            return XCTFail("Expected duplicate correlation failure")
        }
        XCTAssertNotEqual(expected, received)
        XCTAssertEqual(received, speedProcedure)
        XCTAssertTrue(transition.effects.contains(.directUserToConsoleAndSafetyKey))
    }

    func testDuplicateSubmissionForCurrentProcedureFailsClosed() throws {
        let h = Harness()
        var transition = try h.beginTransition()
        let id = try XCTUnwrap(transition.effects.first?.record).id
        h.advance()
        transition = accepted(h.reduce(transition.state, .intentSubmitted(epoch: h.epoch, procedureID: id)))
        h.advance()

        transition = h.reduce(transition.state, .intentSubmitted(epoch: h.epoch, procedureID: id))

        XCTAssertFailedClosed(transition, .procedure(.duplicateOrLate(id)))
        XCTAssertTrue(transition.effects.filter { $0.record != nil }.isEmpty)
    }

    func testRejectedAndUnsupportedCommandsEmitNoRetryOrCompensatingEffect() throws {
        for failure in FailureEvent.allCases {
            let h = Harness()
            let begin = try h.beginTransition()
            let id = try XCTUnwrap(begin.effects.first?.record).id
            h.advance()
            let submitted = accepted(h.reduce(begin.state, .intentSubmitted(epoch: h.epoch, procedureID: id)))
            let transition: WorkoutExecutionTransition
            switch failure {
            case .submission:
                transition = h.reduce(begin.state, .intentSubmissionRejected(epoch: h.epoch, procedureID: id, reason: "transport"))
            case .att:
                transition = h.reduce(submitted.state, .attRejected(epoch: h.epoch, procedureID: id, reason: "ATT error"))
            case .protocol:
                h.advance()
                let acceptedATT = accepted(h.reduce(submitted.state, .attAccepted(epoch: h.epoch, procedureID: id)))
                transition = h.reduce(acceptedATT.state, .protocolRejected(epoch: h.epoch, procedureID: id, reason: "operation failed"))
            case .unsupported:
                h.advance()
                let acceptedATT = accepted(h.reduce(submitted.state, .attAccepted(epoch: h.epoch, procedureID: id)))
                transition = h.reduce(acceptedATT.state, .protocolUnsupported(epoch: h.epoch, procedureID: id))
            case .malformed:
                h.advance()
                let acceptedATT = accepted(h.reduce(submitted.state, .attAccepted(epoch: h.epoch, procedureID: id)))
                transition = h.reduce(acceptedATT.state, .protocolMalformed(epoch: h.epoch, procedureID: id))
            case .unknown:
                h.advance()
                let acceptedATT = accepted(h.reduce(submitted.state, .attAccepted(epoch: h.epoch, procedureID: id)))
                transition = h.reduce(acceptedATT.state, .protocolUnknown(epoch: h.epoch, procedureID: id))
            }
            XCTAssertFalse(transition.effects.contains(where: { $0.record != nil }), "No command effect for \(failure)")
            XCTAssertTrue(transition.state.motionPossible)
            guard case .failedAwaitingHumanStop = transition.state.execution else { return XCTFail("Expected fail closed") }
        }
    }

    func testProcedureTimeoutIsUnknownAndNeverRetries() throws {
        let h = Harness()
        var transition = try h.beginTransition()
        let id = try XCTUnwrap(transition.effects.first?.record).id
        h.advance()
        transition = accepted(h.reduce(transition.state, .intentSubmitted(epoch: h.epoch, procedureID: id)))
        h.advance()
        transition = accepted(h.reduce(transition.state, .attAccepted(epoch: h.epoch, procedureID: id)))
        h.advance(by: 30)

        transition = h.reduce(transition.state, .tick(epoch: h.epoch))

        XCTAssertFailedClosed(transition, .procedure(.responseTimeout))
        XCTAssertTrue(transition.effects.filter { $0.record != nil }.isEmpty)
        guard case .timedOutUnknown = transition.state.procedure else { return XCTFail("Expected unknown timeout") }
    }

    func testProtocolEvidenceAtResponseDeadlineTimesOutWithoutDependingOnTickOrder() throws {
        let h = Harness()
        var transition = try h.beginTransition()
        let id = try XCTUnwrap(transition.effects.first?.record).id
        h.advance()
        transition = accepted(h.reduce(transition.state, .intentSubmitted(epoch: h.epoch, procedureID: id)))
        h.advance()
        transition = accepted(h.reduce(transition.state, .attAccepted(epoch: h.epoch, procedureID: id)))
        h.advance(by: 30)

        transition = h.reduce(transition.state, .protocolAcknowledged(epoch: h.epoch, procedureID: id))

        XCTAssertFailedClosed(transition, .procedure(.responseTimeout))
        guard case .timedOutUnknown = transition.state.procedure else { return XCTFail("Expected unknown timeout") }
        XCTAssertTrue(transition.effects.filter { $0.record != nil }.isEmpty)
    }

    func testTargetObservationAtDeadlineFailsWithoutDependingOnTickOrder() throws {
        let h = Harness(freshness: 50, observation: 4)
        var transition = try h.observationPendingTransition()
        h.advance(by: 4)

        transition = h.reduce(
            transition.state,
            .telemetry(epoch: h.epoch, h.telemetry(speed: "5", inclination: "0"))
        )

        XCTAssertFailedClosed(transition, .observationTimeout)
        guard case .failedAwaitingHumanStop = transition.state.execution else { return XCTFail("Expected fail closed") }
    }

    func testEveryStepReissuesBothTargetsAndProgressesOnlyOnExplicitTick() throws {
        let h = Harness(requiresStart: false, freshness: 50, repeatedTargets: true)
        var transition = try h.runningTransition()
        h.advance(by: 9)
        transition = accepted(h.reduce(transition.state, .tick(epoch: h.epoch)))
        guard case .runningStep = transition.state.execution else { return XCTFail("Should still run") }
        XCTAssertTrue(transition.effects.isEmpty)

        h.advance(by: 1)
        transition = accepted(h.reduce(transition.state, .tick(epoch: h.epoch)))
        XCTAssertEqual(transition.effects.first?.intent, .setTargetSpeed(speed("5")))
        guard case let .applyingStep(application) = transition.state.execution else { return XCTFail("Expected next step") }
        XCTAssertEqual(application.stepIndex, 1)
        XCTAssertEqual(application.remainingIntents, [.setTargetInclination(inclination("0"))])
        let presentation = WorkoutExecutionPresentation(state: transition.state)
        XCTAssertEqual(presentation.requestedSpeed, speed("5"))
        XCTAssertEqual(presentation.speedCommandState, .intentCreated)
        XCTAssertEqual(presentation.inclinationCommandState, .notRequested)
    }

    func testStopRequestImmediatelyFreezesCountdownAndCancellationEmitsNothing() throws {
        let h = Harness(freshness: 50)
        var transition = try h.runningTransition()
        h.advance(by: 3)
        transition = accepted(h.reduce(transition.state, .userRequestsStop(epoch: h.epoch, reason: .userRequested)))
        let frozen = WorkoutExecutionPresentation(state: transition.state)
        XCTAssertEqual(frozen.elapsedActiveSeconds, 3)
        XCTAssertEqual(frozen.currentStep?.remainingSeconds, 7)
        XCTAssertEqual(frozen.stopState, .confirmationRequired)
        XCTAssertTrue(transition.effects.isEmpty)

        h.advance(by: 20)
        transition = accepted(h.reduce(transition.state, .tick(epoch: h.epoch)))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).elapsedActiveSeconds, 3)
        h.advance()
        transition = accepted(h.reduce(transition.state, .userCancelsStop(epoch: h.epoch)))
        XCTAssertTrue(transition.effects.isEmpty)
        h.advance(by: 2)
        transition = accepted(h.reduce(transition.state, .tick(epoch: h.epoch)))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).elapsedActiveSeconds, 5)
    }

    func testStopConfirmationEmitsAtMostOneIntentAndCancellationNeverEmitsOne() throws {
        let h = Harness(freshness: 50)
        var transition = try h.runningTransition()
        h.advance()
        transition = accepted(h.reduce(transition.state, .userRequestsStop(epoch: h.epoch, reason: .userRequested)))
        h.advance()
        let confirmed = accepted(h.reduce(transition.state, .userConfirmsStop(epoch: h.epoch)))
        XCTAssertEqual(confirmed.effects.filter { $0.intent == .stop }.count, 1)
        XCTAssertEqual(WorkoutExecutionPresentation(state: confirmed.state).stopState, .intentCreated)

        h.advance()
        XCTAssertRejected(h.reduce(confirmed.state, .userConfirmsStop(epoch: h.epoch)), .wrongState)
        XCTAssertRejected(h.reduce(confirmed.state, .userRequestsStop(epoch: h.epoch, reason: .userRequested)), .stopAlreadyRequested)
    }

    func testStopSubmissionATTAndProtocolSuccessRemainSentUnconfirmed() throws {
        let h = Harness(freshness: 50)
        var transition = try h.stopIntentTransition()
        let id = try XCTUnwrap(transition.effects.first?.record).id
        h.advance()
        transition = accepted(h.reduce(transition.state, .intentSubmitted(epoch: h.epoch, procedureID: id)))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .submitted)
        XCTAssertFalse(transition.state.isEnded)
        h.advance()
        transition = accepted(h.reduce(transition.state, .attAccepted(epoch: h.epoch, procedureID: id)))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .attAccepted)
        XCTAssertFalse(transition.state.isEnded)
        h.advance()
        transition = accepted(h.reduce(transition.state, .protocolAcknowledged(epoch: h.epoch, procedureID: id)))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .sentUnconfirmed)
        XCTAssertFalse(transition.state.isEnded)

        h.advance()
        transition = accepted(h.reduce(transition.state, .telemetry(epoch: h.epoch, h.telemetry(speed: "0", inclination: "0"))))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .sentUnconfirmed)
        XCTAssertFalse(transition.state.isEnded)
    }

    func testStopWithoutPermissionOrProfileAuthorityProducesNoStopIntent() throws {
        let h = Harness(permitsStop: false, freshness: 50)
        var transition = try h.runningTransition()
        h.advance()
        transition = accepted(h.reduce(transition.state, .userRequestsStop(epoch: h.epoch, reason: .userRequested)))
        h.advance()
        transition = accepted(h.reduce(transition.state, .userConfirmsStop(epoch: h.epoch)))

        XCTAssertTrue(transition.effects.filter { $0.record != nil }.isEmpty)
        XCTAssertTrue(transition.effects.contains(.directUserToConsoleAndSafetyKey))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .notSentUsePhysicalControls)
    }

    func testStopFailureKeepsSeparateCommandOutcomeAndStillNeedsHumanEvidence() throws {
        let h = Harness(freshness: 50)
        var transition = try h.stopIntentTransition()
        let id = try XCTUnwrap(transition.effects.first?.record).id
        h.advance()
        transition = h.reduce(transition.state, .intentSubmissionRejected(epoch: h.epoch, procedureID: id, reason: "not sent"))

        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .failedUsePhysicalControls)
        XCTAssertFalse(transition.state.isEnded)
        XCTAssertTrue(transition.effects.contains(.directUserToConsoleAndSafetyKey))
    }

    func testStopTimeoutAndDisconnectPreserveSentUnconfirmedState() throws {
        let timeoutHarness = Harness(freshness: 100)
        var transition = try timeoutHarness.stopIntentTransition()
        var id = try XCTUnwrap(transition.effects.first?.record).id
        timeoutHarness.advance()
        transition = accepted(timeoutHarness.reduce(transition.state, .intentSubmitted(epoch: timeoutHarness.epoch, procedureID: id)))
        timeoutHarness.advance()
        transition = accepted(timeoutHarness.reduce(transition.state, .attAccepted(epoch: timeoutHarness.epoch, procedureID: id)))
        timeoutHarness.advance(by: 30)
        transition = timeoutHarness.reduce(transition.state, .tick(epoch: timeoutHarness.epoch))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .sentUnconfirmed)
        XCTAssertFalse(transition.state.isEnded)

        let disconnectHarness = Harness(freshness: 100)
        transition = try disconnectHarness.stopIntentTransition()
        id = try XCTUnwrap(transition.effects.first?.record).id
        disconnectHarness.advance()
        transition = accepted(disconnectHarness.reduce(transition.state, .intentSubmitted(epoch: disconnectHarness.epoch, procedureID: id)))
        disconnectHarness.advance()
        transition = disconnectHarness.reduce(transition.state, .connectionLost(epoch: disconnectHarness.epoch, reason: "lost after send"))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .sentUnconfirmed)
        XCTAssertFalse(transition.state.isEnded)
    }

    func testStopCommandOutcomeSurvivesLaterCapabilityAndTelemetryFailures() throws {
        let capabilityHarness = Harness(freshness: 100)
        var transition = try capabilityHarness.stopIntentTransition()
        transition = try capabilityHarness.acknowledgeCurrent(transition)
        let changed = FR30zCapabilitySnapshot(
            identity: "changed",
            equipmentIdentity: capabilityHarness.capability.equipmentIdentity,
            planCapabilities: capabilityHarness.capability.planCapabilities,
            controlPointSupportsWrite: true,
            controlPointSupportsIndicate: true,
            controlPointIndicationsEnabled: true,
            passiveSubscriptionOutcomesResolved: true
        )
        capabilityHarness.advance()
        transition = capabilityHarness.reduce(
            transition.state,
            .capabilityChanged(epoch: capabilityHarness.epoch, capability: changed)
        )
        XCTAssertFailedClosed(transition, .capabilityChanged)
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .sentUnconfirmed)
        guard case .awaitingHumanStop = transition.state.execution else { return XCTFail("Expected preserved stop gate") }

        let telemetryHarness = Harness(freshness: 100)
        transition = try telemetryHarness.stopIntentTransition()
        transition = try telemetryHarness.acknowledgeCurrent(transition)
        telemetryHarness.advance()
        transition = telemetryHarness.reduce(
            transition.state,
            .telemetry(epoch: telemetryHarness.epoch, telemetryHarness.telemetry(speed: "99", inclination: "0"))
        )
        XCTAssertFailedClosed(transition, .telemetry("Contradictory telemetry"))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .sentUnconfirmed)
        guard case .awaitingHumanStop = transition.state.execution else { return XCTFail("Expected preserved stop gate") }
    }

    func testResolvedStopOutcomeIsNotDowngradedByDisconnectOrInterruption() throws {
        let acknowledgedHarness = Harness(freshness: 100)
        var transition = try acknowledgedHarness.stopIntentTransition()
        transition = try acknowledgedHarness.acknowledgeCurrent(transition)
        let acknowledgedProcedure = transition.state.procedure
        acknowledgedHarness.advance()
        transition = acknowledgedHarness.reduce(
            transition.state,
            .connectionLost(epoch: acknowledgedHarness.epoch, reason: "after acknowledgement")
        )
        XCTAssertEqual(transition.state.procedure, acknowledgedProcedure)
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .sentUnconfirmed)

        let failedHarness = Harness(freshness: 100)
        transition = try failedHarness.stopIntentTransition()
        let id = try XCTUnwrap(transition.effects.first?.record).id
        failedHarness.advance()
        transition = failedHarness.reduce(
            transition.state,
            .intentSubmissionRejected(epoch: failedHarness.epoch, procedureID: id, reason: "definite rejection")
        )
        let failedProcedure = transition.state.procedure
        failedHarness.advance()
        transition = failedHarness.reduce(
            transition.state,
            .appBecameInactive(epoch: failedHarness.epoch, reason: "after rejection")
        )
        XCTAssertEqual(transition.state.procedure, failedProcedure)
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .failedUsePhysicalControls)
    }

    func testLateTargetEvidenceCannotDiscardConfirmedStopGate() throws {
        let h = Harness(freshness: 100)
        var transition = try h.beginTransition()
        let targetID = try XCTUnwrap(transition.effects.first?.record).id
        h.advance()
        transition = accepted(h.reduce(transition.state, .userRequestsStop(epoch: h.epoch, reason: .userRequested)))
        h.advance()
        transition = accepted(h.reduce(transition.state, .userConfirmsStop(epoch: h.epoch)))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .notSentUsePhysicalControls)
        h.advance()
        transition = accepted(h.reduce(transition.state, .intentSubmitted(epoch: h.epoch, procedureID: targetID)))
        h.advance()
        transition = accepted(h.reduce(transition.state, .attAccepted(epoch: h.epoch, procedureID: targetID)))
        h.advance()

        transition = h.reduce(transition.state, .protocolAcknowledged(epoch: h.epoch, procedureID: targetID))

        XCTAssertFailedClosed(transition, .procedure(.duplicateOrLate(targetID)))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .notSentUsePhysicalControls)
        guard case .awaitingHumanStop = transition.state.execution else { return XCTFail("Expected preserved stop gate") }
        guard case let .acknowledged(record, _) = transition.state.procedure else { return XCTFail("Expected recorded late acknowledgement") }
        XCTAssertEqual(record.id, targetID)
        XCTAssertEqual(transition.state.procedureHistory.last, .acknowledged(record, at: h.now))
        guard case .invalidated = transition.state.controlPermission else { return XCTFail("Expected invalidated control") }
    }

    func testOnlyHumanStopEvidenceEndsPossibleMotionAndClearsLatch() throws {
        let h = Harness(freshness: 50)
        var transition = try h.stopIntentTransition()
        XCTAssertTrue(transition.state.motionPossible)
        h.advance()
        transition = accepted(h.reduce(transition.state, .humanConfirmsStopped(epoch: h.epoch, note: "Operator observed belt stopped")))

        XCTAssertTrue(transition.state.isEnded)
        XCTAssertFalse(transition.state.motionPossible)
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .humanConfirmed)
        guard case .humanConfirmedStopped = transition.state.observedMachine else { return XCTFail("Expected human evidence") }
        guard case let .ended(.stopped(_, _, evidence)) = transition.state.execution else { return XCTFail("Expected retained evidence") }
        XCTAssertEqual(evidence.note, "Operator observed belt stopped")
    }

    func testTerminalEventsCannotOverwriteHumanStopEvidenceOrReopenMotionLatch() throws {
        let h = Harness(freshness: 100)
        var transition = try h.stopIntentTransition()
        h.advance()
        transition = accepted(
            h.reduce(transition.state, .humanConfirmsStopped(epoch: h.epoch, note: "Belt visibly stopped"))
        )
        let ended = transition.state
        h.advance()
        let lateTelemetry = h.reduce(
            ended,
            .telemetry(epoch: h.epoch, h.telemetry(speed: "5", inclination: "0"))
        )
        XCTAssertEqual(lateTelemetry.disposition, .ignored(.wrongState))
        XCTAssertEqual(lateTelemetry.state, ended)

        h.advance()
        let disconnected = accepted(
            h.reduce(ended, .connectionLost(epoch: h.epoch, reason: "link closed after workout"))
        )
        XCTAssertFalse(disconnected.state.motionPossible)
        XCTAssertEqual(disconnected.state.observedMachine, ended.observedMachine)
        XCTAssertEqual(disconnected.state.execution, ended.execution)
    }

    func testMotionPossibleIsMonotonicAcrossSilenceFailureDisconnectAndInterruption() throws {
        for event in SafetyFailureEvent.allCases {
            let h = Harness(freshness: 50)
            let running = try h.runningTransition().state
            h.advance()
            let transition: WorkoutExecutionTransition
            switch event {
            case .silence:
                h.advance(by: 50)
                transition = h.reduce(running, .tick(epoch: h.epoch))
            case .disconnect:
                transition = h.reduce(running, .connectionLost(epoch: h.epoch, reason: "link lost"))
            case .interruption:
                transition = h.reduce(running, .appBecameInactive(epoch: h.epoch, reason: "background"))
            case .permissionLoss:
                transition = h.reduce(running, .controlPermissionLost(epoch: h.epoch, reason: "console override"))
            }
            XCTAssertTrue(transition.state.motionPossible, "Latch cleared for \(event)")
            XCTAssertTrue(transition.effects.contains(.directUserToConsoleAndSafetyKey))
            XCTAssertFalse(transition.effects.contains(where: { $0.record != nil }))
        }
    }

    func testInterruptionBeforeActuationEndsWithoutStopClaimOrAutomaticEffect() throws {
        let h = Harness()
        let armed = try h.armedState()
        h.advance()
        let transition = h.reduce(armed, .appBecameInactive(epoch: h.epoch, reason: "foreground lost"))

        XCTAssertFailedClosed(transition, .foregroundLost("foreground lost"))
        XCTAssertEqual(transition.state.execution, .ended(.failedBeforeActuation(.foregroundLost("foreground lost"))))
        XCTAssertFalse(transition.state.motionPossible)
        XCTAssertTrue(transition.effects.isEmpty)
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .endedWithoutPhysicalStopClaim)
    }

    func testConfirmedCancellationBeforeActuationMakesNoPhysicalStopClaim() throws {
        let h = Harness()
        var transition = accepted(
            h.reduce(try h.armedState(), .userRequestsStop(epoch: h.epoch, reason: .cancelled))
        )
        h.advance()
        transition = accepted(h.reduce(transition.state, .userConfirmsStop(epoch: h.epoch)))

        XCTAssertEqual(transition.state.execution, .ended(.cancelledBeforeActuation))
        XCTAssertEqual(WorkoutExecutionPresentation(state: transition.state).stopState, .endedWithoutPhysicalStopClaim)
        XCTAssertTrue(transition.effects.isEmpty)
    }

    func testUnexpectedHumanMotionBeforeActuationRaisesLatchAndRequiresHumanStop() throws {
        let h = Harness()
        let armed = try h.armedState()
        h.advance()
        let transition = h.reduce(armed, .humanObservesMotion(epoch: h.epoch))

        XCTAssertFailedClosed(transition, .telemetry("Unexpected human observation of motion"))
        XCTAssertTrue(transition.state.motionPossible)
        guard case .failedAwaitingHumanStop = transition.state.execution else { return XCTFail("Expected human-stop gate") }
        XCTAssertTrue(transition.effects.contains(.directUserToConsoleAndSafetyKey))
    }

    func testConnectionLossNeverReconnectsAndInvalidatesAllCurrentEvidence() throws {
        let h = Harness(freshness: 50)
        let running = try h.runningTransition().state
        h.advance()
        let transition = h.reduce(running, .connectionLost(epoch: h.epoch, reason: "radio lost"))

        XCTAssertEqual(transition.state.connection, .lost(previousEpoch: h.epoch, reason: "radio lost"))
        XCTAssertEqual(transition.state.observedMachine, .unknown)
        XCTAssertEqual(transition.state.telemetry, .unavailable("Connection lost"))
        XCTAssertFalse(transition.effects.contains(where: { $0.record != nil }))
        guard case .invalidated = transition.state.controlPermission else { return XCTFail("Expected invalidated control") }
    }

    func testCapabilityChangeFailsRatherThanAdaptingFrozenPlan() throws {
        let h = Harness(freshness: 50)
        let running = try h.runningTransition().state
        let changed = FR30zCapabilitySnapshot(
            identity: "new snapshot",
            equipmentIdentity: h.capability.equipmentIdentity,
            planCapabilities: h.capability.planCapabilities,
            controlPointSupportsWrite: true,
            controlPointSupportsIndicate: true,
            controlPointIndicationsEnabled: true,
            passiveSubscriptionOutcomesResolved: true
        )
        h.advance()
        let transition = h.reduce(running, .capabilityChanged(epoch: h.epoch, capability: changed))

        XCTAssertFailedClosed(transition, .capabilityChanged)
        XCTAssertEqual(transition.state.armedWorkout?.capability, h.capability)
        XCTAssertTrue(transition.effects.filter { $0.record != nil }.isEmpty)
        XCTAssertEqual(
            transition.state.connection,
            .invalidated(previousEpoch: h.epoch, reason: "Capability evidence changed")
        )
        XCTAssertTrue(WorkoutExecutionPresentation(state: transition.state).preflightBlockers.contains(.connectionNotReady))
    }

    func testInvalidatedConnectionRequiresAnIncreasingExplicitEpochBeforeRestart() throws {
        let h = Harness(epochValue: 7)
        let armed = try h.armedState()
        let changed = FR30zCapabilitySnapshot(
            identity: "changed",
            equipmentIdentity: h.capability.equipmentIdentity,
            planCapabilities: h.capability.planCapabilities,
            controlPointSupportsWrite: true,
            controlPointSupportsIndicate: true,
            controlPointIndicationsEnabled: true,
            passiveSubscriptionOutcomesResolved: true
        )
        h.advance()
        let invalidated = h.reduce(armed, .capabilityChanged(epoch: h.epoch, capability: changed)).state

        XCTAssertRejected(h.reduce(invalidated, .userStartsConnection(h.epoch)), .wrongEpoch)
        XCTAssertRejected(h.reduce(invalidated, .userStartsConnection(.init(rawValue: 6))), .wrongEpoch)
        let restarted = accepted(h.reduce(invalidated, .userStartsConnection(.init(rawValue: 8))))
        XCTAssertEqual(restarted.state.connection, .connecting(.init(rawValue: 8)))
        XCTAssertTrue(restarted.effects.isEmpty)
    }

    func testNonMonotonicClockEventIsRejectedWithoutMutation() throws {
        let h = Harness()
        var state = try h.armedState()
        h.advance(by: 10)
        state = accepted(h.reduce(state, .telemetry(epoch: h.epoch, h.telemetry(speed: "0", inclination: "0")))).state
        h.setTime(state.lastEventTime.seconds - 1)
        let transition = h.reduce(state, .tick(epoch: h.epoch))

        XCTAssertRejected(transition, .nonMonotonicTime)
        XCTAssertEqual(transition.state, state)
    }

    func testPresentationExposesDesignReadyPreflightCurrentNextCountdownAxesElapsedDistanceAndStop() throws {
        let h = Harness(freshness: 50)
        var transition = try h.runningTransition(distance: "42.25")
        h.advance(by: 3)
        transition = accepted(h.reduce(transition.state, .tick(epoch: h.epoch)))
        let presentation = WorkoutExecutionPresentation(state: transition.state)

        XCTAssertTrue(presentation.preflightBlockers.isEmpty)
        XCTAssertEqual(presentation.activity, .indoorRunning)
        XCTAssertEqual(presentation.currentStep?.label, "Warm up")
        XCTAssertEqual(presentation.currentStep?.remainingSeconds, 7)
        XCTAssertEqual(presentation.nextStep?.label, "Run")
        XCTAssertEqual(presentation.requestedSpeed, speed("5"))
        XCTAssertEqual(presentation.actualSpeed, speed("5"))
        XCTAssertEqual(presentation.speedCommandState, .targetObserved)
        XCTAssertEqual(presentation.requestedInclination, inclination("0"))
        XCTAssertEqual(presentation.actualInclination, inclination("0"))
        XCTAssertEqual(presentation.inclinationCommandState, .targetObserved)
        XCTAssertEqual(presentation.elapsedActiveSeconds, 3)
        guard case let .trustworthy(metres, _) = presentation.distance else { return XCTFail("Expected trustworthy distance") }
        XCTAssertEqual(metres, decimal("42.25"))
        XCTAssertEqual(presentation.stopState, .available)
        XCTAssertEqual(presentation.frozenCeilings, h.ceilings)
        XCTAssertEqual(presentation.executionProfileIdentity, h.profile.identity)
    }

    func testFinalStepExpiryRequiresStopConfirmationBeforeAnyStopIntent() throws {
        let h = Harness(requiresStart: false, freshness: 100, repeatedTargets: true)
        var transition = try h.runningTransition(stepIndex: 2)
        h.advance(by: 10)
        transition = accepted(h.reduce(transition.state, .tick(epoch: h.epoch)))

        XCTAssertTrue(transition.effects.isEmpty)
        guard case let .stopConfirmationRequested(request) = transition.state.execution else { return XCTFail("Expected confirmation") }
        XCTAssertEqual(request.reason, .completedPlan)
        XCTAssertFalse(transition.state.isEnded)
    }
}

private extension WorkoutExecutionReducerTests {
    enum FailureEvent: CaseIterable { case submission, att, `protocol`, unsupported, malformed, unknown }
    enum SafetyFailureEvent: CaseIterable { case silence, disconnect, interruption, permissionLoss }

    final class Harness {
        private var seconds: TimeInterval = 10
        let epoch: ConnectionEpoch
        let capability: FR30zCapabilitySnapshot
        let ceilings: WorkoutSessionCeilings
        let profile: FR30zExecutionProfile
        let plan: WorkoutPlanValidator.ValidatedPlan
        let readiness = WorkoutOperatorReadiness(
            deckClear: true,
            consoleImmediatelyReachable: true,
            safetyKeyImmediatelyReachable: true,
            physicallyStationary: true
        )

        lazy var reducer = WorkoutExecutionReducer(clock: { [unowned self] in self.now })
        var now: MonotonicInstant { .init(seconds: seconds) }

        init(
            epochValue: UInt64 = 1,
            targetOrder: FR30zTargetOrder = .speedThenInclination,
            requiresStart: Bool = true,
            permitsStop: Bool = true,
            freshness: TimeInterval = 50,
            observation: TimeInterval = 8,
            repeatedTargets: Bool = false
        ) {
            epoch = .init(rawValue: epochValue)
            capability = .init(
                identity: "capability-v1",
                equipmentIdentity: "FR30z-test-profile",
                planCapabilities: .init(
                    speed: .supported(.init(minimum: Self.speed("0"), maximum: Self.speed("20"), increment: Self.speed("0.1"))),
                    inclination: .supported(.init(minimum: Self.inclination("-3"), maximum: Self.inclination("15"), increment: Self.inclination("0.5")))
                ),
                controlPointSupportsWrite: true,
                controlPointSupportsIndicate: true,
                controlPointIndicationsEnabled: true,
                passiveSubscriptionOutcomesResolved: true
            )
            ceilings = .init(
                maximumSpeed: Self.speed("10"),
                maximumInclination: Self.inclination("6"),
                maximumStepSpeedChange: Self.speed("3")
            )
            profile = .init(
                identity: "synthetic-fr30z-profile-v1",
                equipmentIdentity: capability.equipmentIdentity,
                targetOrder: targetOrder,
                requiresStartForFirstStep: requiresStart,
                permitsStop: permitsStop,
                telemetryFreshnessInterval: freshness,
                targetObservationInterval: observation,
                procedureResponseInterval: 30,
                requestControlEvidenceAccepted: true,
                speedTargetEvidenceAccepted: true,
                inclinationTargetEvidenceAccepted: true,
                startEvidenceAccepted: requiresStart,
                stopEvidenceAccepted: permitsStop
            )
            let steps = repeatedTargets
                ? [Self.step(.warmUp, "Warm up", "5", "0"), Self.step(.interval, "Run", "5", "0"), Self.step(.coolDown, "Cool down", "5", "0")]
                : [Self.step(.warmUp, "Warm up", "5", "0"), Self.step(.interval, "Run", "7", "1"), Self.step(.coolDown, "Cool down", "4", "0")]
            let raw = WorkoutPlan(schemaVersion: 1, suggestedName: "Synthetic", activity: .indoorRunning, steps: steps)
            plan = try! WorkoutPlanValidator.validate(raw, against: capability.planCapabilities).get()
        }

        func advance(by interval: TimeInterval = 1) { seconds += interval }
        func setTime(_ value: TimeInterval) { seconds = value }
        func reduce(_ state: WorkoutExecutionState, _ event: WorkoutExecutionEvent) -> WorkoutExecutionTransition {
            reducer.reduce(state, event)
        }

        func accept(
            _ transition: WorkoutExecutionTransition,
            file: StaticString = #filePath,
            line: UInt = #line
        ) -> WorkoutExecutionTransition {
            XCTAssertEqual(transition.disposition, .accepted, file: file, line: line)
            return transition
        }

        func telemetry(speed speedValue: String, inclination inclinationValue: String, distance: String? = nil) -> WorkoutTelemetryInput {
            .sample(
                speed: Self.speed(speedValue),
                inclination: Self.inclination(inclinationValue),
                totalDistanceMetres: distance.map { Self.decimal($0) }
            )
        }

        func armedState() throws -> WorkoutExecutionState {
            var state = WorkoutExecutionState()
            state = accept(reduce(state, .userStartsConnection(epoch))).state
            advance()
            state = accept(reduce(state, .connectionBecomesReady(epoch: epoch, capability: capability))).state
            advance()
            return accept(reduce(state, .arm(plan: plan, ceilings: ceilings, profile: profile))).state
        }

        func readyToBeginState() throws -> WorkoutExecutionState {
            var transition = accept(reduce(try armedState(), .userRequestsControl(epoch: epoch, readiness: readiness)))
            transition = try acknowledgeCurrent(transition)
            return transition.state
        }

        func beginTransition() throws -> WorkoutExecutionTransition {
            var state = try readyToBeginState()
            advance()
            state = accept(reduce(state, .telemetry(epoch: epoch, telemetry(speed: "0", inclination: "0")))).state
            advance()
            return accept(reduce(state, .userBegins(epoch: epoch, readiness: readiness)))
        }

        func observationPendingTransition() throws -> WorkoutExecutionTransition {
            var transition = try beginTransition()
            repeat {
                transition = try acknowledgeCurrent(transition)
            } while transition.effects.contains(where: { $0.record != nil })
            return transition
        }

        func runningTransition(distance: String? = nil, stepIndex: Int = 0) throws -> WorkoutExecutionTransition {
            var transition = try observationPendingTransition()
            advance()
            transition = accept(reduce(transition.state, .telemetry(epoch: epoch, telemetry(speed: "5", inclination: "0", distance: distance))))
            if stepIndex == 0 { return transition }
            var state = transition.state
            for index in 1...stepIndex {
                advance(by: 10)
                transition = accept(reduce(state, .tick(epoch: epoch)))
                while !transition.effects.isEmpty { transition = try acknowledgeCurrent(transition) }
                advance()
                let step = plan.plan.steps[index]
                transition = accept(reduce(transition.state, .telemetry(epoch: epoch, .sample(speed: step.targetSpeed, inclination: step.targetInclination, totalDistanceMetres: nil))))
                state = transition.state
            }
            return transition
        }

        func stopIntentTransition() throws -> WorkoutExecutionTransition {
            var transition = try runningTransition()
            advance()
            transition = accept(reduce(transition.state, .userRequestsStop(epoch: epoch, reason: .userRequested)))
            advance()
            return accept(reduce(transition.state, .userConfirmsStop(epoch: epoch)))
        }

        func acknowledgeCurrent(_ initial: WorkoutExecutionTransition) throws -> WorkoutExecutionTransition {
            accept(try acknowledgeCurrentAllowingFailure(initial))
        }

        func acknowledgeCurrentAllowingFailure(_ initial: WorkoutExecutionTransition) throws -> WorkoutExecutionTransition {
            var transition = initial
            let id = try XCTUnwrap(transition.state.procedure.activeRecord?.id)
            advance()
            transition = accept(reduce(transition.state, .intentSubmitted(epoch: epoch, procedureID: id)))
            advance()
            transition = accept(reduce(transition.state, .attAccepted(epoch: epoch, procedureID: id)))
            advance()
            return reduce(transition.state, .protocolAcknowledged(epoch: epoch, procedureID: id))
        }

        private static func step(_ kind: WorkoutStepKind, _ label: String, _ speedValue: String, _ inclinationValue: String) -> WorkoutStep {
            .init(
                kind: kind,
                label: label,
                duration: .init(value: 10, unit: .seconds),
                targetSpeed: speed(speedValue),
                targetInclination: inclination(inclinationValue)
            )
        }

        private static func speed(_ value: String) -> WorkoutSpeed {
            .init(value: decimal(value), unit: .kilometresPerHour)
        }

        private static func inclination(_ value: String) -> WorkoutInclination {
            .init(value: decimal(value), unit: .percent)
        }

        private static func decimal(_ value: String) -> Decimal {
            Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
        }
    }

    func accepted(
        _ transition: WorkoutExecutionTransition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> WorkoutExecutionTransition {
        XCTAssertEqual(transition.disposition, .accepted, file: file, line: line)
        return transition
    }

    func XCTAssertRejected(
        _ transition: WorkoutExecutionTransition,
        _ reason: WorkoutGuardRejection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(transition.disposition, .rejected(reason), file: file, line: line)
        XCTAssertTrue(transition.effects.isEmpty, file: file, line: line)
    }

    func XCTAssertFailedClosed(
        _ transition: WorkoutExecutionTransition,
        _ failure: WorkoutExecutionFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(transition.disposition, .failedClosed(failure), file: file, line: line)
    }

    func speed(_ value: String) -> WorkoutSpeed {
        .init(value: decimal(value), unit: .kilometresPerHour)
    }

    func inclination(_ value: String) -> WorkoutInclination {
        .init(value: decimal(value), unit: .percent)
    }

    func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}

private extension WorkoutExecutionEffect {
    var record: WorkoutProcedureRecord? {
        guard case let .submit(record) = self else { return nil }
        return record
    }

    var intent: WorkoutControlPointIntent? { record?.intent }
}

private extension WorkoutProcedureOutcome {
    var record: WorkoutProcedureRecord {
        switch self {
        case let .acknowledged(record, _), let .failed(record, _), let .timedOutUnknown(record): record
        }
    }
}

private extension WorkoutTelemetryState {
    var sample: WorkoutTelemetrySample? {
        guard case let .fresh(sample) = self else { return nil }
        return sample
    }
}

private extension WorkoutExecutionState {
    var isEnded: Bool {
        guard case .ended = execution else { return false }
        return true
    }
}
