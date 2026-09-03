import Foundation

enum WorkoutImportEvaluationContract {
    static let corpusVersion = "workout-import-corpus/v1"
    static let caseContractVersion = "workout-import-case/v1"
    static let proposalContractVersion = "workout-proposal/v1"
    static let resultContractVersion = "workout-import-result/v1"
    static let scorerVersion = "workout-import-scorer/v1"
    static let promptTemplateVersion = "workout-import-prompt/v1"
    static let acceptedCorpusHash = "be6355a1afdd9d56a14c759e3da0ef836280091218a6f282d7a826029cade79c"
}

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Decimal)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct WorkoutImportManifest: Decodable, Equatable {
    struct CaseIndex: Decodable, Equatable {
        let id: String
        let category: String
    }

    let manifestVersion: Int
    let corpusVersion: String
    let caseContractVersion: String
    let proposalContractVersion: String
    let resultContractVersion: String
    let scorerVersion: String
    let promptTemplateVersion: String
    let supportedLocales: [String]
    let caseIndex: [CaseIndex]
    let hashContract: String
    let corpusHash: String
}

struct WorkoutImportCase: Decodable, Equatable {
    enum GeneratorCondition: String, Decodable {
        case normal
        case providerUnavailable
        case providerFailure
    }

    let caseContractVersion: String
    let id: String
    let category: String
    let locale: String
    let prompt: String
    let generatorCondition: GeneratorCondition
    let capabilities: WorkoutImportCapabilities

    private enum CodingKeys: String, CodingKey {
        case caseContractVersion, id, category, locale, prompt, generatorCondition, capabilities
    }
}

struct WorkoutImportCapabilities: Codable, Equatable, Sendable {
    let speed: WorkoutImportCapability
    let inclination: WorkoutImportCapability
}

struct WorkoutImportCapability: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case unknown
        case unsupported
        case supported
    }

    let state: State
    let minimum: Decimal?
    let maximum: Decimal?
    let increment: Decimal?
}

struct WorkoutProposalV1: Codable, Equatable, Sendable {
    let contractVersion: String
    let suggestedName: String
    let activity: String
    let steps: [WorkoutProposalStepV1]
}

struct WorkoutProposalStepV1: Codable, Equatable, Sendable {
    let kind: String
    let label: String
    let duration: WorkoutProposalQuantityV1
    let targetSpeed: WorkoutProposalQuantityV1
    let targetInclination: WorkoutProposalQuantityV1
}

struct WorkoutProposalQuantityV1: Codable, Equatable, Sendable {
    let value: Decimal
    let unit: String
}

enum NormalizedGeneratorOutcome: Equatable, Sendable {
    case proposal(WorkoutProposalV1)
    case clarificationRequired(reasonCategory: String, affectedPaths: [String])
    case unsupportedRequest(reasonCategory: String, affectedPaths: [String])
    case refusal(reasonCategory: String, affectedPaths: [String])
    case providerUnavailable(reasonCategory: String, affectedPaths: [String])
    case providerFailure(reasonCategory: String, affectedPaths: [String])

    var type: String {
        switch self {
        case .proposal: return "proposal"
        case .clarificationRequired: return "clarificationRequired"
        case .unsupportedRequest: return "unsupportedRequest"
        case .refusal: return "refusal"
        case .providerUnavailable: return "providerUnavailable"
        case .providerFailure: return "providerFailure"
        }
    }
}

extension NormalizedGeneratorOutcome: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, proposal, reasonCategory, affectedPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "proposal":
            self = .proposal(try container.decode(WorkoutProposalV1.self, forKey: .proposal))
        case "clarificationRequired":
            self = .clarificationRequired(
                reasonCategory: try container.decode(String.self, forKey: .reasonCategory),
                affectedPaths: try container.decode([String].self, forKey: .affectedPaths)
            )
        case "unsupportedRequest":
            self = .unsupportedRequest(
                reasonCategory: try container.decode(String.self, forKey: .reasonCategory),
                affectedPaths: try container.decode([String].self, forKey: .affectedPaths)
            )
        case "refusal":
            self = .refusal(
                reasonCategory: try container.decode(String.self, forKey: .reasonCategory),
                affectedPaths: try container.decode([String].self, forKey: .affectedPaths)
            )
        case "providerUnavailable":
            self = .providerUnavailable(
                reasonCategory: try container.decode(String.self, forKey: .reasonCategory),
                affectedPaths: try container.decode([String].self, forKey: .affectedPaths)
            )
        case "providerFailure":
            self = .providerFailure(
                reasonCategory: try container.decode(String.self, forKey: .reasonCategory),
                affectedPaths: try container.decode([String].self, forKey: .affectedPaths)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported normalized outcome."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case let .proposal(proposal):
            try container.encode(proposal, forKey: .proposal)
        case let .clarificationRequired(reason, paths),
             let .unsupportedRequest(reason, paths),
             let .refusal(reason, paths),
             let .providerUnavailable(reason, paths),
             let .providerFailure(reason, paths):
            try container.encode(reason, forKey: .reasonCategory)
            try container.encode(paths, forKey: .affectedPaths)
        }
    }
}

struct GeneratorStructureError: Codable, Equatable, Sendable {
    let code: String
    let path: String
}

enum NormalizedObservedResult: Equatable, Sendable {
    case valid(NormalizedGeneratorOutcome)
    case invalidGeneratorOutput([GeneratorStructureError])
}

extension NormalizedObservedResult: Codable {
    private enum CodingKeys: String, CodingKey {
        case structure, outcome, errors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .structure) {
        case "valid":
            self = .valid(try container.decode(NormalizedGeneratorOutcome.self, forKey: .outcome))
        case "invalidGeneratorOutput":
            self = .invalidGeneratorOutput(try container.decode([GeneratorStructureError].self, forKey: .errors))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .structure,
                in: container,
                debugDescription: "Unsupported generator structure state."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .valid(outcome):
            try container.encode("valid", forKey: .structure)
            try container.encode(outcome, forKey: .outcome)
        case let .invalidGeneratorOutput(errors):
            try container.encode("invalidGeneratorOutput", forKey: .structure)
            try container.encode(errors, forKey: .errors)
        }
    }
}

enum OperationalMeasurement: Equatable, Sendable {
    case measured(name: String, value: Decimal, unit: String)
    case unmeasured(name: String, reason: String)
}

extension OperationalMeasurement: Codable {
    private enum CodingKeys: String, CodingKey { case name, status, value, unit, reason }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        switch try container.decode(String.self, forKey: .status) {
        case "measured":
            self = .measured(
                name: name,
                value: try container.decode(Decimal.self, forKey: .value),
                unit: try container.decode(String.self, forKey: .unit)
            )
        case "unmeasured":
            self = .unmeasured(name: name, reason: try container.decode(String.self, forKey: .reason))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Unsupported measurement status."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .measured(name, value, unit):
            try container.encode(name, forKey: .name)
            try container.encode("measured", forKey: .status)
            try container.encode(value, forKey: .value)
            try container.encode(unit, forKey: .unit)
        case let .unmeasured(name, reason):
            try container.encode(name, forKey: .name)
            try container.encode("unmeasured", forKey: .status)
            try container.encode(reason, forKey: .reason)
        }
    }
}

struct EvaluationCaseResult: Codable, Equatable, Sendable {
    let resultID: String
    let caseID: String
    let repetitionIndex: Int
    let observed: NormalizedObservedResult
    let claimedAuthorities: [String]
    let operationalMeasurements: [OperationalMeasurement]
}

struct EvaluationKeyValue: Codable, Equatable, Sendable {
    let key: String
    let value: String
}

enum AvailableString: Equatable, Sendable {
    case available(String)
    case unavailable(String)
}

extension AvailableString: Codable {
    private enum CodingKeys: String, CodingKey { case status, value, reason }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .status) {
        case "available": self = .available(try container.decode(String.self, forKey: .value))
        case "unavailable": self = .unavailable(try container.decode(String.self, forKey: .reason))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Unsupported availability value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .available(value):
            try container.encode("available", forKey: .status)
            try container.encode(value, forKey: .value)
        case let .unavailable(reason):
            try container.encode("unavailable", forKey: .status)
            try container.encode(reason, forKey: .reason)
        }
    }
}

struct EvaluationRunProvenance: Codable, Equatable, Sendable {
    let runID: String
    let appCommit: String
    let corpusVersion: String
    let corpusHash: String
    let proposalContractVersion: String
    let promptTemplateVersion: String
    let scorerVersion: String
    let evidenceLevel: String
    let deviceClass: String
    let osVersion: String
    let locale: String
    let providerID: String
    let modelID: String
    let modelRevision: AvailableString
    let routingConstraints: [EvaluationKeyValue]
    let inferenceParameters: [EvaluationKeyValue]
    let networkCondition: String
    let runConfigurationID: String
    let startedAt: String
    let endedAt: String
    let measurementTools: [String]
}

struct NormalizedEvaluationRun: Codable, Equatable, Sendable {
    let resultContractVersion: String
    let provenance: EvaluationRunProvenance
    let results: [EvaluationCaseResult]
}
