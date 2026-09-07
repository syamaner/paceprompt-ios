import Foundation
import XCTest
@testable import PacePrompt

final class HomePresentationTests: XCTestCase {
    func testPoweredOnBluetoothAndIdleTreadmillOnlyMarksBluetoothSuccessful() {
        let presentation = makePresentation(availability: .poweredOn, connection: .idle)

        XCTAssertEqual(presentation.bluetooth.title, "Available")
        XCTAssertTrue(presentation.bluetooth.isSuccessful)
        XCTAssertEqual(presentation.treadmill.title, "Idle")
        XCTAssertFalse(presentation.treadmill.isSuccessful)
        XCTAssertTrue(presentation.treadmill.detail.contains("unknown"))
    }

    func testConnectionWithoutCompleteDecodedEvidenceRemainsInProgress() {
        let presentation = makePresentation(
            availability: .poweredOn,
            connection: .connected(name: "Synthetic treadmill"),
            characteristics: readableCharacteristics()
        )

        XCTAssertEqual(presentation.treadmill.title, "Reading capability")
        XCTAssertEqual(presentation.treadmill.tone, .neutral)
        XCTAssertFalse(presentation.treadmill.isSuccessful)
    }

    func testCompleteCurrentEvidenceProducesOnlyConnectedRangePresentation() {
        let presentation = makePresentation(
            availability: .poweredOn,
            connection: .connected(name: "Synthetic treadmill"),
            characteristics: readableCharacteristics(),
            featureFlags: supportedFeatureFlags(),
            speedRange: knownSpeedRange(),
            inclinationRange: knownInclinationRange()
        )

        XCTAssertEqual(presentation.treadmill.title, "Connected")
        XCTAssertTrue(presentation.treadmill.isSuccessful)
        XCTAssertTrue(presentation.treadmill.detail.contains("read range evidence"))
        XCTAssertTrue(presentation.treadmill.detail.contains("0.8–16.0 km/h"))
        XCTAssertTrue(presentation.treadmill.detail.contains("0.0–12.0%"))
        XCTAssertFalse(presentation.treadmill.detail.localizedCaseInsensitiveContains("control"))
        XCTAssertFalse(presentation.treadmill.detail.localizedCaseInsensitiveContains("ready"))
    }

    func testMalformedUnavailableAndUnsupportedEvidenceNeverPresentAsSuccessfulOrZero() {
        let malformed = makePresentation(
            connection: .connected(name: "Synthetic treadmill"),
            characteristics: readableCharacteristics(),
            featureFlags: supportedFeatureFlags(),
            speedRange: .malformed(rawHex: "01", reason: "Too short")
        )
        let unavailable = makePresentation(
            connection: .connected(name: "Synthetic treadmill"),
            characteristics: readableCharacteristics(),
            lastError: "Synthetic read failure"
        )
        let unsupported = makePresentation(
            connection: .connected(name: "Synthetic treadmill"),
            characteristics: readableCharacteristics(),
            featureFlags: unsupportedFeatureFlags()
        )

        XCTAssertEqual(malformed.treadmill.title, "Capability malformed")
        XCTAssertEqual(unavailable.treadmill.title, "Capability unavailable")
        XCTAssertEqual(unsupported.treadmill.title, "Capability unsupported")
        for state in [malformed, unavailable, unsupported] {
            XCTAssertFalse(state.treadmill.isSuccessful)
            XCTAssertFalse(state.treadmill.detail.contains("0.0"))
        }
    }

    func testDisconnectedStateNeverPresentsPriorCapabilityValuesAsCurrent() {
        let presentation = makePresentation(
            connection: .disconnected(message: "Synthetic disconnect"),
            characteristics: readableCharacteristics(),
            featureFlags: supportedFeatureFlags(),
            speedRange: knownSpeedRange(),
            inclinationRange: knownInclinationRange()
        )

        XCTAssertEqual(presentation.treadmill.title, "Disconnected")
        XCTAssertTrue(presentation.treadmill.detail.contains("stale"))
        XCTAssertFalse(presentation.treadmill.detail.contains("16.0"))
        XCTAssertFalse(presentation.treadmill.isSuccessful)
    }

    func testFailedStateIsActionableButNeverSuccessful() {
        let presentation = makePresentation(
            availability: .poweredOn,
            connection: .failed(message: "Synthetic timeout")
        )

        XCTAssertEqual(presentation.treadmill.title, "Connection failed")
        XCTAssertEqual(presentation.treadmill.action, .retryScan)
        XCTAssertEqual(presentation.treadmill.tone, .failure)
        XCTAssertFalse(presentation.treadmill.isSuccessful)
    }

    func testUnauthorisedAndPoweredOffBluetoothGiveNonRetryGuidance() {
        let unauthorised = makePresentation(availability: .unauthorized)
        let poweredOff = makePresentation(availability: .poweredOff)

        XCTAssertEqual(unauthorised.bluetooth.title, "Not authorised")
        XCTAssertEqual(unauthorised.bluetooth.action, .openSettings)
        XCTAssertTrue(unauthorised.bluetooth.detail.contains("Retrying will not help"))
        XCTAssertEqual(poweredOff.bluetooth.title, "Powered off")
        XCTAssertNil(poweredOff.bluetooth.action)
        XCTAssertTrue(poweredOff.bluetooth.detail.contains("Control Centre or Settings"))
    }

    @MainActor
    func testReadingHomePresentationDoesNotStartScanningOrConnecting() {
        let client = HomePresentationFakeClient()
        let treadmill = TreadmillSetupViewModel(client: client)

        _ = treadmill.homePresentation

        XCTAssertEqual(client.startScanCount, 0)
        XCTAssertEqual(client.connectCount, 0)
    }

    private func makePresentation(
        availability: BluetoothAvailability = .poweredOn,
        connection: TreadmillConnectionState = .idle,
        characteristics: [FTMSCharacteristicInfo] = [],
        featureFlags: CapabilityRead<FTMSFeatureFlags> = .unavailable,
        speedRange: CapabilityRead<FTMSSpeedRange> = .unavailable,
        inclinationRange: CapabilityRead<FTMSInclinationRange> = .unavailable,
        lastError: String? = nil
    ) -> HomePresentation {
        HomePresentation(
            availability: availability,
            connection: connection,
            characteristics: characteristics,
            featureFlags: featureFlags,
            speedRange: speedRange,
            inclinationRange: inclinationRange,
            lastError: lastError
        )
    }

    private func readableCharacteristics() -> [FTMSCharacteristicInfo] {
        [
            .init(uuid: FTMSUUID.fitnessMachineFeature, properties: ["Read"]),
            .init(uuid: FTMSUUID.supportedSpeedRange, properties: ["Read"]),
            .init(uuid: FTMSUUID.supportedInclinationRange, properties: ["Read"]),
        ]
    }

    private func supportedFeatureFlags() -> CapabilityRead<FTMSFeatureFlags> {
        .value(.init(machineFeatures: 0, targetSettingFeatures: 0x03), rawHex: "00 00 00 00 03 00 00 00")
    }

    private func unsupportedFeatureFlags() -> CapabilityRead<FTMSFeatureFlags> {
        .value(.init(machineFeatures: 0, targetSettingFeatures: 0), rawHex: "00 00 00 00 00 00 00 00")
    }

    private func knownSpeedRange() -> CapabilityRead<FTMSSpeedRange> {
        .value(
            .init(
                minimumKilometresPerHour: 0.8,
                maximumKilometresPerHour: 16,
                minimumIncrementKilometresPerHour: 0.1
            ),
            rawHex: "50 00 40 06 0A 00"
        )
    }

    private func knownInclinationRange() -> CapabilityRead<FTMSInclinationRange> {
        .value(
            .init(minimumPercent: 0, maximumPercent: 12, minimumIncrementPercent: 0.5),
            rawHex: "00 00 78 00 05 00"
        )
    }
}

@MainActor
private final class HomePresentationFakeClient: FTMSClientProtocol {
    weak var delegate: (any FTMSClientDelegate)?
    private(set) var startScanCount = 0
    private(set) var connectCount = 0

    func startScan() { startScanCount += 1 }
    func stopScan() {}
    func connect(to identifier: UUID) { connectCount += 1 }
    func disconnect() {}
}
