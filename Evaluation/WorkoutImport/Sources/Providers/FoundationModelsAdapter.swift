import Foundation
import FoundationModels

struct AppleFoundationModelsConfiguration: Sendable {
    let modelID: String
    let modelRevision: AvailableString
    let model: SystemLanguageModel
    let generationOptions: GenerationOptions
    let inferenceProvenance: [EvaluationKeyValue]

    init(
        modelID: String,
        modelRevision: AvailableString,
        model: SystemLanguageModel,
        generationOptions: GenerationOptions,
        inferenceProvenance: [EvaluationKeyValue]
    ) throws {
        guard !modelID.isEmpty else {
            throw EvaluationRunConfigurationError.invalid("Apple modelID is required")
        }
        guard Set(inferenceProvenance.map(\.key)).count == inferenceProvenance.count else {
            throw EvaluationRunConfigurationError.invalid("Apple inference provenance keys must be unique")
        }
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.model = model
        self.generationOptions = generationOptions
        self.inferenceProvenance = inferenceProvenance
    }
}

struct AppleFoundationModelsAdapter: WorkoutProposalProvider {
    let configuration: AppleFoundationModelsConfiguration

    var identity: EvaluationProviderIdentity {
        EvaluationProviderIdentity(
            providerID: "apple-foundation-models",
            modelID: configuration.modelID,
            modelRevision: configuration.modelRevision
        )
    }

    var declaredRoutingConstraints: [EvaluationKeyValue] { [] }
    var declaredInferenceParameters: [EvaluationKeyValue] { configuration.inferenceProvenance }

    func readiness(for request: WorkoutProposalGenerationRequest) async -> ProviderReadiness {
        let modelState: ProviderAvailabilityState
        switch configuration.model.availability {
        case .available:
            modelState = .available
        case let .unavailable(reason):
            modelState = .unavailable(reason: availabilityReason(reason))
        }
        let localeState: ProviderAvailabilityState = configuration.model.supportsLocale(
            Locale(identifier: request.locale)
        ) ? .available : .unavailable(reason: "localeUnsupported")
        return ProviderReadiness(runtime: .available, model: modelState, locale: localeState)
    }

    func generate(_ request: WorkoutProposalGenerationRequest) async -> ProviderInvocationResult {
        if Task.isCancelled { return .cancelled }
        let readiness = await readiness(for: request)
        guard readiness.isReady else {
            return .unavailable(reasonCategory: readiness.firstUnavailableReason ?? "runtimeUnavailable")
        }
        let session = LanguageModelSession(
            model: configuration.model,
            tools: [],
            instructions: WorkoutImportPromptTemplate.instructions(
                contractVersion: request.proposalContractVersion
            )
        )
        let started = Date()
        do {
            let response = try await session.respond(
                to: WorkoutImportPromptTemplate.request(request),
                generating: AppleGeneratedOutcome.self,
                options: configuration.generationOptions
            )
            let outcome = response.content.normalized
            let data = try JSONEncoder().encode(outcome)
            return .complete(
                data,
                measurements: [
                    .measured(
                        name: "completeResponseLatency",
                        value: decimalMilliseconds(since: started),
                        unit: "milliseconds"
                    ),
                    .unmeasured(name: "inputTokens", reason: "Foundation Models did not report this field"),
                    .unmeasured(name: "cachedInputTokens", reason: "Foundation Models did not report this field"),
                    .unmeasured(name: "outputTokens", reason: "Foundation Models did not report this field"),
                    .unmeasured(name: "providerReportedCost", reason: "on-device generation has no provider-reported cost")
                ]
            )
        } catch is CancellationError {
            return .cancelled
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .refusal:
                return encoded(.refusal(reasonCategory: "providerRefusal", affectedPaths: []))
            case .guardrailViolation:
                return encoded(.refusal(reasonCategory: "guardrailViolation", affectedPaths: []))
            case .unsupportedLanguageOrLocale:
                return .unavailable(reasonCategory: "localeUnsupported")
            case .assetsUnavailable:
                return .unavailable(reasonCategory: "modelNotReady")
            case .decodingFailure:
                return .invalidGeneratorOutput(code: "guidedGenerationDecodingFailure", path: "$")
            case .rateLimited:
                return .failure(reasonCategory: "rateLimited")
            case .exceededContextWindowSize:
                return .failure(reasonCategory: "contextWindowExceeded")
            case .unsupportedGuide:
                return .failure(reasonCategory: "unsupportedGenerationGuide")
            case .concurrentRequests:
                return .failure(reasonCategory: "concurrentRequest")
            @unknown default:
                return .failure(reasonCategory: "generationFailure")
            }
        } catch {
            return .failure(reasonCategory: "generationFailure")
        }
    }

    private func availabilityReason(
        _ reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible: return "deviceNotEligible"
        case .appleIntelligenceNotEnabled: return "appleIntelligenceNotEnabled"
        case .modelNotReady: return "modelNotReady"
        @unknown default: return "runtimeUnavailable"
        }
    }

    private func encoded(_ outcome: NormalizedGeneratorOutcome) -> ProviderInvocationResult {
        guard let data = try? JSONEncoder().encode(outcome) else {
            return .failure(reasonCategory: "responseEncodingFailure")
        }
        return .complete(
            data,
            measurements: [
                .unmeasured(name: "completeResponseLatency", reason: "the provider returned before a complete proposal")
            ]
        )
    }

    private func decimalMilliseconds(since date: Date) -> Decimal {
        Decimal(string: String(format: "%.3f", Date().timeIntervalSince(date) * 1_000),
                locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}

@Generable
private enum AppleGeneratedOutcome {
    case proposal(AppleGeneratedProposal)
    case clarificationRequired(AppleGeneratedReason)
    case unsupportedRequest(AppleGeneratedReason)
    case refusal(AppleGeneratedReason)
    case providerUnavailable(AppleGeneratedReason)
    case providerFailure(AppleGeneratedReason)

    var normalized: NormalizedGeneratorOutcome {
        switch self {
        case let .proposal(value): return .proposal(value.normalized)
        case let .clarificationRequired(value):
            return .clarificationRequired(reasonCategory: value.reasonCategory, affectedPaths: value.affectedPaths)
        case let .unsupportedRequest(value):
            return .unsupportedRequest(reasonCategory: value.reasonCategory, affectedPaths: value.affectedPaths)
        case let .refusal(value):
            return .refusal(reasonCategory: value.reasonCategory, affectedPaths: value.affectedPaths)
        case let .providerUnavailable(value):
            return .providerUnavailable(reasonCategory: value.reasonCategory, affectedPaths: value.affectedPaths)
        case let .providerFailure(value):
            return .providerFailure(reasonCategory: value.reasonCategory, affectedPaths: value.affectedPaths)
        }
    }
}

@Generable
private struct AppleGeneratedReason {
    @Guide(description: "A stable, concise reason category from the prompt contract.")
    let reasonCategory: String

    @Guide(description: "Affected structured field paths, or an empty array when no field applies.")
    let affectedPaths: [String]
}

@Generable
private struct AppleGeneratedProposal {
    @Guide(description: "Exactly workout-proposal/v1.", .constant("workout-proposal/v1"))
    let contractVersion: String

    @Guide(description: "A short synthetic workout name.")
    let suggestedName: String

    let activity: AppleGeneratedActivity

    @Guide(description: "The exact non-empty ordered steps; never insert, merge, remove, or reorder a step.", .minimumCount(1))
    let steps: [AppleGeneratedStep]

    var normalized: WorkoutProposalV1 {
        WorkoutProposalV1(
            contractVersion: contractVersion,
            suggestedName: suggestedName,
            activity: activity.normalized,
            steps: steps.map(\.normalized)
        )
    }
}

@Generable
private enum AppleGeneratedActivity {
    case indoorWalking
    case indoorRunning

    var normalized: String {
        switch self {
        case .indoorWalking: return "indoorWalking"
        case .indoorRunning: return "indoorRunning"
        }
    }
}

@Generable
private struct AppleGeneratedStep {
    let kind: AppleGeneratedStepKind

    @Guide(description: "A non-empty step label.")
    let label: String

    let duration: AppleGeneratedDuration
    let targetSpeed: AppleGeneratedSpeed
    let targetInclination: AppleGeneratedInclination

    var normalized: WorkoutProposalStepV1 {
        WorkoutProposalStepV1(
            kind: kind.normalized,
            label: label,
            duration: .init(value: duration.value, unit: duration.unit.normalized),
            targetSpeed: .init(value: targetSpeed.value, unit: targetSpeed.unit.normalized),
            targetInclination: .init(
                value: targetInclination.value,
                unit: targetInclination.unit.normalized
            )
        )
    }
}

@Generable
private enum AppleGeneratedStepKind {
    case warmUp
    case interval
    case recovery
    case coolDown

    var normalized: String {
        switch self {
        case .warmUp: return "warmUp"
        case .interval: return "interval"
        case .recovery: return "recovery"
        case .coolDown: return "coolDown"
        }
    }
}

@Generable
private struct AppleGeneratedDuration {
    @Guide(description: "A finite value greater than zero.")
    let value: Decimal
    let unit: AppleGeneratedDurationUnit
}

@Generable
private enum AppleGeneratedDurationUnit {
    case seconds
    case minutes

    var normalized: String {
        switch self {
        case .seconds: return "seconds"
        case .minutes: return "minutes"
        }
    }
}

@Generable
private struct AppleGeneratedSpeed {
    @Guide(description: "A finite absolute speed stated by the synthetic request.")
    let value: Decimal
    let unit: AppleGeneratedSpeedUnit
}

@Generable
private enum AppleGeneratedSpeedUnit {
    case kilometresPerHour
    case milesPerHour

    var normalized: String {
        switch self {
        case .kilometresPerHour: return "kilometresPerHour"
        case .milesPerHour: return "milesPerHour"
        }
    }
}

@Generable
private struct AppleGeneratedInclination {
    @Guide(description: "A finite absolute inclination percentage stated by the synthetic request.")
    let value: Decimal
    let unit: AppleGeneratedInclinationUnit
}

@Generable
private enum AppleGeneratedInclinationUnit {
    case percent

    var normalized: String { "percent" }
}
