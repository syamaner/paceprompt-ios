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

struct FTMSDiagnostic: Identifiable, Equatable {
    var id: String { uuid }
    let uuid: String
    let rawHex: String
    let decoded: String
    let isMalformed: Bool
}

enum FTMSClientEvent: Equatable {
    case availability(BluetoothAvailability)
    case connection(TreadmillConnectionState)
    case devices([FTMSDiscoveredDevice])
    case characteristics([FTMSCharacteristicInfo])
    case value(uuid: String, data: Data)
    case valueError(uuid: String, message: String)
}

extension Data {
    var ftmsHex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
