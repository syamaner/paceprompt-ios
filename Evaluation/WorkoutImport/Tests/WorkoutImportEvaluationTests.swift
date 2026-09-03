import XCTest
@testable import PacePromptEvaluation

final class WorkoutImportEvaluationTests: XCTestCase {
    func testAcceptedCorpusLoadsWithoutChangingVersionHashOrCases() throws {
        let corpus = try EvaluationCorpus.acceptedV1(bundle: testBundle)
        XCTAssertEqual(corpus.manifest.corpusHash, WorkoutImportEvaluationContract.acceptedCorpusHash)
        XCTAssertEqual(corpus.cases.count, 20)
        XCTAssertEqual(corpus.cases.first?.id, "WI-V1-001")
        XCTAssertEqual(corpus.cases.last?.id, "WI-V1-020")
        XCTAssertEqual(Set(corpus.cases.map(\.locale)), ["en-GB", "en-US"])
    }

    func testParserPreservesAllSixNormalizedOutcomes() throws {
        let proposal = try XCTUnwrap(proposalData())
        XCTAssertEqual(outcomeType(GeneratorOutputParser.parse(proposal)), "proposal")
        for type in [
            "clarificationRequired", "unsupportedRequest", "refusal",
            "providerUnavailable", "providerFailure"
        ] {
            let data = try JSONSerialization.data(withJSONObject: [
                "type": type,
                "reasonCategory": "fixtureReason",
                "affectedPaths": ["steps[0]"]
            ])
            XCTAssertEqual(outcomeType(GeneratorOutputParser.parse(data)), type)
        }
    }

    func testParserFailsClosedForMalformedUnknownAdditionalAndPartialOutput() throws {
        assertInvalid(Data("{".utf8), code: "malformedJSON")
        assertInvalid(Data("{\"type\":\"invented\"}".utf8), code: "unsupportedOutcome")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(proposalData())) as? [String: Any]
        )
        object["authority"] = "validated"
        assertInvalid(try JSONSerialization.data(withJSONObject: object), code: "additionalProperty")

        object.removeValue(forKey: "authority")
        var proposal = try XCTUnwrap(object["proposal"] as? [String: Any])
        proposal.removeValue(forKey: "steps")
        object["proposal"] = proposal
        assertInvalid(try JSONSerialization.data(withJSONObject: object), code: "missingProperty")
    }

    func testCanonicalMappingUsesExactUnitsAndNeverSkipsLocalValidation() throws {
        let outcome = try XCTUnwrap(validOutcome(GeneratorOutputParser.parse(try XCTUnwrap(proposalData()))))
        let capabilities = WorkoutImportCapabilities(
            speed: .init(state: .supported, minimum: 0, maximum: 20, increment: 0.000001),
            inclination: .init(state: .supported, minimum: 0, maximum: 15, increment: 0.5)
        )
        XCTAssertEqual(
            WorkoutProposalLocalPipeline.process(outcome, capabilities: capabilities).classification,
            .mappedAndValidated
        )

        guard case let .proposal(source) = outcome else { return XCTFail("Expected proposal") }
        let fractional = WorkoutProposalV1(
            contractVersion: source.contractVersion,
            suggestedName: source.suggestedName,
            activity: source.activity,
            steps: [
                .init(
                    kind: "warmUp",
                    label: "Fractional",
                    duration: .init(value: 0.01, unit: "minutes"),
                    targetSpeed: .init(value: 3, unit: "milesPerHour"),
                    targetInclination: .init(value: 0, unit: "percent")
                )
            ]
        )
        let mapping = WorkoutProposalLocalPipeline.process(.proposal(fractional), capabilities: capabilities)
        XCTAssertEqual(mapping.classification, .failedCanonicalMapping)
        XCTAssertEqual(mapping.mappingFailure?.code, "nonIntegralCanonicalDuration")
    }

    func testLocalInvalidPlanAndBlockedValidationRemainDistinct() throws {
        let outcome = try XCTUnwrap(validOutcome(GeneratorOutputParser.parse(try XCTUnwrap(proposalData()))))
        let unknown = WorkoutImportCapabilities(
            speed: .init(state: .unknown, minimum: nil, maximum: nil, increment: nil),
            inclination: .init(state: .unknown, minimum: nil, maximum: nil, increment: nil)
        )
        XCTAssertEqual(
            WorkoutProposalLocalPipeline.process(outcome, capabilities: unknown).classification,
            .localValidationBlocked
        )

        guard case let .proposal(source) = outcome else { return XCTFail("Expected proposal") }
        let badOrder = WorkoutProposalV1(
            contractVersion: source.contractVersion,
            suggestedName: source.suggestedName,
            activity: source.activity,
            steps: Array(source.steps.reversed())
        )
        let supported = WorkoutImportCapabilities(
            speed: .init(state: .supported, minimum: 0, maximum: 20, increment: 0.1),
            inclination: .init(state: .supported, minimum: 0, maximum: 15, increment: 0.5)
        )
        XCTAssertEqual(
            WorkoutProposalLocalPipeline.process(.proposal(badOrder), capabilities: supported).classification,
            .invalidLocalPlan
        )
    }

    func testRunnerUsesAcceptedCorpusAndKeepsProviderConditionsDistinct() async throws {
        let provider = FakeProvider(result: .complete(try XCTUnwrap(proposalData()), measurements: []))
        let runner = WorkoutImportEvaluationRunner(
            corpus: try EvaluationCorpus.acceptedV1(bundle: testBundle),
            provider: provider,
            dates: FixedDates()
        )
        let execution = try await runner.run(configuration: runConfiguration())
        XCTAssertEqual(execution.normalizedRun.resultContractVersion, "workout-import-result/v1")
        XCTAssertEqual(execution.normalizedRun.results.count, 20)
        let invocationCount = await provider.invocationCount
        XCTAssertEqual(invocationCount, 18)
        XCTAssertEqual(resultOutcomeType(execution, caseID: "WI-V1-016"), "providerUnavailable")
        XCTAssertEqual(resultOutcomeType(execution, caseID: "WI-V1-017"), "providerFailure")
        XCTAssertTrue(execution.normalizedRun.results.allSatisfy { $0.claimedAuthorities.isEmpty })
    }

    func testAmbiguousCorpusCaseRemainsClarificationWithoutLocalValidation() async throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "clarificationRequired",
            "reasonCategory": "missingDuration",
            "affectedPaths": ["steps[0].duration"]
        ])
        let execution = try await WorkoutImportEvaluationRunner(
            corpus: EvaluationCorpus.acceptedV1(bundle: testBundle),
            provider: FakeProvider(result: .complete(data, measurements: [])),
            dates: FixedDates()
        ).run(configuration: runConfiguration())
        let ambiguous = try XCTUnwrap(
            execution.caseExecutions.first { $0.normalizedResult.caseID == "WI-V1-006" }
        )
        XCTAssertEqual(ambiguous.normalizedResult.observed, .valid(.clarificationRequired(
            reasonCategory: "missingDuration",
            affectedPaths: ["steps[0].duration"]
        )))
        XCTAssertEqual(ambiguous.pipeline.classification, .notAttempted)
    }

    func testRunnerNormalizesUnavailablePartialMalformedFailureAndCancellation() async throws {
        let corpus = try EvaluationCorpus.acceptedV1(bundle: testBundle)
        let unavailable = FakeProvider(
            readiness: .init(
                runtime: .available,
                model: .unavailable(reason: "modelNotReady"),
                locale: .available
            ),
            result: .failure(reasonCategory: "shouldNotRun")
        )
        let unavailableRun = try await WorkoutImportEvaluationRunner(
            corpus: corpus, provider: unavailable, dates: FixedDates()
        ).run(configuration: runConfiguration())
        XCTAssertEqual(resultOutcomeType(unavailableRun, caseID: "WI-V1-001"), "providerUnavailable")
        let unavailableInvocationCount = await unavailable.invocationCount
        XCTAssertEqual(unavailableInvocationCount, 0)

        let partial = FakeProvider(result: .partial(Data("{".utf8), measurements: []))
        let partialRun = try await WorkoutImportEvaluationRunner(
            corpus: corpus, provider: partial, dates: FixedDates()
        ).run(configuration: runConfiguration())
        XCTAssertEqual(resultStructure(partialRun, caseID: "WI-V1-001"), "invalidGeneratorOutput")

        let failure = FakeProvider(result: .failure(reasonCategory: "networkFailure"))
        let failedRun = try await WorkoutImportEvaluationRunner(
            corpus: corpus, provider: failure, dates: FixedDates()
        ).run(configuration: runConfiguration())
        XCTAssertEqual(resultOutcomeType(failedRun, caseID: "WI-V1-001"), "providerFailure")

        let cancelledTask = Task {
            try await WorkoutImportEvaluationRunner(
                corpus: corpus, provider: partial, dates: FixedDates()
            ).run(configuration: runConfiguration())
        }
        cancelledTask.cancel()
        let cancelled = try await cancelledTask.value
        XCTAssertEqual(resultReason(cancelled, caseID: "WI-V1-001"), "cancelled")
    }

    func testNormalizedFixtureRoundTripsWithoutCredentialOrAuthorityClaims() throws {
        let fixtureURL = try XCTUnwrap(
            testBundle.url(
                forResource: "normalized-results-v1",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) ?? testBundle.url(forResource: "normalized-results-v1", withExtension: "json")
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoded = try JSONDecoder().decode(NormalizedEvaluationRun.self, from: data)
        let encoded = try JSONEncoder().encode(decoded)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: encoded) as? NSDictionary,
            try JSONSerialization.jsonObject(with: data) as? NSDictionary
        )
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("localValidation\""))
    }

    func testStrictOpenRouterSchemaIsDerivedFromBothAcceptedSchemas() throws {
        let schema = try OpenRouterStrictSchema.load(bundle: testBundle)
        let data = try JSONEncoder().encode(schema)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let definitions = try XCTUnwrap(root["$defs"] as? [String: Any])
        let embeddedProposal = try XCTUnwrap(definitions["proposal"] as? [String: Any])
        let acceptedURL = try XCTUnwrap(
            testBundle.url(
                forResource: "workout-proposal-v1.schema",
                withExtension: "json",
                subdirectory: "Contracts"
            ) ?? testBundle.url(forResource: "workout-proposal-v1.schema", withExtension: "json")
        )
        var accepted = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: acceptedURL)) as? [String: Any]
        )
        let acceptedDefinitions = try XCTUnwrap(accepted.removeValue(forKey: "$defs") as? [String: Any])
        accepted.removeValue(forKey: "$schema")
        accepted.removeValue(forKey: "$id")
        XCTAssertEqual(embeddedProposal as NSDictionary, accepted as NSDictionary)
        for key in acceptedDefinitions.keys {
            XCTAssertEqual(
                definitions[key] as? NSDictionary,
                acceptedDefinitions[key] as? NSDictionary,
                "Definition \(key) must remain unchanged"
            )
        }
    }

    func testOpenRouterAdapterPinsRequestRedactsSecretAndReportsUsage() async throws {
        let secret = "synthetic-secret-must-not-leak"
        let credential = try XCTUnwrap(OpenRouterCredential(secret))
        XCTAssertFalse(credential.description.contains(secret))
        let content = String(decoding: try XCTUnwrap(proposalData()), as: UTF8.self)
        let response = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content], "finish_reason": "stop"]],
            "usage": [
                "prompt_tokens": 12,
                "completion_tokens": 8,
                "prompt_tokens_details": ["cached_tokens": 4],
                "cost": 0.001
            ]
        ])
        let transport = RecordingTransport(response: .init(data: response, statusCode: 200))
        let configuration = try OpenRouterConfiguration(
            modelID: "explicit/model",
            modelRevision: .unavailable("not reported"),
            providerRouting: ["order": .array([.string("explicit-provider")])],
            inferenceParameters: ["temperature": .number(0)],
            timeoutSeconds: 2,
            credential: credential
        )
        let adapter = OpenRouterAdapter(
            configuration: configuration,
            strictSchema: try OpenRouterStrictSchema.load(bundle: testBundle),
            transport: transport,
            authorizer: AllowingAuthorizer()
        )
        let result = await adapter.generate(generationRequest())
        guard case let .complete(data, measurements) = result else {
            return XCTFail("Expected complete normalized response")
        }
        XCTAssertEqual(outcomeType(GeneratorOutputParser.parse(data)), "proposal")
        XCTAssertEqual(measurements.count, 5)
        let capturedRequest = await transport.lastRequest
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url, OpenRouterConfiguration.endpoint)
        XCTAssertEqual(request.timeoutInterval, 2)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(secret)")
        XCTAssertFalse(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains(secret))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(secret))
        XCTAssertFalse(configuration.routingProvenance.description.contains(secret))
    }

    func testOpenRouterNetworkUnavailableDeniedAuthorizationFailureAndTimeoutDoNotCallRealProvider() async throws {
        let credential = try XCTUnwrap(OpenRouterCredential("fixture-key"))
        let configuration = try OpenRouterConfiguration(
            modelID: "explicit/model",
            modelRevision: .unavailable("not reported"),
            providerRouting: ["order": .array([.string("explicit-provider")])],
            inferenceParameters: [:],
            timeoutSeconds: 0.01,
            credential: credential
        )
        let schema = try OpenRouterStrictSchema.load(bundle: testBundle)
        let transport = RecordingTransport(error: URLError(.notConnectedToInternet))
        let adapter = OpenRouterAdapter(
            configuration: configuration,
            strictSchema: schema,
            transport: transport,
            authorizer: AllowingAuthorizer()
        )
        let unavailableResult = await adapter.generate(generationRequest(network: "online"))
        XCTAssertEqual(unavailableResult, .unavailable(reasonCategory: "networkUnavailable"))

        let deniedTransport = RecordingTransport(response: .init(data: Data(), statusCode: 200))
        let denied = OpenRouterAdapter(
            configuration: configuration,
            strictSchema: schema,
            transport: deniedTransport,
            authorizer: DenyingAuthorizer()
        )
        let deniedResult = await denied.generate(generationRequest())
        XCTAssertEqual(deniedResult, .unavailable(reasonCategory: "runAuthorizationUnavailable"))
        let deniedRequest = await deniedTransport.lastRequest
        XCTAssertNil(deniedRequest)
        let offlineResult = await denied.generate(generationRequest(network: "offline"))
        XCTAssertEqual(offlineResult, .unavailable(reasonCategory: "networkUnavailable"))

        let slow = OpenRouterAdapter(
            configuration: configuration,
            strictSchema: schema,
            transport: SlowTransport(),
            authorizer: AllowingAuthorizer()
        )
        let timeoutResult = await slow.generate(generationRequest())
        XCTAssertEqual(timeoutResult, .failure(reasonCategory: "timeout"))
    }

    func testWriterAllowsOnlyIgnoredEvidenceBoundary() async throws {
        let provider = FakeProvider(result: .complete(try XCTUnwrap(proposalData()), measurements: []))
        let runner = WorkoutImportEvaluationRunner(
            corpus: try EvaluationCorpus.acceptedV1(bundle: testBundle),
            provider: provider,
            dates: FixedDates()
        )
        let execution = try await runner.run(configuration: runConfiguration())
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try EvaluationRunWriter.write(execution.normalizedRun, to: root))
        let runs = root.appendingPathComponent("Evaluation/WorkoutImport/.runs", isDirectory: true)
        let output = try EvaluationRunWriter.write(execution.normalizedRun, to: runs)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    func testLaunchReadinessNeverDisplaysCredential() {
        let secret = "not-for-display"
        let readiness = EvaluationLaunchReadiness.current(environment: [
            "PACEPROMPT_EVALUATION_PROVIDER": "openrouter",
            "PACEPROMPT_MODEL_ID": "explicit/model",
            "PACEPROMPT_RUN_CONFIGURATION_ID": "config-1",
            "PACEPROMPT_REPETITION_COUNT": "1",
            "PACEPROMPT_APP_COMMIT": String(repeating: "a", count: 40),
            "PACEPROMPT_DEVICE_LOCALE": "en-GB",
            "PACEPROMPT_OPENROUTER_PROVIDER_ROUTING_JSON": "{\"order\":[\"explicit-provider\"]}",
            "PACEPROMPT_OPENROUTER_TIMEOUT_SECONDS": "10",
            "PACEPROMPT_INFERENCE_PARAMETERS_JSON": "{}",
            OpenRouterCredential.environmentKey: secret
        ])
        XCTAssertFalse(String(describing: readiness).contains(secret))
        guard case let .ready(provider, details) = readiness else { return XCTFail("Expected ready") }
        XCTAssertEqual(provider, "OpenRouter")
        XCTAssertTrue(details.contains("Credential: present and redacted"))
    }

    private var testBundle: Bundle { Bundle(for: WorkoutImportEvaluationTests.self) }

    private func runConfiguration() -> EvaluationRunConfiguration {
        EvaluationRunConfiguration(
            runID: "fixture-run",
            appCommit: String(repeating: "a", count: 40),
            runConfigurationID: "explicit-fixture-configuration",
            repetitionCount: 1,
            evidenceLevel: "staticFixture",
            deviceClass: "synthetic-test-host",
            osVersion: "fixture-os",
            locale: "en-GB",
            routingConstraints: [],
            inferenceParameters: [],
            networkCondition: "notApplicable",
            measurementTools: ["XCTest"]
        )
    }

    private func generationRequest(network: String = "online") -> WorkoutProposalGenerationRequest {
        WorkoutProposalGenerationRequest(
            caseID: "WI-V1-001",
            prompt: "Synthetic fixture prompt",
            locale: "en-GB",
            capabilities: .init(
                speed: .init(state: .supported, minimum: 0, maximum: 20, increment: 0.1),
                inclination: .init(state: .supported, minimum: 0, maximum: 15, increment: 0.5)
            ),
            proposalContractVersion: WorkoutImportEvaluationContract.proposalContractVersion,
            promptTemplateVersion: WorkoutImportEvaluationContract.promptTemplateVersion,
            networkCondition: network
        )
    }

    private func proposalData() -> Data? {
        try? JSONSerialization.data(withJSONObject: [
            "type": "proposal",
            "proposal": [
                "contractVersion": "workout-proposal/v1",
                "suggestedName": "Synthetic intervals",
                "activity": "indoorRunning",
                "steps": [
                    step("warmUp", 120, 3, "milesPerHour", 0),
                    step("interval", 60, 6, "milesPerHour", 1),
                    step("coolDown", 120, 3, "milesPerHour", 0)
                ]
            ]
        ])
    }

    private func step(_ kind: String, _ seconds: Int, _ speed: Decimal, _ unit: String, _ incline: Decimal) -> [String: Any] {
        [
            "kind": kind,
            "label": kind,
            "duration": ["value": seconds, "unit": "seconds"],
            "targetSpeed": ["value": NSDecimalNumber(decimal: speed), "unit": unit],
            "targetInclination": ["value": NSDecimalNumber(decimal: incline), "unit": "percent"]
        ]
    }

    private func outcomeType(_ result: NormalizedObservedResult) -> String? {
        validOutcome(result)?.type
    }

    private func validOutcome(_ result: NormalizedObservedResult) -> NormalizedGeneratorOutcome? {
        guard case let .valid(outcome) = result else { return nil }
        return outcome
    }

    private func assertInvalid(_ data: Data, code: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .invalidGeneratorOutput(errors) = GeneratorOutputParser.parse(data) else {
            return XCTFail("Expected invalid generator output", file: file, line: line)
        }
        XCTAssertTrue(errors.contains(where: { $0.code == code }), file: file, line: line)
    }

    private func resultOutcomeType(_ run: EvaluationRunExecution, caseID: String) -> String? {
        guard let result = run.normalizedRun.results.first(where: { $0.caseID == caseID }),
              case let .valid(outcome) = result.observed else { return nil }
        return outcome.type
    }

    private func resultReason(_ run: EvaluationRunExecution, caseID: String) -> String? {
        guard let result = run.normalizedRun.results.first(where: { $0.caseID == caseID }),
              case let .valid(outcome) = result.observed else { return nil }
        switch outcome {
        case let .providerFailure(reason, _): return reason
        default: return nil
        }
    }

    private func resultStructure(_ run: EvaluationRunExecution, caseID: String) -> String? {
        guard let result = run.normalizedRun.results.first(where: { $0.caseID == caseID }) else { return nil }
        switch result.observed {
        case .valid: return "valid"
        case .invalidGeneratorOutput: return "invalidGeneratorOutput"
        }
    }

}

private final class FakeProvider: @unchecked Sendable, WorkoutProposalProvider {
    let identity = EvaluationProviderIdentity(
        providerID: "fixture-provider",
        modelID: "fixture-model",
        modelRevision: .unavailable("fixture")
    )
    let declaredRoutingConstraints: [EvaluationKeyValue] = []
    let declaredInferenceParameters: [EvaluationKeyValue] = []
    let fixedReadiness: ProviderReadiness
    let result: ProviderInvocationResult
    private let lock = NSLock()
    private var count = 0

    var invocationCount: Int {
        get async { lock.withLock { count } }
    }

    init(
        readiness: ProviderReadiness = .init(runtime: .available, model: .available, locale: .available),
        result: ProviderInvocationResult
    ) {
        fixedReadiness = readiness
        self.result = result
    }

    func readiness(for request: WorkoutProposalGenerationRequest) async -> ProviderReadiness {
        fixedReadiness
    }

    func generate(_ request: WorkoutProposalGenerationRequest) async -> ProviderInvocationResult {
        lock.withLock { count += 1 }
        return result
    }
}

private struct FixedDates: EvaluationDateProviding {
    func now() -> Date { Date(timeIntervalSince1970: 1_787_856_000) }
}

private actor RecordingTransport: OpenRouterTransport {
    private(set) var lastRequest: URLRequest?
    let response: OpenRouterHTTPResponse?
    let error: Error?

    init(response: OpenRouterHTTPResponse) {
        self.response = response
        error = nil
    }

    init(error: Error) {
        response = nil
        self.error = error
    }

    func send(_ request: URLRequest) async throws -> OpenRouterHTTPResponse {
        lastRequest = request
        if let error { throw error }
        return response!
    }
}

private struct SlowTransport: OpenRouterTransport {
    func send(_ request: URLRequest) async throws -> OpenRouterHTTPResponse {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return OpenRouterHTTPResponse(data: Data(), statusCode: 200)
    }
}

private struct AllowingAuthorizer: OpenRouterRequestAuthorizing {
    func authorize(_ context: OpenRouterRequestAuthorizationContext) async -> Bool { true }
}

private struct DenyingAuthorizer: OpenRouterRequestAuthorizing {
    func authorize(_ context: OpenRouterRequestAuthorizationContext) async -> Bool { false }
}
