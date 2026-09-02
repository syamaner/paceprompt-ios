import Foundation

enum FTMSParseError: Error, Equatable, LocalizedError {
    case invalidLength(characteristic: String, expected: String, actual: Int)
    case reservedBitsSet(field: String, value: UInt32)
    case trailingBytes(characteristic: String, count: Int)
    case unsupportedCharacteristic(String)
    case invalidUTF8(characteristic: String)

    var errorDescription: String? {
        switch self {
        case let .invalidLength(characteristic, expected, actual):
            "\(characteristic) expected \(expected) bytes, received \(actual)."
        case let .reservedBitsSet(field, value):
            "\(field) contains reserved bits: 0x\(String(value, radix: 16, uppercase: true))."
        case let .trailingBytes(characteristic, count):
            "\(characteristic) contains \(count) unexpected trailing byte\(count == 1 ? "" : "s")."
        case let .unsupportedCharacteristic(uuid):
            "No parser is available for characteristic \(uuid)."
        case let .invalidUTF8(characteristic):
            "\(characteristic) contains an invalid UTF-8 string."
        }
    }
}
enum LittleEndian {
    static func uint16(_ data: Data, at offset: Int) throws -> UInt16 {
        guard data.count >= offset + 2 else {
            throw FTMSParseError.invalidLength(
                characteristic: "Little-endian UInt16",
                expected: "at least \(offset + 2)",
                actual: data.count
            )
        }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    static func int16(_ data: Data, at offset: Int) throws -> Int16 {
        Int16(bitPattern: try uint16(data, at: offset))
    }

    static func uint32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard data.count >= offset + 4 else {
            throw FTMSParseError.invalidLength(
                characteristic: "Little-endian UInt32",
                expected: "at least \(offset + 4)",
                actual: data.count
            )
        }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    static func uint24(_ data: Data, at offset: Int) throws -> UInt32 {
        guard data.count >= offset + 3 else {
            throw FTMSParseError.invalidLength(
                characteristic: "Little-endian UInt24",
                expected: "at least \(offset + 3)",
                actual: data.count
            )
        }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
    }
}

enum FTMSParser {
    private static let definedFeatureBitsMask: UInt32 = 0x0001_FFFF

    static func fitnessMachineFeature(_ data: Data) throws -> FTMSFeatureFlags {
        try requireExactLength(data, 8, characteristic: "Fitness Machine Feature")
        let machine = try LittleEndian.uint32(data, at: 0)
        let targets = try LittleEndian.uint32(data, at: 4)

        let machineReserved = machine & ~definedFeatureBitsMask
        guard machineReserved == 0 else {
            throw FTMSParseError.reservedBitsSet(field: "Fitness Machine Features", value: machineReserved)
        }
        let targetReserved = targets & ~definedFeatureBitsMask
        guard targetReserved == 0 else {
            throw FTMSParseError.reservedBitsSet(field: "Target Setting Features", value: targetReserved)
        }

        return FTMSFeatureFlags(machineFeatures: machine, targetSettingFeatures: targets)
    }

    static func supportedSpeedRange(_ data: Data) throws -> FTMSSpeedRange {
        try requireExactLength(data, 6, characteristic: "Supported Speed Range")
        return FTMSSpeedRange(
            minimumKilometresPerHour: Double(try LittleEndian.uint16(data, at: 0)) * 0.01,
            maximumKilometresPerHour: Double(try LittleEndian.uint16(data, at: 2)) * 0.01,
            minimumIncrementKilometresPerHour: Double(try LittleEndian.uint16(data, at: 4)) * 0.01
        )
    }

    static func supportedInclinationRange(_ data: Data) throws -> FTMSInclinationRange {
        try requireExactLength(data, 6, characteristic: "Supported Inclination Range")
        return FTMSInclinationRange(
            minimumPercent: Double(try LittleEndian.int16(data, at: 0)) * 0.1,
            maximumPercent: Double(try LittleEndian.int16(data, at: 2)) * 0.1,
            minimumIncrementPercent: Double(try LittleEndian.uint16(data, at: 4)) * 0.1
        )
    }

    static func treadmillData(_ data: Data) throws -> FTMSTreadmillData {
        var cursor = PacketCursor(data: data, characteristic: "Treadmill Data")
        let flags = try cursor.uint16(field: "Flags")
        let reserved = flags & 0xE000
        guard reserved == 0 else {
            throw FTMSParseError.reservedBitsSet(field: "Treadmill Data Flags", value: UInt32(reserved))
        }

        let instantaneousSpeed = flags & (1 << 0) == 0
            ? Double(try cursor.uint16(field: "Instantaneous Speed")) * 0.01
            : nil
        let averageSpeed = flags & (1 << 1) != 0
            ? Double(try cursor.uint16(field: "Average Speed")) * 0.01
            : nil
        let totalDistance = flags & (1 << 2) != 0
            ? try cursor.uint24(field: "Total Distance")
            : nil

        var inclination: FTMSMeasurement<Double>?
        var rampAngle: FTMSMeasurement<Double>?
        if flags & (1 << 3) != 0 {
            inclination = unavailableSInt16(
                try cursor.uint16(field: "Inclination"),
                scale: 0.1
            )
            rampAngle = unavailableSInt16(
                try cursor.uint16(field: "Ramp Angle Setting"),
                scale: 0.1
            )
        }

        var positiveElevation: Double?
        var negativeElevation: Double?
        if flags & (1 << 4) != 0 {
            positiveElevation = Double(try cursor.uint16(field: "Positive Elevation Gain")) * 0.1
            negativeElevation = Double(try cursor.uint16(field: "Negative Elevation Gain")) * 0.1
        }

        let instantaneousPace = flags & (1 << 5) != 0
            ? try cursor.uint16(field: "Instantaneous Pace")
            : nil
        let averagePace = flags & (1 << 6) != 0
            ? try cursor.uint16(field: "Average Pace")
            : nil

        var totalEnergy: FTMSMeasurement<UInt16>?
        var energyPerHour: FTMSMeasurement<UInt16>?
        var energyPerMinute: FTMSMeasurement<UInt8>?
        if flags & (1 << 7) != 0 {
            totalEnergy = unavailableUInt16(try cursor.uint16(field: "Total Energy"))
            energyPerHour = unavailableUInt16(try cursor.uint16(field: "Energy Per Hour"))
            let rawPerMinute = try cursor.uint8(field: "Energy Per Minute")
            energyPerMinute = rawPerMinute == .max ? .unavailable : .value(rawPerMinute)
        }

        let heartRate = flags & (1 << 8) != 0
            ? try cursor.uint8(field: "Heart Rate")
            : nil
        let metabolicEquivalent = flags & (1 << 9) != 0
            ? try cursor.uint8(field: "Metabolic Equivalent")
            : nil
        let elapsedTime = flags & (1 << 10) != 0
            ? try cursor.uint16(field: "Elapsed Time")
            : nil
        let remainingTime = flags & (1 << 11) != 0
            ? try cursor.uint16(field: "Remaining Time")
            : nil

        var forceOnBelt: FTMSMeasurement<Int16>?
        var powerOutput: FTMSMeasurement<Int16>?
        if flags & (1 << 12) != 0 {
            forceOnBelt = unavailableRawSInt16(try cursor.uint16(field: "Force On Belt"))
            powerOutput = unavailableRawSInt16(try cursor.uint16(field: "Power Output"))
        }

        try cursor.requireEnd()
        return FTMSTreadmillData(
            flags: flags,
            moreDataFollows: flags & 0x0001 != 0,
            instantaneousSpeedKilometresPerHour: instantaneousSpeed,
            averageSpeedKilometresPerHour: averageSpeed,
            totalDistanceMetres: totalDistance,
            inclinationPercent: inclination,
            rampAngleDegrees: rampAngle,
            positiveElevationGainMetres: positiveElevation,
            negativeElevationGainMetres: negativeElevation,
            instantaneousPaceSecondsPer500Metres: instantaneousPace,
            averagePaceSecondsPer500Metres: averagePace,
            totalEnergyKilocalories: totalEnergy,
            energyPerHourKilocalories: energyPerHour,
            energyPerMinuteKilocalories: energyPerMinute,
            heartRateBeatsPerMinute: heartRate,
            metabolicEquivalent: metabolicEquivalent,
            elapsedTimeSeconds: elapsedTime,
            remainingTimeSeconds: remainingTime,
            forceOnBeltNewtons: forceOnBelt,
            powerOutputWatts: powerOutput
        )
    }

    static func trainingStatus(_ data: Data) throws -> FTMSTrainingStatus {
        var cursor = PacketCursor(data: data, characteristic: "Training Status")
        let flags = try cursor.uint8(field: "Flags")
        let reserved = flags & 0xFC
        guard reserved == 0 else {
            throw FTMSParseError.reservedBitsSet(field: "Training Status Flags", value: UInt32(reserved))
        }
        let stateCode = try cursor.uint8(field: "Training Status")
        let state = trainingState(stateCode)

        var statusString: String?
        if flags & 0x01 != 0 {
            let stringData = cursor.remainingData
            guard let decoded = String(data: stringData, encoding: .utf8) else {
                throw FTMSParseError.invalidUTF8(characteristic: "Training Status")
            }
            statusString = decoded
            cursor.consumeRemaining()
        }
        try cursor.requireEnd()

        return FTMSTrainingStatus(
            flags: flags,
            state: state,
            statusString: statusString,
            hasExtendedString: flags & 0x02 != 0
        )
    }

    static func fitnessMachineStatus(_ data: Data) throws -> FTMSFitnessMachineStatus {
        var cursor = PacketCursor(data: data, characteristic: "Fitness Machine Status")
        let opcode = try cursor.uint8(field: "Op Code")
        let result: FTMSFitnessMachineStatus

        switch opcode {
        case 0x01:
            result = .reset
        case 0x02:
            let information = try cursor.uint8(field: "Control Information")
            let meaning = switch information {
            case 0x01: "Stop"
            case 0x02: "Pause"
            default: "Unknown or reserved"
            }
            result = .stoppedOrPausedByUser(controlInformation: information, meaning: meaning)
        case 0x03:
            result = .stoppedBySafetyKey
        case 0x04:
            result = .startedOrResumedByUser
        case 0x05:
            result = .targetSpeedChanged(
                kilometresPerHour: Double(try cursor.uint16(field: "Target Speed")) * 0.01
            )
        case 0x06:
            result = .targetInclinationChanged(
                percent: Double(try cursor.int16(field: "Target Inclination")) * 0.1
            )
        case 0x07:
            if cursor.remainingCount == 1 {
                result = .targetResistanceChanged(
                    value: Double(try cursor.uint8(field: "Target Resistance")) * 0.1
                )
            } else {
                result = .targetResistanceChanged(
                    value: Double(try cursor.int16(field: "Target Resistance")) * 0.1
                )
            }
        case 0x08:
            result = .targetPowerChanged(watts: try cursor.int16(field: "Target Power"))
        case 0x09:
            result = .targetHeartRateChanged(beatsPerMinute: try cursor.uint8(field: "Target Heart Rate"))
        case 0x0A:
            result = .targetedEnergyChanged(kilocalories: try cursor.uint16(field: "Targeted Energy"))
        case 0x0B:
            result = .targetedStepsChanged(try cursor.uint16(field: "Targeted Steps"))
        case 0x0C:
            result = .targetedStridesChanged(try cursor.uint16(field: "Targeted Strides"))
        case 0x0D:
            result = .targetedDistanceChanged(metres: try cursor.uint24(field: "Targeted Distance"))
        case 0x0E:
            result = .targetedTrainingTimeChanged(seconds: try cursor.uint16(field: "Targeted Training Time"))
        case 0x0F:
            result = .targetedHeartRateZoneTimesChanged(zoneCount: 2, seconds: try zoneTimes(count: 2, cursor: &cursor))
        case 0x10:
            result = .targetedHeartRateZoneTimesChanged(zoneCount: 3, seconds: try zoneTimes(count: 3, cursor: &cursor))
        case 0x11:
            result = .targetedHeartRateZoneTimesChanged(zoneCount: 5, seconds: try zoneTimes(count: 5, cursor: &cursor))
        case 0x12:
            result = .indoorBikeSimulationChanged(
                windMetresPerSecond: Double(try cursor.int16(field: "Wind Speed")) * 0.001,
                gradePercent: Double(try cursor.int16(field: "Grade")) * 0.01,
                rollingResistance: Double(try cursor.uint8(field: "Rolling Resistance")) * 0.0001,
                windResistanceKilogramsPerMetre: Double(try cursor.uint8(field: "Wind Resistance")) * 0.01
            )
        case 0x13:
            result = .wheelCircumferenceChanged(
                millimetres: Double(try cursor.uint16(field: "Wheel Circumference")) * 0.1
            )
        case 0x14:
            let status = try cursor.uint8(field: "Spin Down Status")
            let meaning = switch status {
            case 0x01: "requested"
            case 0x02: "succeeded"
            case 0x03: "error"
            case 0x04: "stop pedalling"
            default: "unknown or reserved"
            }
            result = .spinDownStatus(code: status, meaning: meaning)
        case 0x15:
            result = .targetedCadenceChanged(
                revolutionsPerMinute: Double(try cursor.uint16(field: "Targeted Cadence")) * 0.5
            )
        case 0xFF:
            result = .controlPermissionLost
        default:
            return .unknown(opcode: opcode, parameterHex: cursor.remainingData.ftmsHex)
        }

        try cursor.requireEnd()
        return result
    }

    static func validateSupportedCharacteristic(_ uuid: String) throws {
        let supported = FTMSUUID.readableCapabilities.union(FTMSUUID.passiveNotifications)
        guard supported.contains(uuid.uppercased()) else {
            throw FTMSParseError.unsupportedCharacteristic(uuid.uppercased())
        }
    }

    private static func requireExactLength(
        _ data: Data,
        _ expected: Int,
        characteristic: String
    ) throws {
        guard data.count == expected else {
            throw FTMSParseError.invalidLength(
                characteristic: characteristic,
                expected: "exactly \(expected)",
                actual: data.count
            )
        }
    }

    private static func unavailableSInt16(_ rawValue: UInt16, scale: Double) -> FTMSMeasurement<Double> {
        rawValue == 0x7FFF
            ? .unavailable
            : .value(Double(Int16(bitPattern: rawValue)) * scale)
    }

    private static func unavailableRawSInt16(_ rawValue: UInt16) -> FTMSMeasurement<Int16> {
        rawValue == 0x7FFF
            ? .unavailable
            : .value(Int16(bitPattern: rawValue))
    }

    private static func unavailableUInt16(_ rawValue: UInt16) -> FTMSMeasurement<UInt16> {
        rawValue == .max ? .unavailable : .value(rawValue)
    }

    private static func zoneTimes(count: Int, cursor: inout PacketCursor) throws -> [UInt16] {
        try (0..<count).map { index in
            try cursor.uint16(field: "Heart Rate Zone \(index + 1) Time")
        }
    }

    private static func trainingState(_ value: UInt8) -> FTMSTrainingState {
        switch value {
        case 0x00: .known(code: value, name: "Other")
        case 0x01: .known(code: value, name: "Idle")
        case 0x02: .known(code: value, name: "Warming up")
        case 0x03: .known(code: value, name: "Low intensity interval")
        case 0x04: .known(code: value, name: "High intensity interval")
        case 0x05: .known(code: value, name: "Recovery interval")
        case 0x06: .known(code: value, name: "Isometric")
        case 0x07: .known(code: value, name: "Heart rate control")
        case 0x08: .known(code: value, name: "Fitness test")
        case 0x09: .known(code: value, name: "Speed outside control region - low")
        case 0x0A: .known(code: value, name: "Speed outside control region - high")
        case 0x0B: .known(code: value, name: "Cool down")
        case 0x0C: .known(code: value, name: "Watt control")
        case 0x0D: .known(code: value, name: "Manual mode (quick start)")
        case 0x0E: .known(code: value, name: "Pre-workout")
        case 0x0F: .known(code: value, name: "Post-workout")
        default: .unknown(code: value)
        }
    }
}

private struct PacketCursor {
    let data: Data
    let characteristic: String
    private(set) var offset = 0

    var remainingCount: Int { data.count - offset }
    var remainingData: Data { Data(data.dropFirst(offset)) }

    mutating func uint8(field: String) throws -> UInt8 {
        try require(byteCount: 1, field: field)
        defer { offset += 1 }
        return data[offset]
    }

    mutating func uint16(field: String) throws -> UInt16 {
        try require(byteCount: 2, field: field)
        defer { offset += 2 }
        return try LittleEndian.uint16(data, at: offset)
    }

    mutating func int16(field: String) throws -> Int16 {
        Int16(bitPattern: try uint16(field: field))
    }

    mutating func uint24(field: String) throws -> UInt32 {
        try require(byteCount: 3, field: field)
        defer { offset += 3 }
        return try LittleEndian.uint24(data, at: offset)
    }

    mutating func consumeRemaining() {
        offset = data.count
    }

    func requireEnd() throws {
        guard remainingCount == 0 else {
            throw FTMSParseError.trailingBytes(characteristic: characteristic, count: remainingCount)
        }
    }

    private func require(byteCount: Int, field: String) throws {
        guard remainingCount >= byteCount else {
            throw FTMSParseError.invalidLength(
                characteristic: "\(characteristic) \(field)",
                expected: "at least \(offset + byteCount)",
                actual: data.count
            )
        }
    }
}
