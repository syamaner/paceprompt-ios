import Foundation

enum HomeStatusTone: Equatable {
    case positive
    case neutral
    case warning
    case failure
}

enum HomeStatusAction: Equatable {
    case openSettings
    case retryScan

    var title: String {
        switch self {
        case .openSettings: "Open iOS Settings"
        case .retryScan: "Retry"
        }
    }

    var symbol: String {
        switch self {
        case .openSettings: "gearshape"
        case .retryScan: "arrow.clockwise"
        }
    }
}

struct HomeStatusPresentation: Equatable {
    let category: String
    let title: String
    let detail: String
    let symbol: String
    let tone: HomeStatusTone
    let action: HomeStatusAction?

    var isSuccessful: Bool { tone == .positive }
}

struct HomePresentation: Equatable {
    let bluetooth: HomeStatusPresentation
    let treadmill: HomeStatusPresentation

    init(
        availability: BluetoothAvailability,
        connection: TreadmillConnectionState,
        characteristics: [FTMSCharacteristicInfo],
        featureFlags: CapabilityRead<FTMSFeatureFlags>,
        speedRange: CapabilityRead<FTMSSpeedRange>,
        inclinationRange: CapabilityRead<FTMSInclinationRange>,
        lastError: String?
    ) {
        bluetooth = Self.bluetoothPresentation(for: availability)
        treadmill = Self.treadmillPresentation(
            availability: availability,
            connection: connection,
            characteristics: characteristics,
            featureFlags: featureFlags,
            speedRange: speedRange,
            inclinationRange: inclinationRange,
            lastError: lastError
        )
    }

    private static func bluetoothPresentation(
        for availability: BluetoothAvailability
    ) -> HomeStatusPresentation {
        switch availability {
        case .notDetermined:
            status(category: "Bluetooth", title: "Checking", detail: "Bluetooth availability is being checked.", symbol: "antenna.radiowaves.left.and.right")
        case .resetting:
            status(category: "Bluetooth", title: "Resetting", detail: "Bluetooth is resetting. Wait before starting a scan.", symbol: "antenna.radiowaves.left.and.right")
        case .unsupported:
            status(category: "Bluetooth", title: "Unsupported", detail: "Bluetooth Low Energy is unavailable on this device.", symbol: "exclamationmark.circle.fill", tone: .warning)
        case .unauthorized:
            status(category: "Bluetooth", title: "Not authorised", detail: "PacePrompt has no Bluetooth permission. Retrying will not help.", symbol: "exclamationmark.circle.fill", tone: .warning, action: .openSettings)
        case .poweredOff:
            status(category: "Bluetooth", title: "Powered off", detail: "Turn Bluetooth on in Control Centre or Settings.", symbol: "antenna.radiowaves.left.and.right", tone: .warning)
        case .poweredOn:
            status(category: "Bluetooth", title: "Available", detail: "Radio powered on and authorised for this app.", symbol: "antenna.radiowaves.left.and.right", tone: .positive)
        }
    }

    private static func treadmillPresentation(
        availability: BluetoothAvailability,
        connection: TreadmillConnectionState,
        characteristics: [FTMSCharacteristicInfo],
        featureFlags: CapabilityRead<FTMSFeatureFlags>,
        speedRange: CapabilityRead<FTMSSpeedRange>,
        inclinationRange: CapabilityRead<FTMSInclinationRange>,
        lastError: String?
    ) -> HomeStatusPresentation {
        switch connection {
        case .idle:
            return status(category: "Treadmill", title: "Idle", detail: "No scan started. Capability is unknown until you scan.", symbol: "figure.run")
        case .scanning:
            return status(category: "Treadmill", title: "Scanning", detail: "Scan started by you. Capability remains unknown while scanning.", symbol: "dot.radiowaves.left.and.right")
        case let .connecting(name):
            return status(category: "Treadmill", title: "Connecting", detail: "\(name) · capability not yet read.", symbol: "dot.radiowaves.left.and.right")
        case let .discovering(name):
            return status(category: "Treadmill", title: "Reading capability", detail: "\(name) · current capability evidence is being discovered.", symbol: "dot.radiowaves.left.and.right")
        case let .connected(name):
            return connectedPresentation(
                name: name,
                characteristics: characteristics,
                featureFlags: featureFlags,
                speedRange: speedRange,
                inclinationRange: inclinationRange,
                lastError: lastError
            )
        case .disconnected:
            return status(category: "Treadmill", title: "Disconnected", detail: "Prior capability values are stale and are not shown as current.", symbol: "exclamationmark.circle.fill")
        case let .failed(message):
            let canRetry = availability == .poweredOn
            return status(
                category: "Treadmill",
                title: "Connection failed",
                detail: canRetry
                    ? "\(message) Wake the console and retry the user-started scan."
                    : "\(message) Resolve Bluetooth status before trying setup again.",
                symbol: "exclamationmark.triangle.fill",
                tone: .failure,
                action: canRetry ? .retryScan : nil
            )
        }
    }

    private static func connectedPresentation(
        name: String,
        characteristics: [FTMSCharacteristicInfo],
        featureFlags: CapabilityRead<FTMSFeatureFlags>,
        speedRange: CapabilityRead<FTMSSpeedRange>,
        inclinationRange: CapabilityRead<FTMSInclinationRange>,
        lastError: String?
    ) -> HomeStatusPresentation {
        if [featureFlags.issue, speedRange.issue, inclinationRange.issue].contains(where: { $0 != nil }) {
            return status(category: "Treadmill", title: "Capability malformed", detail: "A current capability value could not be decoded. Open setup to inspect it and retry.", symbol: "exclamationmark.circle.fill", tone: .warning)
        }

        if case let .value(flags, _) = featureFlags,
           !flags.supportsSpeedTargetSetting || !flags.supportsInclinationTargetSetting {
            return status(category: "Treadmill", title: "Capability unsupported", detail: "Current feature evidence reports speed or inclination target-setting as unsupported.", symbol: "exclamationmark.circle.fill", tone: .warning)
        }

        if case .value = featureFlags,
           case let .value(speed, _) = speedRange,
           case let .value(inclination, _) = inclinationRange {
            return status(
                category: "Treadmill",
                title: "Connected",
                detail: "\(name) · read range evidence: speed \(oneDecimal(speed.minimumKilometresPerHour))–\(oneDecimal(speed.maximumKilometresPerHour)) km/h · inclination \(oneDecimal(inclination.minimumPercent))–\(oneDecimal(inclination.maximumPercent))%.",
                symbol: "checkmark.circle.fill",
                tone: .positive
            )
        }

        if let lastError {
            return status(category: "Treadmill", title: "Capability unavailable", detail: "A current capability read failed: \(lastError)", symbol: "exclamationmark.circle.fill", tone: .warning)
        }

        if requiredReadIsUnsupported(in: characteristics) {
            return status(category: "Treadmill", title: "Capability unsupported", detail: "A required read-only capability characteristic is unavailable.", symbol: "exclamationmark.circle.fill", tone: .warning)
        }

        return status(category: "Treadmill", title: "Reading capability", detail: "\(name) is connected, but current decoded capability evidence is incomplete.", symbol: "dot.radiowaves.left.and.right")
    }

    private static func requiredReadIsUnsupported(
        in characteristics: [FTMSCharacteristicInfo]
    ) -> Bool {
        let required = [FTMSUUID.fitnessMachineFeature, FTMSUUID.supportedSpeedRange, FTMSUUID.supportedInclinationRange]
        return required.contains { uuid in
            !characteristics.contains { characteristic in
                characteristic.uuid == uuid && characteristic.properties.contains("Read")
            }
        }
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func status(
        category: String,
        title: String,
        detail: String,
        symbol: String,
        tone: HomeStatusTone = .neutral,
        action: HomeStatusAction? = nil
    ) -> HomeStatusPresentation {
        HomeStatusPresentation(category: category, title: title, detail: detail, symbol: symbol, tone: tone, action: action)
    }
}
