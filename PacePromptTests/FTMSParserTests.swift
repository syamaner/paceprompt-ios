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
        XCTAssertEqual(try LittleEndian.uint24(Data([0x56, 0x34, 0x12]), at: 0), 0x12_3456)
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

    func testTreadmillDataDecodesInstantaneousSpeedAndOptionalFieldsInOrder() throws {
        let packet = try FTMSParser.treadmillData(
            Data([
                0xFE, 0x1F, // Flags: every optional field, without More Data
                0x20, 0x03, // Instantaneous speed: 8.00 km/h
                0x10, 0x03, // Average speed: 7.84 km/h
                0x39, 0x30, 0x00, // Distance: 12,345 m
                0x19, 0x00, // Inclination: 2.5%
                0x0F, 0x00, // Ramp angle: 1.5 degrees
                0x7B, 0x00, // Positive elevation gain: 12.3 m
                0x2D, 0x00, // Negative elevation gain: 4.5 m
                0xE1, 0x00, // Instantaneous pace: 225 s/500 m
                0xF0, 0x00, // Average pace: 240 s/500 m
                0x64, 0x00, // Total energy: 100 kcal
                0xF4, 0x01, // Energy/hour: 500 kcal
                0x08, // Energy/minute: 8 kcal
                0x90, // Heart rate: 144 bpm
                0x08, // Metabolic equivalent: 8 MET
                0x3C, 0x00, // Elapsed: 60 s
                0x78, 0x00, // Remaining: 120 s
                0xE2, 0xFF, // Force on belt: -30 N
                0xFA, 0x00, // Power output: 250 W
            ])
        )

        XCTAssertFalse(packet.moreDataFollows)
        XCTAssertEqual(packet.instantaneousSpeedKilometresPerHour, 8.0)
        XCTAssertEqual(packet.averageSpeedKilometresPerHour, 7.84)
        XCTAssertEqual(packet.totalDistanceMetres, 12_345)
        XCTAssertEqual(packet.inclinationPercent, .value(2.5))
        XCTAssertEqual(packet.rampAngleDegrees, .value(1.5))
        XCTAssertEqual(packet.positiveElevationGainMetres, 12.3)
        XCTAssertEqual(packet.negativeElevationGainMetres, 4.5)
        XCTAssertEqual(packet.instantaneousPaceSecondsPer500Metres, 225)
        XCTAssertEqual(packet.averagePaceSecondsPer500Metres, 240)
        XCTAssertEqual(packet.totalEnergyKilocalories, .value(100))
        XCTAssertEqual(packet.energyPerHourKilocalories, .value(500))
        XCTAssertEqual(packet.energyPerMinuteKilocalories, .value(8))
        XCTAssertEqual(packet.heartRateBeatsPerMinute, 144)
        XCTAssertEqual(packet.metabolicEquivalent, 8)
        XCTAssertEqual(packet.elapsedTimeSeconds, 60)
        XCTAssertEqual(packet.remainingTimeSeconds, 120)
        XCTAssertEqual(packet.forceOnBeltNewtons, .value(-30))
        XCTAssertEqual(packet.powerOutputWatts, .value(250))
    }

    func testTreadmillDataPreservesMoreDataAndUnavailableValues() throws {
        let packet = try FTMSParser.treadmillData(
            Data([
                0x89, 0x10, // More data, incline/ramp, energy, force/power
                0xFF, 0x7F, 0xFF, 0x7F,
                0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                0xFF, 0x7F, 0xFF, 0x7F,
            ])
        )

        XCTAssertTrue(packet.moreDataFollows)
        XCTAssertNil(packet.instantaneousSpeedKilometresPerHour)
        XCTAssertEqual(packet.inclinationPercent, .unavailable)
        XCTAssertEqual(packet.rampAngleDegrees, .unavailable)
        XCTAssertEqual(packet.totalEnergyKilocalories, .unavailable)
        XCTAssertEqual(packet.energyPerHourKilocalories, .unavailable)
        XCTAssertEqual(packet.energyPerMinuteKilocalories, .unavailable)
        XCTAssertEqual(packet.forceOnBeltNewtons, .unavailable)
        XCTAssertEqual(packet.powerOutputWatts, .unavailable)
        XCTAssertTrue(packet.decodedLines.contains("Instantaneous speed: Not included in this packet"))
        XCTAssertTrue(packet.decodedLines.contains("Inclination: Data unavailable"))
    }

    func testTreadmillDataRejectsShortFlaggedFieldsReservedFlagsAndTrailingBytes() {
        XCTAssertThrowsError(try FTMSParser.treadmillData(Data([0x00])))
        XCTAssertThrowsError(try FTMSParser.treadmillData(Data([0x02, 0x00, 0x20, 0x03])))
        XCTAssertThrowsError(try FTMSParser.treadmillData(Data([0x00, 0x20, 0x20, 0x03])))
        XCTAssertThrowsError(try FTMSParser.treadmillData(Data([0x00, 0x00, 0x20, 0x03, 0xAA])))
    }

    func testTrainingStatusDecodesKnownUnknownAndExtendedStringStates() throws {
        let known = try FTMSParser.trainingStatus(Data([0x03, 0x02]) + Data("Warm-up A".utf8))
        XCTAssertEqual(known.state, .known(code: 0x02, name: "Warming up"))
        XCTAssertEqual(known.statusString, "Warm-up A")
        XCTAssertTrue(known.hasExtendedString)

        let unknown = try FTMSParser.trainingStatus(Data([0x00, 0x80]))
        XCTAssertEqual(unknown.state, .unknown(code: 0x80))
        XCTAssertTrue(unknown.state.isUnknown)
    }

    func testTrainingStatusRejectsShortReservedInvalidUTF8AndUnexpectedString() {
        XCTAssertThrowsError(try FTMSParser.trainingStatus(Data([0x00])))
        XCTAssertThrowsError(try FTMSParser.trainingStatus(Data([0x04, 0x01])))
        XCTAssertThrowsError(try FTMSParser.trainingStatus(Data([0x01, 0x01, 0xFF])))
        XCTAssertThrowsError(try FTMSParser.trainingStatus(Data([0x00, 0x01, 0x41])))
    }

    func testFitnessMachineStatusDecodesKnownParameterLayouts() throws {
        XCTAssertEqual(
            try FTMSParser.fitnessMachineStatus(Data([0x05, 0x20, 0x03])),
            .targetSpeedChanged(kilometresPerHour: 8.0)
        )
        XCTAssertEqual(
            try FTMSParser.fitnessMachineStatus(Data([0x0D, 0x39, 0x30, 0x00])),
            .targetedDistanceChanged(metres: 12_345)
        )
        XCTAssertEqual(
            try FTMSParser.fitnessMachineStatus(Data([0x10, 0x0A, 0x00, 0x14, 0x00, 0x1E, 0x00])),
            .targetedHeartRateZoneTimesChanged(zoneCount: 3, seconds: [10, 20, 30])
        )
        XCTAssertEqual(
            try FTMSParser.fitnessMachineStatus(Data([0x12, 0xE8, 0x03, 0xF4, 0x01, 0x64, 0x32])),
            .indoorBikeSimulationChanged(
                windMetresPerSecond: 1.0,
                gradePercent: 5.0,
                rollingResistance: 0.01,
                windResistanceKilogramsPerMetre: 0.5
            )
        )
        XCTAssertEqual(
            try FTMSParser.fitnessMachineStatus(Data([0x07, 0x32])),
            .targetResistanceChanged(value: 5.0)
        )
        XCTAssertEqual(
            try FTMSParser.fitnessMachineStatus(Data([0x07, 0xCE, 0xFF])),
            .targetResistanceChanged(value: -5.0)
        )
    }

    func testFitnessMachineStatusPreservesUnknownOpcodeAndRejectsMalformedKnownPackets() throws {
        XCTAssertEqual(
            try FTMSParser.fitnessMachineStatus(Data([0xFE, 0xAA, 0xBB])),
            .unknown(opcode: 0xFE, parameterHex: "AA BB")
        )
        XCTAssertThrowsError(try FTMSParser.fitnessMachineStatus(Data()))
        XCTAssertThrowsError(try FTMSParser.fitnessMachineStatus(Data([0x05, 0x01])))
        XCTAssertThrowsError(try FTMSParser.fitnessMachineStatus(Data([0x01, 0x00])))
        XCTAssertThrowsError(try FTMSParser.fitnessMachineStatus(Data([0x07])))
    }

    func testFitnessMachineStatusPreservesUnknownNestedValues() throws {
        XCTAssertTrue(
            try FTMSParser.fitnessMachineStatus(Data([0x02, 0x00])).isUnknown
        )
        XCTAssertTrue(
            try FTMSParser.fitnessMachineStatus(Data([0x14, 0x00])).isUnknown
        )
    }
}
