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
            status(category: "Bluetooth", title: "Available", detail: "Bluetooth is on and PacePrompt has permission to use it.", symbol: "antenna.radiowaves.left.and.right", tone: .positive)
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
            return status(category: "Treadmill", title: "Idle", detail: "Choose Set up treadmill to find and check your treadmill.", symbol: "figure.run")
        case .scanning:
            return status(category: "Treadmill", title: "Scanning", detail: "Looking for nearby treadmills. Their supported settings are not yet known.", symbol: "dot.radiowaves.left.and.right")
        case let .connecting(name):
            return status(category: "Treadmill", title: "Connecting", detail: "\(name) · supported settings not yet checked.", symbol: "dot.radiowaves.left.and.right")
        case let .discovering(name):
            return status(category: "Treadmill", title: "Checking treadmill", detail: "\(name) · checking supported settings.", symbol: "dot.radiowaves.left.and.right")
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
            return status(category: "Treadmill", title: "Disconnected", detail: "Reconnect in treadmill setup to check its current settings.", symbol: "exclamationmark.circle.fill")
        case .failed:
            let canRetry = availability == .poweredOn
            return status(
                category: "Treadmill",
                title: "Connection failed",
                detail: canRetry
                    ? "Wake the treadmill console and try scanning again."
                    : "Check Bluetooth permission and turn it on before trying setup again.",
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
            return status(category: "Treadmill", title: "Treadmill settings unreadable", detail: "The treadmill sent an unreadable setting. Open setup to check the connection.", symbol: "exclamationmark.circle.fill", tone: .warning)
        }

        if case let .value(flags, _) = featureFlags,
           !flags.supportsSpeedTargetSetting || !flags.supportsInclinationTargetSetting {
            return status(category: "Treadmill", title: "Settings not supported", detail: "This treadmill reports that speed or incline cannot be changed by the app.", symbol: "exclamationmark.circle.fill", tone: .warning)
        }

        if case .value = featureFlags,
           case let .value(speed, _) = speedRange,
           case let .value(inclination, _) = inclinationRange {
            return status(
                category: "Treadmill",
                title: "Connected",
                detail: "\(name) · supported speed \(oneDecimal(speed.minimumKilometresPerHour))–\(oneDecimal(speed.maximumKilometresPerHour)) km/h · inclination \(oneDecimal(inclination.minimumPercent))–\(oneDecimal(inclination.maximumPercent))%.",
                symbol: "checkmark.circle.fill",
                tone: .positive
            )
        }

        if lastError != nil {
            return status(category: "Treadmill", title: "Treadmill check unavailable", detail: "Could not read the supported treadmill settings. Open setup to check the connection.", symbol: "exclamationmark.circle.fill", tone: .warning)
        }

        if requiredReadIsUnsupported(in: characteristics) {
            return status(category: "Treadmill", title: "Settings not supported", detail: "The treadmill does not provide the settings needed for a workout.", symbol: "exclamationmark.circle.fill", tone: .warning)
        }

        return status(category: "Treadmill", title: "Checking treadmill", detail: "\(name) is connected. Its supported settings are still being checked.", symbol: "dot.radiowaves.left.and.right")
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
