import Foundation

struct OpenRouterCredential: @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    static let environmentKey = "PACEPROMPT_OPENROUTER_API_KEY"

    private let value: String

    init?(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.value = value
    }

    static func fromLaunchEnvironment(_ environment: [String: String]) -> OpenRouterCredential? {
        environment[environmentKey].flatMap(OpenRouterCredential.init)
    }

    fileprivate var authorizationHeader: String { "Bearer \(value)" }
    var description: String { "<redacted OpenRouter credential>" }
    var debugDescription: String { description }
}

struct OpenRouterRequestAuthorizationContext: Equatable, Sendable {
    let caseID: String
    let modelID: String
}

protocol OpenRouterRequestAuthorizing: Sendable {
    func authorize(_ context: OpenRouterRequestAuthorizationContext) async -> Bool
}

struct OpenRouterHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

protocol OpenRouterTransport: Sendable {
    func send(_ request: URLRequest) async throws -> OpenRouterHTTPResponse
}

struct URLSessionOpenRouterTransport: OpenRouterTransport {
    let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func send(_ request: URLRequest) async throws -> OpenRouterHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return OpenRouterHTTPResponse(data: data, statusCode: http.statusCode)
    }
}

enum OpenRouterConfigurationError: Error, Equatable {
    case invalid(String)
}

struct OpenRouterConfiguration: Sendable {
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    let modelID: String
    let modelRevision: AvailableString
    let providerRouting: [String: JSONValue]
    let inferenceParameters: [String: JSONValue]
    let timeoutSeconds: Double
    let credential: OpenRouterCredential

    init(
        modelID: String,
        modelRevision: AvailableString,
        providerRouting: [String: JSONValue],
        inferenceParameters: [String: JSONValue],
        timeoutSeconds: Double,
        credential: OpenRouterCredential
    ) throws {
        guard !modelID.isEmpty else { throw OpenRouterConfigurationError.invalid("modelID is required") }
        guard !providerRouting.isEmpty else {
            throw OpenRouterConfigurationError.invalid("explicit provider routing is required")
        }
        guard timeoutSeconds.isFinite,
              timeoutSeconds > 0,
              timeoutSeconds < Double(UInt64.max) / 1_000_000_000 else {
            throw OpenRouterConfigurationError.invalid("timeoutSeconds must be positive and bounded")
        }
        let reserved = Set(["model", "messages", "provider", "response_format", "stream"])
        guard reserved.isDisjoint(with: inferenceParameters.keys) else {
            throw OpenRouterConfigurationError.invalid("inference parameters cannot replace fixed request fields")
        }
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.providerRouting = providerRouting
        self.inferenceParameters = inferenceParameters
        self.timeoutSeconds = timeoutSeconds
        self.credential = credential
    }

    var routingProvenance: [EvaluationKeyValue] { provenance(providerRouting) }
    var inferenceProvenance: [EvaluationKeyValue] { provenance(inferenceParameters) }

    private func provenance(_ values: [String: JSONValue]) -> [EvaluationKeyValue] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return values.keys.sorted().map { key in
            let text = (try? encoder.encode(values[key]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "null"
            return EvaluationKeyValue(key: key, value: text)
        }
    }
}

enum OpenRouterStrictSchemaError: Error, Equatable {
    case missingResource(String)
    case invalidAcceptedSchema
}

enum OpenRouterStrictSchema {
    static func load(bundle: Bundle) throws -> JSONValue {
        let proposalURL = try contractURL("workout-proposal-v1.schema", bundle: bundle)
        let resultURL = try contractURL("workout-import-result-v1.schema", bundle: bundle)
        guard var proposal = try JSONSerialization.jsonObject(with: Data(contentsOf: proposalURL)) as? [String: Any],
              let result = try JSONSerialization.jsonObject(with: Data(contentsOf: resultURL)) as? [String: Any],
              let resultDefinitions = result["$defs"] as? [String: Any],
              var proposalOutcome = resultDefinitions["proposalOutcome"] as? [String: Any],
              let reasonOutcome = resultDefinitions["reasonOutcome"] as? [String: Any],
              let proposalDefinitions = proposal["$defs"] as? [String: Any],
              var proposalOutcomeProperties = proposalOutcome["properties"] as? [String: Any],
              var proposalProperty = proposalOutcomeProperties["proposal"] as? [String: Any] else {
            throw OpenRouterStrictSchemaError.invalidAcceptedSchema
        }
        guard reasonTypes(in: reasonOutcome) == [
            "clarificationRequired", "providerFailure", "providerUnavailable", "refusal", "unsupportedRequest"
        ] else {
            throw OpenRouterStrictSchemaError.invalidAcceptedSchema
        }

        proposal.removeValue(forKey: "$schema")
        proposal.removeValue(forKey: "$id")
        proposal.removeValue(forKey: "$defs")
        proposalProperty["$ref"] = "#/$defs/proposal"
        proposalOutcomeProperties["proposal"] = proposalProperty
        proposalOutcome["properties"] = proposalOutcomeProperties

        var definitions = proposalDefinitions
        definitions["proposal"] = proposal
        let schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "oneOf": [proposalOutcome, reasonOutcome],
            "$defs": definitions
        ]
        return try jsonValue(schema)
    }

    private static func contractURL(_ name: String, bundle: Bundle) throws -> URL {
        if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Contracts") {
            return url
        }
        if let contracts = bundle.url(forResource: "Contracts", withExtension: nil) {
            return contracts.appendingPathComponent("\(name).json")
        }
        throw OpenRouterStrictSchemaError.missingResource("Contracts/\(name).json")
    }

    private static func reasonTypes(in schema: [String: Any]) -> [String] {
        guard let properties = schema["properties"] as? [String: Any],
              let type = properties["type"] as? [String: Any],
              let values = type["enum"] as? [String] else { return [] }
        return values.sorted()
    }

    private static func jsonValue(_ value: Any) throws -> JSONValue {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

struct OpenRouterAdapter: WorkoutProposalProvider {
    let configuration: OpenRouterConfiguration
    let strictSchema: JSONValue
    let transport: any OpenRouterTransport
    let authorizer: any OpenRouterRequestAuthorizing

    var identity: EvaluationProviderIdentity {
        EvaluationProviderIdentity(
            providerID: "openrouter",
            modelID: configuration.modelID,
            modelRevision: configuration.modelRevision
        )
    }

    var declaredRoutingConstraints: [EvaluationKeyValue] { configuration.routingProvenance }
    var declaredInferenceParameters: [EvaluationKeyValue] { configuration.inferenceProvenance }

    func readiness(for request: WorkoutProposalGenerationRequest) async -> ProviderReadiness {
        guard request.proposalContractVersion == WorkoutImportEvaluationContract.proposalContractVersion,
              request.promptTemplateVersion == WorkoutImportEvaluationContract.promptTemplateVersion else {
            return ProviderReadiness(
                runtime: .available,
                model: .unavailable(reason: "unsupportedContractVersion"),
                locale: .unknown
            )
        }
        return ProviderReadiness(runtime: .available, model: .available, locale: .available)
    }

    func generate(_ request: WorkoutProposalGenerationRequest) async -> ProviderInvocationResult {
        if Task.isCancelled { return .cancelled }
        if request.networkCondition == "offline" {
            return .unavailable(reasonCategory: "networkUnavailable")
        }
        let context = OpenRouterRequestAuthorizationContext(
            caseID: request.caseID,
            modelID: configuration.modelID
        )
        guard await authorizer.authorize(context) else {
            return .unavailable(reasonCategory: "runAuthorizationUnavailable")
        }
        let urlRequest: URLRequest
        do {
            urlRequest = try makeRequest(request)
        } catch {
            return .failure(reasonCategory: "requestEncodingFailure")
        }
        let started = Date()
        do {
            let response = try await sendWithTimeout(urlRequest)
            guard (200...299).contains(response.statusCode) else {
                return .failure(reasonCategory: "httpFailure")
            }
            let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: response.data)
            guard let choice = decoded.choices.first else {
                return .failure(reasonCategory: "incompleteResponse")
            }
            var measurements = decoded.usage.measurements
            measurements.append(.measured(
                name: "completeResponseLatency",
                value: decimalMilliseconds(since: started),
                unit: "milliseconds"
            ))
            if choice.message.refusal?.isEmpty == false {
                let outcome = NormalizedGeneratorOutcome.refusal(
                    reasonCategory: "providerRefusal",
                    affectedPaths: []
                )
                guard let data = try? JSONEncoder().encode(outcome) else {
                    return .failure(reasonCategory: "responseEncodingFailure")
                }
                return .complete(data, measurements: measurements)
            }
            guard let content = choice.message.content,
                  let data = content.data(using: .utf8) else {
                return .failure(reasonCategory: "incompleteResponse")
            }
            guard choice.finishReason == "stop" else {
                return .partial(data, measurements: measurements)
            }
            return .complete(data, measurements: measurements)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where Self.unavailableNetworkCodes.contains(error.code) {
            return .unavailable(reasonCategory: "networkUnavailable")
        } catch OpenRouterTimeoutError.timedOut {
            return .failure(reasonCategory: "timeout")
        } catch {
            return .failure(reasonCategory: "networkFailure")
        }
    }

    private func makeRequest(_ request: WorkoutProposalGenerationRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(configuration.modelID),
            "messages": .array([
                .object([
                    "role": .string("system"),
                    "content": .string(WorkoutImportPromptTemplate.instructions(
                        contractVersion: request.proposalContractVersion
                    ))
                ]),
                .object([
                    "role": .string("user"),
                    "content": .string(WorkoutImportPromptTemplate.request(request))
                ])
            ]),
            "provider": .object(configuration.providerRouting),
            "response_format": .object([
                "type": .string("json_schema"),
                "json_schema": .object([
                    "name": .string("paceprompt_workout_import_outcome_v1"),
                    "strict": .boolean(true),
                    "schema": strictSchema
                ])
            ]),
            "stream": .boolean(false)
        ]
        for (key, value) in configuration.inferenceParameters { body[key] = value }
        var result = URLRequest(url: OpenRouterConfiguration.endpoint)
        result.httpMethod = "POST"
        result.cachePolicy = .reloadIgnoringLocalCacheData
        result.timeoutInterval = configuration.timeoutSeconds
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue(configuration.credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        result.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return result
    }

    private func sendWithTimeout(_ request: URLRequest) async throws -> OpenRouterHTTPResponse {
        try await withThrowingTaskGroup(of: OpenRouterHTTPResponse.self) { group in
            group.addTask { try await transport.send(request) }
            group.addTask {
                try await Task.sleep(
                    nanoseconds: UInt64(configuration.timeoutSeconds * 1_000_000_000)
                )
                throw OpenRouterTimeoutError.timedOut
            }
            guard let first = try await group.next() else { throw OpenRouterTimeoutError.timedOut }
            group.cancelAll()
            return first
        }
    }

    private func decimalMilliseconds(since date: Date) -> Decimal {
        Decimal(string: String(format: "%.3f", Date().timeIntervalSince(date) * 1_000),
                locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static let unavailableNetworkCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff,
        .dataNotAllowed, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed
    ]
}

private enum OpenRouterTimeoutError: Error {
    case timedOut
}

private struct OpenRouterResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let refusal: String?
        }

        let message: Message
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Decodable {
        struct Details: Decodable { let cachedTokens: Decimal? }

        let promptTokens: Decimal?
        let completionTokens: Decimal?
        let cost: Decimal?
        let promptTokensDetails: Details?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case cost
            case promptTokensDetails = "prompt_tokens_details"
        }

        var measurements: [OperationalMeasurement] {
            [
                measurement("inputTokens", promptTokens, unit: "tokens"),
                measurement("cachedInputTokens", promptTokensDetails?.cachedTokens, unit: "tokens"),
                measurement("outputTokens", completionTokens, unit: "tokens"),
                measurement("providerReportedCost", cost, unit: "USD")
            ]
        }

        private func measurement(
            _ name: String,
            _ value: Decimal?,
            unit: String
        ) -> OperationalMeasurement {
            value.map { .measured(name: name, value: $0, unit: unit) }
                ?? .unmeasured(name: name, reason: "the provider did not report this field")
        }
    }

    let choices: [Choice]
    let usage: Usage

    private enum CodingKeys: String, CodingKey { case choices, usage }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decode([Choice].self, forKey: .choices)
        usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
            ?? Usage(promptTokens: nil, completionTokens: nil, cost: nil, promptTokensDetails: nil)
    }
}
