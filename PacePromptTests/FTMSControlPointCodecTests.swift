import Foundation
import XCTest
@testable import PacePrompt

final class FTMSControlPointCodecTests: XCTestCase {
    private let supported = FTMSControlPointEligibility(
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

    func testRecordsTheReverifiedAdoptedProtocolRevisions() {
        XCTAssertEqual(
            FTMSControlPointCodec.adoptedServiceRevision,
            "Fitness Machine Service 1.0.1 (2024-10-01)"
        )
        XCTAssertEqual(
            FTMSControlPointCodec.adoptedProfileRevision,
            "Fitness Machine Profile 1.0.1 (2024-10-01)"
        )
    }

    func testEncodesOnlyTheReviewedMVPProcedureBytes() throws {
        XCTAssertEqual(try encode(.requestControl), Data([0x00]))
        XCTAssertEqual(try encode(.setTargetSpeed(kilometresPerHour: 4.5)), Data([0x02, 0xC2, 0x01]))
        XCTAssertEqual(try encode(.setTargetInclination(percent: -2.5)), Data([0x03, 0xE7, 0xFF]))
        XCTAssertEqual(try encode(.start), Data([0x07]))
        XCTAssertEqual(try encode(.stop), Data([0x08, 0x01]))
    }

    func testEncodesInclusiveRangeBoundariesAndLittleEndianFields() throws {
        XCTAssertEqual(try encode(.setTargetSpeed(kilometresPerHour: 0.5)), Data([0x02, 0x32, 0x00]))
        XCTAssertEqual(try encode(.setTargetSpeed(kilometresPerHour: 20)), Data([0x02, 0xD0, 0x07]))
        XCTAssertEqual(try encode(.setTargetInclination(percent: -5)), Data([0x03, 0xCE, 0xFF]))
        XCTAssertEqual(try encode(.setTargetInclination(percent: 15)), Data([0x03, 0x96, 0x00]))
    }

    func testParserDecodedRangeValuesRoundTripDespiteBinaryFloatingPointTails() throws {
        let speedRange = try FTMSParser.supportedSpeedRange(
            Data([0x32, 0x00, 0xCF, 0x07, 0x01, 0x00])
        )
        let speedEligibility = FTMSControlPointEligibility(
            features: supported.features,
            speedRange: speedRange,
            inclinationRange: supported.inclinationRange
        )
        XCTAssertEqual(speedRange.maximumKilometresPerHour, 19.990000000000002)
        XCTAssertEqual(
            try FTMSControlPointCodec.encode(
                .setTargetSpeed(kilometresPerHour: speedRange.maximumKilometresPerHour),
                eligibility: speedEligibility
            ),
            Data([0x02, 0xCF, 0x07])
        )

        let inclinationRange = try FTMSParser.supportedInclinationRange(
            Data([0xD5, 0xFE, 0x7F, 0x00, 0x01, 0x00])
        )
        let inclinationEligibility = FTMSControlPointEligibility(
            features: supported.features,
            speedRange: supported.speedRange,
            inclinationRange: inclinationRange
        )
        XCTAssertEqual(inclinationRange.minimumPercent, -29.900000000000002)
        XCTAssertEqual(
            try FTMSControlPointCodec.encode(
                .setTargetInclination(percent: inclinationRange.minimumPercent),
                eligibility: inclinationEligibility
            ),
            Data([0x03, 0xD5, 0xFE])
        )
    }

    func testRejectsTargetsWithoutAdvertisedSupportOrRangeEvidence() {
        let noFeatures = FTMSControlPointEligibility(
            features: FTMSFeatureFlags(machineFeatures: 0, targetSettingFeatures: 0),
            speedRange: supported.speedRange,
            inclinationRange: supported.inclinationRange
        )
        XCTAssertCodecError(.speedTargetUnsupported) {
            try FTMSControlPointCodec.encode(.setTargetSpeed(kilometresPerHour: 4), eligibility: noFeatures)
        }
        XCTAssertCodecError(.inclinationTargetUnsupported) {
            try FTMSControlPointCodec.encode(.setTargetInclination(percent: 2), eligibility: noFeatures)
        }

        let noRanges = FTMSControlPointEligibility(
            features: supported.features,
            speedRange: nil,
            inclinationRange: nil
        )
        XCTAssertCodecError(.missingSpeedRange) {
            try FTMSControlPointCodec.encode(.setTargetSpeed(kilometresPerHour: 4), eligibility: noRanges)
        }
        XCTAssertCodecError(.missingInclinationRange) {
            try FTMSControlPointCodec.encode(.setTargetInclination(percent: 2), eligibility: noRanges)
        }
    }

    func testRejectsNonFiniteOverflowingOutOfRangeAndResolutionMisalignedTargets() {
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertCodecError(.nonFiniteValue) {
                try encode(.setTargetSpeed(kilometresPerHour: invalid))
            }
            XCTAssertCodecError(.nonFiniteValue) {
                try encode(.setTargetInclination(percent: invalid))
            }
        }

        XCTAssertCodecError(.valueOverflow) {
            try encode(.setTargetSpeed(kilometresPerHour: 700))
        }
        XCTAssertCodecError(.valueOverflow) {
            try encode(.setTargetInclination(percent: 4_000))
        }
        XCTAssertCodecError(.valueOutOfRange) {
            try encode(.setTargetSpeed(kilometresPerHour: 0.4))
        }
        XCTAssertCodecError(.valueOutOfRange) {
            try encode(.setTargetInclination(percent: 15.5))
        }
        XCTAssertCodecError(.valueNotRepresentable(resolution: "0.01 km/h")) {
            try encode(.setTargetSpeed(kilometresPerHour: 4.005))
        }
        XCTAssertCodecError(.valueNotRepresentable(resolution: "0.1%")) {
            try encode(.setTargetInclination(percent: 2.05))
        }
    }

    func testRejectsIncrementMisalignmentWithoutRoundingOrClamping() {
        XCTAssertCodecError(.valueNotIncrementAligned) {
            try encode(.setTargetSpeed(kilometresPerHour: 0.55))
        }
        XCTAssertCodecError(.valueNotIncrementAligned) {
            try encode(.setTargetInclination(percent: -4.9))
        }
    }

    func testRejectsMalformedRangeEvidence() {
        let invalidRanges: [(FTMSSpeedRange, FTMSControlPointCodecError)] = [
            (
                FTMSSpeedRange(
                    minimumKilometresPerHour: 5,
                    maximumKilometresPerHour: 4,
                    minimumIncrementKilometresPerHour: 0.1
                ),
                .invalidRange("minimum exceeds maximum")
            ),
            (
                FTMSSpeedRange(
                    minimumKilometresPerHour: 0,
                    maximumKilometresPerHour: 20,
                    minimumIncrementKilometresPerHour: 0
                ),
                .invalidRange("increment overflows the FTMS field")
            ),
            (
                FTMSSpeedRange(
                    minimumKilometresPerHour: .nan,
                    maximumKilometresPerHour: 20,
                    minimumIncrementKilometresPerHour: 0.1
                ),
                .invalidRange("minimum is not finite")
            ),
            (
                FTMSSpeedRange(
                    minimumKilometresPerHour: 0,
                    maximumKilometresPerHour: 20.001,
                    minimumIncrementKilometresPerHour: 0.1
                ),
                .invalidRange("maximum is not aligned to 0.01 km/h")
            ),
        ]

        for (range, expected) in invalidRanges {
            var eligibility = supported
            eligibility = FTMSControlPointEligibility(
                features: eligibility.features,
                speedRange: range,
                inclinationRange: eligibility.inclinationRange
            )
            XCTAssertCodecError(expected) {
                try FTMSControlPointCodec.encode(
                    .setTargetSpeed(kilometresPerHour: 5),
                    eligibility: eligibility
                )
            }
        }
    }

    func testDecodesEveryDefinedResultForEverySupportedRequestOpcode() throws {
        for opcode: UInt8 in [0x00, 0x02, 0x03, 0x07, 0x08] {
            for result in [
                FTMSControlPointResult.success,
                .opcodeNotSupported,
                .invalidParameter,
                .operationFailed,
                .controlNotPermitted,
            ] {
                let bytes = Data([0x80, opcode, result.rawValue])
                XCTAssertEqual(
                    try FTMSControlPointCodec.decodeResponse(bytes),
                    FTMSControlPointResponse(
                        requestOpcode: opcode,
                        result: result,
                        rawBytes: bytes
                    )
                )
            }
        }
    }

    func testRejectsMalformedMismatchedSurfaceReservedAndTrailingResponses() {
        for bytes in [Data(), Data([0x80]), Data([0x80, 0x00]), Data([0x80, 0x00, 0x01, 0x00])] {
            XCTAssertCodecError(.invalidResponseLength(actual: bytes.count)) {
                try FTMSControlPointCodec.decodeResponse(bytes)
            }
        }
        XCTAssertCodecError(.invalidResponseOpcode(0x81)) {
            try FTMSControlPointCodec.decodeResponse(Data([0x81, 0x00, 0x01]))
        }
        for opcode: UInt8 in [0x01, 0x06, 0x09, 0xFF] {
            XCTAssertCodecError(.unsupportedResponseRequestOpcode(opcode)) {
                try FTMSControlPointCodec.decodeResponse(Data([0x80, opcode, 0x01]))
            }
        }
        for result: UInt8 in [0x00, 0x06, 0x7F, 0xFF] {
            XCTAssertCodecError(.reservedResponseResult(result)) {
                try FTMSControlPointCodec.decodeResponse(Data([0x80, 0x00, result]))
            }
        }
    }

    private func encode(_ intent: FitnessMachineControlIntent) throws -> Data {
        try FTMSControlPointCodec.encode(intent, eligibility: supported)
    }

    private func XCTAssertCodecError(
        _ expected: FTMSControlPointCodecError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? FTMSControlPointCodecError, expected, file: file, line: line)
        }
    }
}
