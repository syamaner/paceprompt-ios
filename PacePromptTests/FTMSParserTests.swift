import XCTest
@testable import PacePrompt

final class FTMSParserTests: XCTestCase {
    func testFitnessMachineFeatureParsesBothLittleEndianFields() throws {
        let data = Data([0x08, 0x04, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00])

        let result = try FTMSParser.fitnessMachineFeature(data)

        XCTAssertEqual(result.machineFeatures, 0x0000_0408)
        XCTAssertEqual(result.targetSettingFeatures, 0x0000_0003)
        XCTAssertTrue(result.supportsSpeedTargetSetting)
        XCTAssertTrue(result.supportsInclinationTargetSetting)
    }

    func testFitnessMachineFeatureRejectsReservedBits() {
        let data = Data([0, 0, 0, 0x80, 0, 0, 0, 0])

        XCTAssertThrowsError(try FTMSParser.fitnessMachineFeature(data)) { error in
            guard case FTMSParseError.reservedBitsSet = error else {
                return XCTFail("Expected reservedBitsSet, received \(error)")
            }
        }
    }

    func testSupportedSpeedRangeUsesHundredthKilometrePerHourResolution() throws {
        let data = Data([0x32, 0x00, 0xD0, 0x07, 0x0A, 0x00])

        let result = try FTMSParser.supportedSpeedRange(data)

        XCTAssertEqual(result.minimumKilometresPerHour, 0.50, accuracy: 0.0001)
        XCTAssertEqual(result.maximumKilometresPerHour, 20.00, accuracy: 0.0001)
        XCTAssertEqual(result.minimumIncrementKilometresPerHour, 0.10, accuracy: 0.0001)
    }

    func testSupportedInclinationRangeUsesSignedTenths() throws {
        let data = Data([0xE2, 0xFF, 0x96, 0x00, 0x05, 0x00])

        let result = try FTMSParser.supportedInclinationRange(data)

        XCTAssertEqual(result.minimumPercent, -3.0, accuracy: 0.0001)
        XCTAssertEqual(result.maximumPercent, 15.0, accuracy: 0.0001)
        XCTAssertEqual(result.minimumIncrementPercent, 0.5, accuracy: 0.0001)
    }

    func testLittleEndianSignedAndUnsignedValues() throws {
        XCTAssertEqual(try LittleEndian.uint16(Data([0x34, 0x12]), at: 0), 0x1234)
        XCTAssertEqual(try LittleEndian.int16(Data([0xD4, 0xFE]), at: 0), -300)
        XCTAssertEqual(
            try LittleEndian.uint32(Data([0x78, 0x56, 0x34, 0x12]), at: 0),
            0x1234_5678
        )
    }

    func testFixedLengthPayloadsRejectShortAndLongValues() {
        XCTAssertThrowsError(try FTMSParser.fitnessMachineFeature(Data(repeating: 0, count: 7)))
        XCTAssertThrowsError(try FTMSParser.supportedSpeedRange(Data(repeating: 0, count: 5)))
        XCTAssertThrowsError(try FTMSParser.supportedInclinationRange(Data(repeating: 0, count: 7)))
    }

    func testUnsupportedCharacteristicIsExplicit() {
        XCTAssertThrowsError(
            try FTMSParser.validateSupportedCharacteristic(FTMSUUID.fitnessMachineControlPoint)
        ) { error in
            XCTAssertEqual(
                error as? FTMSParseError,
                .unsupportedCharacteristic(FTMSUUID.fitnessMachineControlPoint)
            )
        }
    }

    func testKnownPassiveRangeCharacteristicsUseAssignedNames() {
        XCTAssertEqual(
            FTMSUUID.name(for: FTMSUUID.supportedResistanceLevelRange),
            "Supported Resistance Level Range"
        )
        XCTAssertEqual(
            FTMSUUID.name(for: FTMSUUID.supportedHeartRateRange),
            "Supported Heart Rate Range"
        )
        XCTAssertEqual(
            FTMSUUID.name(for: FTMSUUID.supportedPowerRange),
            "Supported Power Range"
        )
    }

    func testTreadmillDataReportsInstantaneousSpeedWithoutControllingMachine() throws {
        let summary = try FTMSParser.treadmillDataSummary(
            Data([0x00, 0x00, 0x20, 0x03])
        )

        XCTAssertEqual(summary, "Flags 0x0000 · instantaneous speed 8.00 km/h")
    }

    func testTrainingAndMachineStatusMalformedPacketsAreRejected() {
        XCTAssertThrowsError(try FTMSParser.trainingStatusSummary(Data([0x00])))
        XCTAssertThrowsError(try FTMSParser.fitnessMachineStatusSummary(Data()))
        XCTAssertThrowsError(try FTMSParser.fitnessMachineStatusSummary(Data([0x05, 0x01])))
    }
}
