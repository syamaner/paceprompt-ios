import Foundation

@MainActor
protocol ImportTransport: AnyObject {
    func send(_ request: URLRequest, completion: @escaping @MainActor (Result<(Data, HTTPURLResponse), ImportFailure>) -> Void)
    func cancel()
}

final class ImportSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}

@MainActor
final class SessionImportTransport: ImportTransport {
    nonisolated static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        return configuration
    }
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var deadline: Task<Void, Never>?
    private var identifier: UUID?
    private var completion: (@MainActor (Result<(Data, HTTPURLResponse), ImportFailure>) -> Void)?
    private let makeConfiguration: () -> URLSessionConfiguration
    private let deadlineNanoseconds: UInt64

    init(makeConfiguration: @escaping () -> URLSessionConfiguration = SessionImportTransport.configuration,
         deadlineNanoseconds: UInt64 = 180_000_000_000) {
        self.makeConfiguration = makeConfiguration
        self.deadlineNanoseconds = deadlineNanoseconds
    }
    func send(_ request: URLRequest, completion: @escaping @MainActor (Result<(Data, HTTPURLResponse), ImportFailure>) -> Void) {
        cancel()
        let id = UUID()
        let clock = ContinuousClock()
        let expires = clock.now.advanced(by: .nanoseconds(Int64(clamping: deadlineNanoseconds)))
        identifier = id
        self.completion = completion
        let session = URLSession(configuration: makeConfiguration(), delegate: ImportSessionDelegate(), delegateQueue: nil)
        self.session = session
        task = session.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self, self.identifier == id else { return }
                guard clock.now < expires else { self.finish(.failure(.timeout)); return }
                if let error = error as? URLError {
                    self.finish(.failure(error.code == .timedOut ? .timeout : error.code == .cancelled ? .cancelled : .transport))
                } else if error != nil {
                    self.finish(.failure(.transport))
                } else if let data, let response = response as? HTTPURLResponse {
                    self.finish(.success((data, response)))
                } else { self.finish(.failure(.transport)) }
            }
        }
        deadline = Task { [weak self] in
            do { try await clock.sleep(until: expires) } catch { return }
            guard let self, self.identifier == id else { return }
            self.finish(.failure(.timeout))
        }
        task?.resume()
    }
    func cancel() { if identifier != nil { finish(.failure(.cancelled)) } }
    private func finish(_ result: Result<(Data, HTTPURLResponse), ImportFailure>) {
        identifier = nil
        let callback = completion
        completion = nil
        deadline?.cancel(); deadline = nil
        task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
        callback?(result)
    }
}

@MainActor
protocol WorkoutImportGenerating: AnyObject {
    func generate(_ request: ImportRequestSnapshot, completion: @escaping @MainActor (WorkoutImportOutcome) -> Void)
    func cancel()
}

@MainActor
final class OpenRouterImportAdapter: WorkoutImportGenerating {
    private let credential: ImportCredentialStore
    private let transport: any ImportTransport
    private let resources: () throws -> ImportResources
    private var identifier: UUID?
#if DEBUG
    private let diagnostics: any ImportDiagnosticSink
    private var diagnosticRequestCount = 0
    private var diagnosticStartedAt: TimeInterval?
#endif

#if DEBUG
    init(credential: ImportCredentialStore, transport: (any ImportTransport)? = nil,
         resources: @escaping () throws -> ImportResources = { try ImportResources() },
         diagnostics: any ImportDiagnosticSink = UnifiedImportDiagnosticSink.shared) {
        self.credential = credential
        self.transport = transport ?? SessionImportTransport()
        self.resources = resources
        self.diagnostics = diagnostics
    }
#else
    init(credential: ImportCredentialStore, transport: (any ImportTransport)? = nil,
         resources: @escaping () throws -> ImportResources = { try ImportResources() }) {
        self.credential = credential; self.transport = transport ?? SessionImportTransport(); self.resources = resources
    }
#endif
    func generate(_ snapshot: ImportRequestSnapshot, completion: @escaping @MainActor (WorkoutImportOutcome) -> Void) {
        cancel()
        let id = UUID()
        identifier = id
        do {
            var request = try resources().request(for: snapshot)
            try credential.authorize(&request)
#if DEBUG
            diagnosticRequestCount += 1
            diagnosticStartedAt = ProcessInfo.processInfo.systemUptime
            diagnostics.record(.requestCount(diagnosticRequestCount))
            diagnostics.record(.check(.requestLifecycle, .started))
#endif
            transport.send(request) { [weak self] result in
                guard let self, self.identifier == id else { return }
                self.identifier = nil
#if DEBUG
                self.diagnostics.record(.check(.transport, .completed))
                if let started = self.diagnosticStartedAt {
                    self.diagnostics.record(.elapsed(.init(seconds: ProcessInfo.processInfo.systemUptime - started)))
                }
                self.diagnosticStartedAt = nil
                self.diagnostics.record(.check(.requestLifecycle, .completed))
#endif
                switch result {
                case let .failure(error): completion(.providerFailure(error))
                case let .success((data, response)):
                    guard response.url == WorkoutImportContract.endpoint else {
#if DEBUG
                        self.diagnostics.record(.check(.endpoint, .rejected))
#endif
                        completion(.providerFailure(.identityResponseURL)); return
                    }
#if DEBUG
                    self.diagnostics.record(.check(.endpoint, .accepted))
                    self.diagnostics.record(.statusClass(.init(response.statusCode)))
                    self.diagnostics.record(.check(.status, response.statusCode == 200 ? .accepted : .rejected))
#endif
                    guard response.statusCode == 200 else {
                        switch response.statusCode {
                        case 301, 302, 303, 307, 308: completion(.providerFailure(.redirect))
                        case 401: completion(.providerUnavailable(.authentication))
                        case 402: completion(.providerUnavailable(.credits))
                        case 403: completion(.providerUnavailable(.restrictedRoute))
                        case 404, 503: completion(.providerUnavailable(.unavailable))
                        case 429: completion(.providerUnavailable(.rateLimited))
                        default: completion(.providerFailure(.transport))
                        }
                        return
                    }
                    guard response.mimeType?.lowercased() == "application/json" else {
#if DEBUG
                        self.diagnostics.record(.check(.contentType, .rejected))
#endif
                        completion(.providerFailure(.responseContentType)); return
                    }
#if DEBUG
                    self.diagnostics.record(.check(.contentType, .accepted))
                    ImportDiagnosticInspector.inspectEnvelope(data, sink: self.diagnostics)
#endif
                    do { completion(try WorkoutImportContract.parseEnvelope(data)) }
                    catch let error as ImportFailure { completion(.providerFailure(error)) }
                    catch { completion(.providerFailure(.structure)) }
                }
            }
        } catch {
            identifier = nil
            let failure = (error as? ImportFailure) ?? .transport
            completion(failure == .missingCredential ? .providerUnavailable(failure) : .providerFailure(failure))
        }
    }
    func cancel() {
#if DEBUG
        let wasActive = identifier != nil
#endif
        identifier = nil
        transport.cancel()
#if DEBUG
        if wasActive {
            diagnosticStartedAt = nil
            diagnostics.record(.check(.requestLifecycle, .cancelled))
        }
#endif
    }
}
