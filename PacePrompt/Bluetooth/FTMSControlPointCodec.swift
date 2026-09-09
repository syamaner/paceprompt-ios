import Foundation

enum FitnessMachineControlIntent: Equatable {
    case requestControl
    case setTargetSpeed(kilometresPerHour: Double)
    case setTargetInclination(percent: Double)
    case start
    case stop

    var opcode: UInt8 {
        switch self {
        case .requestControl: 0x00
        case .setTargetSpeed: 0x02
        case .setTargetInclination: 0x03
        case .start: 0x07
        case .stop: 0x08
        }
    }
}

struct FTMSControlPointEligibility: Equatable {
    let features: FTMSFeatureFlags
    let speedRange: FTMSSpeedRange?
    let inclinationRange: FTMSInclinationRange?
}

enum FTMSControlPointResult: UInt8, Equatable {
    case success = 0x01
    case opcodeNotSupported = 0x02
    case invalidParameter = 0x03
    case operationFailed = 0x04
    case controlNotPermitted = 0x05
}

struct FTMSControlPointResponse: Equatable {
    let requestOpcode: UInt8
    let result: FTMSControlPointResult
    let rawBytes: Data
}

enum FTMSControlPointCodecError: Error, Equatable, LocalizedError {
    case speedTargetUnsupported
    case inclinationTargetUnsupported
    case missingSpeedRange
    case missingInclinationRange
    case invalidRange(String)
    case nonFiniteValue
    case valueNotRepresentable(resolution: String)
    case valueOverflow
    case valueOutOfRange
    case valueNotIncrementAligned
    case invalidResponseLength(actual: Int)
    case invalidResponseOpcode(UInt8)
    case unsupportedResponseRequestOpcode(UInt8)
    case reservedResponseResult(UInt8)

    var errorDescription: String? {
        switch self {
        case .speedTargetUnsupported:
            "Speed target setting is not supported by the current FTMS feature snapshot."
        case .inclinationTargetUnsupported:
            "Inclination target setting is not supported by the current FTMS feature snapshot."
        case .missingSpeedRange:
            "The supported speed range is unavailable."
        case .missingInclinationRange:
            "The supported inclination range is unavailable."
        case let .invalidRange(reason):
            "The supported range is invalid: \(reason)."
        case .nonFiniteValue:
            "The requested value is not finite."
        case let .valueNotRepresentable(resolution):
            "The requested value is not exactly representable at \(resolution) resolution."
        case .valueOverflow:
            "The requested value overflows the FTMS field."
        case .valueOutOfRange:
            "The requested value is outside the supported range."
        case .valueNotIncrementAligned:
            "The requested value is not aligned to the supported increment."
        case let .invalidResponseLength(actual):
            "The FTMS Control Point response must contain exactly 3 bytes; received \(actual)."
        case let .invalidResponseOpcode(opcode):
            String(format: "The FTMS Control Point response opcode is 0x%02X, not 0x80.", opcode)
        case let .unsupportedResponseRequestOpcode(opcode):
            String(format: "The response names unsupported or reserved request opcode 0x%02X.", opcode)
        case let .reservedResponseResult(result):
            String(format: "The response contains reserved result code 0x%02X.", result)
        }
    }
}

enum FTMSControlPointCodec {
    // Bluetooth SIG Fitness Machine Service 1.0.1, revision date 2024-10-01.
    static let adoptedServiceRevision = "Fitness Machine Service 1.0.1 (2024-10-01)"
    static let adoptedProfileRevision = "Fitness Machine Profile 1.0.1 (2024-10-01)"

    static func encode(
        _ intent: FitnessMachineControlIntent,
        eligibility: FTMSControlPointEligibility
    ) throws -> Data {
        switch intent {
        case .requestControl:
            return Data([0x00])
        case let .setTargetSpeed(value):
            guard eligibility.features.supportsSpeedTargetSetting else {
                throw FTMSControlPointCodecError.speedTargetUnsupported
            }
            guard let range = eligibility.speedRange else {
                throw FTMSControlPointCodecError.missingSpeedRange
            }
            let raw = try encodeScaledValue(
                value,
                minimum: range.minimumKilometresPerHour,
                maximum: range.maximumKilometresPerHour,
                increment: range.minimumIncrementKilometresPerHour,
                scale: 100,
                rawMinimum: 0,
                rawMaximum: Int64(UInt16.max),
                resolution: "0.01 km/h"
            )
            let field = UInt16(raw)
            return Data([0x02, UInt8(field & 0x00FF), UInt8(field >> 8)])
        case let .setTargetInclination(value):
            guard eligibility.features.supportsInclinationTargetSetting else {
                throw FTMSControlPointCodecError.inclinationTargetUnsupported
            }
            guard let range = eligibility.inclinationRange else {
                throw FTMSControlPointCodecError.missingInclinationRange
            }
            let raw = try encodeScaledValue(
                value,
                minimum: range.minimumPercent,
                maximum: range.maximumPercent,
                increment: range.minimumIncrementPercent,
                scale: 10,
                rawMinimum: Int64(Int16.min),
                rawMaximum: Int64(Int16.max),
                resolution: "0.1%"
            )
            let field = UInt16(bitPattern: Int16(raw))
            return Data([0x03, UInt8(field & 0x00FF), UInt8(field >> 8)])
        case .start:
            return Data([0x07])
        case .stop:
            return Data([0x08, 0x01])
        }
    }

    static func decodeResponse(_ data: Data) throws -> FTMSControlPointResponse {
        guard data.count == 3 else {
            throw FTMSControlPointCodecError.invalidResponseLength(actual: data.count)
        }
        guard data[0] == 0x80 else {
            throw FTMSControlPointCodecError.invalidResponseOpcode(data[0])
        }
        guard [UInt8(0x00), 0x02, 0x03, 0x07, 0x08].contains(data[1]) else {
            throw FTMSControlPointCodecError.unsupportedResponseRequestOpcode(data[1])
        }
        guard let result = FTMSControlPointResult(rawValue: data[2]) else {
            throw FTMSControlPointCodecError.reservedResponseResult(data[2])
        }
        return FTMSControlPointResponse(
            requestOpcode: data[1],
            result: result,
            rawBytes: data
        )
    }

    private static func encodeScaledValue(
        _ value: Double,
        minimum: Double,
        maximum: Double,
        increment: Double,
        scale: Int,
        rawMinimum: Int64,
        rawMaximum: Int64,
        resolution: String
    ) throws -> Int64 {
        guard value.isFinite else {
            throw FTMSControlPointCodecError.nonFiniteValue
        }

        let minimumRaw = try exactScaledInteger(
            minimum,
            scale: scale,
            rawMinimum: rawMinimum,
            rawMaximum: rawMaximum,
            resolution: resolution,
            rangeField: "minimum"
        )
        let maximumRaw = try exactScaledInteger(
            maximum,
            scale: scale,
            rawMinimum: rawMinimum,
            rawMaximum: rawMaximum,
            resolution: resolution,
            rangeField: "maximum"
        )
        let incrementRaw = try exactScaledInteger(
            increment,
            scale: scale,
            rawMinimum: 1,
            rawMaximum: rawMaximum,
            resolution: resolution,
            rangeField: "increment"
        )
        guard minimumRaw <= maximumRaw else {
            throw FTMSControlPointCodecError.invalidRange("minimum exceeds maximum")
        }

        let valueRaw = try exactScaledInteger(
            value,
            scale: scale,
            rawMinimum: rawMinimum,
            rawMaximum: rawMaximum,
            resolution: resolution,
            rangeField: nil
        )
        guard valueRaw >= minimumRaw, valueRaw <= maximumRaw else {
            throw FTMSControlPointCodecError.valueOutOfRange
        }
        guard (valueRaw - minimumRaw).isMultiple(of: incrementRaw) else {
            throw FTMSControlPointCodecError.valueNotIncrementAligned
        }
        return valueRaw
    }

    private static func exactScaledInteger(
        _ value: Double,
        scale: Int,
        rawMinimum: Int64,
        rawMaximum: Int64,
        resolution: String,
        rangeField: String?
    ) throws -> Int64 {
        guard value.isFinite else {
            if let rangeField {
                throw FTMSControlPointCodecError.invalidRange("\(rangeField) is not finite")
            }
            throw FTMSControlPointCodecError.nonFiniteValue
        }
        guard var decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else {
            if let rangeField {
                throw FTMSControlPointCodecError.invalidRange("\(rangeField) is not representable")
            }
            throw FTMSControlPointCodecError.valueOverflow
        }
        decimal *= Decimal(scale)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, 0, .plain)
        guard decimal == rounded else {
            if let rangeField {
                throw FTMSControlPointCodecError.invalidRange("\(rangeField) is not aligned to \(resolution)")
            }
            throw FTMSControlPointCodecError.valueNotRepresentable(resolution: resolution)
        }
        let lower = Decimal(rawMinimum)
        let upper = Decimal(rawMaximum)
        guard rounded >= lower, rounded <= upper else {
            if let rangeField {
                throw FTMSControlPointCodecError.invalidRange("\(rangeField) overflows the FTMS field")
            }
            throw FTMSControlPointCodecError.valueOverflow
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
