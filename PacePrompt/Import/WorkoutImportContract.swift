import Foundation

struct WorkoutProposal: Equatable {
    let contractVersion = "workout-proposal/v1"
    let suggestedName: String
    let activity: WorkoutActivity
    let steps: [Step]

    struct Value: Equatable {
        let number: ImportJSON
        let unit: String
    }
    struct Step: Equatable {
        let kind: WorkoutStepKind
        let label: String
        let duration: Value
        let speed: Value
        let inclination: Value
    }
}

struct ImportProblem: Equatable {
    let reason: String
    let paths: [String]
}

enum WorkoutImportOutcome: Equatable {
    case proposal(WorkoutProposal)
    case clarificationRequired(ImportProblem)
    case unsupportedRequest(ImportProblem)
    case refusal(ImportProblem)
    case providerUnavailable(ImportFailure)
    case providerFailure(ImportFailure)
}

enum WorkoutProposalMapper {
    static func map(_ proposal: WorkoutProposal) throws -> WorkoutPlan {
        guard proposal.contractVersion == "workout-proposal/v1" else { throw ImportFailure.structure }
        return try WorkoutPlan(schemaVersion: 1, suggestedName: proposal.suggestedName,
                               activity: proposal.activity, steps: proposal.steps.map { step in
            guard ["seconds", "minutes"].contains(step.duration.unit),
                  ["kilometresPerHour", "milesPerHour"].contains(step.speed.unit),
                  step.inclination.unit == "percent" else { throw ImportFailure.mapping }
            let seconds = try ExactImportDecimal.multiply(step.duration.number.decimal(), step.duration.unit == "minutes" ? 60 : 1)
            guard let duration = Int(NSDecimalNumber(decimal: seconds).stringValue),
                  Decimal(duration) == seconds else { throw ImportFailure.mapping }
            let speed = try ExactImportDecimal.multiply(step.speed.number.decimal(),
                step.speed.unit == "milesPerHour" ? ExactImportDecimal.parse("1.609344") : 1)
            return try WorkoutStep(kind: step.kind, label: step.label,
                duration: .init(value: duration, unit: .seconds),
                targetSpeed: .init(value: speed, unit: .kilometresPerHour),
                targetInclination: .init(value: step.inclination.number.decimal(), unit: .percent))
        })
    }
}

// Deliberately independent of the evaluation parser, scorer and provider adapter.
enum WorkoutImportContract {
    static let model = "openai/gpt-5.6-sol"
    static let revision = "openai/gpt-5.6-sol-20260709"
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    static let pathOrder = ["activity", "steps", "steps.repetitions", "steps.kind", "steps.duration",
        "steps.duration.value", "steps.duration.unit", "steps.targetSpeed", "steps.targetSpeed.value",
        "steps.targetSpeed.unit", "steps.targetInclination", "steps.targetInclination.value",
        "steps.targetInclination.unit", "capabilities.speed", "capabilities.inclination"]

    static func parseEnvelope(_ data: Data) throws -> WorkoutImportOutcome {
        let root = try StrictImportJSON.parse(data)
        guard let rootFields = root.object else { throw ImportFailure.structure }
        guard rootFields["model"] != nil else { throw ImportFailure.identityModelMissing }
        guard rootFields["provider"] != nil else { throw ImportFailure.identityProviderMissing }
        let o = try root.fields(required: ["id", "object", "created", "model", "provider", "choices"],
                                optional: ["system_fingerprint", "usage", "service_tier"])
        try validateIdentity(model: o["model"]!, provider: o["provider"]!)
        guard let id = o["id"]?.string, !id.isEmpty, o["object"] == .string("chat.completion"),
              try o["created"]!.integer() >= 0,
              let choices = o["choices"]?.array, choices.count == 1 else { throw ImportFailure.structure }
        if let fingerprint = o["system_fingerprint"], fingerprint != .null, fingerprint.string == nil { throw ImportFailure.structure }
        if let tier = o["service_tier"], tier != .null, tier != .string("default") {
            throw ImportFailure.identityServiceTier
        }
        if let usage = o["usage"] { try validateUsage(usage) }
        let choice = try choices[0].fields(required: ["index", "finish_reason", "message"], optional: ["native_finish_reason", "logprobs"])
        guard try choice["index"]!.integer() == 0, choice["finish_reason"] == .string("stop") else { throw ImportFailure.structure }
        if let native = choice["native_finish_reason"], native != .string("stop") { throw ImportFailure.structure }
        if let logs = choice["logprobs"], logs != .null { throw ImportFailure.structure }
        let message = try choice["message"]!.fields(required: ["role", "content"],
            optional: ["refusal", "reasoning", "reasoning_details", "tool_calls", "model"])
        guard message["role"] == .string("assistant"), let content = message["content"]?.string else { throw ImportFailure.structure }
        for key in ["refusal", "reasoning"] {
            if let value = message[key], value != .null, value != .string("") { throw ImportFailure.structure }
        }
        for key in ["reasoning_details", "tool_calls"] {
            if let value = message[key], value != .array([]) { throw ImportFailure.structure }
        }
        if let model = message["model"], model != .string(revision) {
            throw ImportFailure.identityMessageModel
        }
        return try parseModelOutput(Data(content.utf8))
    }

    private static func validateIdentity(model value: ImportJSON, provider: ImportJSON) throws {
        guard let returned = value.string else { throw ImportFailure.identityModelNonString }
        guard [ImportJSON.string("openai"), .string("OpenAI")].contains(provider) else {
            throw ImportFailure.identityProviderMismatch
        }
        switch returned {
        case revision, model: return
        case String(revision.dropFirst("openai/".count)):
            throw ImportFailure.identityModelRevisionWithoutProvider
        default: throw ImportFailure.identityModelMismatch
        }
    }

    static func parseModelOutput(_ data: Data) throws -> WorkoutImportOutcome {
        let root = try StrictImportJSON.parse(data)
        _ = try root.fields(required: ["contractVersion", "outcome"])
        guard root["contractVersion"] == .string("workout-import-model-output/v2"), let outcome = root["outcome"] else { throw ImportFailure.structure }
        let o = try outcome.fields(required: ["type", "proposal", "reasonCategory", "affectedPaths"])
        guard let type = o["type"]?.string, let reason = o["reasonCategory"]?.string,
              let pathValues = o["affectedPaths"]?.array, pathValues.count <= 15 else { throw ImportFailure.structure }
        let paths = try pathValues.map { value -> String in
            guard let path = value.string, pathOrder.contains(path) else { throw ImportFailure.structure }; return path
        }
        guard pathOrder.filter({ paths.contains($0) }) == paths else { throw ImportFailure.structure }
        let p = try o["proposal"]!.fields(required: ["present", "contractVersion", "suggestedName", "activity", "steps"])
        if type == "proposal" {
            guard reason == "notApplicable", paths.isEmpty, p["present"] == .bool(true),
                  p["contractVersion"] == .string("workout-proposal/v2"),
                  let name = p["suggestedName"]?.string, let rawActivity = p["activity"]?.string,
                  let activity = WorkoutActivity(rawValue: rawActivity),
                  let wireSteps = p["steps"]?.array, (1...64).contains(wireSteps.count) else { throw ImportFailure.structure }
            let steps = try wireSteps.map { wire -> WorkoutProposal.Step in
                let s = try wire.fields(required: ["kind", "label", "duration", "targetSpeed", "targetInclination"])
                guard let rawKind = s["kind"]?.string, let kind = WorkoutStepKind(rawValue: rawKind),
                      let label = s["label"]?.string else { throw ImportFailure.structure }
                let duration = try value(s["duration"]!, units: ["seconds", "minutes"])
                // Preserve mapping errors separately; sign is determined lexically without rounding.
                guard case let .number(token) = duration.number,
                      !token.hasPrefix("-"), token.lowercased().split(separator: "e")[0].contains(where: { "123456789".contains($0) }) else { throw ImportFailure.structure }
                return try .init(kind: kind, label: label, duration: duration,
                    speed: value(s["targetSpeed"]!, units: ["kilometresPerHour", "milesPerHour"]),
                    inclination: value(s["targetInclination"]!, units: ["percent"]))
            }
            return .proposal(.init(suggestedName: name, activity: activity, steps: steps))
        }
        guard p == ["present": .bool(false), "contractVersion": .string("notApplicable"),
                    "suggestedName": .string(""), "activity": .string("notApplicable"), "steps": .array([])] else { throw ImportFailure.structure }
        let problem = ImportProblem(reason: reason, paths: paths)
        switch type {
        case "clarificationRequired" where ["missingRequiredField", "ambiguousRequiredField", "contradictoryRequest"].contains(reason):
            return .clarificationRequired(problem)
        case "unsupportedRequest" where ["outOfDomain", "unsupportedActivity", "unsupportedTarget", "unsupportedUnit", "unsupportedOperation", "knownCapabilityUnsupported", "excessiveComplexity"].contains(reason):
            if reason == "unsupportedActivity", paths != ["activity"] { throw ImportFailure.structure }
            if reason == "unsupportedOperation", !paths.isEmpty { throw ImportFailure.structure }
            if reason == "knownCapabilityUnsupported", paths != ["capabilities.speed"], paths != ["capabilities.inclination"] { throw ImportFailure.structure }
            return .unsupportedRequest(problem)
        case "refusal" where ["promptInjection", "unsafeRequest", "medicalRequest"].contains(reason) && paths.isEmpty:
            return .refusal(problem)
        default: throw ImportFailure.structure
        }
    }
    private static func value(_ wire: ImportJSON, units: [String]) throws -> WorkoutProposal.Value {
        let o = try wire.fields(required: ["value", "unit"])
        guard let unit = o["unit"]?.string, units.contains(unit), case .number = o["value"]! else { throw ImportFailure.structure }
        return .init(number: o["value"]!, unit: unit)
    }
    private static func validateUsage(_ wire: ImportJSON) throws {
        let o = try wire.fields(required: ["prompt_tokens", "completion_tokens", "total_tokens"],
            optional: ["cost", "is_byok", "prompt_tokens_details", "completion_tokens_details", "cost_details"])
        let prompt = try o["prompt_tokens"]!.integer(), completion = try o["completion_tokens"]!.integer()
        let (sum, overflow) = prompt.addingReportingOverflow(completion)
        guard prompt >= 0, completion >= 0, !overflow, try o["total_tokens"]!.integer() == sum else { throw ImportFailure.structure }
        if let cost = o["cost"], cost != .null, try cost.decimal() < 0 { throw ImportFailure.structure }
        if let byok = o["is_byok"], case .bool = byok {} else if o["is_byok"] != nil { throw ImportFailure.structure }
        try detail(o["prompt_tokens_details"], keys: ["cached_tokens", "cache_write_tokens", "audio_tokens", "video_tokens"], integer: true, nullable: false)
        try detail(o["completion_tokens_details"], keys: ["reasoning_tokens", "audio_tokens", "accepted_prediction_tokens", "rejected_prediction_tokens"], integer: true, nullable: true)
        try detail(o["cost_details"], keys: ["upstream_inference_cost", "upstream_inference_prompt_cost", "upstream_inference_completions_cost"], integer: false, nullable: true)
    }
#if DEBUG
    static func parseEnvelopeUsageForDiagnostics(_ wire: ImportJSON) throws {
        try validateUsage(wire)
    }
#endif
    private static func detail(_ wire: ImportJSON?, keys: Set<String>, integer: Bool, nullable: Bool) throws {
        guard let wire, wire != .null else { return }
        let o = try wire.fields(required: [], optional: keys)
        for value in o.values {
            if nullable && value == .null { continue }
            if integer { guard try value.integer() >= 0 else { throw ImportFailure.structure } }
            else { guard try value.decimal() >= 0 else { throw ImportFailure.structure } }
        }
    }
}
