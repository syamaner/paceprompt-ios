import Combine
import Foundation

@MainActor
final class TreadmillSetupViewModel: ObservableObject {
    @Published private(set) var availability: BluetoothAvailability = .notDetermined
    @Published private(set) var connectionState: TreadmillConnectionState = .idle
    @Published private(set) var devices: [FTMSDiscoveredDevice] = []
    @Published private(set) var characteristics: [FTMSCharacteristicInfo] = []
    @Published private(set) var featureFlags: CapabilityRead<FTMSFeatureFlags> = .unavailable
    @Published private(set) var speedRange: CapabilityRead<FTMSSpeedRange> = .unavailable
    @Published private(set) var inclinationRange: CapabilityRead<FTMSInclinationRange> = .unavailable
    @Published private(set) var diagnostics: [FTMSDiagnostic] = []
    @Published private(set) var lastError: String?

    private let client: any FTMSClientProtocol

    init(client: (any FTMSClientProtocol)? = nil) {
        let resolvedClient = client ?? FTMSClient()
        self.client = resolvedClient
        resolvedClient.delegate = self
    }

    var isScanning: Bool {
        connectionState == .scanning
    }

    var canScan: Bool {
        availability.isAvailable && !canDisconnect
    }

    var canDisconnect: Bool {
        switch connectionState {
        case .connecting, .discovering, .connected:
            true
        default:
            false
        }
    }

    var speedTargetSettingText: String {
        switch featureFlags {
        case .unavailable:
            "Unavailable"
        case let .value(flags, _):
            flags.supportsSpeedTargetSetting ? "Supported" : "Not supported"
        case .malformed:
            "Malformed"
        }
    }

    var inclinationTargetSettingText: String {
        switch featureFlags {
        case .unavailable:
            "Unavailable"
        case let .value(flags, _):
            flags.supportsInclinationTargetSetting ? "Supported" : "Not supported"
        case .malformed:
            "Malformed"
        }
    }

    var speedRangeText: String {
        switch speedRange {
        case .unavailable:
            "Unavailable"
        case let .value(range, _):
            String(
                format: "%.2f–%.2f km/h · %.2f km/h increments",
                range.minimumKilometresPerHour,
                range.maximumKilometresPerHour,
                range.minimumIncrementKilometresPerHour
            )
        case .malformed:
            "Malformed"
        }
    }

    var inclinationRangeText: String {
        switch inclinationRange {
        case .unavailable:
            "Unavailable"
        case let .value(range, _):
            String(
                format: "%.1f–%.1f%% · %.1f%% increments",
                range.minimumPercent,
                range.maximumPercent,
                range.minimumIncrementPercent
            )
        case .malformed:
            "Malformed"
        }
    }

    func toggleScan() {
        if isScanning {
            client.stopScan()
        } else {
            resetCapabilityResults()
            lastError = nil
            client.startScan()
        }
    }

    func connect(to device: FTMSDiscoveredDevice) {
        lastError = nil
        client.connect(to: device.id)
    }

    func disconnect() {
        client.disconnect()
    }

    private func resetCapabilityResults() {
        featureFlags = .unavailable
        speedRange = .unavailable
        inclinationRange = .unavailable
        characteristics = []
        diagnostics = []
    }

    private func consume(uuid: String, data: Data) {
        let rawHex = data.ftmsHex
        do {
            switch uuid {
            case FTMSUUID.fitnessMachineFeature:
                featureFlags = .value(try FTMSParser.fitnessMachineFeature(data), rawHex: rawHex)
            case FTMSUUID.supportedSpeedRange:
                speedRange = .value(try FTMSParser.supportedSpeedRange(data), rawHex: rawHex)
            case FTMSUUID.supportedInclinationRange:
                inclinationRange = .value(try FTMSParser.supportedInclinationRange(data), rawHex: rawHex)
            case FTMSUUID.treadmillData:
                updateDiagnostic(
                    uuid: uuid,
                    rawHex: rawHex,
                    decoded: try FTMSParser.treadmillDataSummary(data),
                    isMalformed: false
                )
            case FTMSUUID.trainingStatus:
                updateDiagnostic(
                    uuid: uuid,
                    rawHex: rawHex,
                    decoded: try FTMSParser.trainingStatusSummary(data),
                    isMalformed: false
                )
            case FTMSUUID.fitnessMachineStatus:
                updateDiagnostic(
                    uuid: uuid,
                    rawHex: rawHex,
                    decoded: try FTMSParser.fitnessMachineStatusSummary(data),
                    isMalformed: false
                )
            default:
                try FTMSParser.validateSupportedCharacteristic(uuid)
            }
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            switch uuid {
            case FTMSUUID.fitnessMachineFeature:
                featureFlags = .malformed(rawHex: rawHex, reason: reason)
            case FTMSUUID.supportedSpeedRange:
                speedRange = .malformed(rawHex: rawHex, reason: reason)
            case FTMSUUID.supportedInclinationRange:
                inclinationRange = .malformed(rawHex: rawHex, reason: reason)
            default:
                updateDiagnostic(
                    uuid: uuid,
                    rawHex: rawHex,
                    decoded: reason,
                    isMalformed: true
                )
            }
            lastError = reason
        }
    }

    private func updateDiagnostic(
        uuid: String,
        rawHex: String,
        decoded: String,
        isMalformed: Bool
    ) {
        let diagnostic = FTMSDiagnostic(
            uuid: uuid,
            rawHex: rawHex,
            decoded: decoded,
            isMalformed: isMalformed
        )
        if let index = diagnostics.firstIndex(where: { $0.uuid == uuid }) {
            diagnostics[index] = diagnostic
        } else {
            diagnostics.append(diagnostic)
            diagnostics.sort { $0.uuid < $1.uuid }
        }
    }
}

extension TreadmillSetupViewModel: FTMSClientDelegate {
    func ftmsClient(_ client: any FTMSClientProtocol, didReceive event: FTMSClientEvent) {
        switch event {
        case let .availability(value):
            availability = value
        case let .connection(value):
            connectionState = value
            if let detail = value.detail {
                lastError = detail
            }
        case let .devices(value):
            devices = value
        case let .characteristics(value):
            characteristics = value
        case let .value(uuid, data):
            consume(uuid: uuid, data: data)
        case let .valueError(uuid, message):
            lastError = message
            updateDiagnostic(
                uuid: uuid,
                rawHex: "Unavailable",
                decoded: message,
                isMalformed: true
            )
        }
    }
}
