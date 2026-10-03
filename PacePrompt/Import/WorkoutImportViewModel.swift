import Combine
import Foundation

@MainActor
final class WorkoutImportViewModel: ObservableObject {
    @Published private(set) var isPresented = false
    @Published var text = "" { didSet { if text != oldValue { requestChanged() } } }
    @Published private(set) var disclosure: ImportRequestSnapshot?
    @Published private(set) var isSending = false
    @Published private(set) var outcome: WorkoutImportOutcome?
    @Published private(set) var feedback: String?
    @Published private(set) var mappingFailure = false
    @Published private(set) var validationIssues: [WorkoutPlanValidationIssue] = []
    private let generator: any WorkoutImportGenerating
    private let plans: PlansViewModel
    private var capabilities = WorkoutPlanCapabilities(speed: .unknown, inclination: .unknown)
    private var requestID: UUID?
    private var previewCapabilities: WorkoutPlanCapabilities?
    private var foreground = true
    private var protectedDataAvailable = true
#if DEBUG
    private let diagnostics: any ImportDiagnosticSink
#endif

#if DEBUG
    init(generator: any WorkoutImportGenerating, plans: PlansViewModel,
         diagnostics: any ImportDiagnosticSink = UnifiedImportDiagnosticSink.shared) {
        self.generator = generator
        self.plans = plans
        self.diagnostics = diagnostics
    }
#else
    init(generator: any WorkoutImportGenerating, plans: PlansViewModel) { self.generator = generator; self.plans = plans }
#endif
    func begin(capabilities: WorkoutPlanCapabilities) {
        cancel()
        self.capabilities = capabilities
        isPresented = true
    }
    func updateCapabilities(_ value: WorkoutPlanCapabilities) {
        guard value != capabilities else { return }
        capabilities = value
        requestChanged()
    }
    func reviewDisclosure() {
        guard foreground, protectedDataAvailable, !isSending,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        disclosure = .init(text: text, capabilities: capabilities)
    }
    func dismissDisclosure() {
        // A programmatic dismissal after consent must not cancel the accepted send.
        guard disclosure != nil else { return }
        requestChanged()
        text = ""
    }
    func consentAndSend() {
        guard foreground, protectedDataAvailable, !isSending, let snapshot = disclosure,
              snapshot == ImportRequestSnapshot(text: text, capabilities: capabilities) else { return }
        disclosure = nil // One affirmative decision permits exactly one request.
        outcome = nil; feedback = nil; mappingFailure = false; validationIssues = []
        let id = UUID(); requestID = id; isSending = true
#if DEBUG
        diagnostics.record(.check(.disclosure, .accepted))
#endif
        generator.generate(snapshot) { [weak self] result in
            guard let self, self.requestID == id, self.foreground, self.protectedDataAvailable,
                  snapshot == ImportRequestSnapshot(text: self.text, capabilities: self.capabilities) else { return }
            self.requestID = nil; self.isSending = false
            switch result {
            case let .proposal(proposal):
                do {
                    let plan = try WorkoutProposalMapper.map(proposal)
#if DEBUG
                    self.diagnostics.record(.check(.deterministicMapping, .accepted))
#endif
                    switch self.plans.reviewImportedForAuthoring(plan) {
                    case let .failure(failure):
#if DEBUG
                        self.diagnostics.record(.check(.localCapabilityValidation, .rejected))
                        self.diagnostics.record(.check(.previewEligibility, .rejected))
                        self.diagnostics.record(.terminal(.localValidationFailure))
#endif
                        self.terminal("Some plan details need attention. Review the listed fields or enter the plan manually.")
                        self.validationIssues = failure.issues
                    case .success:
#if DEBUG
                        self.diagnostics.record(.check(.localCapabilityValidation, .accepted))
                        self.diagnostics.record(.check(.previewEligibility, .accepted))
                        self.diagnostics.record(.terminal(.previewEligible))
#endif
                        self.previewCapabilities = self.capabilities
                        // The untrusted proposal and raw exchange are not retained after mapping.
                        self.outcome = nil
                    }
                } catch {
#if DEBUG
                    self.diagnostics.record(.check(.deterministicMapping, .rejected))
                    self.diagnostics.record(.check(.previewEligibility, .rejected))
                    self.diagnostics.record(.terminal(.mappingFailure))
#endif
                    self.terminal("The values could not be converted exactly. Use whole seconds and explicit units, or enter the plan manually.")
                    self.mappingFailure = true
                }
            default:
#if DEBUG
                self.diagnostics.record(.check(.previewEligibility, .rejected))
                self.diagnostics.record(.terminal(Self.diagnosticTerminal(result)))
#endif
                self.terminal(Self.message(result))
                self.outcome = result // Only closed codes/paths, never provider prose.
            }
        }
    }
    func confirmSave(acknowledging mismatch: HistoricalPlanCompatibility? = nil) {
        guard foreground, protectedDataAvailable, previewCapabilities == capabilities,
              plans.preview != nil else { requestChanged(); return }
        plans.confirmSave(acknowledging: mismatch)
        if let error = plans.saveError {
#if DEBUG
            diagnostics.record(.terminal(.saveFailure))
#endif
            if plans.saveRequiresHistoricalReview { feedback = error }
            else { terminal(error) }
        } else if plans.preview == nil {
#if DEBUG
            diagnostics.record(.terminal(.saved))
#endif
            cancel()
        }
    }
    func returnToInput() { requestChanged() }
    func cancel() {
        requestChanged()
        text = ""
        isPresented = false
    }
    func setForeground(_ available: Bool) {
        foreground = available
        if !available { cancel() }
    }
    func setProtectedDataAvailable(_ available: Bool) {
        protectedDataAvailable = available
        if !available { cancel() }
    }
    private func requestChanged() {
        requestID = nil; generator.cancel(); disclosure = nil; isSending = false
        if previewCapabilities != nil { plans.cancelEditor() }
        previewCapabilities = nil; outcome = nil; feedback = nil; mappingFailure = false; validationIssues = []
    }
    private func terminal(_ message: String) {
        requestChanged()
        plans.cancelEditor()
        text = ""
        feedback = message
    }
    static func fieldLabel(_ path: String) -> String {
        switch path {
        case "activity": "activity"
        case "steps": "workout steps"
        case "steps.repetitions": "step repetitions"
        case "steps.kind": "step type"
        case "steps.duration", "steps.duration.value": "step duration"
        case "steps.duration.unit": "duration unit"
        case "steps.targetSpeed", "steps.targetSpeed.value": "step speed"
        case "steps.targetSpeed.unit": "speed unit"
        case "steps.targetInclination", "steps.targetInclination.value": "step incline"
        case "steps.targetInclination.unit": "incline unit"
        case "capabilities.speed": "treadmill speed support"
        case "capabilities.inclination": "treadmill incline support"
        default: "workout details"
        }
    }
    static func failureMessage(_ failure: ImportFailure) -> String {
        switch failure {
        case .missingCredential: "Add your OpenRouter key in Settings."
        case .authentication: "OpenRouter did not accept your key. Check it in Settings."
        case .credits: "Check the credit balance on your OpenRouter account."
        case .restrictedRoute: "Your OpenRouter account does not allow the required service. Check your account settings."
        case .rateLimited: "The service is receiving too many requests. Try again later."
        case .transport: "Could not reach the import service. Check your internet connection."
        case .timeout: "The import service did not respond in time."
        case .cancelled: "The request was cancelled."
        case .unavailable: "The import service is unavailable. Try again later."
        case .resources: "The import instructions could not be loaded."
        case .mapping: "The returned values could not be converted exactly. Try whole seconds and explicit units."
        case .structure, .responseContentType: "The service returned an unreadable workout."
        case .identity, .redirect, .identityResponseURL, .identityModelMissing,
             .identityModelRevisionWithoutProvider, .identityModelNonString, .identityModelMismatch,
             .identityProviderMissing, .identityProviderMismatch, .identityServiceTier, .identityMessageModel:
            "The response could not be verified as coming from the agreed AI service."
        }
    }
    static func message(_ outcome: WorkoutImportOutcome) -> String {
        func describe(_ problem: ImportProblem) -> String {
            let action: String
            switch problem.reason {
            case "missingRequiredField": action = "Include every required activity, step, value and unit."
            case "ambiguousRequiredField": action = "State one explicit value and unit for each field."
            case "contradictoryRequest": action = "Resolve contradictory workout instructions."
            case "unsupportedActivity": action = "Only indoor treadmill walking and running are supported."
            case "unsupportedUnit": action = "Use seconds or minutes, km/h or mph, and percent inclination."
            case "knownCapabilityUnsupported": action = "The current capability state does not support this target."
            case "excessiveComplexity": action = "Use at most 64 explicit steps without nested repetitions."
            case "medicalRequest": action = "Medical exercise prescriptions cannot be imported. Use a non-medical workout description."
            case "unsafeRequest", "promptInjection": action = "This request was refused. Provide a workout description that preserves safety controls."
            default: action = "Describe an importable treadmill workout with duration, speed and inclination."
            }
            return action + (problem.paths.isEmpty ? "" : " Affected fields: " + problem.paths.map(Self.fieldLabel).joined(separator: ", ") + ".")
        }
        switch outcome {
        case let .clarificationRequired(p): return "Clarification required. " + describe(p)
        case let .unsupportedRequest(p): return "Unsupported request. " + describe(p)
        case let .refusal(p): return describe(p)
        case let .providerUnavailable(reason): return "Import unavailable. " + Self.failureMessage(reason) + " Nothing was saved. Review and agree to a new request before trying again."
        case let .providerFailure(reason): return "Import failed. " + Self.failureMessage(reason) + " Nothing was saved. Review and agree to a new request before trying again."
        case .proposal: return ""
        }
    }
#if DEBUG
    private static func diagnosticTerminal(_ outcome: WorkoutImportOutcome) -> ImportDiagnosticTerminal {
        switch outcome {
        case .proposal: .previewEligible
        case .clarificationRequired: .clarificationRequired
        case .unsupportedRequest: .unsupportedRequest
        case .refusal: .refusal
        case .providerUnavailable: .providerUnavailable
        case .providerFailure: .providerFailure
        }
    }
#endif
}
