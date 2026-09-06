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

    init(generator: any WorkoutImportGenerating, plans: PlansViewModel) { self.generator = generator; self.plans = plans }
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
        generator.generate(snapshot) { [weak self] result in
            guard let self, self.requestID == id, self.foreground, self.protectedDataAvailable,
                  snapshot == ImportRequestSnapshot(text: self.text, capabilities: self.capabilities) else { return }
            self.requestID = nil; self.isSending = false
            switch result {
            case let .proposal(proposal):
                do {
                    let plan = try WorkoutProposalMapper.map(proposal)
                    switch self.plans.reviewImportedPlan(plan, against: self.capabilities) {
                    case let .failure(failure):
                        self.terminal("Local validation blocked this plan. Review the listed fields or use manual entry.")
                        self.validationIssues = failure.issues
                    case .success:
                        self.previewCapabilities = self.capabilities
                        // The untrusted proposal and raw exchange are not retained after mapping.
                        self.outcome = nil
                    }
                } catch {
                    self.terminal("Exact unit conversion failed. Use representable values and whole canonical seconds, or enter the plan manually.")
                    self.mappingFailure = true
                }
            default:
                self.terminal(Self.message(result))
                self.outcome = result // Only closed codes/paths, never provider prose.
            }
        }
    }
    func confirmSave() {
        guard foreground, protectedDataAvailable, previewCapabilities == capabilities,
              plans.preview != nil else { requestChanged(); return }
        plans.confirmSave()
        if let error = plans.saveError { terminal(error) }
        else if plans.preview == nil { cancel() }
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
    private static func message(_ outcome: WorkoutImportOutcome) -> String {
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
            return action + (problem.paths.isEmpty ? "" : " Affected fields: " + problem.paths.joined(separator: ", ") + ".")
        }
        switch outcome {
        case let .clarificationRequired(p): return "Clarification required. " + describe(p)
        case let .unsupportedRequest(p): return "Unsupported request. " + describe(p)
        case let .refusal(p): return describe(p)
        case let .providerUnavailable(reason): return "Remote import unavailable (\(reason.rawValue)). Check the stored key or route availability, then review a new disclosure to try again."
        case let .providerFailure(reason): return "Remote import failed (\(reason.rawValue)). Nothing was saved. A new attempt requires a new disclosure."
        case .proposal: return ""
        }
    }
}
