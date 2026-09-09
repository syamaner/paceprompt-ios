#if DEBUG
import Foundation

enum RequestControlDiagnosticReadiness: Equatable {
    case awaitingConnection
    case preparing(String)
    case ready
    case attemptConsumed
    case failed(String)

    var title: String {
        switch self {
        case .awaitingConnection: "Awaiting connection"
        case .preparing: "Preparing"
        case .ready: "Ready for one request"
        case .attemptConsumed: "One request consumed"
        case .failed: "Unavailable"
        }
    }

    var detail: String? {
        switch self {
        case .awaitingConnection:
            "Connect to the identified FR30z after an explicit user action."
        case let .preparing(detail), let .failed(detail):
            detail
        case .ready:
            "All reads and subscription outcomes are recorded. The next confirmed action may submit exactly 00 once."
        case .attemptConsumed:
            "The issue #51 one-write allowance has been consumed. Reinstalling or reconnecting is not a retry authority."
        }
    }

    var permitsRequest: Bool {
        self == .ready
    }
}

enum RequestControlDiagnosticEvent: Equatable {
    case controlPointDiscovered(write: Bool, indicate: Bool)
    case indicationSubscriptionSucceeded
    case indicationSubscriptionFailed(String)
    case readiness(RequestControlDiagnosticReadiness)
    case requestSubmitted(Data)
    case procedureSubmitted(ProcedureID)
    case attAccepted
    case attRejected(code: Int, message: String)
    case writeDeliveryUnknown(String)
    case indication(Data)
    case indicationFailed(String)
    case outcome(FTMSControlPointProcedureOutcome)
    case disconnectRequested
    case disconnected(String?)
    case blocked(String)
}

struct RequestControlDiagnosticRecord: Identifiable, Equatable {
    let id: UInt64
    let timestamp: Date
    let event: RequestControlDiagnosticEvent
}

enum RequestControlWriteGateError: Error, Equatable, LocalizedError {
    case disallowedBytes(Data)
    case attemptAlreadyConsumed

    var errorDescription: String? {
        switch self {
        case let .disallowedBytes(data):
            "The issue #51 diagnostic blocked disallowed Control Point bytes: \(data.ftmsHex). No write occurred."
        case .attemptAlreadyConsumed:
            "The issue #51 diagnostic already consumed its one Request Control write. No retry occurred."
        }
    }
}

final class RequestControlWriteGate {
    static let exactRequest = Data([0x00])
    static let defaultAttemptKey = "PacePrompt.issue51.requestControlAttemptConsumed.v1"

    private let defaults: UserDefaults
    private let attemptKey: String

    init(
        defaults: UserDefaults = .standard,
        attemptKey: String = RequestControlWriteGate.defaultAttemptKey
    ) {
        self.defaults = defaults
        self.attemptKey = attemptKey
    }

    var wasConsumed: Bool {
        defaults.bool(forKey: attemptKey)
    }

    func consume(_ data: Data) throws {
        guard data == Self.exactRequest else {
            throw RequestControlWriteGateError.disallowedBytes(data)
        }
        guard !wasConsumed else {
            throw RequestControlWriteGateError.attemptAlreadyConsumed
        }
        // Consume before forwarding. A crash or disconnect must never create
        // implicit retry authority for this installed diagnostic build.
        defaults.set(true, forKey: attemptKey)
    }
}

@MainActor
final class RequestControlOnlyLink: FTMSControlPointLink {
    var eventHandler: ((FTMSControlPointLinkEvent) -> Void)? {
        didSet {
            underlying.eventHandler = { [weak self] event in
                self?.eventHandler?(event)
            }
        }
    }

    var supportsWriteWithResponse: Bool { underlying.supportsWriteWithResponse }
    var supportsIndications: Bool { underlying.supportsIndications }

    var requestSubmitted: ((Data) -> Void)?
    var requestBlocked: ((String) -> Void)?

    private let underlying: any FTMSControlPointLink
    private let gate: RequestControlWriteGate

    init(
        underlying: any FTMSControlPointLink,
        gate: RequestControlWriteGate
    ) {
        self.underlying = underlying
        self.gate = gate
    }

    func enableIndications() {
        underlying.enableIndications()
    }

    func writeWithResponse(_ data: Data) {
        do {
            try gate.consume(data)
        } catch {
            let message = error.localizedDescription
            requestBlocked?(message)
            underlying.invalidate()
            eventHandler?(.writeDeliveryUnknown("Blocked locally before CoreBluetooth write. \(message)"))
            return
        }

        requestSubmitted?(data)
        underlying.writeWithResponse(data)
    }

    func invalidate() {
        underlying.invalidate()
    }

    func abort(reason: String) {
        underlying.invalidate()
        eventHandler?(.indicationFailed(reason))
    }
}

extension RequestControlDiagnosticEvent {
    var reportLine: String {
        switch self {
        case let .controlPointDiscovered(write, indicate):
            "Control Point 0x2AD9 discovered: Write \(write ? "present" : "absent"), Indicate \(indicate ? "present" : "absent")"
        case .indicationSubscriptionSucceeded:
            "Control Point indication subscription confirmed; CoreBluetooth reported no security or pairing error"
        case let .indicationSubscriptionFailed(message):
            "Control Point indication subscription failed: \(message)"
        case let .readiness(value):
            "Readiness: \(value.title)\(value.detail.map { " - \($0)" } ?? "")"
        case let .requestSubmitted(data):
            "CoreBluetooth write submitted once with response; exact bytes: \(data.ftmsHex)"
        case let .procedureSubmitted(id):
            "Local procedure ID: epoch \(id.epoch.rawValue), sequence \(id.sequence)"
        case .attAccepted:
            "ATT write callback: accepted; the FTMS procedure started but was not yet acknowledged"
        case let .attRejected(code, message):
            "ATT write callback: rejected (code \(code)) - \(message)"
        case let .writeDeliveryUnknown(message):
            "CoreBluetooth write callback left delivery unknown: \(message)"
        case let .indication(data):
            "Control Point indication received; raw bytes: \(data.ftmsHex)"
        case let .indicationFailed(message):
            "Control Point indication failed: \(message)"
        case let .outcome(outcome):
            "Procedure outcome: \(Self.describe(outcome))"
        case .disconnectRequested:
            "Explicit disconnect requested"
        case let .disconnected(message):
            "CoreBluetooth disconnected\(message.map { ": \($0)" } ?? "")"
        case let .blocked(message):
            "Request blocked locally: \(message)"
        }
    }

    private static func describe(_ outcome: FTMSControlPointProcedureOutcome) -> String {
        switch outcome.result {
        case let .acknowledged(response):
            return "acknowledged response \(response.rawBytes.ftmsHex) for opcode 0x\(String(format: "%02X", response.requestOpcode))"
        case let .attRejected(code, message):
            return "ATT rejected code \(code) - \(message)"
        case let .ftmsRejected(response):
            return "FTMS rejected with \(response.rawBytes.ftmsHex)"
        case .timedOut:
            return "timed out after the 30-second indication deadline"
        case let .timedOutByDisconnect(message):
            return "timed out by disconnect\(message.map { " - \($0)" } ?? "")"
        case let .deliveryUnknown(message):
            return "delivery unknown - \(message)"
        case let .deliveryUnknownDisconnect(message):
            return "delivery unknown at disconnect\(message.map { " - \($0)" } ?? "")"
        case let .protocolAnomaly(reason, rawBytes):
            return "protocol anomaly - \(reason)\(rawBytes.map { "; raw \($0.ftmsHex)" } ?? "")"
        }
    }
}
#endif
