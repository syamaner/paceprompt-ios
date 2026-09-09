import Foundation
import XCTest
@testable import PacePrompt

@MainActor
final class RequestControlDiagnosticTests: XCTestCase {
    func testGateConsumesOnlyExactRequestControlAndPersistsAcrossInstances() throws {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let gate = RequestControlWriteGate(
            defaults: fixture.defaults,
            attemptKey: "attempt"
        )

        try gate.consume(Data([0x00]))

        XCTAssertTrue(gate.wasConsumed)
        let reloaded = RequestControlWriteGate(
            defaults: fixture.defaults,
            attemptKey: "attempt"
        )
        XCTAssertThrowsError(try reloaded.consume(Data([0x00]))) { error in
            XCTAssertEqual(error as? RequestControlWriteGateError, .attemptAlreadyConsumed)
        }
    }

    func testGateRejectsEveryScopedDisallowedOpcodeWithoutConsumingAttempt() {
        let disallowedRequests = [
            Data([0x01]),
            Data([0x02, 0x64, 0x00]),
            Data([0x03, 0x00, 0x00]),
            Data([0x07]),
            Data([0x08, 0x01]),
            Data([0x08, 0x02]),
        ]

        for (index, request) in disallowedRequests.enumerated() {
            let fixture = makeDefaults(suffix: "\(index)")
            defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
            let gate = RequestControlWriteGate(
                defaults: fixture.defaults,
                attemptKey: "attempt"
            )

            XCTAssertThrowsError(try gate.consume(request)) { error in
                XCTAssertEqual(error as? RequestControlWriteGateError, .disallowedBytes(request))
            }
            XCTAssertFalse(gate.wasConsumed)
        }
    }

    func testRestrictedLinkForwardsExactRequestOnceWithResponse() {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let underlying = FakeControlPointLink()
        let link = RequestControlOnlyLink(
            underlying: underlying,
            gate: RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt")
        )
        var audited: [Data] = []
        link.requestSubmitted = { audited.append($0) }

        link.writeWithResponse(Data([0x00]))

        XCTAssertEqual(underlying.writes, [Data([0x00])])
        XCTAssertEqual(audited, [Data([0x00])])
        XCTAssertEqual(underlying.invalidateCount, 0)
    }

    func testRestrictedLinkBlocksDuplicateBeforeCoreBluetoothWrite() {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let underlying = FakeControlPointLink()
        let link = RequestControlOnlyLink(
            underlying: underlying,
            gate: RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt")
        )
        var blocked: [String] = []
        var events: [FTMSControlPointLinkEvent] = []
        link.requestBlocked = { blocked.append($0) }
        link.eventHandler = { events.append($0) }

        link.writeWithResponse(Data([0x00]))
        link.writeWithResponse(Data([0x00]))

        XCTAssertEqual(underlying.writes, [Data([0x00])])
        XCTAssertEqual(blocked.count, 1)
        XCTAssertEqual(underlying.invalidateCount, 1)
        XCTAssertEqual(events.count, 1)
        guard case let .writeDeliveryUnknown(message) = events[0] else {
            return XCTFail("Expected a local block event")
        }
        XCTAssertTrue(message.contains("No retry occurred"))
    }

    func testRestrictedLinkBlocksNonRequestBytesBeforeUnderlyingWrite() {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let underlying = FakeControlPointLink()
        let link = RequestControlOnlyLink(
            underlying: underlying,
            gate: RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt")
        )

        link.writeWithResponse(Data([0x07]))

        XCTAssertTrue(underlying.writes.isEmpty)
        XCTAssertEqual(underlying.invalidateCount, 1)
    }

    func testRestrictedLinkAbortInvalidatesWithoutWritingAndPublishesFailure() {
        let fixture = makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let underlying = FakeControlPointLink()
        let link = RequestControlOnlyLink(
            underlying: underlying,
            gate: RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt")
        )
        var events: [FTMSControlPointLinkEvent] = []
        link.eventHandler = { events.append($0) }

        link.abort(reason: "Malformed passive packet")

        XCTAssertTrue(underlying.writes.isEmpty)
        XCTAssertEqual(underlying.invalidateCount, 1)
        XCTAssertEqual(events, [.indicationFailed("Malformed passive packet")])
        XCTAssertFalse(RequestControlWriteGate(defaults: fixture.defaults, attemptKey: "attempt").wasConsumed)
    }

    private func makeDefaults(suffix: String = UUID().uuidString) -> (defaults: UserDefaults, suite: String) {
        let suite = "RequestControlDiagnosticTests.\(suffix)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}

@MainActor
private final class FakeControlPointLink: FTMSControlPointLink {
    let supportsWriteWithResponse = true
    let supportsIndications = true
    var eventHandler: ((FTMSControlPointLinkEvent) -> Void)?
    private(set) var enableIndicationsCount = 0
    private(set) var writes: [Data] = []
    private(set) var invalidateCount = 0

    func enableIndications() {
        enableIndicationsCount += 1
    }

    func writeWithResponse(_ data: Data) {
        writes.append(data)
    }

    func invalidate() {
        invalidateCount += 1
    }
}
