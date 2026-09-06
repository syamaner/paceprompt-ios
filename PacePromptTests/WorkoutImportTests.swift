import XCTest
import Security
@testable import PacePrompt

@MainActor
final class WorkoutImportTests: XCTestCase {
    func testResourceHashesAndCompleteAuthorizedRequestMatchesFrozenFixture() throws {
        let resources = try ImportResources()
        let snapshot = ImportRequestSnapshot(text: "Synthetic import contract fixture.", capabilities: .init(speed: .unknown, inclination: .unknown))
        let backend = SyntheticKeychain()
        backend.data = Data("synthetic-key".utf8)
        let transport = CapturingTransport()
        let adapter = OpenRouterImportAdapter(
            credential: ImportCredentialStore(backend: backend),
            transport: transport,
            resources: { resources }
        )
        adapter.generate(snapshot) { _ in XCTFail("The capturing transport must not complete during request inspection") }

        let request = try XCTUnwrap(transport.requests.only)
        XCTAssertEqual(request.url, WorkoutImportContract.endpoint)
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.allHTTPHeaderFields?.count, 3)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")

        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "outbound-request", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? NSDictionary)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body as NSDictionary, fixture)

        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 24)
        XCTAssertEqual(messages.last?["content"], snapshot.userMessage)
        for message in resources.examples where message["role"] == "assistant" {
            _ = try WorkoutImportContract.parseModelOutput(Data(message["content"]!.utf8))
        }
    }
}

@MainActor
final class WorkoutImportBoundaryTests: XCTestCase {
    func testKeychainQueryIsScopedAndNonSynchronisingWithoutReadingAKey() {
        let query = DeviceImportKeychain.query
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "com.paceprompt.workout-import.openrouter")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "workout-import")
        XCTAssertNil(query[kSecAttrAccessGroup as String])
    }

    func testCredentialLifecycleAndFailuresAreRedactedAndClearEntry() throws {
        let backend = SyntheticKeychain(), store = ImportCredentialStore(backend: SyntheticKeychain())
        store.refresh(); XCTAssertEqual(store.state, .absent)
        let credential = ImportCredentialStore(backend: backend)
        credential.entry = "synthetic-key-one"; credential.save(replacing: false)
        XCTAssertEqual(credential.state, .present); XCTAssertEqual(credential.entry, "")
        credential.beginReplacement(); XCTAssertEqual(credential.state, .replacing)
        backend.fail = true; credential.entry = "synthetic-key-two"; credential.save(replacing: true)
        XCTAssertEqual(credential.state, .failed); XCTAssertEqual(credential.entry, "")
        XCTAssertEqual(backend.data, Data("synthetic-key-one".utf8))
        credential.delete(); XCTAssertEqual(credential.state, .failed)
        XCTAssertNotNil(backend.data)
        backend.fail = false; credential.beginReplacement(); credential.entry = "synthetic-key-two"; credential.save(replacing: true)
        XCTAssertEqual(backend.data, Data("synthetic-key-two".utf8))
        credential.entry = "synthetic-cancel"; credential.cancelEntry(); XCTAssertEqual(credential.entry, "")
        credential.entry = "synthetic-lock"; credential.protectedDataLost(); XCTAssertEqual(credential.entry, "")
        credential.delete(); XCTAssertEqual(credential.state, .absent); XCTAssertNil(backend.data)
    }

    func testCredentialCannotAuthorizeOtherEndpointAndLockedOrMissingSendsNothing() throws {
        let backend = SyntheticKeychain(), credential = ImportCredentialStore(backend: backend), transport = CapturingTransport()
        var wrong = URLRequest(url: URL(string: "https://example.invalid/")!); wrong.httpMethod = "POST"
        XCTAssertThrowsError(try credential.authorize(&wrong)); XCTAssertEqual(backend.reads, 0)
        let adapter = OpenRouterImportAdapter(credential: credential, transport: transport)
        var result: WorkoutImportOutcome?
        adapter.generate(snapshot()) { result = $0 }
        XCTAssertEqual(result, .providerUnavailable(.missingCredential)); XCTAssertEqual(transport.requests.count, 0)
        backend.data = Data("synthetic-key".utf8); backend.fail = true
        adapter.generate(snapshot()) { result = $0 }
        XCTAssertEqual(result, .providerUnavailable(.missingCredential)); XCTAssertEqual(transport.requests.count, 0)
    }

    func testConsentIsSingleUseAndEveryEditDismissalAndLifecycleChangeInvalidatesIt() {
        let generator = SyntheticGenerator(), repository = ImportRepositoryDouble()
        let plans = PlansViewModel(repository: repository)
        let model = WorkoutImportViewModel(generator: generator, plans: plans)
        model.begin(capabilities: known()); model.text = "Synthetic text"
        model.consentAndSend(); XCTAssertEqual(generator.requests.count, 0)
        model.reviewDisclosure(); model.dismissDisclosure(); model.consentAndSend(); XCTAssertEqual(generator.requests.count, 0)
        XCTAssertTrue(model.text.isEmpty); model.text = "Synthetic replacement text"
        model.reviewDisclosure(); model.text += " changed"; model.consentAndSend(); XCTAssertEqual(generator.requests.count, 0)
        model.reviewDisclosure(); model.updateCapabilities(.init(speed: .unknown, inclination: .unknown)); model.consentAndSend()
        XCTAssertEqual(generator.requests.count, 0)
        model.reviewDisclosure(); model.consentAndSend(); model.consentAndSend(); XCTAssertEqual(generator.requests.count, 1)
        model.cancel(); generator.complete(.providerFailure(.transport)); XCTAssertNil(model.outcome); XCTAssertTrue(model.text.isEmpty)
        for background in [true, false] {
            model.setForeground(true); model.setProtectedDataAvailable(true)
            model.begin(capabilities: known()); model.text = "Synthetic new text"; model.reviewDisclosure()
            if background { model.setForeground(false) } else { model.setProtectedDataAvailable(false) }
            model.consentAndSend(); XCTAssertEqual(generator.requests.count, 1)
        }
        XCTAssertNil(plans.preview); XCTAssertEqual(repository.records.count, 0)
    }

    func testExactProposalPreviewAndSeparateSavePreserveOrderValuesAndClearTransientText() throws {
        let repository = ImportRepositoryDouble(), generator = SyntheticGenerator()
        let savingPlans = PlansViewModel(repository: repository)
        let model = WorkoutImportViewModel(generator: generator, plans: savingPlans)
        model.begin(capabilities: known()); model.text = "Synthetic workout"; model.reviewDisclosure(); model.consentAndSend()
        let proposal = try parsedProposal()
        generator.complete(.proposal(proposal))
        XCTAssertEqual(repository.records.count, 0)
        let exact = try WorkoutProposalMapper.map(proposal)
        XCTAssertEqual(savingPlans.preview?.plan, exact)
        XCTAssertEqual(exact.steps.map(\.duration.value), [30, 120, 60])
        XCTAssertEqual(exact.steps.map(\.kind), [.warmUp, .interval, .coolDown])
        XCTAssertEqual(exact.steps[1].targetSpeed.value, Decimal(string: "8.04672"))
        model.confirmSave()
        XCTAssertEqual(repository.records.map(\.plan), [exact])
        XCTAssertEqual(model.text, ""); XCTAssertNil(model.outcome); XCTAssertNil(savingPlans.preview); XCTAssertFalse(model.isPresented)
    }

    func testPreviewInvalidatedByCapabilityOrTextChangeAndStaleResponseCannotRestoreIt() throws {
        for change in 0..<4 {
            let repository = ImportRepositoryDouble(), generator = SyntheticGenerator()
            let plans = PlansViewModel(repository: repository)
            let model = WorkoutImportViewModel(generator: generator, plans: plans)
            model.begin(capabilities: known()); model.text = "Synthetic workout"; model.reviewDisclosure(); model.consentAndSend()
            generator.complete(.proposal(try parsedProposal())); XCTAssertNotNil(plans.preview)
            switch change {
            case 0: model.updateCapabilities(.init(speed: .unknown, inclination: .unknown))
            case 1: model.text += " edited"
            case 2: model.setForeground(false)
            default: model.setProtectedDataAvailable(false)
            }
            model.confirmSave(); generator.complete(.proposal(try parsedProposal()))
            XCTAssertNil(plans.preview); XCTAssertEqual(repository.records.count, 0)
        }
    }

    func testAllNonProposalOutcomesHaveNoPreviewOrSaveAndClearText() {
        let results: [WorkoutImportOutcome] = [
            .clarificationRequired(.init(reason: "missingRequiredField", paths: ["activity"])),
            .unsupportedRequest(.init(reason: "unsupportedActivity", paths: ["activity"])),
            .refusal(.init(reason: "medicalRequest", paths: [])), .providerUnavailable(.rateLimited), .providerFailure(.structure)]
        for result in results {
            let repository = ImportRepositoryDouble(), generator = SyntheticGenerator()
            let plans = PlansViewModel(repository: repository)
            let model = WorkoutImportViewModel(generator: generator, plans: plans)
            model.begin(capabilities: known()); model.text = "Synthetic workout"; model.reviewDisclosure(); model.consentAndSend(); generator.complete(result)
            XCTAssertEqual(model.outcome, result); XCTAssertNil(plans.preview); XCTAssertEqual(model.text, "")
            model.confirmSave(); XCTAssertEqual(repository.records.count, 0)
        }
    }

    func testMappingFailureIsSeparateFromLocalValidationAndSaveFailureClearsPreview() throws {
        let repo = ImportRepositoryDouble(), generator = SyntheticGenerator()
        let plans = PlansViewModel(repository: repo)
        let model = WorkoutImportViewModel(generator: generator, plans: plans)
        model.begin(capabilities: known()); model.text = "Synthetic"; model.reviewDisclosure(); model.consentAndSend()
        generator.complete(.proposal(try parsedProposal(duration: "0.001")))
        XCTAssertTrue(model.mappingFailure); XCTAssertTrue(model.validationIssues.isEmpty); XCTAssertNil(plans.preview); XCTAssertTrue(model.text.isEmpty)
        let savePlans = PlansViewModel(repository: repo)
        let failing = WorkoutImportViewModel(generator: generator, plans: savePlans)
        repo.fail = true
        failing.begin(capabilities: known()); failing.text = "Synthetic"; failing.reviewDisclosure(); failing.consentAndSend()
        generator.complete(.proposal(try parsedProposal())); failing.confirmSave()
        XCTAssertNil(savePlans.preview); XCTAssertNotNil(failing.feedback); XCTAssertTrue(failing.text.isEmpty); XCTAssertTrue(repo.records.isEmpty)
    }

    func testEveryValidatorBoundaryBlocksImportedPreview() throws {
        let base = try WorkoutProposalMapper.map(parsedProposal())
        var fixtures: [(WorkoutPlan, WorkoutPlanCapabilities, WorkoutPlanValidationIssue.Code)] = []
        func altered(name: String? = nil, steps: [WorkoutStep]? = nil, version: Int = 1) -> WorkoutPlan {
            .init(schemaVersion: version, suggestedName: name ?? base.suggestedName, activity: base.activity, steps: steps ?? base.steps)
        }
        fixtures += [(altered(version: 99), known(), .unsupportedSchemaVersion), (altered(name: ""), known(), .missingSuggestedName),
                     (altered(steps: []), known(), .missingSteps), (altered(steps: Array(base.steps.reversed())), known(), .invalidStepOrder),
                     (altered(steps: [base.steps[0], base.steps[2]]), known(), .missingInterval)]
        for (label, duration, speed, inclination, code) in [
            ("", 30, Decimal(5), Decimal(0), WorkoutPlanValidationIssue.Code.missingStepLabel),
            ("Warm", 0, Decimal(5), Decimal(0), .invalidDuration),
            ("Warm", 30, Decimal.nan, Decimal(0), .nonFiniteTarget),
            ("Warm", 30, Decimal(99), Decimal(0), .targetOutOfRange),
            ("Warm", 30, Decimal(5), Decimal(99), .targetOutOfRange)] {
            var steps = base.steps
            steps[0] = .init(kind: .warmUp, label: label, duration: .init(value: duration, unit: .seconds),
                             targetSpeed: .init(value: speed, unit: .kilometresPerHour), targetInclination: .init(value: inclination, unit: .percent))
            fixtures.append((altered(steps: steps), known(), code))
        }
        fixtures += [(base, .init(speed: .unknown, inclination: known().inclination), .capabilityUnknown),
                     (base, .init(speed: known().speed, inclination: .unknown), .capabilityUnknown),
                     (base, .init(speed: .unsupported, inclination: known().inclination), .targetUnsupported),
                     (base, .init(speed: known().speed, inclination: .unsupported), .targetUnsupported),
                     (base, known(increment: 0), .invalidCapabilityRange),
                     (base, known(increment: 1), .targetNotIncrementAligned)]
        for (plan, capabilities, code) in fixtures {
            let repo = ImportRepositoryDouble()
            let plans = PlansViewModel(repository: repo)
            guard case let .failure(failure) = plans.reviewImportedPlan(plan, against: capabilities) else { XCTFail("Expected \(code)"); continue }
            XCTAssertTrue(failure.issues.contains(where: { $0.code == code })); XCTAssertNil(plans.preview)
            plans.confirmSave(); XCTAssertTrue(repo.records.isEmpty)
        }
    }

    func testStrictEnvelopeIdentityFieldsToolsTruncationAndDuplicateKeys() throws {
        let valid = try envelope()
        XCTAssertNoThrow(try WorkoutImportContract.parseEnvelope(valid))
        for key in ["model", "provider", "choices", "created", "id", "object"] {
            var object = try json(valid); object.removeValue(forKey: key)
            XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(object)), key)
        }
        for model in ["other", ""] {
            var o = try json(valid); o["model"] = model; XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(o)))
        }
        for provider in ["Azure", "OPENAI", "openai/fast", ""] {
            var o = try json(valid); o["provider"] = provider; XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(o)))
        }
        var extra = try json(valid); extra["unknown"] = 1; XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(extra)))
        for finish in ["length", "tool_calls", "error", "content_filter"] {
            var o = try json(valid); var choices = o["choices"] as! [[String: Any]]; choices[0]["finish_reason"] = finish; o["choices"] = choices
            XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(o)))
        }
        for (key, value) in [("tool_calls", [["id": "synthetic-tool"]] as Any), ("reasoning", "unexpected"), ("extra", 1), ("content", NSNull())] {
            var o = try json(valid); var choices = o["choices"] as! [[String: Any]]; var message = choices[0]["message"] as! [String: Any]
            message[key] = value; choices[0]["message"] = message; o["choices"] = choices
            XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(o)))
        }
        var multi = try json(valid); multi["choices"] = (multi["choices"] as! [[String: Any]]) + (multi["choices"] as! [[String: Any]])
        XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(multi)))
        for raw in ["{\"x\":1,\"x\":2}", "{\"x\":1,\"\\u0078\":2}", "[1,]", "{\"x\":true,}", "NaN", "01", "1 trailing", "\"\\uD800\""] {
            XCTAssertThrowsError(try StrictImportJSON.parse(Data(raw.utf8)), raw)
        }
        XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(valid.dropLast()))
    }

    func testIdentityFailuresAreFieldSpecificWithoutIncludingReceivedValues() throws {
        func failure(_ object: [String: Any]) throws -> ImportFailure {
            do {
                _ = try WorkoutImportContract.parseEnvelope(data(object))
                XCTFail("Expected a closed identity failure")
                return .structure
            } catch let error as ImportFailure {
                return error
            }
        }

        let valid = try json(envelope())
        var missingModel = valid; missingModel.removeValue(forKey: "model")
        XCTAssertEqual(try failure(missingModel), .identityModelMissing)
        var unqualifiedRevision = valid; unqualifiedRevision["model"] = "gpt-5.6-sol-20260709"
        XCTAssertEqual(try failure(unqualifiedRevision), .identityModelRevisionWithoutProvider)
        var nonStringModel = valid; nonStringModel["model"] = 56
        XCTAssertEqual(try failure(nonStringModel), .identityModelNonString)
        var wrongModel = valid; wrongModel["model"] = "synthetic-secret-model-value"
        XCTAssertEqual(try failure(wrongModel), .identityModelMismatch)
        var missingProvider = valid; missingProvider.removeValue(forKey: "provider")
        XCTAssertEqual(try failure(missingProvider), .identityProviderMissing)
        var wrongProvider = valid; wrongProvider["provider"] = "synthetic-secret-provider-value"
        XCTAssertEqual(try failure(wrongProvider), .identityProviderMismatch)
        var wrongTier = valid; wrongTier["service_tier"] = "synthetic-secret-tier-value"
        XCTAssertEqual(try failure(wrongTier), .identityServiceTier)
        var wrongMessageModel = valid
        var choices = wrongMessageModel["choices"] as! [[String: Any]]
        var message = choices[0]["message"] as! [String: Any]
        message["model"] = "synthetic-secret-message-model-value"
        choices[0]["message"] = message; wrongMessageModel["choices"] = choices
        XCTAssertEqual(try failure(wrongMessageModel), .identityMessageModel)

        for code in [ImportFailure.identityModelMissing,
                     .identityModelRevisionWithoutProvider, .identityModelNonString, .identityModelMismatch,
                     .identityProviderMissing, .identityProviderMismatch,
                     .identityServiceTier, .identityMessageModel] {
            XCTAssertFalse(code.rawValue.contains("synthetic-secret"))
        }
    }

    func testRequestedAliasIsAcceptedOnlyWithAuthorizedProviderIdentity() throws {
        let valid = try json(envelope())
        for provider in ["openai", "OpenAI"] {
            var object = valid
            object["model"] = WorkoutImportContract.model
            object["provider"] = provider
            XCTAssertNoThrow(try WorkoutImportContract.parseEnvelope(data(object)), provider)
        }
        for provider in ["Azure", "OPENAI", "openai/fast", ""] {
            var object = valid
            object["model"] = WorkoutImportContract.model
            object["provider"] = provider
            XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(object))) { error in
                XCTAssertEqual(error as? ImportFailure, .identityProviderMismatch)
            }
        }
    }

    func testAdapterReportsResponseURLIdentityWithoutDisclosingURL() throws {
        let backend = SyntheticKeychain(); backend.data = Data("synthetic-key".utf8)
        let transport = CapturingTransport()
        let adapter = OpenRouterImportAdapter(credential: ImportCredentialStore(backend: backend), transport: transport)
        var outcome: WorkoutImportOutcome?
        adapter.generate(snapshot()) { outcome = $0 }
        let wrongURL = URL(string: "https://synthetic-secret.invalid/redirect")!
        let response = HTTPURLResponse(url: wrongURL, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        transport.complete(.success((try envelope(), response)))
        XCTAssertEqual(outcome, .providerFailure(.identityResponseURL))
        XCTAssertFalse(String(describing: outcome).contains(wrongURL.absoluteString))
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAdapterReportsRedirectAndContentTypeWithoutResponseDetails() throws {
        for (response, expected) in [
            (HTTPURLResponse(url: WorkoutImportContract.endpoint, statusCode: 307, httpVersion: "HTTP/1.1",
                             headerFields: ["Location": "https://synthetic-secret.invalid/redirect"])!, ImportFailure.redirect),
            (HTTPURLResponse(url: WorkoutImportContract.endpoint, statusCode: 200, httpVersion: "HTTP/1.1",
                             headerFields: ["Content-Type": "text/synthetic-secret"])!, .responseContentType)
        ] {
            let backend = SyntheticKeychain(); backend.data = Data("synthetic-key".utf8)
            let transport = CapturingTransport()
            let adapter = OpenRouterImportAdapter(credential: ImportCredentialStore(backend: backend), transport: transport)
            var outcome: WorkoutImportOutcome?
            adapter.generate(snapshot()) { outcome = $0 }
            transport.complete(.success((Data("synthetic-secret-response".utf8), response)))
            XCTAssertEqual(outcome, .providerFailure(expected))
            XCTAssertFalse(String(describing: outcome).contains("synthetic-secret"))
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testIdentityDiagnosticsReachFeedbackAsCodesOnly() {
        let codes: [ImportFailure] = [.identityResponseURL, .identityModelMissing,
                                      .identityModelRevisionWithoutProvider, .identityModelNonString, .identityModelMismatch,
                                      .identityProviderMissing, .identityProviderMismatch,
                                      .identityServiceTier, .identityMessageModel, .redirect, .responseContentType]
        for code in codes {
            let generator = SyntheticGenerator()
            let model = WorkoutImportViewModel(generator: generator,
                                               plans: PlansViewModel(repository: ImportRepositoryDouble()))
            model.begin(capabilities: known()); model.text = "Synthetic workout"
            model.reviewDisclosure(); model.consentAndSend()
            generator.complete(.providerFailure(code))
            XCTAssertEqual(model.feedback,
                           "Remote import failed (\(code.rawValue)). Nothing was saved. A new attempt requires a new disclosure.")
            XCTAssertFalse(model.feedback?.contains("Synthetic workout") ?? true)
        }
    }

    func testSentinelsVersionsOutcomePairingPathsAndAdditionalFields() throws {
        var valid = try json(modelOutput())
        var o = valid["outcome"] as! [String: Any]
        for (key, value) in [("reasonCategory", "missingRequiredField" as Any), ("affectedPaths", ["activity"]), ("type", "providerFailure"), ("extra", true)] {
            var changed = o; changed[key] = value; var root = valid; root["outcome"] = changed
            XCTAssertThrowsError(try WorkoutImportContract.parseModelOutput(data(root)))
        }
        for version in ["workout-import-model-output/v1", "unknown"] {
            valid["contractVersion"] = version; XCTAssertThrowsError(try WorkoutImportContract.parseModelOutput(data(valid)))
        }
        for (type, reason, paths) in [("clarificationRequired", "missingRequiredField", ["activity"]), ("unsupportedRequest", "unsupportedActivity", ["activity"]), ("refusal", "unsafeRequest", [])] {
            let sentinel: [String: Any] = ["present": false, "contractVersion": "notApplicable", "suggestedName": "", "activity": "notApplicable", "steps": []]
            o = ["type": type, "reasonCategory": reason, "affectedPaths": paths, "proposal": sentinel]
            let root: [String: Any] = ["contractVersion": "workout-import-model-output/v2", "outcome": o]
            XCTAssertNoThrow(try WorkoutImportContract.parseModelOutput(data(root)))
            for key in sentinel.keys {
                var s = sentinel; s[key] = "invalid"; var changed = o; changed["proposal"] = s
                XCTAssertThrowsError(try WorkoutImportContract.parseModelOutput(data(["contractVersion": "workout-import-model-output/v2", "outcome": changed])))
            }
            o["reasonCategory"] = "notApplicable"
            XCTAssertThrowsError(try WorkoutImportContract.parseModelOutput(data(["contractVersion": "workout-import-model-output/v2", "outcome": o])))
        }
        for raw in [try modelOutput().string.replacingOccurrences(of: "workout-proposal/v2", with: "workout-proposal/v1"),
                    try modelOutput().string.replacingOccurrences(of: "\"value\":0.5", with: "\"value\":0.5,\"value\":1"),
                    try modelOutput().string.replacingOccurrences(of: "\"unit\":\"minutes\"", with: "\"unit\":\"hours\"")] {
            XCTAssertThrowsError(try WorkoutImportContract.parseModelOutput(Data(raw.utf8)))
        }
    }

    func testExactDecimalsRejectRoundingOverflowAndFractionalSeconds() throws {
        XCTAssertEqual(try ExactImportDecimal.parse("1.609344"), Decimal(string: "1.609344"))
        XCTAssertEqual(try ExactImportDecimal.parse("0.5000000000000000000000000000000000000000"), Decimal(string: "0.5"))
        for token in ["", "1-2", "01", "1.2.3", "1234567890123456789012345678901234567890123456789", "1e999", "1e-999"] {
            XCTAssertThrowsError(try ExactImportDecimal.parse(token))
        }
        for duration in ["0.001", "1e50"] { XCTAssertThrowsError(try WorkoutProposalMapper.map(parsedProposal(duration: duration))) }
        XCTAssertThrowsError(try ExactImportDecimal.multiply(ExactImportDecimal.parse("1e127"), 100))
    }

    func testAdapterHasNoRetryAfterAnyFailureAndDiscardsCancelledLateResponse() throws {
        for status in [301, 302, 307, 308, 400, 401, 402, 403, 404, 429, 500, 503] {
            let backend = SyntheticKeychain(); backend.data = Data("synthetic-key".utf8)
            let transport = CapturingTransport()
            let tested = OpenRouterImportAdapter(credential: ImportCredentialStore(backend: backend), transport: transport)
            var outcome: WorkoutImportOutcome?
            tested.generate(snapshot()) { outcome = $0 }
            XCTAssertEqual(transport.requests.count, 1)
            XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
            transport.complete(.success((Data("synthetic-private-error".utf8), response(status))))
            XCTAssertNotNil(outcome); XCTAssertEqual(transport.requests.count, 1)
            XCTAssertFalse(String(describing: outcome).contains("synthetic-private-error"))
        }
        let backend = SyntheticKeychain(); backend.data = Data("synthetic-key".utf8)
        let transport = CapturingTransport()
        let tested = OpenRouterImportAdapter(credential: ImportCredentialStore(backend: backend), transport: transport)
        var calls = 0
        tested.generate(snapshot()) { _ in calls += 1 }; tested.cancel()
        transport.complete(.success((try envelope(), response(200))))
        XCTAssertEqual(calls, 0); XCTAssertEqual(transport.requests.count, 1)
        for failure in [ImportFailure.timeout, .cancelled, .transport] {
            tested.generate(snapshot()) { _ in calls += 1 }; transport.complete(.failure(failure))
        }
        XCTAssertEqual(calls, 3); XCTAssertEqual(transport.requests.count, 4)
    }

    func testPermittedEnvelopeMetadataIsClosedAndCannotChangeProposalMeaning() throws {
        var object = try json(envelope())
        object["system_fingerprint"] = "synthetic-fingerprint"
        object["service_tier"] = "default"
        let usage: [String: Any] = [
            "prompt_tokens": 100, "completion_tokens": 20, "total_tokens": 120, "cost": 0.001, "is_byok": false,
            "prompt_tokens_details": ["cached_tokens": 0, "cache_write_tokens": 0, "audio_tokens": 0, "video_tokens": 0],
            "completion_tokens_details": ["reasoning_tokens": 0, "audio_tokens": NSNull(), "accepted_prediction_tokens": 0, "rejected_prediction_tokens": 0],
            "cost_details": ["upstream_inference_cost": NSNull(), "upstream_inference_prompt_cost": 0.001, "upstream_inference_completions_cost": 0]
        ]
        object["usage"] = usage
        XCTAssertEqual(try WorkoutImportContract.parseEnvelope(data(object)), try WorkoutImportContract.parseEnvelope(envelope()))
        for field in ["prompt_tokens_details", "completion_tokens_details", "cost_details"] {
            var changed = usage
            var details = changed[field] as! [String: Any]; details["unexpected"] = true; changed[field] = details
            object["usage"] = changed
            XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(object)))
        }
        for (key, value) in [("total_tokens", 121 as Any), ("prompt_tokens", -1), ("cost", "not a number"), ("is_byok", "false"), ("unexpected", 0)] {
            var changed = usage; changed[key] = value; object["usage"] = changed
            XCTAssertThrowsError(try WorkoutImportContract.parseEnvelope(data(object)))
        }
    }

    func testEveryModelObjectIsClosedAndRequiredAtEveryDepth() throws {
        let original = try json(modelOutput())
        let paths: [[String]] = [[], ["outcome"], ["outcome", "proposal"]]
        func mutate(_ object: [String: Any], path: [String], operation: (inout [String: Any]) -> Void) -> [String: Any] {
            var result = object
            if let first = path.first {
                result[first] = mutate(result[first] as! [String: Any], path: Array(path.dropFirst()), operation: operation)
            } else { operation(&result) }
            return result
        }
        for path in paths {
            var node = original
            for key in path { node = node[key] as! [String: Any] }
            for key in node.keys {
                XCTAssertThrowsError(try WorkoutImportContract.parseModelOutput(data(mutate(original, path: path) { $0.removeValue(forKey: key) })))
            }
            XCTAssertThrowsError(try WorkoutImportContract.parseModelOutput(data(mutate(original, path: path) { $0["unexpected"] = true })))
        }
        let originalOutcome = original["outcome"] as! [String: Any]
        let originalProposal = originalOutcome["proposal"] as! [String: Any]
        let originalSteps = originalProposal["steps"] as! [[String: Any]]
        for path in [[], ["duration"], ["targetSpeed"], ["targetInclination"]] as [[String]] {
            var node = originalSteps[0]
            for key in path { node = node[key] as! [String: Any] }
            for key in Array(node.keys) + ["unexpected"] {
                var steps = originalSteps
                steps[0] = mutate(steps[0], path: path) {
                    if key == "unexpected" { $0[key] = true } else { $0.removeValue(forKey: key) }
                }
                var proposal = originalProposal; proposal["steps"] = steps
                var outcome = originalOutcome; outcome["proposal"] = proposal
                XCTAssertThrowsError(try WorkoutImportContract.parseModelOutput(data(["contractVersion": "workout-import-model-output/v2", "outcome": outcome])))
            }
        }
        for count in [0, 65] {
            var proposal = originalProposal; proposal["steps"] = Array(repeating: originalSteps[0], count: count)
            var outcome = originalOutcome; outcome["proposal"] = proposal
            XCTAssertThrowsError(try WorkoutImportContract.parseModelOutput(data(["contractVersion": "workout-import-model-output/v2", "outcome": outcome])))
        }
    }

    func testUnknownCapabilitiesAndMalformedRangesHaveNoPreviewThroughGenerator() throws {
        let malformedInclination = WorkoutTargetCapability<WorkoutInclinationRange>.supported(.init(
            minimum: .init(value: 2, unit: .percent), maximum: .init(value: 1, unit: .percent), increment: .init(value: 0, unit: .percent)))
        for capabilities in [WorkoutPlanCapabilities(speed: .unknown, inclination: .unknown),
                             .init(speed: .unsupported, inclination: .unsupported),
                             .init(speed: known().speed, inclination: malformedInclination)] {
            let repo = ImportRepositoryDouble(), generator = SyntheticGenerator()
            let plans = PlansViewModel(repository: repo)
            let tested = WorkoutImportViewModel(generator: generator, plans: plans)
            tested.begin(capabilities: capabilities); tested.text = "Synthetic workout"; tested.reviewDisclosure(); tested.consentAndSend()
            generator.complete(.proposal(try parsedProposal()))
            XCTAssertFalse(tested.validationIssues.isEmpty); XCTAssertNil(plans.preview); XCTAssertTrue(tested.text.isEmpty)
            tested.confirmSave(); XCTAssertTrue(repo.records.isEmpty)
        }
    }

    func testOldAttemptCannotOverwriteNewAttemptOrRestoreCancelledPreview() throws {
        let repo = ImportRepositoryDouble(), generator = SyntheticGenerator()
        let plans = PlansViewModel(repository: repo)
        let tested = WorkoutImportViewModel(generator: generator, plans: plans)
        tested.begin(capabilities: known()); tested.text = "Synthetic first"; tested.reviewDisclosure(); tested.consentAndSend()
        let old = generator.completion
        tested.text = "Synthetic second"; tested.reviewDisclosure(); tested.consentAndSend()
        old?(.proposal(try parsedProposal()))
        XCTAssertNil(plans.preview); XCTAssertTrue(tested.isSending)
        generator.complete(.proposal(try parsedProposal())); XCTAssertNotNil(plans.preview)
        tested.cancel(); old?(.proposal(try parsedProposal())); XCTAssertNil(plans.preview); XCTAssertTrue(repo.records.isEmpty)
    }

    private func parsedProposal(duration: String = "0.5") throws -> WorkoutProposal {
        guard case let .proposal(p) = try WorkoutImportContract.parseModelOutput(modelOutput(duration: duration)) else { throw ImportFailure.structure }; return p
    }
    private func snapshot() -> ImportRequestSnapshot { .init(text: "Synthetic workout", capabilities: known()) }
    private func modelOutput(duration: String = "0.5") throws -> Data {
        Data("""
        {"contractVersion":"workout-import-model-output/v2","outcome":{"type":"proposal","reasonCategory":"notApplicable","affectedPaths":[],"proposal":{"present":true,"contractVersion":"workout-proposal/v2","suggestedName":"Synthetic plan","activity":"indoorRunning","steps":[
        {"kind":"warmUp","label":"Warm","duration":{"value":\(duration),"unit":"minutes"},"targetSpeed":{"value":5,"unit":"kilometresPerHour"},"targetInclination":{"value":0,"unit":"percent"}},
        {"kind":"interval","label":"Run","duration":{"value":2,"unit":"minutes"},"targetSpeed":{"value":5,"unit":"milesPerHour"},"targetInclination":{"value":1,"unit":"percent"}},
        {"kind":"coolDown","label":"Cool","duration":{"value":60,"unit":"seconds"},"targetSpeed":{"value":4,"unit":"kilometresPerHour"},"targetInclination":{"value":0,"unit":"percent"}}]}}}
        """.utf8)
    }
    private func envelope() throws -> Data {
        try data(["id": "synthetic-completion", "created": 1, "object": "chat.completion", "model": WorkoutImportContract.revision, "provider": "OpenAI",
                  "choices": [["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": modelOutput().string]]]])
    }
    private func json(_ data: Data) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
    private func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: .sortedKeys) }
}

private extension Data { var string: String { String(decoding: self, as: UTF8.self) } }
private extension Array { var only: Element? { count == 1 ? self[0] : nil } }
private func known(increment: Decimal = Decimal(string: "0.00001")!) -> WorkoutPlanCapabilities {
    .init(speed: .supported(.init(minimum: .init(value: 0, unit: .kilometresPerHour), maximum: .init(value: 20, unit: .kilometresPerHour), increment: .init(value: increment, unit: .kilometresPerHour))),
          inclination: .supported(.init(minimum: .init(value: 0, unit: .percent), maximum: .init(value: 15, unit: .percent), increment: .init(value: 1, unit: .percent))))
}
private func response(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: WorkoutImportContract.endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
}
@MainActor private final class SyntheticKeychain: ImportKeychainBackend {
    var data: Data?; var fail = false; var reads = 0
    func contains() throws -> Bool { if fail { throw ImportFailure.missingCredential }; return data != nil }
    func add(_ data: Data) throws { if fail || self.data != nil { throw ImportFailure.missingCredential }; self.data = data }
    func replace(_ data: Data) throws { if fail || self.data == nil { throw ImportFailure.missingCredential }; self.data = data }
    func delete() throws { if fail { throw ImportFailure.missingCredential }; data = nil }
    func read() throws -> Data { reads += 1; if fail { throw ImportFailure.missingCredential }; guard let data else { throw ImportFailure.missingCredential }; return data }
}
@MainActor private final class CapturingTransport: ImportTransport {
    var requests: [URLRequest] = []
    var completion: (@MainActor (Result<(Data, HTTPURLResponse), ImportFailure>) -> Void)?
    func send(_ request: URLRequest, completion: @escaping @MainActor (Result<(Data, HTTPURLResponse), ImportFailure>) -> Void) { requests.append(request); self.completion = completion }
    func complete(_ result: Result<(Data, HTTPURLResponse), ImportFailure>) { completion?(result) }
    func cancel() {} // Deliberately adversarial: permits late completion after cancellation.
}
@MainActor private final class SyntheticGenerator: WorkoutImportGenerating {
    var requests: [ImportRequestSnapshot] = []
    var completion: (@MainActor (WorkoutImportOutcome) -> Void)?
    func generate(_ request: ImportRequestSnapshot, completion: @escaping @MainActor (WorkoutImportOutcome) -> Void) { requests.append(request); self.completion = completion }
    func complete(_ value: WorkoutImportOutcome) { completion?(value) }
    func cancel() {}
}
private final class ImportRepositoryDouble: SavedPlanRepositoryProtocol {
    var records: [SavedPlanRecord] = []; var fail = false
    func list() -> SavedPlanRepositoryStatus { .init(canonical: records.isEmpty ? .empty : .available(records: records), staging: .absent) }
    func create(_ plan: WorkoutPlanValidator.ValidatedPlan) throws -> SavedPlanRecord {
        if fail { throw SavedPlanMutationFailure.writeFailed(.atomicReplacement) }
        let record = SavedPlanRecord(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), modifiedAt: Date(timeIntervalSince1970: 1), plan: plan.plan)
        records.append(record); return record
    }
    func replace(id: UUID, with plan: WorkoutPlanValidator.ValidatedPlan) throws -> SavedPlanRecord { throw SavedPlanMutationFailure.recordNotFound(id) }
}

@MainActor
final class ImportSessionTransportTests: XCTestCase {
    func testEphemeralConfigurationDisablesPersistence() {
        let configuration = SessionImportTransport.configuration()
        XCTAssertNil(configuration.urlCache); XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage); XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 60)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 180)
        XCTAssertNil(configuration.identifier)
    }
    func testLocalProtocolReceivesOneRequestAndTimeoutStopsIt() async throws {
        LocalImportProtocol.reset(status: nil)
        let transport = SessionImportTransport(makeConfiguration: mockConfiguration, deadlineNanoseconds: 30_000_000)
        let done = expectation(description: "independent total deadline")
        let request = try ImportResources().request(for: .init(text: "Synthetic timeout", capabilities: known()))
        transport.send(request) { result in
            guard case .failure(.timeout) = result else { XCTFail("Expected timeout"); done.fulfill(); return }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(LocalImportProtocol.count, 1)
        transport.cancel()
    }
    func testResponseCannotWinAfterAbsoluteDeadlineEvenIfTimerCallbackIsLate() async throws {
        LocalImportProtocol.reset(status: 200)
        let transport = SessionImportTransport(makeConfiguration: mockConfiguration, deadlineNanoseconds: 0)
        let done = expectation(description: "expired before callback")
        transport.send(try ImportResources().request(for: .init(text: "Synthetic expired request", capabilities: known()))) { result in
            guard case .failure(.timeout) = result else { XCTFail("Late success must not win"); done.fulfill(); return }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 3)
        XCTAssertLessThanOrEqual(LocalImportProtocol.count, 1)
    }

    func testLocalProtocolHTTPFailuresNeverRetry() async throws {
        for status in [401, 429, 503, 302, 307] {
            LocalImportProtocol.reset(status: status)
            let transport = SessionImportTransport(makeConfiguration: mockConfiguration)
            let done = expectation(description: "one response \(status)")
            let request = try ImportResources().request(for: .init(text: "Synthetic status", capabilities: known()))
            transport.send(request) { result in
                guard case let .success((_, response)) = result else { XCTFail("Expected local HTTP response"); done.fulfill(); return }
                XCTAssertEqual(response.statusCode, status); done.fulfill()
            }
            await fulfillment(of: [done], timeout: 3)
            XCTAssertEqual(LocalImportProtocol.count, 1)
        }
    }
    func testCancellationCompletesOnceAndNoSecondRequest() async throws {
        LocalImportProtocol.reset(status: nil)
        let transport = SessionImportTransport(makeConfiguration: mockConfiguration)
        var completions = 0
        transport.send(try ImportResources().request(for: .init(text: "Synthetic cancellation", capabilities: known()))) { result in
            completions += 1
            guard case .failure(.cancelled) = result else { return XCTFail("Expected cancellation") }
        }
        transport.cancel(); transport.cancel()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(completions, 1); XCTAssertLessThanOrEqual(LocalImportProtocol.count, 1)
    }
    func testRedirectDelegateRejectsSecondRequest() {
        let session = URLSession(configuration: mockConfiguration())
        let task = session.dataTask(with: WorkoutImportContract.endpoint)
        let delegate = ImportSessionDelegate()
        var callbackCount = 0
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response(302),
                            newRequest: URLRequest(url: URL(string: "https://example.invalid/redirect")!)) { redirected in
            XCTAssertNil(redirected); callbackCount += 1
        }
        XCTAssertEqual(callbackCount, 1)
        task.cancel(); session.invalidateAndCancel()
    }

    private nonisolated func mockConfiguration() -> URLSessionConfiguration {
        let configuration = SessionImportTransport.configuration()
        configuration.protocolClasses = [LocalImportProtocol.self]
        return configuration
    }
}

// Handles every URL in this session. No request can escape to a network provider.
private final class LocalImportProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var status: Int?
    private static var requests = 0
    static var count: Int { lock.lock(); defer { lock.unlock() }; return requests }
    static func reset(status: Int?) { lock.lock(); defer { lock.unlock() }; self.status = status; requests = 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests += 1; let status = Self.status; Self.lock.unlock()
        guard let status else { return }
        client?.urlProtocol(self, didReceive: response(status), cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("synthetic-private-error".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
