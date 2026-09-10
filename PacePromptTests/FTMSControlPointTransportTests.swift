import Foundation
import XCTest
@testable import PacePrompt

@MainActor
final class FTMSControlPointTransportTests: XCTestCase {
    func testRequiresConfirmedIndicationsBeforeAnyWrite() throws {
        let harness = try Harness(autoEnable: false)

        XCTAssertEqual(harness.transport.state.link, .awaitingIndicationEnablement(harness.epoch))
        XCTAssertThrowsTransportError(.indicationsNotConfirmed) {
            try harness.transport.submit(.requestControl)
        }
        XCTAssertTrue(harness.link.writes.isEmpty)

        try harness.transport.enableIndications()
        XCTAssertEqual(harness.link.enableIndicationsCount, 1)
        XCTAssertEqual(harness.transport.state.link, .enablingIndications(harness.epoch))
        XCTAssertThrowsTransportError(.indicationsNotConfirmed) {
            try harness.transport.submit(.requestControl)
        }

        harness.link.send(.indicationsEnabled)
        XCTAssertEqual(harness.transport.state.link, .ready(harness.epoch))
        _ = try harness.transport.submit(.requestControl)
        XCTAssertEqual(harness.link.writes, [Data([0x00])])
    }

    func testMissingWriteOrIndicatePropertyFailsClosed() throws {
        for properties in [(false, true), (true, false), (false, false)] {
            let harness = try Harness(
                autoEnable: false,
                supportsWrite: properties.0,
                supportsIndications: properties.1
            )
            XCTAssertThrowsTransportError(.unsupportedControlPointProperties) {
                try harness.transport.enableIndications()
            }
            XCTAssertInvalidated(harness.transport.state, epoch: harness.epoch)
            XCTAssertTrue(harness.link.writes.isEmpty)
            XCTAssertEqual(harness.link.invalidateCount, 1)
        }
    }

    func testProcedureIDsEpochBytesAndMonotonicTimestampsAreRetained() throws {
        let harness = try Harness()
        harness.clock.seconds = 10
        let id = try harness.transport.submit(.requestControl)

        XCTAssertEqual(id, ProcedureID(epoch: harness.epoch, sequence: 1))
        XCTAssertEqual(harness.transport.state.permission, .requesting(id))
        XCTAssertEqual(
            harness.transport.state.inFlight,
            FTMSControlPointProcedureEvidence(
                id: id,
                intent: .requestControl,
                exactRequestBytes: Data([0x00]),
                submittedAt: MonotonicInstant(seconds: 10),
                attOutcome: nil,
                response: nil,
                responseReceivedAt: nil
            )
        )
        XCTAssertThrowsTransportError(.procedureInFlight(id)) {
            try harness.transport.submit(.requestControl)
        }
        XCTAssertEqual(harness.link.writes, [Data([0x00])])

        harness.clock.seconds = 11
        harness.link.send(.writeAccepted)
        XCTAssertEqual(harness.scheduler.intervals, [30])
        guard case let .accepted(attAt, deadline)? = harness.transport.state.inFlight?.attOutcome else {
            return XCTFail("Expected ATT acceptance evidence")
        }
        XCTAssertEqual(attAt, MonotonicInstant(seconds: 11))
        XCTAssertEqual(deadline, MonotonicInstant(seconds: 41))

        harness.clock.seconds = 40.999
        harness.link.send(.indication(Data([0x80, 0x00, 0x01])))
        XCTAssertEqual(
            harness.transport.state.permission,
            .held(harness.epoch, acknowledgedAt: MonotonicInstant(seconds: 40.999))
        )
        XCTAssertNil(harness.transport.state.inFlight)
        XCTAssertEqual(harness.transport.state.outcomes.count, 1)
        guard case let .acknowledged(response) = harness.transport.state.outcomes[0].result else {
            return XCTFail("Expected protocol acknowledgement")
        }
        XCTAssertEqual(response.rawBytes, Data([0x80, 0x00, 0x01]))
        XCTAssertEqual(harness.transport.state.outcomes[0].evidence.exactRequestBytes, Data([0x00]))
        XCTAssertTrue(harness.scheduler.tokens[0].isCancelled)
    }

    func testControlPermissionGatesEveryNonRequestProcedure() throws {
        let harness = try Harness()
        let intents: [FitnessMachineControlIntent] = [
            .setTargetSpeed(kilometresPerHour: 4.5),
            .setTargetInclination(percent: 2),
            .start,
            .stop,
        ]
        for intent in intents {
            XCTAssertThrowsTransportError(.controlNotHeld) {
                try harness.transport.submit(intent)
            }
        }
        XCTAssertTrue(harness.link.writes.isEmpty)
    }

    func testHeldControlAllowsOnlyExactReviewedProcedureBytesOneAtATime() throws {
        let harness = try Harness()
        try harness.grantControl()

        let cases: [(FitnessMachineControlIntent, Data, UInt8)] = [
            (.setTargetSpeed(kilometresPerHour: 4.5), Data([0x02, 0xC2, 0x01]), 0x02),
            (.setTargetInclination(percent: -2.5), Data([0x03, 0xE7, 0xFF]), 0x03),
            (.start, Data([0x07]), 0x07),
            (.stop, Data([0x08, 0x01]), 0x08),
        ]

        for (offset, item) in cases.enumerated() {
            harness.clock.seconds += 1
            let id = try harness.transport.submit(item.0)
            XCTAssertEqual(id, ProcedureID(epoch: harness.epoch, sequence: UInt64(offset + 2)))
            XCTAssertEqual(harness.link.writes.last, item.1)
            XCTAssertEqual(harness.transport.state.inFlight?.intent, item.0)

            harness.link.send(.writeAccepted)
            harness.clock.seconds += 1
            harness.link.send(.indication(Data([0x80, item.2, 0x01])))
            guard case .acknowledged = harness.transport.state.outcomes.last?.result else {
                return XCTFail("Expected a distinct FTMS acknowledgement")
            }
            XCTAssertEqual(
                harness.transport.state.permission,
                .held(harness.epoch, acknowledgedAt: MonotonicInstant(seconds: 2))
            )
        }
        XCTAssertEqual(harness.link.writes.count, 5)
    }

    func testRequestControlCannotBeRepeatedWhilePermissionIsHeld() throws {
        let harness = try Harness()
        try harness.grantControl()
        XCTAssertThrowsTransportError(.requestControlWhileHeld) {
            try harness.transport.submit(.requestControl)
        }
        XCTAssertEqual(harness.link.writes.count, 1)
    }

    func testExplicitATTErrorIsKnownNotDeliveredAndDoesNotRetry() throws {
        let harness = try Harness()
        _ = try harness.transport.submit(.requestControl)
        harness.clock.seconds = 1
        harness.link.send(.writeATTRejected(code: 0x81, message: "Write not permitted"))

        XCTAssertEqual(harness.transport.state.link, .ready(harness.epoch))
        XCTAssertEqual(harness.transport.state.permission, .notHeld)
        XCTAssertNil(harness.transport.state.inFlight)
        XCTAssertEqual(harness.link.writes.count, 1)
        guard case let .attRejected(code, message) = harness.transport.state.outcomes[0].result else {
            return XCTFail("Expected explicit ATT rejection")
        }
        XCTAssertEqual(code, 0x81)
        XCTAssertEqual(message, "Write not permitted")
        guard case let .rejected(recordedCode, _, at)? = harness.transport.state.outcomes[0].evidence.attOutcome else {
            return XCTFail("Expected retained ATT result")
        }
        XCTAssertEqual(recordedCode, 0x81)
        XCTAssertEqual(at, MonotonicInstant(seconds: 1))
    }

    func testLocalWriteErrorLeavesDeliveryUnknownAndInvalidatesLink() throws {
        let harness = try Harness()
        _ = try harness.transport.submit(.requestControl)
        harness.clock.seconds = 1
        harness.link.send(.writeDeliveryUnknown("Bluetooth reset"))

        XCTAssertInvalidated(harness.transport.state, epoch: harness.epoch)
        XCTAssertEqual(harness.transport.state.permission, .notHeld)
        XCTAssertEqual(harness.link.writes.count, 1)
        guard case .deliveryUnknown("Bluetooth reset") = harness.transport.state.outcomes[0].result else {
            return XCTFail("Expected delivery-unknown outcome")
        }
    }

    func testEveryDefinedNegativeFTMSResultIsRetainedWithoutRetry() throws {
        for result in [
            FTMSControlPointResult.opcodeNotSupported,
            .invalidParameter,
            .operationFailed,
            .controlNotPermitted,
        ] {
            let harness = try Harness()
            _ = try harness.transport.submit(.requestControl)
            harness.link.send(.writeAccepted)
            harness.clock.seconds = 1
            let bytes = Data([0x80, 0x00, result.rawValue])
            harness.link.send(.indication(bytes))

            XCTAssertEqual(harness.transport.state.link, .ready(harness.epoch))
            XCTAssertEqual(harness.transport.state.permission, .notHeld)
            XCTAssertEqual(harness.link.writes.count, 1)
            guard case let .ftmsRejected(response) = harness.transport.state.outcomes[0].result else {
                return XCTFail("Expected negative FTMS response")
            }
            XCTAssertEqual(response.result, result)
            XCTAssertEqual(response.rawBytes, bytes)
        }
    }

    func testMalformedReservedAndMismatchedIndicationsFailClosed() throws {
        let cases: [(Data, String)] = [
            (Data([0x80, 0x00]), "exactly 3 bytes"),
            (Data([0x81, 0x00, 0x01]), "not 0x80"),
            (Data([0x80, 0x01, 0x01]), "unsupported or reserved"),
            (Data([0x80, 0x00, 0x00]), "reserved result"),
            (Data([0x80, 0x02, 0x01]), "did not match"),
        ]

        for (bytes, expectedReason) in cases {
            let harness = try Harness()
            _ = try harness.transport.submit(.requestControl)
            harness.link.send(.writeAccepted)
            harness.clock.seconds = 1
            harness.link.send(.indication(bytes))

            XCTAssertInvalidated(harness.transport.state, epoch: harness.epoch)
            XCTAssertEqual(harness.link.writes.count, 1)
            guard case let .protocolAnomaly(reason, raw)? = harness.transport.state.outcomes.last?.result else {
                return XCTFail("Expected protocol anomaly")
            }
            XCTAssertTrue(reason.contains(expectedReason), "\(reason) did not contain \(expectedReason)")
            XCTAssertEqual(raw, bytes)
            XCTAssertEqual(
                harness.transport.state.outcomes.last?.evidence.responseReceivedAt,
                MonotonicInstant(seconds: 1)
            )
        }

    }

    func testEarlyMatchingIndicationIsProvisionalUntilATTAcceptance() throws {
        let harness = try Harness()
        harness.clock.seconds = 10
        let id = try harness.transport.submit(.requestControl)
        harness.clock.seconds = 11
        let bytes = Data([0x80, 0x00, 0x01])
        harness.link.send(.indication(bytes))

        XCTAssertEqual(harness.transport.state.permission, .requesting(id))
        XCTAssertTrue(harness.transport.state.inFlight?.hasProvisionalResponse == true)
        XCTAssertEqual(harness.transport.state.inFlight?.id, id)
        XCTAssertEqual(harness.transport.state.inFlight?.provisionalResponse?.rawBytes, bytes)
        XCTAssertNil(harness.transport.state.inFlight?.response)
        XCTAssertEqual(
            harness.transport.state.inFlight?.responseReceivedAt,
            MonotonicInstant(seconds: 11)
        )
        XCTAssertTrue(harness.scheduler.tokens.isEmpty)
        XCTAssertTrue(harness.transport.state.outcomes.isEmpty)

        harness.clock.seconds = 12
        harness.link.send(.writeAccepted)

        XCTAssertNil(harness.transport.state.inFlight)
        XCTAssertEqual(
            harness.transport.state.permission,
            .held(harness.epoch, acknowledgedAt: MonotonicInstant(seconds: 12))
        )
        XCTAssertTrue(harness.scheduler.tokens.isEmpty)
        guard case let .acknowledged(response) = harness.transport.state.outcomes[0].result else {
            return XCTFail("Expected acknowledgement only after ATT acceptance")
        }
        XCTAssertEqual(response.rawBytes, bytes)
        XCTAssertEqual(harness.transport.state.outcomes[0].evidence.id, id)
        XCTAssertNil(harness.transport.state.outcomes[0].evidence.provisionalResponse)
        XCTAssertEqual(harness.transport.state.outcomes[0].evidence.response?.rawBytes, bytes)
        XCTAssertEqual(
            harness.transport.state.outcomes[0].evidence.attOutcome,
            .accepted(
                at: MonotonicInstant(seconds: 12),
                indicationDeadline: MonotonicInstant(seconds: 42)
            )
        )
        XCTAssertEqual(
            harness.transport.state.outcomes[0].evidence.responseReceivedAt,
            MonotonicInstant(seconds: 11)
        )
        XCTAssertEqual(
            harness.transport.state.outcomes[0].completedAt,
            MonotonicInstant(seconds: 12)
        )
        XCTAssertEqual(harness.link.writes, [Data([0x00])])
    }

    func testEarlyMatchingIndicationCannotOverrideATTRejectionOrUnknownDelivery() throws {
        let rejected = try Harness()
        _ = try rejected.transport.submit(.requestControl)
        let bytes = Data([0x80, 0x00, 0x01])
        rejected.link.send(.indication(bytes))
        rejected.clock.seconds = 1
        rejected.link.send(.writeATTRejected(code: 0x03, message: "Write not permitted"))

        XCTAssertEqual(rejected.transport.state.permission, .notHeld)
        XCTAssertNil(rejected.transport.state.inFlight)
        XCTAssertEqual(rejected.link.writes, [Data([0x00])])
        guard case .attRejected(code: 0x03, message: "Write not permitted") =
            rejected.transport.state.outcomes[0].result else {
            return XCTFail("Expected ATT rejection to remain authoritative")
        }
        XCTAssertEqual(
            rejected.transport.state.outcomes[0].evidence.provisionalResponse?.rawBytes,
            bytes
        )
        XCTAssertNil(rejected.transport.state.outcomes[0].evidence.response)

        let unknown = try Harness()
        _ = try unknown.transport.submit(.requestControl)
        unknown.link.send(.indication(bytes))
        unknown.clock.seconds = 1
        unknown.link.send(.writeDeliveryUnknown("Bluetooth reset"))

        XCTAssertInvalidated(unknown.transport.state, epoch: unknown.epoch)
        XCTAssertEqual(unknown.transport.state.permission, .notHeld)
        XCTAssertEqual(unknown.link.writes, [Data([0x00])])
        guard case .deliveryUnknown("Bluetooth reset") = unknown.transport.state.outcomes[0].result else {
            return XCTFail("Expected unknown delivery to fail closed")
        }
        XCTAssertEqual(unknown.transport.state.outcomes[0].evidence.provisionalResponse?.rawBytes, bytes)
        XCTAssertNil(unknown.transport.state.outcomes[0].evidence.response)
    }

    func testEarlyResponseDisconnectRemainsDeliveryUnknown() throws {
        let harness = try Harness()
        _ = try harness.transport.submit(.requestControl)
        let bytes = Data([0x80, 0x00, 0x01])
        harness.link.send(.indication(bytes))
        harness.clock.seconds = 1
        harness.link.send(.disconnected("Link lost"))

        XCTAssertEqual(harness.transport.state.link, .disconnected)
        XCTAssertEqual(harness.transport.state.permission, .notHeld)
        XCTAssertEqual(harness.link.writes, [Data([0x00])])
        guard case .deliveryUnknownDisconnect("Link lost") = harness.transport.state.outcomes[0].result else {
            return XCTFail("Expected disconnect before ATT acceptance to preserve uncertainty")
        }
        XCTAssertEqual(harness.transport.state.outcomes[0].evidence.provisionalResponse?.rawBytes, bytes)
        XCTAssertNil(harness.transport.state.outcomes[0].evidence.response)
    }

    func testMalformedMismatchedDuplicateAndInvalidTimeEarlyResponsesFailClosed() throws {
        for bytes in [
            Data([0x80, 0x00]),
            Data([0x80, 0x02, 0x01]),
        ] {
            let harness = try Harness()
            _ = try harness.transport.submit(.requestControl)
            harness.link.send(.indication(bytes))
            XCTAssertInvalidated(harness.transport.state, epoch: harness.epoch)
            XCTAssertEqual(harness.link.writes, [Data([0x00])])
            guard case .protocolAnomaly = harness.transport.state.outcomes[0].result else {
                return XCTFail("Expected malformed or mismatched early response to fail closed")
            }
        }

        let duplicate = try Harness()
        _ = try duplicate.transport.submit(.requestControl)
        let bytes = Data([0x80, 0x00, 0x01])
        duplicate.link.send(.indication(bytes))
        duplicate.clock.seconds = 1
        duplicate.link.send(.indication(bytes))
        XCTAssertInvalidated(duplicate.transport.state, epoch: duplicate.epoch)
        guard case let .protocolAnomaly(reason, raw) = duplicate.transport.state.outcomes[0].result else {
            return XCTFail("Expected duplicate early response to fail closed")
        }
        XCTAssertTrue(reason.contains("Duplicate"))
        XCTAssertEqual(raw, bytes)

        let invalidTime = try Harness()
        invalidTime.clock.seconds = 1
        _ = try invalidTime.transport.submit(.requestControl)
        invalidTime.clock.seconds = .nan
        invalidTime.link.send(.indication(bytes))
        XCTAssertInvalidated(invalidTime.transport.state, epoch: invalidTime.epoch)
        XCTAssertEqual(invalidTime.transport.state.permission, .notHeld)
        XCTAssertEqual(invalidTime.link.writes, [Data([0x00])])
        XCTAssertTrue(invalidTime.transport.state.outcomes.isEmpty)
    }

    func testProvisionalResponseCannotCrossConnectionEpochOrProcedureIdentity() throws {
        let clock = FakeMonotonicClock()
        let scheduler = FakeDeadlineScheduler()
        let transport = FTMSSingleProcedureTransport(clock: { clock.instant }, scheduler: scheduler)
        let first = FakeControlPointLink()
        let firstEpoch = ConnectionEpoch(rawValue: 7)
        try transport.establishLink(epoch: firstEpoch, eligibility: Harness.eligibility, link: first)
        try transport.enableIndications()
        first.send(.indicationsEnabled)
        let firstID = try transport.submit(.requestControl)
        first.send(.indication(Data([0x80, 0x00, 0x01])))
        XCTAssertEqual(transport.state.inFlight?.id, firstID)
        first.send(.disconnected("First link ended"))

        let second = FakeControlPointLink()
        let secondEpoch = ConnectionEpoch(rawValue: 8)
        try transport.establishLink(epoch: secondEpoch, eligibility: Harness.eligibility, link: second)
        try transport.enableIndications()
        second.send(.indicationsEnabled)
        let secondID = try transport.submit(.requestControl)
        XCTAssertNotEqual(firstID, secondID)

        first.send(.writeAccepted)
        XCTAssertEqual(transport.state.inFlight?.id, secondID)
        XCTAssertNil(transport.state.inFlight?.provisionalResponse)
        XCTAssertNil(transport.state.inFlight?.response)
        XCTAssertEqual(transport.state.permission, .requesting(secondID))
        XCTAssertEqual(transport.state.anomalies.last, .staleLinkEvent(firstEpoch))
        XCTAssertEqual(second.writes, [Data([0x00])])
    }

    func testDuplicateAndLateIndicationsInvalidateWithoutChangingPriorSuccess() throws {
        let duplicate = try Harness()
        try duplicate.grantControl()
        let priorOutcome = duplicate.transport.state.outcomes[0]
        duplicate.link.send(.indication(Data([0x80, 0x00, 0x01])))
        XCTAssertInvalidated(duplicate.transport.state, epoch: duplicate.epoch)
        XCTAssertEqual(duplicate.transport.state.outcomes, [priorOutcome])
        XCTAssertEqual(
            duplicate.transport.state.anomalies.last,
            .unexpectedEvent("Duplicate or late Control Point indication")
        )

        let late = try Harness()
        _ = try late.transport.submit(.requestControl)
        late.link.send(.writeAccepted)
        late.clock.seconds = 30
        let bytes = Data([0x80, 0x00, 0x01])
        late.link.send(.indication(bytes))
        XCTAssertInvalidated(late.transport.state, epoch: late.epoch)
        guard case let .protocolAnomaly(reason, raw) = late.transport.state.outcomes[0].result else {
            return XCTFail("Expected late response anomaly")
        }
        XCTAssertTrue(reason.contains("at or after the 30-second deadline"))
        XCTAssertEqual(raw, bytes)
    }

    func testThirtySecondDeadlineTimesOutAndRequiresNewLink() throws {
        let harness = try Harness()
        _ = try harness.transport.submit(.requestControl)
        harness.link.send(.writeAccepted)
        XCTAssertEqual(harness.scheduler.intervals, [30])

        harness.clock.seconds = 29.999
        XCTAssertNotNil(harness.transport.state.inFlight)
        harness.clock.seconds = 30
        harness.scheduler.fireLast()

        XCTAssertInvalidated(harness.transport.state, epoch: harness.epoch)
        guard case .timedOut = harness.transport.state.outcomes[0].result else {
            return XCTFail("Expected timeout")
        }
        XCTAssertThrowsTransportError(.linkInvalidated) {
            try harness.transport.submit(.requestControl)
        }
        XCTAssertEqual(harness.link.writes.count, 1)
    }

    func testDisconnectPreservesPreATTDeliveryUncertaintyAndPostATTProfileTimeout() throws {
        let beforeATT = try Harness()
        _ = try beforeATT.transport.submit(.requestControl)
        beforeATT.clock.seconds = 1
        beforeATT.link.send(.disconnected("Link lost"))
        XCTAssertEqual(beforeATT.transport.state.link, .disconnected)
        guard case .deliveryUnknownDisconnect("Link lost") = beforeATT.transport.state.outcomes[0].result else {
            return XCTFail("Expected delivery-unknown disconnect")
        }

        let afterATT = try Harness()
        _ = try afterATT.transport.submit(.requestControl)
        afterATT.link.send(.writeAccepted)
        afterATT.clock.seconds = 1
        afterATT.link.send(.disconnected(nil))
        XCTAssertEqual(afterATT.transport.state.link, .disconnected)
        guard case .timedOutByDisconnect(nil) = afterATT.transport.state.outcomes[0].result else {
            return XCTFail("Expected Profile-defined timeout on link loss")
        }
        XCTAssertTrue(afterATT.scheduler.tokens[0].isCancelled)
    }

    func testConnectionEpochsMustAdvanceAndStaleCallbacksCannotCorruptNewLink() throws {
        let clock = FakeMonotonicClock()
        let scheduler = FakeDeadlineScheduler()
        let transport = FTMSSingleProcedureTransport(clock: { clock.instant }, scheduler: scheduler)
        let first = FakeControlPointLink()
        let eligibility = Harness.eligibility

        try transport.establishLink(epoch: ConnectionEpoch(rawValue: 7), eligibility: eligibility, link: first)
        try transport.enableIndications()
        first.send(.indicationsEnabled)
        first.send(.disconnected("First link ended"))

        XCTAssertThrowsTransportError(.invalidConnectionEpoch) {
            try transport.establishLink(
                epoch: ConnectionEpoch(rawValue: 7),
                eligibility: eligibility,
                link: FakeControlPointLink()
            )
        }
        let second = FakeControlPointLink()
        let secondEpoch = ConnectionEpoch(rawValue: 8)
        try transport.establishLink(epoch: secondEpoch, eligibility: eligibility, link: second)
        try transport.enableIndications()
        second.send(.indicationsEnabled)

        first.send(.writeAccepted)
        XCTAssertEqual(transport.state.link, .ready(secondEpoch))
        XCTAssertEqual(transport.state.anomalies.last, .staleLinkEvent(ConnectionEpoch(rawValue: 7)))
        XCTAssertTrue(second.writes.isEmpty)
        let id = try transport.submit(.requestControl)
        XCTAssertEqual(id, ProcedureID(epoch: secondEpoch, sequence: 1))
    }

    func testInvalidTargetsAreRejectedBeforeWriting() throws {
        let harness = try Harness()
        try harness.grantControl()
        let count = harness.link.writes.count

        for intent in [
            FitnessMachineControlIntent.setTargetSpeed(kilometresPerHour: .nan),
            .setTargetSpeed(kilometresPerHour: 30),
            .setTargetSpeed(kilometresPerHour: 4.55),
            .setTargetInclination(percent: .infinity),
            .setTargetInclination(percent: 16),
            .setTargetInclination(percent: 2.1),
        ] {
            XCTAssertThrowsError(try harness.transport.submit(intent)) { error in
                guard case .invalidIntent = error as? FTMSControlPointTransportError else {
                    return XCTFail("Expected invalid-intent rejection, received \(error)")
                }
            }
        }
        XCTAssertEqual(harness.link.writes.count, count)
        XCTAssertNil(harness.transport.state.inFlight)
        XCTAssertEqual(harness.transport.state.link, .ready(harness.epoch))
    }

    func testNonMonotonicTimeIndicationAndSubscriptionFailuresFailClosed() throws {
        let clockFailure = try Harness()
        clockFailure.clock.seconds = 5
        _ = try clockFailure.transport.submit(.requestControl)
        clockFailure.clock.seconds = 4
        clockFailure.link.send(.writeAccepted)
        XCTAssertInvalidated(clockFailure.transport.state, epoch: clockFailure.epoch)

        let indicationFailure = try Harness()
        _ = try indicationFailure.transport.submit(.requestControl)
        indicationFailure.link.send(.writeAccepted)
        indicationFailure.link.send(.indicationFailed("Decode channel failed"))
        XCTAssertInvalidated(indicationFailure.transport.state, epoch: indicationFailure.epoch)
        guard case let .protocolAnomaly(reason, nil) = indicationFailure.transport.state.outcomes[0].result else {
            return XCTFail("Expected retained indication failure")
        }
        XCTAssertTrue(reason.contains("Decode channel failed"))

        let subscriptionFailure = try Harness(autoEnable: false)
        try subscriptionFailure.transport.enableIndications()
        subscriptionFailure.link.send(.indicationEnableFailed("CCCD rejected"))
        XCTAssertInvalidated(subscriptionFailure.transport.state, epoch: subscriptionFailure.epoch)
        XCTAssertTrue(subscriptionFailure.link.writes.isEmpty)
    }

    func testDuplicateATTCallbackFailsClosedAndNeverStartsAnotherWrite() throws {
        let harness = try Harness()
        _ = try harness.transport.submit(.requestControl)
        harness.link.send(.writeAccepted)
        harness.link.send(.writeAccepted)

        XCTAssertInvalidated(harness.transport.state, epoch: harness.epoch)
        XCTAssertEqual(harness.link.writes.count, 1)
        XCTAssertEqual(
            harness.transport.state.anomalies.last,
            .unexpectedEvent("Duplicate or late ATT write response")
        )
    }

    private func XCTAssertThrowsTransportError(
        _ expected: FTMSControlPointTransportError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? FTMSControlPointTransportError, expected, file: file, line: line)
        }
    }

    private func XCTAssertInvalidated(
        _ state: FTMSControlPointTransportState,
        epoch: ConnectionEpoch,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .invalidated(actualEpoch, reason) = state.link else {
            return XCTFail("Expected invalidated state, received \(state.link)", file: file, line: line)
        }
        XCTAssertEqual(actualEpoch, epoch, file: file, line: line)
        XCTAssertFalse(reason.isEmpty, file: file, line: line)
    }
}

@MainActor
private final class Harness {
    static let eligibility = FTMSControlPointEligibility(
        features: FTMSFeatureFlags(machineFeatures: 0, targetSettingFeatures: 0x0000_0003),
        speedRange: FTMSSpeedRange(
            minimumKilometresPerHour: 0.5,
            maximumKilometresPerHour: 20,
            minimumIncrementKilometresPerHour: 0.1
        ),
        inclinationRange: FTMSInclinationRange(
            minimumPercent: -5,
            maximumPercent: 15,
            minimumIncrementPercent: 0.5
        )
    )

    let epoch = ConnectionEpoch(rawValue: 7)
    let clock = FakeMonotonicClock()
    let scheduler = FakeDeadlineScheduler()
    let link: FakeControlPointLink
    let transport: FTMSSingleProcedureTransport

    init(
        autoEnable: Bool = true,
        supportsWrite: Bool = true,
        supportsIndications: Bool = true
    ) throws {
        link = FakeControlPointLink(
            supportsWriteWithResponse: supportsWrite,
            supportsIndications: supportsIndications
        )
        transport = FTMSSingleProcedureTransport(
            clock: { [clock] in clock.instant },
            scheduler: scheduler
        )
        try transport.establishLink(epoch: epoch, eligibility: Self.eligibility, link: link)
        if autoEnable {
            try transport.enableIndications()
            link.send(.indicationsEnabled)
        }
    }

    func grantControl() throws {
        clock.seconds = 1
        _ = try transport.submit(.requestControl)
        link.send(.writeAccepted)
        clock.seconds = 2
        link.send(.indication(Data([0x80, 0x00, 0x01])))
    }
}

@MainActor
private final class FakeMonotonicClock {
    var seconds: TimeInterval = 0
    var instant: MonotonicInstant { MonotonicInstant(seconds: seconds) }
}

@MainActor
private final class FakeDeadlineToken: FTMSDeadlineCancellation {
    let interval: TimeInterval
    let action: @MainActor () -> Void
    private(set) var isCancelled = false

    init(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.action = action
    }

    func cancel() {
        isCancelled = true
    }

    func fire() {
        guard !isCancelled else { return }
        action()
    }
}

@MainActor
private final class FakeDeadlineScheduler: FTMSDeadlineScheduling {
    private(set) var tokens: [FakeDeadlineToken] = []
    var intervals: [TimeInterval] { tokens.map(\.interval) }

    func schedule(
        after interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any FTMSDeadlineCancellation {
        let token = FakeDeadlineToken(interval: interval, action: action)
        tokens.append(token)
        return token
    }

    func fireLast() {
        tokens.last?.fire()
    }
}

@MainActor
private final class FakeControlPointLink: FTMSControlPointLink {
    let supportsWriteWithResponse: Bool
    let supportsIndications: Bool
    var eventHandler: ((FTMSControlPointLinkEvent) -> Void)?
    private(set) var enableIndicationsCount = 0
    private(set) var writes: [Data] = []
    private(set) var invalidateCount = 0

    init(supportsWriteWithResponse: Bool = true, supportsIndications: Bool = true) {
        self.supportsWriteWithResponse = supportsWriteWithResponse
        self.supportsIndications = supportsIndications
    }

    func enableIndications() {
        enableIndicationsCount += 1
    }

    func writeWithResponse(_ data: Data) {
        writes.append(data)
    }

    func invalidate() {
        invalidateCount += 1
    }

    func send(_ event: FTMSControlPointLinkEvent) {
        eventHandler?(event)
    }
}
