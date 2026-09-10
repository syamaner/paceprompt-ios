import Foundation
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
        XCTAssertEqual(model.workoutPlanCapabilities.speed, .unknown)
        XCTAssertEqual(model.workoutPlanCapabilities.inclination, .unknown)
        XCTAssertEqual(
            model.subscription(for: FTMSUUID.treadmillData),
            .inactive(reason: "Not connected")
        )
    }

    func testWorkoutValidationCapabilitiesRequireFeatureSupportAndKnownRanges() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)
        client.send(
            .value(
                uuid: FTMSUUID.fitnessMachineFeature,
                data: Data([0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00]),
                source: .initialRead
            )
        )
        client.send(
            .value(
                uuid: FTMSUUID.supportedSpeedRange,
                data: Data([0x32, 0x00, 0xD0, 0x07, 0x0A, 0x00]),
                source: .initialRead
            )
        )
        client.send(
            .value(
                uuid: FTMSUUID.supportedInclinationRange,
                data: Data([0xE2, 0xFF, 0x96, 0x00, 0x05, 0x00]),
                source: .initialRead
            )
        )

        let capabilities = model.workoutPlanCapabilities

        XCTAssertEqual(
            capabilities.speed,
            .supported(
                .init(
                    minimum: .init(value: decimal("0.5"), unit: .kilometresPerHour),
                    maximum: .init(value: decimal("20"), unit: .kilometresPerHour),
                    increment: .init(value: decimal("0.1"), unit: .kilometresPerHour)
                )
            )
        )
        XCTAssertEqual(
            capabilities.inclination,
            .supported(
                .init(
                    minimum: .init(value: decimal("-3"), unit: .percent),
                    maximum: .init(value: decimal("15"), unit: .percent),
                    increment: .init(value: decimal("0.5"), unit: .percent)
                )
            )
        )
    }

    func testUnsupportedTargetFeatureWinsOverAnAvailableRange() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)
        client.send(
            .value(
                uuid: FTMSUUID.fitnessMachineFeature,
                data: Data(repeating: 0, count: 8),
                source: .initialRead
            )
        )
        client.send(
            .value(
                uuid: FTMSUUID.supportedSpeedRange,
                data: Data([0x32, 0x00, 0xD0, 0x07, 0x0A, 0x00]),
                source: .initialRead
            )
        )

        XCTAssertEqual(model.workoutPlanCapabilities.speed, .unsupported)
        XCTAssertEqual(model.workoutPlanCapabilities.inclination, .unsupported)
    }

    func testMalformedSupportedRangeReachesValidatorAsInvalidNotUnknown() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)
        client.send(
            .value(
                uuid: FTMSUUID.fitnessMachineFeature,
                data: Data([0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00]),
                source: .initialRead
            )
        )
        client.send(
            .value(
                uuid: FTMSUUID.supportedSpeedRange,
                data: Data([0x01]),
                source: .initialRead
            )
        )

        guard case let .supported(range) = model.workoutPlanCapabilities.speed else {
            return XCTFail("Malformed supported range should remain distinct from unknown")
        }
        XCTAssertTrue(range.minimum.value.isNaN)
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
        XCTAssertTrue(report.contains("0x2ACD Treadmill Data: Inactive - No terminal subscription outcome recorded"))
        XCTAssertTrue(report.contains("hard-allows exactly one Request Control 00 write"))
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

    func testIssue51DiagnosticForwardsExplicitActionAndRecordsExactEvidenceLayers() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(
            client: client,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        model.submitRequestControlDiagnosticOnce()
        XCTAssertEqual(client.requestControlSubmitCount, 1)

        client.send(.requestControlDiagnostic(.indicationSubscriptionSucceeded))
        client.send(.requestControlDiagnostic(.readiness(.ready)))
        client.send(.requestControlDiagnostic(.requestSubmitted(Data([0x00]))))
        client.send(.requestControlDiagnostic(.attAccepted))
        client.send(.requestControlDiagnostic(.indication(Data([0x80, 0x00, 0x01]))))
        client.send(.requestControlDiagnostic(.disconnectRequested))
        client.send(.requestControlDiagnostic(.disconnected(nil)))

        XCTAssertEqual(model.requestControlReadiness, .ready)
        XCTAssertTrue(model.diagnosticReport.contains("exact bytes: 00"))
        XCTAssertTrue(model.diagnosticReport.contains("ATT write callback: accepted"))
        XCTAssertTrue(model.diagnosticReport.contains("raw bytes: 80 00 01"))
        XCTAssertTrue(model.diagnosticReport.contains("Explicit disconnect requested"))
        XCTAssertTrue(model.diagnosticReport.contains("CoreBluetooth disconnected"))
        XCTAssertTrue(model.diagnosticReport.contains("without an OS-mediated security or pairing error"))
    }

    func testIssue51ReportIncludesRecoveredProtectedJournalEvidence() {
        let client = FakeFTMSClient()
        client.requestControlDiagnosticJournalRecords = [
            RequestControlDiagnosticJournalEntry(
                sequence: 42,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000051")!,
                kind: .previousSessionRecovered,
                detail: "Recovered through forwardingStarted; final Bluetooth state remains unknown."
            ),
        ]
        let model = TreadmillSetupViewModel(client: client)

        let report = model.diagnosticReport

        XCTAssertTrue(report.contains("Protected durable issue #51 journal (1)"))
        XCTAssertTrue(report.contains("sequence 42 · previousSessionRecovered"))
        XCTAssertTrue(report.contains("final Bluetooth state remains unknown"))
    }

    func testIssue51ReportRetainsEveryPassivePacketBeyondBoundedUIList() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client, diagnosticLimit: 2)

        for status in UInt8(0)...2 {
            client.send(
                .value(
                    uuid: FTMSUUID.trainingStatus,
                    data: Data([0x00, status]),
                    source: .notification
                )
            )
        }

        XCTAssertEqual(model.diagnostics.count, 2)
        XCTAssertTrue(model.diagnosticReport.contains("Complete issue #51 passive packet log (3)"))
        XCTAssertEqual(model.diagnosticReport.components(separatedBy: "0x2AD3 Notification").count - 1, 3)
    }

    func testIssue51ReportPreservesTerminalSubscriptionOutcomesAfterDisconnect() {
        let client = FakeFTMSClient()
        let model = TreadmillSetupViewModel(client: client)
        client.send(.subscription(uuid: FTMSUUID.treadmillData, state: .subscribed))
        client.send(.subscription(uuid: FTMSUUID.trainingStatus, state: .subscribed))
        client.send(.subscription(uuid: FTMSUUID.fitnessMachineStatus, state: .subscribed))

        client.send(.subscription(uuid: FTMSUUID.treadmillData, state: .inactive(reason: "Disconnected")))
        client.send(.subscription(uuid: FTMSUUID.trainingStatus, state: .inactive(reason: "Disconnected")))
        client.send(.subscription(uuid: FTMSUUID.fitnessMachineStatus, state: .inactive(reason: "Disconnected")))

        XCTAssertEqual(model.subscription(for: FTMSUUID.treadmillData), .inactive(reason: "Disconnected"))
        XCTAssertTrue(model.diagnosticReport.contains("0x2ACD Treadmill Data: Subscribed"))
        XCTAssertTrue(model.diagnosticReport.contains("0x2AD3 Training Status: Subscribed"))
        XCTAssertTrue(model.diagnosticReport.contains("0x2ADA Fitness Machine Status: Subscribed"))
    }
}

private func decimal(_ value: String) -> Decimal {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
}

@MainActor
private final class FakeFTMSClient: FTMSClientProtocol {
    weak var delegate: (any FTMSClientDelegate)?
    var requestControlDiagnosticJournalRecords: [RequestControlDiagnosticJournalEntry] = []
    private(set) var startScanCount = 0
    private(set) var stopScanCount = 0
    private(set) var connectedIdentifiers: [UUID] = []
    private(set) var disconnectCount = 0
    private(set) var requestControlSubmitCount = 0

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

    func submitRequestControlDiagnosticOnce() {
        requestControlSubmitCount += 1
    }

    func send(_ event: FTMSClientEvent) {
        delegate?.ftmsClient(self, didReceive: event)
    }
}
