import Combine
import Foundation
#if DEBUG
import UIKit
#endif

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
#if DEBUG
    @Published private(set) var requestControlReadiness: RequestControlDiagnosticReadiness = .awaitingConnection
    @Published private(set) var requestControlDiagnostics: [RequestControlDiagnosticRecord] = []
    private var requestControlPassiveDiagnostics: [FTMSDiagnostic] = []
    private var requestControlPassiveSubscriptionOutcomes: [String: FTMSSubscriptionState] = [:]
#endif

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

    var homePresentation: HomePresentation {
        HomePresentation(
            availability: availability,
            connection: connectionState,
            characteristics: characteristics,
            featureFlags: featureFlags,
            speedRange: speedRange,
            inclinationRange: inclinationRange,
            lastError: lastError
        )
    }

    var workoutPlanCapabilities: WorkoutPlanCapabilities {
        WorkoutPlanCapabilities(
            speed: Self.speedCapability(featureFlags: featureFlags, range: speedRange),
            inclination: Self.inclinationCapability(
                featureFlags: featureFlags,
                range: inclinationRange
            )
        )
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

    var diagnosticReport: String {
#if DEBUG
        var lines = [
            "PacePrompt issue #51 Request Control diagnostic",
            "Equipment: Reebok FR30z (operator identified)",
            "Treadmill dongle/firmware: unavailable from the current FTMS-only diagnostic",
            "Central: \(UIDevice.current.model) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · built-in Bluetooth",
            "Security/pairing: \(requestControlSecurityPairingSummary)",
            "Connection: \(connectionState.title)",
            "Bluetooth: \(availability.title)",
            "",
            "Discovered FTMS devices",
        ]
#else
        var lines = [
            "PacePrompt read-only FTMS diagnostics",
            "Connection: \(connectionState.title)",
            "Bluetooth: \(availability.title)",
            "",
            "Discovered FTMS devices",
        ]
#endif

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
#if DEBUG
        let reportedSubscriptions = FTMSUUID.passiveNotifications.sorted().map { uuid in
            FTMSSubscription(
                uuid: uuid,
                state: requestControlPassiveSubscriptionOutcomes[uuid]
                    ?? .inactive(reason: "No terminal subscription outcome recorded")
            )
        }
#else
        let reportedSubscriptions = subscriptions
#endif
        for subscription in reportedSubscriptions {
            let detail = subscription.state.detail.map { " - \($0)" } ?? ""
            lines.append("0x\(subscription.uuid) \(FTMSUUID.name(for: subscription.uuid)): \(subscription.state.title)\(detail)")
        }

#if DEBUG
        let reportedDiagnostics = requestControlPassiveDiagnostics
        lines.append(contentsOf: ["", "Complete issue #51 passive packet log (\(reportedDiagnostics.count))"])
#else
        let reportedDiagnostics = diagnostics
        lines.append(contentsOf: ["", "Packet log (\(reportedDiagnostics.count)/\(diagnosticLimit))"])
#endif
        if reportedDiagnostics.isEmpty {
            lines.append("Unavailable - no packets received")
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for diagnostic in reportedDiagnostics {
                lines.append("[\(formatter.string(from: diagnostic.timestamp))] 0x\(diagnostic.uuid) \(diagnostic.source.title) · \(diagnostic.kind.reportLabel)")
                lines.append("Raw: \(diagnostic.rawHex)")
                lines.append(contentsOf: diagnostic.decodedLines.map { "Decoded: \($0)" })
            }
        }

#if DEBUG
        lines.append(contentsOf: ["", "Issue #51 Control Point log"])
        if requestControlDiagnostics.isEmpty {
            lines.append("Unavailable - no Control Point diagnostic events recorded")
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for record in requestControlDiagnostics {
                lines.append("[\(formatter.string(from: record.timestamp))] \(record.event.reportLine)")
            }
        }
        lines.append(contentsOf: [
            "",
            "Debug-only issue #51 build. Its Control Point path hard-allows exactly one Request Control 00 write and no other command.",
        ])
#else
        lines.append(contentsOf: [
            "",
            "Read-only capture. No FTMS Control Point 0x2AD9 write was performed.",
        ])
#endif
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

#if DEBUG
    func submitRequestControlDiagnosticOnce() {
        client.submitRequestControlDiagnosticOnce()
    }
#endif

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
#if DEBUG
        requestControlPassiveDiagnostics = []
        requestControlPassiveSubscriptionOutcomes = [:]
#endif
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
#if DEBUG
        // The ordinary UI list stays bounded, but the short, explicitly
        // supervised issue #51 session retains every passive packet for its
        // terminal raw report.
        requestControlPassiveDiagnostics.append(diagnostic)
#endif
        diagnostics.append(diagnostic)
        if diagnostics.count > diagnosticLimit {
            diagnostics.removeFirst(diagnostics.count - diagnosticLimit)
        }
    }

    private func updateSubscription(uuid: String, state: FTMSSubscriptionState) {
        guard let index = subscriptions.firstIndex(where: { $0.uuid == uuid }) else { return }
        subscriptions[index] = FTMSSubscription(uuid: uuid, state: state)
#if DEBUG
        switch state {
        case .subscribed, .unsupported, .failed:
            requestControlPassiveSubscriptionOutcomes[uuid] = state
        case .inactive, .subscribing:
            break
        }
#endif
    }

    private static func inactiveSubscriptions(reason: String) -> [FTMSSubscription] {
        FTMSUUID.passiveNotifications.sorted().map {
            FTMSSubscription(uuid: $0, state: .inactive(reason: reason))
        }
    }

    private static func speedCapability(
        featureFlags: CapabilityRead<FTMSFeatureFlags>,
        range: CapabilityRead<FTMSSpeedRange>
    ) -> WorkoutTargetCapability<WorkoutSpeedRange> {
        switch featureFlags {
        case .unavailable, .malformed:
            return .unknown
        case let .value(flags, _):
            guard flags.supportsSpeedTargetSetting else { return .unsupported }
        }

        switch range {
        case .unavailable:
            return .unknown
        case .malformed:
            return .supported(
                WorkoutSpeedRange(
                    minimum: .init(value: .nan, unit: .kilometresPerHour),
                    maximum: .init(value: .nan, unit: .kilometresPerHour),
                    increment: .init(value: .nan, unit: .kilometresPerHour)
                )
            )
        case let .value(value, _):
            return .supported(
                WorkoutSpeedRange(
                    minimum: .init(value: decimal(value.minimumKilometresPerHour), unit: .kilometresPerHour),
                    maximum: .init(value: decimal(value.maximumKilometresPerHour), unit: .kilometresPerHour),
                    increment: .init(value: decimal(value.minimumIncrementKilometresPerHour), unit: .kilometresPerHour)
                )
            )
        }
    }

    private static func inclinationCapability(
        featureFlags: CapabilityRead<FTMSFeatureFlags>,
        range: CapabilityRead<FTMSInclinationRange>
    ) -> WorkoutTargetCapability<WorkoutInclinationRange> {
        switch featureFlags {
        case .unavailable, .malformed:
            return .unknown
        case let .value(flags, _):
            guard flags.supportsInclinationTargetSetting else { return .unsupported }
        }

        switch range {
        case .unavailable:
            return .unknown
        case .malformed:
            return .supported(
                WorkoutInclinationRange(
                    minimum: .init(value: .nan, unit: .percent),
                    maximum: .init(value: .nan, unit: .percent),
                    increment: .init(value: .nan, unit: .percent)
                )
            )
        case let .value(value, _):
            return .supported(
                WorkoutInclinationRange(
                    minimum: .init(value: decimal(value.minimumPercent), unit: .percent),
                    maximum: .init(value: decimal(value.maximumPercent), unit: .percent),
                    increment: .init(value: decimal(value.minimumIncrementPercent), unit: .percent)
                )
            )
        }
    }

    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? .nan
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
#if DEBUG
        case let .requestControlDiagnostic(event):
            consumeRequestControlDiagnostic(event)
#endif
        }
    }
}

#if DEBUG
private extension TreadmillSetupViewModel {
    var requestControlSecurityPairingSummary: String {
        for record in requestControlDiagnostics.reversed() {
            switch record.event {
            case .indicationSubscriptionSucceeded:
                return "CoreBluetooth enabled the security-restricted Control Point indication subscription without an OS-mediated security or pairing error; negotiated LE security details are not exposed"
            case let .indicationSubscriptionFailed(message):
                return "failed while enabling the Control Point indication subscription - \(message)"
            default:
                continue
            }
        }
        return "not yet observed"
    }

    func consumeRequestControlDiagnostic(_ event: RequestControlDiagnosticEvent) {
        if case let .readiness(readiness) = event {
            requestControlReadiness = readiness
        }
        nextDiagnosticID += 1
        let record = RequestControlDiagnosticRecord(
            id: nextDiagnosticID,
            timestamp: now(),
            event: event
        )
        requestControlDiagnostics.append(record)
        if requestControlDiagnostics.count > diagnosticLimit {
            requestControlDiagnostics.removeFirst(requestControlDiagnostics.count - diagnosticLimit)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        print("PACEPROMPT_ISSUE51 [\(formatter.string(from: record.timestamp))] \(event.reportLine)")

        if case .disconnected = event {
            print("PACEPROMPT_ISSUE51_REPORT_BEGIN")
            print(diagnosticReport)
            print("PACEPROMPT_ISSUE51_REPORT_END")
        }
    }
}
#endif

private extension FTMSDiagnosticKind {
    var reportLabel: String {
        switch self {
        case .decoded: "Decoded"
        case .unknown: "Unknown protocol value"
        case .malformed: "Malformed"
        }
    }
}
