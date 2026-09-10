#if DEBUG
import Foundation

enum RequestControlDiagnosticJournalKind: String, Codable, Equatable {
    case sessionStarted
    case previousSessionRecovered
    case controlPointDiscovered
    case indicationSubscriptionSucceeded
    case indicationSubscriptionFailed
    case readiness
    case requestPathEntered
    case gateConsumed
    case forwardingStarted
    case requestSubmitted
    case procedureSubmitted
    case attAccepted
    case attRejected
    case writeDeliveryUnknown
    case indicationReceived
    case indicationFailed
    case outcome
    case disconnectRequested
    case disconnected
    case blocked
}

struct RequestControlDiagnosticJournalEntry: Codable, Identifiable, Equatable {
    var id: UInt64 { sequence }

    let sequence: UInt64
    let timestamp: Date
    let sessionID: UUID
    let kind: RequestControlDiagnosticJournalKind
    let detail: String
}

struct RequestControlDiagnosticJournalDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let nextSequence: UInt64
    let entries: [RequestControlDiagnosticJournalEntry]
}

enum RequestControlDiagnosticJournalError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int)
    case invalidSequence
    case sequenceExhausted
    case protectionUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "The Request Control diagnostic journal uses unsupported schema version \(version)."
        case .invalidSequence:
            "The Request Control diagnostic journal has missing, duplicate, reordered, or rolled-back sequence evidence."
        case .sequenceExhausted:
            "The Request Control diagnostic journal sequence is exhausted."
        case let .protectionUnavailable(detail):
            "The Request Control diagnostic journal could not establish protected local storage: \(detail)"
        }
    }
}

protocol RequestControlDiagnosticJournalStore {
    func load() throws -> Data?
    func saveAtomicallyProtected(_ data: Data) throws
}

protocol RequestControlDiagnosticJournalFileSystem {
    func applicationSupportDirectory() throws -> URL
    func fileExists(at url: URL) throws -> Bool
    func createProtectedDirectory(at url: URL) throws
    func readData(at url: URL) throws -> Data
    func writeAtomicallyProtectedData(_ data: Data, to url: URL) throws
    func applyCompleteFileProtection(to url: URL) throws
    func hasCompleteFileProtection(at url: URL) throws -> Bool
    func excludeFromBackup(_ url: URL) throws
    func isExcludedFromBackup(_ url: URL) throws -> Bool
}

struct FoundationRequestControlDiagnosticJournalFileSystem: RequestControlDiagnosticJournalFileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func applicationSupportDirectory() throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    func fileExists(at url: URL) throws -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: url.path)
            return true
        } catch {
            let cocoaError = error as NSError
            guard cocoaError.domain == NSCocoaErrorDomain,
                  cocoaError.code == CocoaError.fileNoSuchFile.rawValue
                    || cocoaError.code == CocoaError.fileReadNoSuchFile.rawValue else {
                throw error
            }
            return false
        }
    }

    func createProtectedDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeAtomicallyProtectedData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func applyCompleteFileProtection(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    func hasCompleteFileProtection(at url: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.protectionKey] as? FileProtectionType) == .complete
    }

    func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }
}

final class RequestControlDiagnosticJournalFileStore: RequestControlDiagnosticJournalStore {
    private static let directoryName = "PacePromptIssue51Diagnostic"
    private static let fileName = "request-control-journal-v1.json"

    private let fileSystem: any RequestControlDiagnosticJournalFileSystem
    private let directoryURL: URL
    private let fileURL: URL

    convenience init(
        fileSystem: any RequestControlDiagnosticJournalFileSystem = FoundationRequestControlDiagnosticJournalFileSystem()
    ) throws {
        let applicationSupport = try fileSystem.applicationSupportDirectory()
        try self.init(
            directoryURL: applicationSupport.appendingPathComponent(Self.directoryName, isDirectory: true),
            fileSystem: fileSystem
        )
    }

    init(
        directoryURL: URL,
        fileSystem: any RequestControlDiagnosticJournalFileSystem
    ) throws {
        self.fileSystem = fileSystem
        self.directoryURL = directoryURL
        fileURL = directoryURL.appendingPathComponent(Self.fileName, isDirectory: false)
        try prepareProtectedDirectory()
    }

    func load() throws -> Data? {
        guard try fileSystem.fileExists(at: fileURL) else { return nil }
        try verifyProtectionAndBackupExclusion(for: fileURL)
        return try fileSystem.readData(at: fileURL)
    }

    func saveAtomicallyProtected(_ data: Data) throws {
        try fileSystem.writeAtomicallyProtectedData(data, to: fileURL)
        try fileSystem.applyCompleteFileProtection(to: fileURL)
        try fileSystem.excludeFromBackup(fileURL)
        try verifyProtectionAndBackupExclusion(for: fileURL)
    }

    private func prepareProtectedDirectory() throws {
        try fileSystem.createProtectedDirectory(at: directoryURL)
        try fileSystem.applyCompleteFileProtection(to: directoryURL)
        try fileSystem.excludeFromBackup(directoryURL)
        try verifyProtectionAndBackupExclusion(for: directoryURL)
    }

    private func verifyProtectionAndBackupExclusion(for url: URL) throws {
        guard try fileSystem.hasCompleteFileProtection(at: url) else {
            throw RequestControlDiagnosticJournalError.protectionUnavailable(
                "complete file protection was not verified"
            )
        }
        guard try fileSystem.isExcludedFromBackup(url) else {
            throw RequestControlDiagnosticJournalError.protectionUnavailable(
                "backup exclusion was not verified"
            )
        }
    }
}

@MainActor
protocol RequestControlDiagnosticJournaling: AnyObject {
    var records: [RequestControlDiagnosticJournalEntry] { get }

    func record(
        _ kind: RequestControlDiagnosticJournalKind,
        detail: String
    ) throws
}

@MainActor
final class RequestControlDiagnosticJournal: RequestControlDiagnosticJournaling {
    private let store: any RequestControlDiagnosticJournalStore
    private let maximumRecordCount: Int
    private let now: () -> Date
    private let sessionID: UUID
    private var document: RequestControlDiagnosticJournalDocument

    init(
        store: any RequestControlDiagnosticJournalStore,
        maximumRecordCount: Int = 200,
        now: @escaping () -> Date = { Date() },
        sessionID: UUID = UUID()
    ) throws {
        precondition(maximumRecordCount >= 2)
        self.store = store
        self.maximumRecordCount = maximumRecordCount
        self.now = now
        self.sessionID = sessionID

        if let data = try store.load() {
            let decoded = try JSONDecoder().decode(RequestControlDiagnosticJournalDocument.self, from: data)
            try Self.validate(decoded, maximumRecordCount: maximumRecordCount)
            document = decoded
        } else {
            document = RequestControlDiagnosticJournalDocument(
                schemaVersion: RequestControlDiagnosticJournalDocument.currentSchemaVersion,
                nextSequence: 1,
                entries: []
            )
        }

        let previousLast = document.entries.last
        var startupRecords: [(RequestControlDiagnosticJournalKind, String)] = [
            (
                .sessionStarted,
                "DEBUG diagnostic process session started. This is not Bluetooth activity or write authority."
            ),
        ]
        if let previousLast {
            startupRecords.append(
                (
                    .previousSessionRecovered,
                    Self.recoveryDetail(previousLast: previousLast)
                )
            )
        }
        try appendBatch(startupRecords)
    }

    var records: [RequestControlDiagnosticJournalEntry] {
        document.entries
    }

    func record(
        _ kind: RequestControlDiagnosticJournalKind,
        detail: String
    ) throws {
        try appendBatch([(kind, detail)])
    }

    private func appendBatch(
        _ values: [(RequestControlDiagnosticJournalKind, String)]
    ) throws {
        var candidate = document
        var entries = candidate.entries
        var nextSequence = candidate.nextSequence

        for (kind, detail) in values {
            guard nextSequence < UInt64.max else {
                throw RequestControlDiagnosticJournalError.sequenceExhausted
            }
            entries.append(
                RequestControlDiagnosticJournalEntry(
                    sequence: nextSequence,
                    timestamp: now(),
                    sessionID: sessionID,
                    kind: kind,
                    detail: detail
                )
            )
            nextSequence += 1
        }

        if entries.count > maximumRecordCount {
            entries.removeFirst(entries.count - maximumRecordCount)
        }

        candidate = RequestControlDiagnosticJournalDocument(
            schemaVersion: RequestControlDiagnosticJournalDocument.currentSchemaVersion,
            nextSequence: nextSequence,
            entries: entries
        )
        try Self.validate(candidate, maximumRecordCount: maximumRecordCount)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(candidate)
        try store.saveAtomicallyProtected(data)
        document = candidate
    }

    private static func validate(
        _ document: RequestControlDiagnosticJournalDocument,
        maximumRecordCount: Int
    ) throws {
        guard document.schemaVersion == RequestControlDiagnosticJournalDocument.currentSchemaVersion else {
            throw RequestControlDiagnosticJournalError.unsupportedSchema(document.schemaVersion)
        }
        guard document.nextSequence > 0,
              document.entries.count <= maximumRecordCount else {
            throw RequestControlDiagnosticJournalError.invalidSequence
        }

        var previousSequence: UInt64?
        for entry in document.entries {
            guard entry.sequence > 0 else {
                throw RequestControlDiagnosticJournalError.invalidSequence
            }
            if let previousSequence {
                guard previousSequence < UInt64.max,
                      entry.sequence == previousSequence + 1 else {
                    throw RequestControlDiagnosticJournalError.invalidSequence
                }
            }
            previousSequence = entry.sequence
        }

        if let last = document.entries.last {
            guard last.sequence < UInt64.max,
                  document.nextSequence == last.sequence + 1 else {
                throw RequestControlDiagnosticJournalError.invalidSequence
            }
        } else if document.nextSequence != 1 {
            throw RequestControlDiagnosticJournalError.invalidSequence
        }
    }

    private static func recoveryDetail(
        previousLast: RequestControlDiagnosticJournalEntry
    ) -> String {
        let closure = previousLast.kind == .disconnected
            ? "an explicit disconnect was recorded"
            : "no explicit disconnect was recorded; the process-exit cause and final Bluetooth state remain unknown"
        return "Recovered durable evidence through sequence \(previousLast.sequence); \(closure). Recovery grants no retry or write authority."
    }
}

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
    private let journal: any RequestControlDiagnosticJournaling

    init(
        underlying: any FTMSControlPointLink,
        gate: RequestControlWriteGate,
        journal: any RequestControlDiagnosticJournaling
    ) {
        self.underlying = underlying
        self.gate = gate
        self.journal = journal
    }

    func enableIndications() {
        underlying.enableIndications()
    }

    func writeWithResponse(_ data: Data) {
        do {
            try journal.record(
                .requestPathEntered,
                detail: "The explicit Request Control path was entered with bytes \(data.ftmsHex). No CoreBluetooth write has occurred."
            )
        } catch {
            blockBeforeWrite(stage: "recording the explicit trigger boundary", error: error)
            return
        }

        do {
            try gate.consume(data)
        } catch {
            let message = error.localizedDescription
            requestBlocked?(message)
            underlying.invalidate()
            eventHandler?(.writeDeliveryUnknown("Blocked locally before CoreBluetooth write. \(message)"))
            return
        }

        do {
            try journal.record(
                .gateConsumed,
                detail: "The persistent one-shot gate was consumed for exact bytes \(data.ftmsHex). No CoreBluetooth write has occurred."
            )
            try journal.record(
                .forwardingStarted,
                detail: "The next operation invokes CoreBluetooth Write With Response for exact bytes \(data.ftmsHex); delivery is unknown until later evidence."
            )
        } catch {
            blockBeforeWrite(stage: "sealing the consumed gate and forwarding boundary", error: error)
            return
        }

        underlying.writeWithResponse(data)
        requestSubmitted?(data)
    }

    func invalidate() {
        underlying.invalidate()
    }

    func abort(reason: String) {
        underlying.invalidate()
        eventHandler?(.indicationFailed(reason))
    }

    private func blockBeforeWrite(stage: String, error: Error) {
        let message = "Protected diagnostic journal failed while \(stage). No CoreBluetooth write occurred and no retry is authorised. \(error.localizedDescription)"
        requestBlocked?(message)
        underlying.invalidate()
        eventHandler?(.writeDeliveryUnknown(message))
    }
}

extension RequestControlDiagnosticEvent {
    var journalKind: RequestControlDiagnosticJournalKind {
        switch self {
        case .controlPointDiscovered: .controlPointDiscovered
        case .indicationSubscriptionSucceeded: .indicationSubscriptionSucceeded
        case .indicationSubscriptionFailed: .indicationSubscriptionFailed
        case .readiness: .readiness
        case .requestSubmitted: .requestSubmitted
        case .procedureSubmitted: .procedureSubmitted
        case .attAccepted: .attAccepted
        case .attRejected: .attRejected
        case .writeDeliveryUnknown: .writeDeliveryUnknown
        case .indication: .indicationReceived
        case .indicationFailed: .indicationFailed
        case .outcome: .outcome
        case .disconnectRequested: .disconnectRequested
        case .disconnected: .disconnected
        case .blocked: .blocked
        }
    }

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
