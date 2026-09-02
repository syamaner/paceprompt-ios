import Foundation

enum FTMSParseError: Error, Equatable, LocalizedError {
    case invalidLength(characteristic: String, expected: String, actual: Int)
    case reservedBitsSet(field: String, value: UInt32)
    case unsupportedCharacteristic(String)
    case invalidUTF8(characteristic: String)

    var errorDescription: String? {
        switch self {
        case let .invalidLength(characteristic, expected, actual):
            "\(characteristic) expected \(expected) bytes, received \(actual)."
        case let .reservedBitsSet(field, value):
            "\(field) contains reserved bits: 0x\(String(value, radix: 16, uppercase: true))."
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

    static func treadmillDataSummary(_ data: Data) throws -> String {
        guard data.count >= 2 else {
            throw FTMSParseError.invalidLength(
                characteristic: "Treadmill Data",
                expected: "at least 2",
                actual: data.count
            )
        }
        let flags = try LittleEndian.uint16(data, at: 0)
        if flags & 0x0001 == 0 {
            guard data.count >= 4 else {
                throw FTMSParseError.invalidLength(
                    characteristic: "Treadmill Data with instantaneous speed",
                    expected: "at least 4",
                    actual: data.count
                )
            }
            let speed = Double(try LittleEndian.uint16(data, at: 2)) * 0.01
            return String(format: "Flags 0x%04X · instantaneous speed %.2f km/h", flags, speed)
        }
        return String(format: "Flags 0x%04X · continuation packet; instantaneous speed omitted", flags)
    }

    static func trainingStatusSummary(_ data: Data) throws -> String {
        guard data.count >= 2 else {
            throw FTMSParseError.invalidLength(
                characteristic: "Training Status",
                expected: "at least 2",
                actual: data.count
            )
        }
        let flags = data[0]
        let status = trainingStatusName(data[1])
        guard flags & 0x01 != 0 else { return status }

        let stringData = data.dropFirst(2)
        guard let detail = String(data: stringData, encoding: .utf8) else {
            throw FTMSParseError.invalidUTF8(characteristic: "Training Status")
        }
        return detail.isEmpty ? status : "\(status) · \(detail)"
    }

    static func fitnessMachineStatusSummary(_ data: Data) throws -> String {
        guard let opcode = data.first else {
            throw FTMSParseError.invalidLength(
                characteristic: "Fitness Machine Status",
                expected: "at least 1",
                actual: 0
            )
        }
        switch opcode {
        case 0x01:
            return "Reset"
        case 0x02:
            return "Stopped or paused by user"
        case 0x03:
            return "Stopped by safety key"
        case 0x04:
            return "Started or resumed by user"
        case 0x05:
            guard data.count >= 3 else {
                throw FTMSParseError.invalidLength(
                    characteristic: "Target Speed Changed",
                    expected: "at least 3",
                    actual: data.count
                )
            }
            return String(
                format: "Target speed changed to %.2f km/h",
                Double(try LittleEndian.uint16(data, at: 1)) * 0.01
            )
        case 0x06:
            guard data.count >= 3 else {
                throw FTMSParseError.invalidLength(
                    characteristic: "Target Inclination Changed",
                    expected: "at least 3",
                    actual: data.count
                )
            }
            return String(
                format: "Target inclination changed to %.1f%%",
                Double(try LittleEndian.int16(data, at: 1)) * 0.1
            )
        case 0xFF:
            return "Control permission lost"
        default:
            return String(
                format: "Status opcode 0x%02X · parameter %@",
                opcode,
                Data(data.dropFirst()).ftmsHex
            )
        }
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

    private static func trainingStatusName(_ value: UInt8) -> String {
        switch value {
        case 0x00: "Other"
        case 0x01: "Idle"
        case 0x02: "Warming up"
        case 0x03: "Low intensity interval"
        case 0x04: "High intensity interval"
        case 0x05: "Recovery interval"
        case 0x06: "Isometric"
        case 0x07: "Heart rate control"
        case 0x08: "Fitness test"
        case 0x09: "Speed below control region"
        case 0x0A: "Speed above control region"
        case 0x0B: "Cool down"
        case 0x0C: "Watt control"
        case 0x0D: "Manual mode"
        case 0x0E: "Pre-workout"
        case 0x0F: "Post-workout"
        default: String(format: "Reserved training status 0x%02X", value)
        }
    }
}
