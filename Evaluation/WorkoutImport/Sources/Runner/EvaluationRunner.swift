import Foundation

enum EvaluationRunConfigurationError: Error, Equatable, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(reason): return "The explicit evaluation run configuration is invalid: \(reason)"
        }
    }
}

struct EvaluationRunConfiguration: Equatable, Sendable {
    let runID: String
    let appCommit: String
    let runConfigurationID: String
    let repetitionCount: Int
    let evidenceLevel: String
    let deviceClass: String
    let osVersion: String
    let locale: String
    let routingConstraints: [EvaluationKeyValue]
    let inferenceParameters: [EvaluationKeyValue]
    let networkCondition: String
    let measurementTools: [String]

    func validate() throws {
        guard !runID.isEmpty, !runConfigurationID.isEmpty else {
            throw EvaluationRunConfigurationError.invalid("run identities must be non-empty")
        }
        let shaPattern = try! NSRegularExpression(pattern: "^[0-9a-f]{40}$")
        let shaRange = NSRange(appCommit.startIndex..<appCommit.endIndex, in: appCommit)
        guard shaPattern.firstMatch(in: appCommit, range: shaRange) != nil else {
            throw EvaluationRunConfigurationError.invalid("appCommit must be an exact lowercase Git SHA")
        }
        guard repetitionCount > 0 else {
            throw EvaluationRunConfigurationError.invalid("repetitionCount must be explicitly greater than zero")
        }
        guard ["staticFixture", "simulator", "physicalIPhone", "remoteProvider"].contains(evidenceLevel) else {
            throw EvaluationRunConfigurationError.invalid("evidenceLevel is unsupported")
        }
        guard ["offline", "online", "notApplicable"].contains(networkCondition) else {
            throw EvaluationRunConfigurationError.invalid("networkCondition is unsupported")
        }
        guard !deviceClass.isEmpty, !osVersion.isEmpty, !locale.isEmpty else {
            throw EvaluationRunConfigurationError.invalid("device, OS, and locale provenance are required")
        }
        guard Set(routingConstraints.map(\.key)).count == routingConstraints.count,
              Set(inferenceParameters.map(\.key)).count == inferenceParameters.count,
              Set(measurementTools).count == measurementTools.count else {
            throw EvaluationRunConfigurationError.invalid("provenance keys and measurement tools must be unique")
        }
        guard routingConstraints.allSatisfy({ !$0.key.isEmpty }),
              inferenceParameters.allSatisfy({ !$0.key.isEmpty }),
              measurementTools.allSatisfy({ !$0.isEmpty }) else {
            throw EvaluationRunConfigurationError.invalid("provenance keys and measurement tools must be non-empty")
        }
    }
}

protocol EvaluationDateProviding: Sendable {
    func now() -> Date
}

struct SystemEvaluationDateProvider: EvaluationDateProviding {
    func now() -> Date { Date() }
}

struct EvaluationCaseExecution: Equatable, Sendable {
    let normalizedResult: EvaluationCaseResult
    let pipeline: ProposalPipelineResult
}

struct EvaluationRunExecution: Equatable, Sendable {
    let normalizedRun: NormalizedEvaluationRun
    let caseExecutions: [EvaluationCaseExecution]
}

struct WorkoutImportEvaluationRunner: Sendable {
    let corpus: EvaluationCorpus
    let provider: any WorkoutProposalProvider
    let dates: any EvaluationDateProviding

    init(
        corpus: EvaluationCorpus,
        provider: any WorkoutProposalProvider,
        dates: any EvaluationDateProviding = SystemEvaluationDateProvider()
    ) {
        self.corpus = corpus
        self.provider = provider
        self.dates = dates
    }

    func run(configuration: EvaluationRunConfiguration) async throws -> EvaluationRunExecution {
        try configuration.validate()
        guard !provider.identity.providerID.isEmpty, !provider.identity.modelID.isEmpty else {
            throw EvaluationRunConfigurationError.invalid("provider and model identities are required")
        }
        guard provider.declaredRoutingConstraints == configuration.routingConstraints,
              provider.declaredInferenceParameters == configuration.inferenceParameters else {
            throw EvaluationRunConfigurationError.invalid(
                "recorded routing and inference parameters must exactly match the configured adapter"
            )
        }
        let startedAt = dates.now()
        var executions: [EvaluationCaseExecution] = []
        for repetition in 1...configuration.repetitionCount {
            for evaluationCase in corpus.cases {
                let result = await execute(
                    evaluationCase,
                    repetition: repetition,
                    configuration: configuration
                )
                executions.append(result)
            }
        }
        let endedAt = dates.now()
        guard endedAt >= startedAt else {
            throw EvaluationRunConfigurationError.invalid("the run end time precedes its start time")
        }
        let provenance = EvaluationRunProvenance(
            runID: configuration.runID,
            appCommit: configuration.appCommit,
            corpusVersion: corpus.manifest.corpusVersion,
            corpusHash: corpus.manifest.corpusHash,
            proposalContractVersion: corpus.manifest.proposalContractVersion,
            promptTemplateVersion: corpus.manifest.promptTemplateVersion,
            scorerVersion: corpus.manifest.scorerVersion,
            evidenceLevel: configuration.evidenceLevel,
            deviceClass: configuration.deviceClass,
            osVersion: configuration.osVersion,
            locale: configuration.locale,
            providerID: provider.identity.providerID,
            modelID: provider.identity.modelID,
            modelRevision: provider.identity.modelRevision,
            routingConstraints: configuration.routingConstraints,
            inferenceParameters: configuration.inferenceParameters,
            networkCondition: configuration.networkCondition,
            runConfigurationID: configuration.runConfigurationID,
            startedAt: timestamp(startedAt),
            endedAt: timestamp(endedAt),
            measurementTools: configuration.measurementTools
        )
        return EvaluationRunExecution(
            normalizedRun: NormalizedEvaluationRun(
                resultContractVersion: corpus.manifest.resultContractVersion,
                provenance: provenance,
                results: executions.map(\.normalizedResult)
            ),
            caseExecutions: executions
        )
    }

    private func execute(
        _ evaluationCase: WorkoutImportCase,
        repetition: Int,
        configuration: EvaluationRunConfiguration
    ) async -> EvaluationCaseExecution {
        let request = WorkoutProposalGenerationRequest(
            caseID: evaluationCase.id,
            prompt: evaluationCase.prompt,
            locale: evaluationCase.locale,
            capabilities: evaluationCase.capabilities,
            proposalContractVersion: corpus.manifest.proposalContractVersion,
            promptTemplateVersion: corpus.manifest.promptTemplateVersion,
            networkCondition: configuration.networkCondition
        )
        let invocation: ProviderInvocationResult
        switch evaluationCase.generatorCondition {
        case .providerUnavailable:
            invocation = .unavailable(reasonCategory: "runtimeUnavailable")
        case .providerFailure:
            invocation = .failure(reasonCategory: "invocationFailure")
        case .normal:
            if Task.isCancelled {
                invocation = .cancelled
            } else {
                let readiness = await provider.readiness(for: request)
                if readiness.isReady {
                    invocation = await provider.generate(request)
                } else {
                    invocation = .unavailable(
                        reasonCategory: readiness.firstUnavailableReason ?? "providerNotReady"
                    )
                }
            }
        }

        let observed: NormalizedObservedResult
        let measurements: [OperationalMeasurement]
        switch invocation {
        case let .complete(data, providerMeasurements):
            observed = GeneratorOutputParser.parse(data)
            measurements = providerMeasurements
        case let .partial(_, providerMeasurements):
            observed = .invalidGeneratorOutput([.init(code: "incompleteResponse", path: "$")])
            measurements = providerMeasurements + [
                .unmeasured(name: "completeResponseLatency", reason: "the provider response was incomplete")
            ]
        case let .invalidGeneratorOutput(code, path):
            observed = .invalidGeneratorOutput([.init(code: code, path: path)])
            measurements = [
                .unmeasured(name: "completeResponseLatency", reason: "guided generation was structurally invalid")
            ]
        case let .unavailable(reason):
            observed = .valid(.providerUnavailable(reasonCategory: reason, affectedPaths: []))
            measurements = [.unmeasured(name: "completeResponseLatency", reason: "the provider was unavailable")]
        case let .failure(reason):
            observed = .valid(.providerFailure(reasonCategory: reason, affectedPaths: []))
            measurements = [.unmeasured(name: "completeResponseLatency", reason: "the provider invocation failed")]
        case .cancelled:
            observed = .valid(.providerFailure(reasonCategory: "cancelled", affectedPaths: []))
            measurements = [.unmeasured(name: "completeResponseLatency", reason: "the invocation was cancelled")]
        }
        let pipeline: ProposalPipelineResult
        if case let .valid(outcome) = observed {
            pipeline = WorkoutProposalLocalPipeline.process(outcome, capabilities: evaluationCase.capabilities)
        } else {
            pipeline = .notAttempted
        }
        let normalized = EvaluationCaseResult(
            resultID: "\(configuration.runID):\(evaluationCase.id):r\(repetition)",
            caseID: evaluationCase.id,
            repetitionIndex: repetition,
            observed: observed,
            claimedAuthorities: [],
            operationalMeasurements: measurements
        )
        return EvaluationCaseExecution(normalizedResult: normalized, pipeline: pipeline)
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
