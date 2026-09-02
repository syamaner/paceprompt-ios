import XCTest
@testable import PacePrompt

@MainActor
final class TreadmillPresentationTests: XCTestCase {
    func testCapabilitiesBeginAsExplicitlyUnavailable() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)

        XCTAssertEqual(model.speedTargetSettingText, "Unavailable")
        XCTAssertEqual(model.inclinationTargetSettingText, "Unavailable")
        XCTAssertEqual(model.speedRangeText, "Unavailable")
        XCTAssertEqual(model.inclinationRangeText, "Unavailable")
        XCTAssertEqual(model.speedRange.rawHex, "Unavailable")
    }

    func testScanStartsOnlyAfterPresentationAction() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)

        XCTAssertEqual(client.startScanCount, 0)
        client.send(.availability(.poweredOn))
        model.toggleScan()

        XCTAssertEqual(client.startScanCount, 1)
    }

    func testScanIsUnavailableDuringActiveConnection() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)

        client.send(.availability(.poweredOn))
        client.send(.connection(.connected(name: "Synthetic treadmill")))

        XCTAssertFalse(model.canScan)
        XCTAssertTrue(model.canDisconnect)
    }

    func testValidCapabilityValueUpdatesDecodedAndRawPresentation() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)

        client.send(
            .value(
                uuid: FTMSUUID.supportedSpeedRange,
                data: Data([0x32, 0x00, 0xD0, 0x07, 0x0A, 0x00])
            )
        )

        XCTAssertEqual(model.speedRangeText, "0.50–20.00 km/h · 0.10 km/h increments")
        XCTAssertEqual(model.speedRange.rawHex, "32 00 D0 07 0A 00")
        XCTAssertNil(model.speedRange.issue)
    }

    func testMalformedCapabilityRemainsVisibleWithRawValueAndReason() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)

        client.send(
            .value(
                uuid: FTMSUUID.supportedInclinationRange,
                data: Data([0x01, 0x02])
            )
        )

        XCTAssertEqual(model.inclinationRangeText, "Malformed")
        XCTAssertEqual(model.inclinationRange.rawHex, "01 02")
        XCTAssertNotNil(model.inclinationRange.issue)
        XCTAssertNotNil(model.lastError)
    }
}

@MainActor
private final class FakeFTMSClient: FTMSClientProtocol {
    weak var delegate: (any FTMSClientDelegate)?
    private(set) var startScanCount = 0
    private(set) var stopScanCount = 0
    private(set) var connectedIdentifiers: [UUID] = []
    private(set) var disconnectCount = 0

    func startScan() {
        startScanCount += 1
    }

    func stopScan() {
        stopScanCount += 1
    }

    func connect(to identifier: UUID) {
        connectedIdentifiers.append(identifier)
    }

    func disconnect() {
        disconnectCount += 1
    }

    func send(_ event: FTMSClientEvent) {
        delegate?.ftmsClient(self, didReceive: event)
    }
}
