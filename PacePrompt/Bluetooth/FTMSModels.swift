import Foundation

struct FTMSFeatureFlags: Equatable {
    let machineFeatures: UInt32
    let targetSettingFeatures: UInt32

    var supportsSpeedTargetSetting: Bool {
        targetSettingFeatures & (1 << 0) != 0
    }

    var supportsInclinationTargetSetting: Bool {
        targetSettingFeatures & (1 << 1) != 0
    }
}

struct FTMSSpeedRange: Equatable {
    let minimumKilometresPerHour: Double
    let maximumKilometresPerHour: Double
    let minimumIncrementKilometresPerHour: Double
}

struct FTMSInclinationRange: Equatable {
    let minimumPercent: Double
    let maximumPercent: Double
    let minimumIncrementPercent: Double
}

enum FTMSMeasurement<Value: Equatable>: Equatable {
    case value(Value)
    case unavailable
}

struct FTMSTreadmillData: Equatable {
    let flags: UInt16
    let moreDataFollows: Bool
    let instantaneousSpeedKilometresPerHour: Double?
    let averageSpeedKilometresPerHour: Double?
    let totalDistanceMetres: UInt32?
    let inclinationPercent: FTMSMeasurement<Double>?
    let rampAngleDegrees: FTMSMeasurement<Double>?
    let positiveElevationGainMetres: Double?
    let negativeElevationGainMetres: Double?
    let instantaneousPaceSecondsPer500Metres: UInt16?
    let averagePaceSecondsPer500Metres: UInt16?
    let totalEnergyKilocalories: FTMSMeasurement<UInt16>?
    let energyPerHourKilocalories: FTMSMeasurement<UInt16>?
    let energyPerMinuteKilocalories: FTMSMeasurement<UInt8>?
    let heartRateBeatsPerMinute: UInt8?
    let metabolicEquivalent: UInt8?
    let elapsedTimeSeconds: UInt16?
    let remainingTimeSeconds: UInt16?
    let forceOnBeltNewtons: FTMSMeasurement<Int16>?
    let powerOutputWatts: FTMSMeasurement<Int16>?

    var decodedLines: [String] {
        var lines = [
            String(format: "Flags: 0x%04X", flags),
            "More data follows: \(moreDataFollows ? "Yes" : "No")",
        ]

        if let instantaneousSpeedKilometresPerHour {
            lines.append(String(format: "Instantaneous speed: %.2f km/h", instantaneousSpeedKilometresPerHour))
        } else {
            lines.append("Instantaneous speed: Not included in this packet")
        }
        if let averageSpeedKilometresPerHour {
            lines.append(String(format: "Average speed: %.2f km/h", averageSpeedKilometresPerHour))
        }
        if let totalDistanceMetres {
            lines.append("Total distance: \(totalDistanceMetres) m")
        }
        appendMeasurement(inclinationPercent, label: "Inclination", format: "%.1f%%", to: &lines)
        appendMeasurement(rampAngleDegrees, label: "Ramp angle", format: "%.1f°", to: &lines)
        if let positiveElevationGainMetres {
            lines.append(String(format: "Positive elevation gain: %.1f m", positiveElevationGainMetres))
        }
        if let negativeElevationGainMetres {
            lines.append(String(format: "Negative elevation gain: %.1f m", negativeElevationGainMetres))
        }
        if let instantaneousPaceSecondsPer500Metres {
            lines.append("Instantaneous pace: \(instantaneousPaceSecondsPer500Metres) s/500 m")
        }
        if let averagePaceSecondsPer500Metres {
            lines.append("Average pace: \(averagePaceSecondsPer500Metres) s/500 m")
        }
        appendMeasurement(totalEnergyKilocalories, label: "Total energy", suffix: " kcal", to: &lines)
        appendMeasurement(energyPerHourKilocalories, label: "Energy per hour", suffix: " kcal", to: &lines)
        appendMeasurement(energyPerMinuteKilocalories, label: "Energy per minute", suffix: " kcal", to: &lines)
        if let heartRateBeatsPerMinute {
            lines.append("Heart rate: \(heartRateBeatsPerMinute) bpm")
        }
        if let metabolicEquivalent {
            lines.append("Metabolic equivalent: \(metabolicEquivalent) MET")
        }
        if let elapsedTimeSeconds {
            lines.append("Elapsed time: \(elapsedTimeSeconds) s")
        }
        if let remainingTimeSeconds {
            lines.append("Remaining time: \(remainingTimeSeconds) s")
        }
        appendMeasurement(forceOnBeltNewtons, label: "Force on belt", suffix: " N", to: &lines)
        appendMeasurement(powerOutputWatts, label: "Power output", suffix: " W", to: &lines)
        return lines
    }

    private func appendMeasurement(
        _ measurement: FTMSMeasurement<Double>?,
        label: String,
        format: String,
        to lines: inout [String]
    ) {
        guard let measurement else { return }
        switch measurement {
        case let .value(value):
            lines.append("\(label): \(String(format: format, value))")
        case .unavailable:
            lines.append("\(label): Data unavailable")
        }
    }

    private func appendMeasurement<Value>(
        _ measurement: FTMSMeasurement<Value>?,
        label: String,
        suffix: String,
        to lines: inout [String]
    ) where Value: Equatable {
        guard let measurement else { return }
        switch measurement {
        case let .value(value):
            lines.append("\(label): \(value)\(suffix)")
        case .unavailable:
            lines.append("\(label): Data unavailable")
        }
    }
}

enum FTMSTrainingState: Equatable {
    case known(code: UInt8, name: String)
    case unknown(code: UInt8)

    var text: String {
        switch self {
        case let .known(_, name):
            name
        case let .unknown(code):
            String(format: "Unknown training status 0x%02X", code)
        }
    }

    var isUnknown: Bool {
        guard case .unknown = self else { return false }
        return true
    }
}

struct FTMSTrainingStatus: Equatable {
    let flags: UInt8
    let state: FTMSTrainingState
    let statusString: String?
    let hasExtendedString: Bool

    var decodedLines: [String] {
        var lines = [
            String(format: "Flags: 0x%02X", flags),
            "Training status: \(state.text)",
        ]
        if let statusString {
            lines.append("Status detail: \(statusString.isEmpty ? "Empty string" : statusString)")
        } else {
            lines.append("Status detail: Not included")
        }
        if hasExtendedString {
            lines.append("Extended status string: More text may be available via a separate read")
        }
        return lines
    }
}

enum FTMSFitnessMachineStatus: Equatable {
    case reset
    case stoppedOrPausedByUser(controlInformation: UInt8, meaning: String)
    case stoppedBySafetyKey
    case startedOrResumedByUser
    case targetSpeedChanged(kilometresPerHour: Double)
    case targetInclinationChanged(percent: Double)
    case targetResistanceChanged(value: Double)
    case targetPowerChanged(watts: Int16)
    case targetHeartRateChanged(beatsPerMinute: UInt8)
    case targetedEnergyChanged(kilocalories: UInt16)
    case targetedStepsChanged(UInt16)
    case targetedStridesChanged(UInt16)
    case targetedDistanceChanged(metres: UInt32)
    case targetedTrainingTimeChanged(seconds: UInt16)
    case targetedHeartRateZoneTimesChanged(zoneCount: Int, seconds: [UInt16])
    case indoorBikeSimulationChanged(windMetresPerSecond: Double, gradePercent: Double, rollingResistance: Double, windResistanceKilogramsPerMetre: Double)
    case wheelCircumferenceChanged(millimetres: Double)
    case spinDownStatus(code: UInt8, meaning: String)
    case targetedCadenceChanged(revolutionsPerMinute: Double)
    case controlPermissionLost
    case unknown(opcode: UInt8, parameterHex: String)

    var isUnknown: Bool {
        switch self {
        case let .stoppedOrPausedByUser(controlInformation, _):
            controlInformation != 0x01 && controlInformation != 0x02
        case let .spinDownStatus(code, _):
            !(0x01...0x04).contains(code)
        case .unknown:
            true
        default:
            false
        }
    }

    var decodedLines: [String] {
        switch self {
        case .reset:
            ["Machine status: Reset"]
        case let .stoppedOrPausedByUser(controlInformation, meaning):
            ["Machine status: Stopped or paused by user", String(format: "Control information: %@ (0x%02X)", meaning, controlInformation)]
        case .stoppedBySafetyKey:
            ["Machine status: Stopped by safety key"]
        case .startedOrResumedByUser:
            ["Machine status: Started or resumed by user"]
        case let .targetSpeedChanged(value):
            [String(format: "Machine status: Target speed changed to %.2f km/h", value)]
        case let .targetInclinationChanged(value):
            [String(format: "Machine status: Target inclination changed to %.1f%%", value)]
        case let .targetResistanceChanged(value):
            [String(format: "Machine status: Target resistance changed to %.1f", value)]
        case let .targetPowerChanged(value):
            ["Machine status: Target power changed to \(value) W"]
        case let .targetHeartRateChanged(value):
            ["Machine status: Target heart rate changed to \(value) bpm"]
        case let .targetedEnergyChanged(value):
            ["Machine status: Targeted energy changed to \(value) kcal"]
        case let .targetedStepsChanged(value):
            ["Machine status: Targeted steps changed to \(value)"]
        case let .targetedStridesChanged(value):
            ["Machine status: Targeted strides changed to \(value)"]
        case let .targetedDistanceChanged(value):
            ["Machine status: Targeted distance changed to \(value) m"]
        case let .targetedTrainingTimeChanged(value):
            ["Machine status: Targeted training time changed to \(value) s"]
        case let .targetedHeartRateZoneTimesChanged(zoneCount, seconds):
            ["Machine status: Targeted time in \(zoneCount) heart-rate zones changed", "Zone times: \(seconds.map { "\($0) s" }.joined(separator: ", "))"]
        case let .indoorBikeSimulationChanged(wind, grade, rolling, resistance):
            [
                "Machine status: Indoor-bike simulation parameters changed",
                String(format: "Wind %.3f m/s · grade %.2f%% · rolling resistance %.4f · wind resistance %.2f kg/m", wind, grade, rolling, resistance),
            ]
        case let .wheelCircumferenceChanged(value):
            [String(format: "Machine status: Wheel circumference changed to %.1f mm", value)]
        case let .spinDownStatus(code, meaning):
            [String(format: "Machine status: Spin down %@ (0x%02X)", meaning, code)]
        case let .targetedCadenceChanged(value):
            [String(format: "Machine status: Targeted cadence changed to %.1f rpm", value)]
        case .controlPermissionLost:
            ["Machine status: Control permission lost"]
        case let .unknown(opcode, parameterHex):
            [
                String(format: "Machine status: Unknown opcode 0x%02X", opcode),
                "Parameter: \(parameterHex.isEmpty ? "None" : parameterHex)",
            ]
        }
    }
}

enum FTMSDecodedPacket: Equatable {
    case treadmillData(FTMSTreadmillData)
    case trainingStatus(FTMSTrainingStatus)
    case fitnessMachineStatus(FTMSFitnessMachineStatus)

    var decodedLines: [String] {
        switch self {
        case let .treadmillData(value): value.decodedLines
        case let .trainingStatus(value): value.decodedLines
        case let .fitnessMachineStatus(value): value.decodedLines
        }
    }

    var isUnknown: Bool {
        switch self {
        case .treadmillData:
            false
        case let .trainingStatus(value):
            value.state.isUnknown
        case let .fitnessMachineStatus(value):
            value.isUnknown
        }
    }
}

enum CapabilityRead<Value: Equatable>: Equatable {
    case unavailable
    case value(Value, rawHex: String)
    case malformed(rawHex: String, reason: String)

    var rawHex: String {
        switch self {
        case .unavailable:
            "Unavailable"
        case let .value(_, rawHex), let .malformed(rawHex, _):
            rawHex
        }
    }

    var issue: String? {
        guard case let .malformed(_, reason) = self else { return nil }
        return reason
    }
}

enum BluetoothAvailability: Equatable {
    case notDetermined
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn

    var title: String {
        switch self {
        case .notDetermined: "Checking"
        case .resetting: "Resetting"
        case .unsupported: "Unavailable on this device"
        case .unauthorized: "Permission not granted"
        case .poweredOff: "Bluetooth is off"
        case .poweredOn: "Available"
        }
    }

    var isAvailable: Bool { self == .poweredOn }
}

enum TreadmillConnectionState: Equatable {
    case idle
    case scanning
    case connecting(name: String)
    case discovering(name: String)
    case connected(name: String)
    case disconnected(message: String?)
    case failed(message: String)

    var title: String {
        switch self {
        case .idle: "Not connected"
        case .scanning: "Scanning"
        case let .connecting(name): "Connecting to \(name)"
        case let .discovering(name): "Inspecting \(name)"
        case let .connected(name): "Connected to \(name)"
        case .disconnected: "Disconnected"
        case .failed: "Connection failed"
        }
    }

    var detail: String? {
        switch self {
        case let .disconnected(message): message
        case let .failed(message): message
        default: nil
        }
    }
}

struct FTMSDiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

struct FTMSCharacteristicInfo: Identifiable, Equatable {
    var id: String { uuid }
    let uuid: String
    let properties: [String]
}

enum FTMSSubscriptionState: Equatable {
    case inactive(reason: String)
    case subscribing
    case subscribed
    case unsupported(reason: String)
    case failed(message: String)

    var title: String {
        switch self {
        case .inactive: "Inactive"
        case .subscribing: "Subscribing"
        case .subscribed: "Subscribed"
        case .unsupported: "Not subscribable"
        case .failed: "Subscription failed"
        }
    }

    var detail: String? {
        switch self {
        case let .inactive(reason), let .unsupported(reason): reason
        case let .failed(message): message
        case .subscribing, .subscribed: nil
        }
    }
}

struct FTMSSubscription: Identifiable, Equatable {
    var id: String { uuid }
    let uuid: String
    let state: FTMSSubscriptionState
}

enum FTMSDiagnosticKind: Equatable {
    case decoded
    case unknown
    case malformed
}

enum FTMSValueSource: Equatable {
    case initialRead
    case notification

    var title: String {
        switch self {
        case .initialRead: "Initial read"
        case .notification: "Notification"
        }
    }
}

struct FTMSDiagnostic: Identifiable, Equatable {
    let id: UInt64
    let timestamp: Date
    let uuid: String
    let source: FTMSValueSource
    let rawHex: String
    let decodedLines: [String]
    let kind: FTMSDiagnosticKind
}

enum FTMSClientEvent: Equatable {
    case availability(BluetoothAvailability)
    case connection(TreadmillConnectionState)
    case devices([FTMSDiscoveredDevice])
    case characteristics([FTMSCharacteristicInfo])
    case subscription(uuid: String, state: FTMSSubscriptionState)
    case value(uuid: String, data: Data, source: FTMSValueSource)
    case valueError(uuid: String, source: FTMSValueSource, message: String)
#if DEBUG
    case requestControlDiagnostic(RequestControlDiagnosticEvent)
#endif
}

extension Data {
    var ftmsHex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
