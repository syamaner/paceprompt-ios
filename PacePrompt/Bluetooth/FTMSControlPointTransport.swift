import Foundation

enum FTMSControlPointLinkEvent: Equatable {
    case indicationsEnabled
    case indicationEnableFailed(String)
    case writeAccepted
    case writeATTRejected(code: Int, message: String)
    case writeDeliveryUnknown(String)
    case indication(Data)
    case indicationFailed(String)
    case disconnected(String?)
}

@MainActor
protocol FTMSControlPointLink: AnyObject {
    var supportsWriteWithResponse: Bool { get }
    var supportsIndications: Bool { get }
    var eventHandler: ((FTMSControlPointLinkEvent) -> Void)? { get set }

    func enableIndications()
    func writeWithResponse(_ data: Data)
    func invalidate()
}

@MainActor
protocol FTMSDeadlineCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol FTMSDeadlineScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any FTMSDeadlineCancellation
}

@MainActor
private final class FTMSSystemDeadlineCancellation: FTMSDeadlineCancellation {
    private var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class FTMSSystemDeadlineScheduler: FTMSDeadlineScheduling {
    func schedule(
        after interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any FTMSDeadlineCancellation {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        return FTMSSystemDeadlineCancellation(timer: timer)
    }
}

enum FTMSControlPointLinkState: Equatable {
    case disconnected
    case awaitingIndicationEnablement(ConnectionEpoch)
    case enablingIndications(ConnectionEpoch)
    case ready(ConnectionEpoch)
    case invalidated(ConnectionEpoch, reason: String)

    var epoch: ConnectionEpoch? {
        switch self {
        case .disconnected:
            nil
        case let .awaitingIndicationEnablement(epoch), let .enablingIndications(epoch),
             let .ready(epoch), let .invalidated(epoch, _):
            epoch
        }
    }
}

enum FTMSControlPointPermission: Equatable {
    case notHeld
    case requesting(ProcedureID)
    case held(ConnectionEpoch, acknowledgedAt: MonotonicInstant)
}

enum FTMSControlPointATTOutcome: Equatable {
    case accepted(at: MonotonicInstant, indicationDeadline: MonotonicInstant)
    case rejected(code: Int, message: String, at: MonotonicInstant)
    case deliveryUnknown(message: String, at: MonotonicInstant)
}

struct FTMSControlPointProcedureEvidence: Equatable {
    let id: ProcedureID
    let intent: FitnessMachineControlIntent
    let exactRequestBytes: Data
    let submittedAt: MonotonicInstant
    var attOutcome: FTMSControlPointATTOutcome?
    var provisionalResponse: FTMSControlPointResponse? = nil
    var response: FTMSControlPointResponse?
    var responseReceivedAt: MonotonicInstant?

    var hasProvisionalResponse: Bool {
        provisionalResponse != nil && response == nil && attOutcome == nil
    }
}

enum FTMSControlPointProcedureResult: Equatable {
    case acknowledged(FTMSControlPointResponse)
    case attRejected(code: Int, message: String)
    case ftmsRejected(FTMSControlPointResponse)
    case timedOut
    case timedOutByDisconnect(String?)
    case deliveryUnknown(String)
    case deliveryUnknownDisconnect(String?)
    case protocolAnomaly(reason: String, rawBytes: Data?)
}

struct FTMSControlPointProcedureOutcome: Equatable {
    let evidence: FTMSControlPointProcedureEvidence
    let result: FTMSControlPointProcedureResult
    let completedAt: MonotonicInstant
}

enum FTMSControlPointTransportAnomaly: Equatable {
    case staleLinkEvent(ConnectionEpoch)
    case unexpectedEvent(String)
}

struct FTMSControlPointTransportState: Equatable {
    var link: FTMSControlPointLinkState = .disconnected
    var permission: FTMSControlPointPermission = .notHeld
    var inFlight: FTMSControlPointProcedureEvidence?
    var outcomes: [FTMSControlPointProcedureOutcome] = []
    var anomalies: [FTMSControlPointTransportAnomaly] = []
}

enum FTMSControlPointTransportError: Error, Equatable, LocalizedError {
    case invalidConnectionEpoch
    case connectionAlreadyActive
    case noActiveLink
    case linkInvalidated
    case indicationsNotConfirmed
    case unsupportedControlPointProperties
    case procedureInFlight(ProcedureID)
    case controlNotHeld
    case requestControlWhileHeld
    case procedureIDOverflow
    case nonMonotonicClock
    case invalidIntent(FTMSControlPointCodecError)

    var errorDescription: String? {
        switch self {
        case .invalidConnectionEpoch:
            "A connection epoch must be newer than every previously established epoch."
        case .connectionAlreadyActive:
            "The current link must disconnect or be invalidated before a new link is established."
        case .noActiveLink:
            "No FTMS Control Point link is active."
        case .linkInvalidated:
            "The FTMS Control Point link is invalidated. A new link is required."
        case .indicationsNotConfirmed:
            "FTMS Control Point indications have not been confirmed."
        case .unsupportedControlPointProperties:
            "The characteristic does not expose both Write and Indicate."
        case let .procedureInFlight(id):
            "Procedure \(id.sequence) is already in flight for connection epoch \(id.epoch.rawValue)."
        case .controlNotHeld:
            "A successful Request Control procedure is required first."
        case .requestControlWhileHeld:
            "Control is already held on the current connection."
        case .procedureIDOverflow:
            "The local procedure identifier sequence overflowed."
        case .nonMonotonicClock:
            "The monotonic clock returned an invalid or decreasing value."
        case let .invalidIntent(error):
            error.localizedDescription
        }
    }
}

@MainActor
protocol FitnessMachineControlTransport: AnyObject {
    var state: FTMSControlPointTransportState { get }
    var stateHandler: ((FTMSControlPointTransportState) -> Void)? { get set }

    func establishLink(
        epoch: ConnectionEpoch,
        eligibility: FTMSControlPointEligibility,
        link: any FTMSControlPointLink
    ) throws
    func enableIndications() throws
    @discardableResult func submit(_ intent: FitnessMachineControlIntent) throws -> ProcedureID
    func disconnect()
}

@MainActor
final class FTMSSingleProcedureTransport: FitnessMachineControlTransport {
    static let indicationDeadline: TimeInterval = 30

    private(set) var state = FTMSControlPointTransportState()
    var stateHandler: ((FTMSControlPointTransportState) -> Void)?

    private let clock: () -> MonotonicInstant
    private let scheduler: any FTMSDeadlineScheduling
    private var currentLink: (any FTMSControlPointLink)?
    private var currentLinkIdentifier: ObjectIdentifier?
    private var eligibility: FTMSControlPointEligibility?
    private var deadlineCancellation: (any FTMSDeadlineCancellation)?
    private var latestEpoch: ConnectionEpoch?
    private var nextProcedureSequence: UInt64 = 1
    private var lastTimestamp = MonotonicInstant(seconds: 0)

    convenience init() {
        self.init(
            clock: { MonotonicInstant(seconds: ProcessInfo.processInfo.systemUptime) },
            scheduler: FTMSSystemDeadlineScheduler()
        )
    }

    init(
        clock: @escaping () -> MonotonicInstant,
        scheduler: any FTMSDeadlineScheduling
    ) {
        self.clock = clock
        self.scheduler = scheduler
    }

    func establishLink(
        epoch: ConnectionEpoch,
        eligibility: FTMSControlPointEligibility,
        link: any FTMSControlPointLink
    ) throws {
        switch state.link {
        case .disconnected, .invalidated:
            break
        case .awaitingIndicationEnablement, .enablingIndications, .ready:
            throw FTMSControlPointTransportError.connectionAlreadyActive
        }
        if let latestEpoch, epoch.rawValue <= latestEpoch.rawValue {
            throw FTMSControlPointTransportError.invalidConnectionEpoch
        }

        cancelDeadline()
        currentLink?.invalidate()
        currentLink = link
        currentLinkIdentifier = ObjectIdentifier(link)
        self.eligibility = eligibility
        latestEpoch = epoch
        state.link = .awaitingIndicationEnablement(epoch)
        state.permission = .notHeld
        state.inFlight = nil

        let linkIdentifier = ObjectIdentifier(link)
        link.eventHandler = { [weak self] event in
            self?.receive(event, epoch: epoch, linkIdentifier: linkIdentifier)
        }
        publishState()
    }

    func enableIndications() throws {
        guard let currentLink else {
            throw FTMSControlPointTransportError.noActiveLink
        }
        guard case let .awaitingIndicationEnablement(epoch) = state.link else {
            if case .invalidated = state.link {
                throw FTMSControlPointTransportError.linkInvalidated
            }
            throw FTMSControlPointTransportError.indicationsNotConfirmed
        }
        guard currentLink.supportsWriteWithResponse, currentLink.supportsIndications else {
            invalidateLink(epoch: epoch, reason: "Control Point Write and Indicate properties were not both present")
            throw FTMSControlPointTransportError.unsupportedControlPointProperties
        }

        state.link = .enablingIndications(epoch)
        publishState()
        currentLink.enableIndications()
    }

    @discardableResult
    func submit(_ intent: FitnessMachineControlIntent) throws -> ProcedureID {
        guard case let .ready(epoch) = state.link else {
            if case .invalidated = state.link {
                throw FTMSControlPointTransportError.linkInvalidated
            }
            throw FTMSControlPointTransportError.indicationsNotConfirmed
        }
        guard let currentLink, let eligibility else {
            throw FTMSControlPointTransportError.noActiveLink
        }
        if let inFlight = state.inFlight {
            throw FTMSControlPointTransportError.procedureInFlight(inFlight.id)
        }

        switch intent {
        case .requestControl:
            if case .held = state.permission {
                throw FTMSControlPointTransportError.requestControlWhileHeld
            }
        case .setTargetSpeed, .setTargetInclination, .start, .stop:
            guard case let .held(heldEpoch, _) = state.permission, heldEpoch == epoch else {
                throw FTMSControlPointTransportError.controlNotHeld
            }
        }

        let bytes: Data
        do {
            bytes = try FTMSControlPointCodec.encode(intent, eligibility: eligibility)
        } catch let error as FTMSControlPointCodecError {
            throw FTMSControlPointTransportError.invalidIntent(error)
        }
        guard nextProcedureSequence < UInt64.max else {
            invalidateLink(epoch: epoch, reason: "Local procedure identifier sequence overflowed")
            throw FTMSControlPointTransportError.procedureIDOverflow
        }
        let now = try monotonicNow(epoch: epoch)
        let id = ProcedureID(epoch: epoch, sequence: nextProcedureSequence)
        nextProcedureSequence += 1
        state.inFlight = FTMSControlPointProcedureEvidence(
            id: id,
            intent: intent,
            exactRequestBytes: bytes,
            submittedAt: now,
            attOutcome: nil,
            response: nil,
            responseReceivedAt: nil
        )
        if intent == .requestControl {
            state.permission = .requesting(id)
        }
        publishState()
        currentLink.writeWithResponse(bytes)
        return id
    }

    func disconnect() {
        guard let epoch = state.link.epoch else { return }
        handleDisconnect(epoch: epoch, reason: "Disconnected by caller")
    }

    private func receive(
        _ event: FTMSControlPointLinkEvent,
        epoch: ConnectionEpoch,
        linkIdentifier: ObjectIdentifier
    ) {
        guard currentLinkIdentifier == linkIdentifier, state.link.epoch == epoch else {
            state.anomalies.append(.staleLinkEvent(epoch))
            publishState()
            return
        }

        switch event {
        case .indicationsEnabled:
            guard case .enablingIndications(epoch) = state.link else {
                failUnexpected("Duplicate or out-of-order indication enablement", epoch: epoch)
                return
            }
            state.link = .ready(epoch)
            publishState()
        case let .indicationEnableFailed(message):
            invalidateLink(epoch: epoch, reason: "Indication enablement failed: \(message)")
        case .writeAccepted:
            handleWriteAccepted(epoch: epoch)
        case let .writeATTRejected(code, message):
            handleATTRejection(epoch: epoch, code: code, message: message)
        case let .writeDeliveryUnknown(message):
            handleDeliveryUnknown(epoch: epoch, message: message)
        case let .indication(data):
            handleIndication(data, epoch: epoch)
        case let .indicationFailed(message):
            handleIndicationFailure(epoch: epoch, message: message)
        case let .disconnected(message):
            handleDisconnect(epoch: epoch, reason: message)
        }
    }

    private func handleWriteAccepted(epoch: ConnectionEpoch) {
        guard var procedure = state.inFlight, procedure.attOutcome == nil else {
            failUnexpected("Duplicate or late ATT write response", epoch: epoch)
            return
        }
        guard let now = validTimestampOrInvalidate(epoch: epoch) else { return }
        let deadline = now.advanced(by: Self.indicationDeadline)
        procedure.attOutcome = .accepted(at: now, indicationDeadline: deadline)

        if let response = procedure.provisionalResponse {
            procedure.provisionalResponse = nil
            procedure.response = response
            completeResponse(procedure, response: response, epoch: epoch, at: now)
            return
        }

        state.inFlight = procedure
        cancelDeadline()
        deadlineCancellation = scheduler.schedule(after: Self.indicationDeadline) { [weak self] in
            self?.deadlineReached(procedureID: procedure.id, epoch: epoch)
        }
        publishState()
    }

    private func handleATTRejection(epoch: ConnectionEpoch, code: Int, message: String) {
        guard var procedure = state.inFlight, procedure.attOutcome == nil else {
            failUnexpected("Duplicate or late ATT error response", epoch: epoch)
            return
        }
        guard let now = validTimestampOrInvalidate(epoch: epoch) else { return }
        procedure.attOutcome = .rejected(code: code, message: message, at: now)
        complete(
            procedure,
            result: .attRejected(code: code, message: message),
            at: now
        )
        if procedure.intent == .requestControl {
            state.permission = .notHeld
        }
        publishState()
    }

    private func handleDeliveryUnknown(epoch: ConnectionEpoch, message: String) {
        guard var procedure = state.inFlight, procedure.attOutcome == nil else {
            failUnexpected("Duplicate or late delivery-unknown write result", epoch: epoch)
            return
        }
        guard let now = validTimestampOrInvalidate(epoch: epoch) else { return }
        procedure.attOutcome = .deliveryUnknown(message: message, at: now)
        complete(procedure, result: .deliveryUnknown(message), at: now)
        invalidateLink(epoch: epoch, reason: "Write delivery is unknown: \(message)")
    }

    private func handleIndication(_ data: Data, epoch: ConnectionEpoch) {
        guard var procedure = state.inFlight else {
            failUnexpected("Duplicate or late Control Point indication", epoch: epoch)
            return
        }
        guard procedure.provisionalResponse == nil, procedure.response == nil else {
            completeProtocolAnomaly(
                procedure,
                epoch: epoch,
                reason: "Duplicate Control Point indication arrived for the in-flight procedure",
                rawBytes: data
            )
            return
        }
        guard let now = validTimestampOrInvalidate(epoch: epoch) else { return }
        procedure.responseReceivedAt = now

        if case let .accepted(_, deadline)? = procedure.attOutcome {
            guard now < deadline else {
                completeProtocolAnomaly(
                    procedure,
                    epoch: epoch,
                    reason: "Control Point indication arrived at or after the 30-second deadline",
                    rawBytes: data,
                    at: now
                )
                return
            }
        }

        let response: FTMSControlPointResponse
        do {
            response = try FTMSControlPointCodec.decodeResponse(data)
        } catch {
            completeProtocolAnomaly(
                procedure,
                epoch: epoch,
                reason: error.localizedDescription,
                rawBytes: data,
                at: now
            )
            return
        }
        guard response.requestOpcode == procedure.intent.opcode else {
            completeProtocolAnomaly(
                procedure,
                epoch: epoch,
                reason: String(
                    format: "Response request opcode 0x%02X did not match in-flight opcode 0x%02X",
                    response.requestOpcode,
                    procedure.intent.opcode
                ),
                rawBytes: data,
                at: now
            )
            return
        }

        procedure.responseReceivedAt = now

        guard case .accepted? = procedure.attOutcome else {
            procedure.provisionalResponse = response
            state.inFlight = procedure
            publishState()
            return
        }

        procedure.response = response
        completeResponse(procedure, response: response, epoch: epoch, at: now)
    }

    private func completeResponse(
        _ procedure: FTMSControlPointProcedureEvidence,
        response: FTMSControlPointResponse,
        epoch: ConnectionEpoch,
        at now: MonotonicInstant
    ) {
        cancelDeadline()
        if response.result == .success {
            complete(procedure, result: .acknowledged(response), at: now)
            if procedure.intent == .requestControl {
                state.permission = .held(epoch, acknowledgedAt: now)
            }
        } else {
            complete(procedure, result: .ftmsRejected(response), at: now)
            state.permission = .notHeld
        }
        publishState()
    }

    private func handleIndicationFailure(epoch: ConnectionEpoch, message: String) {
        if let procedure = state.inFlight {
            let now = validTimestampOrFallback(epoch: epoch)
            complete(
                procedure,
                result: .protocolAnomaly(reason: "Indication delivery failed: \(message)", rawBytes: nil),
                at: now
            )
        }
        invalidateLink(epoch: epoch, reason: "Indication delivery failed: \(message)")
    }

    private func handleDisconnect(epoch: ConnectionEpoch, reason: String?) {
        cancelDeadline()
        if let procedure = state.inFlight {
            let now = validTimestampOrFallback(epoch: epoch)
            let result: FTMSControlPointProcedureResult
            if case .accepted? = procedure.attOutcome {
                result = .timedOutByDisconnect(reason)
            } else {
                result = .deliveryUnknownDisconnect(reason)
            }
            complete(procedure, result: result, at: now)
        }
        currentLink?.invalidate()
        currentLink = nil
        currentLinkIdentifier = nil
        eligibility = nil
        state.link = .disconnected
        state.permission = .notHeld
        publishState()
    }

    private func deadlineReached(procedureID: ProcedureID, epoch: ConnectionEpoch) {
        guard let procedure = state.inFlight, procedure.id == procedureID else { return }
        guard case let .accepted(_, deadline)? = procedure.attOutcome else { return }
        guard let now = validTimestampOrInvalidate(epoch: epoch) else { return }
        guard now >= deadline else {
            failUnexpected("The indication deadline fired before 30 seconds", epoch: epoch)
            return
        }
        complete(procedure, result: .timedOut, at: now)
        invalidateLink(epoch: epoch, reason: "FTMS Control Point indication timed out after 30 seconds")
    }

    private func completeProtocolAnomaly(
        _ suppliedProcedure: FTMSControlPointProcedureEvidence,
        epoch: ConnectionEpoch,
        reason: String,
        rawBytes: Data?,
        at suppliedTime: MonotonicInstant? = nil
    ) {
        let now = suppliedTime ?? validTimestampOrFallback(epoch: epoch)
        var procedure = suppliedProcedure
        if rawBytes != nil, procedure.responseReceivedAt == nil {
            procedure.responseReceivedAt = now
        }
        cancelDeadline()
        complete(
            procedure,
            result: .protocolAnomaly(reason: reason, rawBytes: rawBytes),
            at: now
        )
        invalidateLink(epoch: epoch, reason: reason)
    }

    private func failUnexpected(_ reason: String, epoch: ConnectionEpoch) {
        state.anomalies.append(.unexpectedEvent(reason))
        invalidateLink(epoch: epoch, reason: reason)
    }

    private func complete(
        _ evidence: FTMSControlPointProcedureEvidence,
        result: FTMSControlPointProcedureResult,
        at time: MonotonicInstant
    ) {
        state.outcomes.append(
            FTMSControlPointProcedureOutcome(
                evidence: evidence,
                result: result,
                completedAt: time
            )
        )
        state.inFlight = nil
    }

    private func invalidateLink(epoch: ConnectionEpoch, reason: String) {
        cancelDeadline()
        currentLink?.invalidate()
        state.link = .invalidated(epoch, reason: reason)
        state.permission = .notHeld
        publishState()
    }

    private func monotonicNow(epoch: ConnectionEpoch) throws -> MonotonicInstant {
        let now = clock()
        guard now.seconds.isFinite, now >= lastTimestamp else {
            invalidateLink(epoch: epoch, reason: "Monotonic clock became invalid")
            throw FTMSControlPointTransportError.nonMonotonicClock
        }
        lastTimestamp = now
        return now
    }

    private func validTimestampOrInvalidate(epoch: ConnectionEpoch) -> MonotonicInstant? {
        do {
            return try monotonicNow(epoch: epoch)
        } catch {
            return nil
        }
    }

    private func validTimestampOrFallback(epoch: ConnectionEpoch) -> MonotonicInstant {
        (try? monotonicNow(epoch: epoch)) ?? lastTimestamp
    }

    private func cancelDeadline() {
        deadlineCancellation?.cancel()
        deadlineCancellation = nil
    }

    private func publishState() {
        stateHandler?(state)
    }
}
