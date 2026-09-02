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
    @Published private(set) var subscriptions: [FTMSSubscription]
    @Published private(set) var diagnostics: [FTMSDiagnostic] = []
    @Published private(set) var lastError: String?

    private let client: any FTMSClientProtocol
    private let now: () -> Date
    private let diagnosticLimit: Int
    private var nextDiagnosticID: UInt64 = 0

    init(
        client: (any FTMSClientProtocol)? = nil,
        now: @escaping () -> Date = { Date() },
        diagnosticLimit: Int = 100
    ) {
        precondition(diagnosticLimit > 0)
        let resolvedClient = client ?? FTMSClient()
        self.client = resolvedClient
        self.now = now
        self.diagnosticLimit = diagnosticLimit
        subscriptions = Self.inactiveSubscriptions(reason: "Not connected")
        resolvedClient.delegate = self
    }

    var isScanning: Bool {
        connectionState == .scanning
    }

    var diagnosticCapacity: Int { diagnosticLimit }

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

    var diagnosticReport: String {
        var lines = [
            "PacePrompt read-only FTMS diagnostics",
            "Connection: \(connectionState.title)",
            "Bluetooth: \(availability.title)",
            "",
            "Discovered FTMS devices",
        ]

        if devices.isEmpty {
            lines.append("Unavailable - no devices discovered")
        } else {
            for device in devices {
                lines.append("\(device.name) - \(device.id.uuidString) - RSSI \(device.rssi) dBm")
            }
        }

        lines.append(contentsOf: [
            "",
            "Discovered characteristics",
        ])

        if characteristics.isEmpty {
            lines.append("Unavailable - no characteristics discovered")
        } else {
            for characteristic in characteristics {
                lines.append("0x\(characteristic.uuid) \(FTMSUUID.name(for: characteristic.uuid)): \(characteristic.properties.joined(separator: ", "))")
            }
        }

        lines.append(contentsOf: ["", "Capability reads"])
        lines.append("0x\(FTMSUUID.fitnessMachineFeature): \(featureFlags.rawHex) - speed target \(speedTargetSettingText), inclination target \(inclinationTargetSettingText)")
        lines.append("0x\(FTMSUUID.supportedSpeedRange): \(speedRange.rawHex) - \(speedRangeText)")
        lines.append("0x\(FTMSUUID.supportedInclinationRange): \(inclinationRange.rawHex) - \(inclinationRangeText)")

        lines.append(contentsOf: ["", "Passive subscriptions"])
        for subscription in subscriptions {
            let detail = subscription.state.detail.map { " - \($0)" } ?? ""
            lines.append("0x\(subscription.uuid) \(FTMSUUID.name(for: subscription.uuid)): \(subscription.state.title)\(detail)")
        }

        lines.append(contentsOf: ["", "Packet log (\(diagnostics.count)/\(diagnosticLimit))"])
        if diagnostics.isEmpty {
            lines.append("Unavailable - no packets received")
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for diagnostic in diagnostics {
                lines.append("[\(formatter.string(from: diagnostic.timestamp))] 0x\(diagnostic.uuid) \(diagnostic.source.title) · \(diagnostic.kind.reportLabel)")
                lines.append("Raw: \(diagnostic.rawHex)")
                lines.append(contentsOf: diagnostic.decodedLines.map { "Decoded: \($0)" })
            }
        }

        lines.append(contentsOf: [
            "",
            "Read-only capture. No FTMS Control Point 0x2AD9 write was performed.",
        ])
        return lines.joined(separator: "\n")
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

    func clearDiagnostics() {
        diagnostics.removeAll()
    }

    func subscription(for uuid: String) -> FTMSSubscriptionState {
        subscriptions.first(where: { $0.uuid == uuid })?.state
            ?? .inactive(reason: "State unavailable")
    }

    private func resetCapabilityResults() {
        featureFlags = .unavailable
        speedRange = .unavailable
        inclinationRange = .unavailable
        characteristics = []
        diagnostics = []
        subscriptions = Self.inactiveSubscriptions(reason: "Not connected")
        nextDiagnosticID = 0
    }

    private func consume(uuid: String, data: Data, source: FTMSValueSource) {
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
                appendDiagnostic(
                    uuid: uuid,
                    source: source,
                    rawHex: rawHex,
                    decoded: .treadmillData(try FTMSParser.treadmillData(data))
                )
            case FTMSUUID.trainingStatus:
                appendDiagnostic(
                    uuid: uuid,
                    source: source,
                    rawHex: rawHex,
                    decoded: .trainingStatus(try FTMSParser.trainingStatus(data))
                )
            case FTMSUUID.fitnessMachineStatus:
                appendDiagnostic(
                    uuid: uuid,
                    source: source,
                    rawHex: rawHex,
                    decoded: .fitnessMachineStatus(try FTMSParser.fitnessMachineStatus(data))
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
                appendDiagnostic(
                    uuid: uuid,
                    source: source,
                    rawHex: rawHex,
                    decodedLines: [reason],
                    kind: .malformed
                )
            }
            lastError = reason
        }
    }

    private func appendDiagnostic(
        uuid: String,
        source: FTMSValueSource,
        rawHex: String,
        decoded: FTMSDecodedPacket
    ) {
        appendDiagnostic(
            uuid: uuid,
            source: source,
            rawHex: rawHex,
            decodedLines: decoded.decodedLines,
            kind: decoded.isUnknown ? .unknown : .decoded
        )
    }

    private func appendDiagnostic(
        uuid: String,
        source: FTMSValueSource,
        rawHex: String,
        decodedLines: [String],
        kind: FTMSDiagnosticKind
    ) {
        nextDiagnosticID += 1
        let diagnostic = FTMSDiagnostic(
            id: nextDiagnosticID,
            timestamp: now(),
            uuid: uuid,
            source: source,
            rawHex: rawHex,
            decodedLines: decodedLines,
            kind: kind
        )
        diagnostics.append(diagnostic)
        if diagnostics.count > diagnosticLimit {
            diagnostics.removeFirst(diagnostics.count - diagnosticLimit)
        }
    }

    private func updateSubscription(uuid: String, state: FTMSSubscriptionState) {
        guard let index = subscriptions.firstIndex(where: { $0.uuid == uuid }) else { return }
        subscriptions[index] = FTMSSubscription(uuid: uuid, state: state)
    }

    private static func inactiveSubscriptions(reason: String) -> [FTMSSubscription] {
        FTMSUUID.passiveNotifications.sorted().map {
            FTMSSubscription(uuid: $0, state: .inactive(reason: reason))
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
        case let .subscription(uuid, state):
            updateSubscription(uuid: uuid, state: state)
        case let .value(uuid, data, source):
            consume(uuid: uuid, data: data, source: source)
        case let .valueError(_, _, message):
            lastError = message
        }
    }
}

private extension FTMSDiagnosticKind {
    var reportLabel: String {
        switch self {
        case .decoded: "Decoded"
        case .unknown: "Unknown protocol value"
        case .malformed: "Malformed"
        }
    }
}
