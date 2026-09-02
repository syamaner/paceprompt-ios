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
        XCTAssertEqual(model.diagnostics.count, 0)
        XCTAssertEqual(
            model.subscription(for: FTMSUUID.treadmillData),
            .inactive(reason: "Not connected")
        )
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
                data: Data([0x32, 0x00, 0xD0, 0x07, 0x0A, 0x00]),
                source: .initialRead
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
                data: Data([0x01, 0x02]),
                source: .initialRead
            )
        )

        XCTAssertEqual(model.inclinationRangeText, "Malformed")
        XCTAssertEqual(model.inclinationRange.rawHex, "01 02")
        XCTAssertNotNil(model.inclinationRange.issue)
        XCTAssertNotNil(model.lastError)
    }

    func testSubscriptionSuccessFailureAndUnsupportedStatesRemainDistinct() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)

        client.send(.subscription(uuid: FTMSUUID.treadmillData, state: .subscribed))
        client.send(
            .subscription(
                uuid: FTMSUUID.trainingStatus,
                state: .failed(message: "Synthetic subscription error")
            )
        )
        client.send(
            .subscription(
                uuid: FTMSUUID.fitnessMachineStatus,
                state: .unsupported(reason: "Notify property was not discovered")
            )
        )

        XCTAssertEqual(model.subscription(for: FTMSUUID.treadmillData), .subscribed)
        XCTAssertEqual(
            model.subscription(for: FTMSUUID.trainingStatus),
            .failed(message: "Synthetic subscription error")
        )
        XCTAssertEqual(
            model.subscription(for: FTMSUUID.fitnessMachineStatus),
            .unsupported(reason: "Notify property was not discovered")
        )
        XCTAssertTrue(model.diagnostics.isEmpty)
    }

    func testPacketLogKeepsTimestampRawBytesAndEveryPacket() {
        let client = FakeFTMSClient()
        let timestamp = Date(timeIntervalSince1970: 1_788_379_200.125)
        let model = TreadmillSetupViewModel(client: client, now: { timestamp })

        client.send(.value(uuid: FTMSUUID.treadmillData, data: Data([0x00, 0x00, 0x20, 0x03]), source: .notification))
        client.send(.value(uuid: FTMSUUID.trainingStatus, data: Data([0x00, 0x01]), source: .initialRead))

        XCTAssertEqual(model.diagnostics.count, 2)
        XCTAssertEqual(model.diagnostics.map(\.id), [1, 2])
        XCTAssertEqual(model.diagnostics.map(\.timestamp), [timestamp, timestamp])
        XCTAssertEqual(model.diagnostics[0].rawHex, "00 00 20 03")
        XCTAssertEqual(model.diagnostics[0].kind, .decoded)
        XCTAssertEqual(model.diagnostics.map(\.source), [.notification, .initialRead])
        XCTAssertTrue(model.diagnostics[0].decodedLines.contains("Instantaneous speed: 8.00 km/h"))
    }

    func testPacketLogIsBoundedToNewestPackets() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client, diagnosticLimit: 2)

        client.send(.value(uuid: FTMSUUID.trainingStatus, data: Data([0x00, 0x01]), source: .notification))
        client.send(.value(uuid: FTMSUUID.trainingStatus, data: Data([0x00, 0x02]), source: .notification))
        client.send(.value(uuid: FTMSUUID.trainingStatus, data: Data([0x00, 0x03]), source: .notification))

        XCTAssertEqual(model.diagnostics.map(\.id), [2, 3])
        XCTAssertEqual(model.diagnosticCapacity, 2)
    }

    func testUnknownAndMalformedPacketsRemainDistinctWithRawBytes() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)

        client.send(.value(uuid: FTMSUUID.fitnessMachineStatus, data: Data([0xFE, 0xAA]), source: .notification))
        client.send(.value(uuid: FTMSUUID.treadmillData, data: Data([0x00]), source: .notification))

        XCTAssertEqual(model.diagnostics.map(\.kind), [.unknown, .malformed])
        XCTAssertEqual(model.diagnostics.map(\.rawHex), ["FE AA", "00"])
        XCTAssertNotNil(model.lastError)
    }

    func testDiagnosticReportIncludesExplicitUnavailableStateAndReadOnlyBoundary() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)
        let identifier = UUID(uuidString: "30A9AABC-52F0-46BE-91E5-7EBD907B33A9")!
        client.send(.devices([.init(id: identifier, name: "Synthetic treadmill", rssi: -54)]))

        let report = model.diagnosticReport

        XCTAssertTrue(report.contains("Unavailable - no packets received"))
        XCTAssertTrue(report.contains("Synthetic treadmill - \(identifier.uuidString) - RSSI -54 dBm"))
        XCTAssertTrue(report.contains("0x2ACD Treadmill Data: Inactive - Not connected"))
        XCTAssertTrue(report.contains("No FTMS Control Point 0x2AD9 write was performed"))
    }

    func testValueUpdateErrorDoesNotRewriteSubscriptionOutcome() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)
        client.send(.subscription(uuid: FTMSUUID.treadmillData, state: .subscribed))

        client.send(.valueError(uuid: FTMSUUID.treadmillData, source: .notification, message: "Synthetic packet error"))

        XCTAssertEqual(model.subscription(for: FTMSUUID.treadmillData), .subscribed)
        XCTAssertEqual(model.lastError, "Synthetic packet error")
    }

    func testClearDiagnosticsDoesNotChangeSubscriptionEvidence() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)
        client.send(.subscription(uuid: FTMSUUID.treadmillData, state: .subscribed))
        client.send(.value(uuid: FTMSUUID.treadmillData, data: Data([0x00, 0x00, 0x00, 0x00]), source: .notification))

        model.clearDiagnostics()

        XCTAssertTrue(model.diagnostics.isEmpty)
        XCTAssertEqual(model.subscription(for: FTMSUUID.treadmillData), .subscribed)
    }

    func testTrainingStatusIsBothInitiallyReadAndPassivelySubscribed() {
        XCTAssertTrue(FTMSUUID.initialReads.contains(FTMSUUID.trainingStatus))
        XCTAssertTrue(FTMSUUID.passiveNotifications.contains(FTMSUUID.trainingStatus))
    }

    func testDiagnosticReportDistinguishesInitialReadFromNotification() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)

        client.send(.value(uuid: FTMSUUID.trainingStatus, data: Data([0x00, 0x01]), source: .initialRead))
        client.send(.value(uuid: FTMSUUID.trainingStatus, data: Data([0x00, 0x02]), source: .notification))

        XCTAssertTrue(model.diagnosticReport.contains("0x2AD3 Initial read · Decoded"))
        XCTAssertTrue(model.diagnosticReport.contains("0x2AD3 Notification · Decoded"))
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
