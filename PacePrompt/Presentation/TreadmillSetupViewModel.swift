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
    @Published private(set) var captureMarkers: [FTMSCaptureMarker] = []
    @Published private(set) var applicationActivity: FTMSApplicationActivity = .unknown
    @Published private(set) var lastError: String?

    private let client: any FTMSClientProtocol
    private let now: () -> Date
    private let monotonicNow: () -> TimeInterval
    private let diagnosticLimit: Int
    private let captureDiagnosticLimit: Int
    private var captureDiagnostics: [FTMSDiagnostic] = []
    private var droppedCaptureDiagnosticCount = 0
    private var terminalPassiveSubscriptionOutcomes: [String: FTMSSubscriptionState] = [:]
    private var captureStartedAt: Date
    private var captureStartedMonotonic: TimeInterval
    private var lastTreadmillNotificationMonotonic: TimeInterval?
    private var nextDiagnosticID: UInt64 = 0
    private var nextCaptureMarkerID: UInt64 = 0

    init(
        client: (any FTMSClientProtocol)? = nil,
        now: @escaping () -> Date = { Date() },
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        diagnosticLimit: Int = 100,
        captureDiagnosticLimit: Int = 10_000
    ) {
        precondition(diagnosticLimit > 0)
        precondition(captureDiagnosticLimit >= diagnosticLimit)
        let resolvedClient = client ?? FTMSClient()
        self.client = resolvedClient
        self.now = now
        self.monotonicNow = monotonicNow
        self.diagnosticLimit = diagnosticLimit
        self.captureDiagnosticLimit = captureDiagnosticLimit
        captureStartedAt = now()
        captureStartedMonotonic = monotonicNow()
        subscriptions = Self.inactiveSubscriptions(reason: "Not connected")
        appendCaptureMarker(.captureStarted, timestamp: captureStartedAt, monotonic: captureStartedMonotonic)
        resolvedClient.delegate = self
    }

    var isScanning: Bool {
        connectionState == .scanning
    }

    var diagnosticCapacity: Int { diagnosticLimit }

    var captureDiagnosticCapacity: Int { captureDiagnosticLimit }

    var capturedDiagnosticCount: Int { captureDiagnostics.count }

    var droppedCaptureDiagnostics: Int { droppedCaptureDiagnosticCount }

    var canRecordOperatorObservation: Bool {
        guard case .connected = connectionState else { return false }
        return true
    }

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

    var treadmillDataFreshnessReport: String {
        let generatedAt = now()
        let generatedMonotonic = monotonicNow()
        let elapsed = max(0, generatedMonotonic - captureStartedMonotonic)
        let treadmillPackets = captureDiagnostics.filter { $0.uuid == FTMSUUID.treadmillData }
        let treadmillNotifications = treadmillPackets.filter { $0.source == .notification }
        let malformedTreadmillNotifications = treadmillNotifications.filter { $0.kind == .malformed }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines = [
            "PacePrompt issue #52 read-only Treadmill Data capture",
            "Capture started: \(formatter.string(from: captureStartedAt))",
            "Report generated: \(formatter.string(from: generatedAt)) (+\(Self.seconds(elapsed)) s monotonic)",
            "Application state at report generation: \(applicationActivity.title)",
            "Policy state: measurement only; no freshness window or target-observation deadline has been adopted",
            "Evidence boundary: packet silence and the last sample are not proof of current treadmill state or a stop",
            "Build boundary: no FTMS Control Point write path is compiled in any configuration",
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

        lines.append(contentsOf: ["", "Passive subscription outcomes"])
        for uuid in FTMSUUID.passiveNotifications.sorted() {
            let state = terminalPassiveSubscriptionOutcomes[uuid]
                ?? subscriptions.first(where: { $0.uuid == uuid })?.state
                ?? .inactive(reason: "No terminal subscription outcome recorded")
            let detail = state.detail.map { " - \($0)" } ?? ""
            lines.append("0x\(uuid) \(FTMSUUID.name(for: uuid)): \(state.title)\(detail)")
        }

        lines.append(contentsOf: [
            "",
            "Treadmill Data delivery summary",
            "0x2ACD packets: \(treadmillPackets.count) total; \(treadmillNotifications.count) notifications; \(malformedTreadmillNotifications.count) malformed notifications",
        ])
        if let first = treadmillNotifications.first, let last = treadmillNotifications.last {
            lines.append("First 0x2ACD notification: +\(Self.seconds(first.captureOffsetSeconds)) s")
            lines.append("Last 0x2ACD notification: +\(Self.seconds(last.captureOffsetSeconds)) s")
            let silence = max(0, generatedMonotonic - captureStartedMonotonic - last.captureOffsetSeconds)
            lines.append("Measured silence since last 0x2ACD notification at report generation: \(Self.seconds(silence)) s; this is not machine-state evidence")
        } else {
            lines.append("No 0x2ACD notification was received; packet silence is not machine-state evidence")
        }

        lines.append(contentsOf: ["", "Capture timeline markers (\(captureMarkers.count))"])
        for marker in captureMarkers {
            lines.append(
                "[\(formatter.string(from: marker.timestamp))] [+\(Self.seconds(marker.captureOffsetSeconds)) s] \(marker.kind.reportLine)"
            )
        }

        lines.append(contentsOf: [
            "",
            "Complete passive packet capture (\(captureDiagnostics.count)/\(captureDiagnosticLimit); dropped \(droppedCaptureDiagnosticCount))",
        ])
        if droppedCaptureDiagnosticCount > 0 {
            lines.append("INCOMPLETE CAPTURE - the in-memory safety limit was reached; do not use this report to ratify timing")
        }
        if captureDiagnostics.isEmpty {
            lines.append("Unavailable - no packets received")
        } else {
            for diagnostic in captureDiagnostics {
                var timing = "+\(Self.seconds(diagnostic.captureOffsetSeconds)) s"
                if diagnostic.uuid == FTMSUUID.treadmillData, diagnostic.source == .notification {
                    if let interval = diagnostic.intervalSincePreviousTreadmillNotificationSeconds {
                        timing += "; interval \(Self.seconds(interval)) s from prior 0x2ACD notification"
                    } else {
                        timing += "; first 0x2ACD notification"
                    }
                }
                lines.append("[\(formatter.string(from: diagnostic.timestamp))] [\(timing)] 0x\(diagnostic.uuid) \(diagnostic.source.title) · \(diagnostic.kind.reportLabel)")
                lines.append("Raw: \(diagnostic.rawHex)")
                lines.append(contentsOf: diagnostic.decodedLines.map { "Decoded: \($0)" })
            }
        }

        lines.append(contentsOf: [
            "",
            "Operator markers record only the operator's button press and description; they are not protocol or sensor evidence.",
            "Read-only capture. No FTMS Control Point 0x2AD9 write path is available in any build configuration.",
        ])
        return lines.joined(separator: "\n")
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
        let reportedSubscriptions = FTMSUUID.passiveNotifications.sorted().map { uuid in
            FTMSSubscription(
                uuid: uuid,
                state: terminalPassiveSubscriptionOutcomes[uuid]
                    ?? .inactive(reason: "No terminal subscription outcome recorded")
            )
        }
        for subscription in reportedSubscriptions {
            let detail = subscription.state.detail.map { " - \($0)" } ?? ""
            lines.append("0x\(subscription.uuid) \(FTMSUUID.name(for: subscription.uuid)): \(subscription.state.title)\(detail)")
        }

        let reportedDiagnostics = captureDiagnostics
        lines.append(contentsOf: ["", "Packet log (\(reportedDiagnostics.count)/\(captureDiagnosticLimit); dropped \(droppedCaptureDiagnosticCount))"])
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
        let durableRecords = client.requestControlDiagnosticJournalRecords
        lines.append(contentsOf: ["", "Protected durable issue #51 journal (\(durableRecords.count))"])
        if durableRecords.isEmpty {
            lines.append("Unavailable - protected journal could not be loaded")
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for record in durableRecords {
                lines.append(
                    "[\(formatter.string(from: record.timestamp))] sequence \(record.sequence) · \(record.kind.rawValue) · \(record.detail)"
                )
            }
        }

#endif
        lines.append(contentsOf: [
            "",
            "Read-only capture. No FTMS Control Point 0x2AD9 write path is compiled in any build configuration.",
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
        resetCaptureEvidence()
    }

    func recordOperatorObservation(_ observation: FTMSOperatorObservation) {
        guard canRecordOperatorObservation else { return }
        appendCaptureMarker(.operatorObservation(observation))
    }

    func setApplicationActivity(_ activity: FTMSApplicationActivity) {
        guard applicationActivity != activity else { return }
        applicationActivity = activity
        appendCaptureMarker(.applicationActivity(activity))
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
        terminalPassiveSubscriptionOutcomes = [:]
        subscriptions = Self.inactiveSubscriptions(reason: "Not connected")
        resetCaptureEvidence()
    }

    private func resetCaptureEvidence() {
        diagnostics = []
        captureDiagnostics = []
        droppedCaptureDiagnosticCount = 0
        let startedAt = now()
        let startedMonotonic = monotonicNow()
        captureStartedAt = startedAt
        captureStartedMonotonic = startedMonotonic
        lastTreadmillNotificationMonotonic = nil
        nextDiagnosticID = 0
        nextCaptureMarkerID = 0
        captureMarkers = []
        appendCaptureMarker(.captureStarted, timestamp: startedAt, monotonic: startedMonotonic)
        if applicationActivity != .unknown {
            appendCaptureMarker(
                .applicationActivity(applicationActivity),
                timestamp: startedAt,
                monotonic: startedMonotonic
            )
        }
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
        let timestamp = now()
        let monotonic = monotonicNow()
        let captureOffset = max(0, monotonic - captureStartedMonotonic)
        let treadmillInterval: TimeInterval?
        if uuid == FTMSUUID.treadmillData, source == .notification {
            treadmillInterval = lastTreadmillNotificationMonotonic.map { max(0, monotonic - $0) }
            lastTreadmillNotificationMonotonic = monotonic
        } else {
            treadmillInterval = nil
        }
        nextDiagnosticID += 1
        let diagnostic = FTMSDiagnostic(
            id: nextDiagnosticID,
            timestamp: timestamp,
            captureOffsetSeconds: captureOffset,
            intervalSincePreviousTreadmillNotificationSeconds: treadmillInterval,
            uuid: uuid,
            source: source,
            rawHex: rawHex,
            decodedLines: decodedLines,
            kind: kind
        )
        if captureDiagnostics.count < captureDiagnosticLimit {
            captureDiagnostics.append(diagnostic)
        } else {
            droppedCaptureDiagnosticCount += 1
        }
        diagnostics.append(diagnostic)
        if diagnostics.count > diagnosticLimit {
            diagnostics.removeFirst(diagnostics.count - diagnosticLimit)
        }
    }

    private func updateSubscription(uuid: String, state: FTMSSubscriptionState) {
        guard let index = subscriptions.firstIndex(where: { $0.uuid == uuid }) else { return }
        subscriptions[index] = FTMSSubscription(uuid: uuid, state: state)
        switch state {
        case .subscribed, .unsupported, .failed:
            terminalPassiveSubscriptionOutcomes[uuid] = state
        case .inactive, .subscribing:
            break
        }
    }

    private func appendCaptureMarker(
        _ kind: FTMSCaptureMarkerKind,
        timestamp: Date? = nil,
        monotonic: TimeInterval? = nil
    ) {
        let markerTimestamp = timestamp ?? now()
        let markerMonotonic = monotonic ?? monotonicNow()
        nextCaptureMarkerID += 1
        captureMarkers.append(
            FTMSCaptureMarker(
                id: nextCaptureMarkerID,
                timestamp: markerTimestamp,
                captureOffsetSeconds: max(0, markerMonotonic - captureStartedMonotonic),
                kind: kind
            )
        )
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
            appendCaptureMarker(
                .connection(state: Self.captureStateName(value), detail: value.detail)
            )
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
        case let .valueError(uuid, source, message):
            lastError = message
            appendCaptureMarker(.valueError(uuid: uuid, source: source, message: message))
        }
    }
}

private extension TreadmillSetupViewModel {
    static func captureStateName(_ state: TreadmillConnectionState) -> String {
        switch state {
        case .idle: "Idle"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .discovering: "Discovering"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .failed: "Failed"
        }
    }

    static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
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

private extension FTMSCaptureMarkerKind {
    var reportLine: String {
        switch self {
        case .captureStarted:
            "Capture started"
        case let .applicationActivity(activity):
            "Application state: \(activity.title)"
        case let .connection(state, detail):
            if let detail {
                "Connection state: \(state) - \(detail)"
            } else {
                "Connection state: \(state)"
            }
        case let .valueError(uuid, source, message):
            "0x\(uuid) \(source.title) error: \(message)"
        case let .operatorObservation(observation):
            "Operator recorded: \(observation.title)"
        }
    }
}
