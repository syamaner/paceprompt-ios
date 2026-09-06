#if DEBUG
import Foundation
import OSLog

enum ImportDiagnosticStage: String, CaseIterable, Hashable {
    case disclosure
    case requestLifecycle
    case transport
    case endpoint
    case status
    case contentType
    case outerJSONSyntax
    case outerFieldAllowlist
    case outerContract
    case modelClassification
    case providerClassification
    case serviceTier
    case usageContract
    case choiceCount
    case choiceFieldAllowlist
    case choiceIndex
    case finishReason
    case nativeFinishReason
    case logprobs
    case messageFieldAllowlist
    case messageRole
    case messageContent
    case refusal
    case reasoning
    case reasoningDetails
    case toolCalls
    case messageModel
    case structuredContentJSON
    case structuredContentContract
    case deterministicMapping
    case localCapabilityValidation
    case previewEligibility
    case terminalOutcome
}

enum ImportDiagnosticResult: String {
    case accepted
    case rejected
    case started
    case completed
    case cancelled
    case present
    case absent
}

enum ImportDiagnosticClassification: String {
    case missing
    case canonicalModel
    case requestedModel
    case revisionWithoutProvider
    case nonString
    case other
    case providerIdentifier
    case providerName
    case defaultTier
    case nullOrAbsent
    case zero
    case one
    case multiple
    case nonArray
    case nonzero
    case nonInteger
    case stop
    case completed
    case otherString
    case nullValue
    case emptyString
    case nonEmptyString
    case emptyArray
    case nonEmptyArray
    case assistant
    case otherRole
}

enum ImportDiagnosticStatusClass: String {
    case informational
    case success
    case redirection
    case clientError
    case serverError
    case invalid

    init(_ status: Int) {
        switch status {
        case 100..<200: self = .informational
        case 200..<300: self = .success
        case 300..<400: self = .redirection
        case 400..<500: self = .clientError
        case 500..<600: self = .serverError
        default: self = .invalid
        }
    }
}

enum ImportDiagnosticElapsedBucket: String {
    case underOneSecond
    case oneToFiveSeconds
    case fiveToThirtySeconds
    case thirtyToSixtySeconds
    case overSixtySeconds

    init(seconds: TimeInterval) {
        switch seconds {
        case ..<1: self = .underOneSecond
        case ..<5: self = .oneToFiveSeconds
        case ..<30: self = .fiveToThirtySeconds
        case ..<60: self = .thirtyToSixtySeconds
        default: self = .overSixtySeconds
        }
    }
}

enum ImportDiagnosticTerminal: String {
    case previewEligible
    case clarificationRequired
    case unsupportedRequest
    case refusal
    case providerUnavailable
    case providerFailure
    case mappingFailure
    case localValidationFailure
    case saveFailure
    case saved
    case cancelled
}

enum ImportDiagnosticEvent: Equatable {
    case check(ImportDiagnosticStage, ImportDiagnosticResult)
    case classification(ImportDiagnosticStage, ImportDiagnosticClassification)
    case statusClass(ImportDiagnosticStatusClass)
    case requestCount(Int)
    case elapsed(ImportDiagnosticElapsedBucket)
    case terminal(ImportDiagnosticTerminal)

    var stage: ImportDiagnosticStage? {
        switch self {
        case let .check(stage, _), let .classification(stage, _): stage
        case .statusClass: .status
        case .requestCount, .elapsed: .requestLifecycle
        case .terminal: .terminalOutcome
        }
    }

    var code: String {
        switch self {
        case let .check(stage, result): "check.\(stage.rawValue).\(result.rawValue)"
        case let .classification(stage, value): "classification.\(stage.rawValue).\(value.rawValue)"
        case let .statusClass(value): "statusClass.\(value.rawValue)"
        case let .requestCount(value): "requestCount.\(value)"
        case let .elapsed(value): "elapsed.\(value.rawValue)"
        case let .terminal(value): "terminal.\(value.rawValue)"
        }
    }
}

protocol ImportDiagnosticSink: AnyObject {
    func record(_ event: ImportDiagnosticEvent)
}

final class UnifiedImportDiagnosticSink: ImportDiagnosticSink {
    static let shared = UnifiedImportDiagnosticSink()
    private static let logger = Logger(subsystem: "com.paceprompt.app", category: "WorkoutImportValidation")

    private init() {}

    func record(_ event: ImportDiagnosticEvent) {
        Self.logger.debug("paceprompt.import.\(event.code, privacy: .public)")
    }
}

enum ImportDiagnosticInspector {
    static func inspectEnvelope(_ data: Data, sink: any ImportDiagnosticSink) {
        let root: ImportJSON
        do {
            root = try StrictImportJSON.parse(data)
            sink.record(.check(.outerJSONSyntax, .accepted))
        } catch {
            sink.record(.check(.outerJSONSyntax, .rejected))
            return
        }

        guard let fields = root.object else {
            sink.record(.check(.outerFieldAllowlist, .rejected))
            return
        }
        classifyModel(fields["model"], sink: sink)
        classifyProvider(fields["provider"], sink: sink)

        do {
            _ = try root.fields(
                required: ["id", "object", "created", "model", "provider", "choices"],
                optional: ["system_fingerprint", "usage", "service_tier"]
            )
            sink.record(.check(.outerFieldAllowlist, .accepted))
        } catch {
            sink.record(.check(.outerFieldAllowlist, .rejected))
            return
        }

        guard modelAccepted(fields["model"]), providerAccepted(fields["provider"]) else { return }
        do {
            guard let id = fields["id"]?.string, !id.isEmpty,
                  fields["object"] == .string("chat.completion"),
                  try fields["created"]!.integer() >= 0 else {
                sink.record(.check(.outerContract, .rejected))
                return
            }
            sink.record(.check(.outerContract, .accepted))
        } catch {
            sink.record(.check(.outerContract, .rejected))
            return
        }

        let tierAccepted: Bool
        switch fields["service_tier"] {
        case nil, .some(.null):
            sink.record(.classification(.serviceTier, .nullOrAbsent)); tierAccepted = true
        case .some(.string("default")):
            sink.record(.classification(.serviceTier, .defaultTier)); tierAccepted = true
        case .some(.string):
            sink.record(.classification(.serviceTier, .otherString)); tierAccepted = false
        default:
            sink.record(.classification(.serviceTier, .nonString)); tierAccepted = false
        }
        sink.record(.check(.serviceTier, tierAccepted ? .accepted : .rejected))
        guard tierAccepted else { return }

        if let usage = fields["usage"] {
            do {
                _ = try WorkoutImportContract.parseEnvelopeUsageForDiagnostics(usage)
                sink.record(.check(.usageContract, .accepted))
            } catch {
                sink.record(.check(.usageContract, .rejected))
                return
            }
        } else {
            sink.record(.check(.usageContract, .absent))
        }

        guard let choices = fields["choices"]?.array else {
            sink.record(.classification(.choiceCount, .nonArray))
            sink.record(.check(.choiceCount, .rejected))
            return
        }
        switch choices.count {
        case 0: sink.record(.classification(.choiceCount, .zero))
        case 1: sink.record(.classification(.choiceCount, .one))
        default: sink.record(.classification(.choiceCount, .multiple))
        }
        sink.record(.check(.choiceCount, choices.count == 1 ? .accepted : .rejected))
        guard choices.count == 1 else { return }

        let choice: [String: ImportJSON]
        do {
            choice = try choices[0].fields(
                required: ["index", "finish_reason", "message"],
                optional: ["native_finish_reason", "logprobs"]
            )
            sink.record(.check(.choiceFieldAllowlist, .accepted))
        } catch {
            sink.record(.check(.choiceFieldAllowlist, .rejected))
            return
        }

        let indexAccepted: Bool
        do {
            let index = try choice["index"]!.integer()
            sink.record(.classification(.choiceIndex, index == 0 ? .zero : .nonzero))
            indexAccepted = index == 0
        } catch {
            sink.record(.classification(.choiceIndex, .nonInteger)); indexAccepted = false
        }
        sink.record(.check(.choiceIndex, indexAccepted ? .accepted : .rejected))
        guard indexAccepted else { return }

        let finishAccepted = classifyString(choice["finish_reason"], stage: .finishReason, sink: sink) == .stop
        sink.record(.check(.finishReason, finishAccepted ? .accepted : .rejected))
        guard finishAccepted else { return }

        let native = classifyString(choice["native_finish_reason"], stage: .nativeFinishReason, sink: sink)
        let nativeAccepted = native == .missing || native == .stop || native == .completed
        sink.record(.check(.nativeFinishReason, nativeAccepted ? .accepted : .rejected))
        guard nativeAccepted else { return }

        let logprobsAccepted: Bool
        switch choice["logprobs"] {
        case nil:
            sink.record(.classification(.logprobs, .missing)); logprobsAccepted = true
        case .some(.null):
            sink.record(.classification(.logprobs, .nullValue)); logprobsAccepted = true
        default:
            sink.record(.classification(.logprobs, .other)); logprobsAccepted = false
        }
        sink.record(.check(.logprobs, logprobsAccepted ? .accepted : .rejected))
        guard logprobsAccepted else { return }

        let message: [String: ImportJSON]
        do {
            message = try choice["message"]!.fields(
                required: ["role", "content"],
                optional: ["refusal", "reasoning", "reasoning_details", "tool_calls", "model"]
            )
            sink.record(.check(.messageFieldAllowlist, .accepted))
        } catch {
            sink.record(.check(.messageFieldAllowlist, .rejected))
            return
        }

        let roleAccepted = message["role"] == .string("assistant")
        sink.record(.classification(.messageRole, roleAccepted ? .assistant : .otherRole))
        sink.record(.check(.messageRole, roleAccepted ? .accepted : .rejected))
        guard roleAccepted else { return }

        guard let content = message["content"]?.string else {
            sink.record(.check(.messageContent, .rejected))
            return
        }
        sink.record(.check(.messageContent, .accepted))

        guard inspectNullableEmptyString(message["refusal"], stage: .refusal, sink: sink),
              inspectNullableEmptyString(message["reasoning"], stage: .reasoning, sink: sink),
              inspectEmptyArray(message["reasoning_details"], stage: .reasoningDetails, sink: sink),
              inspectEmptyArray(message["tool_calls"], stage: .toolCalls, sink: sink) else { return }

        let messageModelAccepted: Bool
        switch message["model"] {
        case nil:
            sink.record(.classification(.messageModel, .missing)); messageModelAccepted = true
        case .some(.string(WorkoutImportContract.revision)):
            sink.record(.classification(.messageModel, .canonicalModel)); messageModelAccepted = true
        case .some(.string):
            sink.record(.classification(.messageModel, .otherString)); messageModelAccepted = false
        default:
            sink.record(.classification(.messageModel, .nonString)); messageModelAccepted = false
        }
        sink.record(.check(.messageModel, messageModelAccepted ? .accepted : .rejected))
        guard messageModelAccepted else { return }

        inspectStructuredContent(Data(content.utf8), sink: sink)
    }

    private static func inspectStructuredContent(_ data: Data, sink: any ImportDiagnosticSink) {
        do {
            _ = try StrictImportJSON.parse(data)
            sink.record(.check(.structuredContentJSON, .accepted))
        } catch {
            sink.record(.check(.structuredContentJSON, .rejected))
            return
        }
        do {
            _ = try WorkoutImportContract.parseModelOutput(data)
            sink.record(.check(.structuredContentContract, .accepted))
        } catch {
            sink.record(.check(.structuredContentContract, .rejected))
        }
    }

    private static func classifyModel(_ value: ImportJSON?, sink: any ImportDiagnosticSink) {
        let result: ImportDiagnosticClassification
        switch value {
        case nil: result = .missing
        case .some(.string(WorkoutImportContract.revision)): result = .canonicalModel
        case .some(.string(WorkoutImportContract.model)): result = .requestedModel
        case .some(.string(String(WorkoutImportContract.revision.dropFirst("openai/".count)))): result = .revisionWithoutProvider
        case .some(.string): result = .other
        default: result = .nonString
        }
        sink.record(.classification(.modelClassification, result))
        sink.record(.check(.modelClassification, modelAccepted(value) ? .accepted : .rejected))
    }

    private static func classifyProvider(_ value: ImportJSON?, sink: any ImportDiagnosticSink) {
        let result: ImportDiagnosticClassification
        switch value {
        case nil: result = .missing
        case .some(.string("openai")): result = .providerIdentifier
        case .some(.string("OpenAI")): result = .providerName
        case .some(.string): result = .other
        default: result = .nonString
        }
        sink.record(.classification(.providerClassification, result))
        sink.record(.check(.providerClassification, providerAccepted(value) ? .accepted : .rejected))
    }

    private static func modelAccepted(_ value: ImportJSON?) -> Bool {
        value == .string(WorkoutImportContract.revision) || value == .string(WorkoutImportContract.model)
    }

    private static func providerAccepted(_ value: ImportJSON?) -> Bool {
        value == .string("openai") || value == .string("OpenAI")
    }

    private static func classifyString(
        _ value: ImportJSON?,
        stage: ImportDiagnosticStage,
        sink: any ImportDiagnosticSink
    ) -> ImportDiagnosticClassification {
        let result: ImportDiagnosticClassification
        switch value {
        case nil: result = .missing
        case .some(.null): result = .nullValue
        case .some(.string("stop")): result = .stop
        case .some(.string("completed")): result = .completed
        case .some(.string): result = .otherString
        default: result = .nonString
        }
        sink.record(.classification(stage, result))
        return result
    }

    private static func inspectNullableEmptyString(
        _ value: ImportJSON?,
        stage: ImportDiagnosticStage,
        sink: any ImportDiagnosticSink
    ) -> Bool {
        let classification: ImportDiagnosticClassification
        let accepted: Bool
        switch value {
        case nil:
            classification = .missing; accepted = true
        case .some(.null):
            classification = .nullValue; accepted = true
        case .some(.string("")):
            classification = .emptyString; accepted = true
        case .some(.string):
            classification = .nonEmptyString; accepted = false
        default:
            classification = .nonString; accepted = false
        }
        sink.record(.classification(stage, classification))
        sink.record(.check(stage, accepted ? .accepted : .rejected))
        return accepted
    }

    private static func inspectEmptyArray(
        _ value: ImportJSON?,
        stage: ImportDiagnosticStage,
        sink: any ImportDiagnosticSink
    ) -> Bool {
        let classification: ImportDiagnosticClassification
        let accepted: Bool
        switch value {
        case nil:
            classification = .missing; accepted = true
        case .some(.array([])):
            classification = .emptyArray; accepted = true
        case .some(.array):
            classification = .nonEmptyArray; accepted = false
        default:
            classification = .other; accepted = false
        }
        sink.record(.classification(stage, classification))
        sink.record(.check(stage, accepted ? .accepted : .rejected))
        return accepted
    }
}
#endif
