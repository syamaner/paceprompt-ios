import Combine
import Foundation

@MainActor
final class PlansViewModel: ObservableObject {
    @Published private(set) var repositoryStatus: SavedPlanRepositoryStatus
    @Published var draft: ManualWorkoutDraft?
    @Published private(set) var editingRecordID: UUID?
    @Published private(set) var preview: WorkoutPlanPreview?
    @Published private(set) var inputIssues: [ManualWorkoutInputIssue] = []
    @Published private(set) var validationIssues: [WorkoutPlanValidationIssue] = []
    @Published private(set) var saveError: String?

    private let repository: any SavedPlanRepositoryProtocol
    private let makeNewDraft: () -> ManualWorkoutDraft

    init(
        repository: any SavedPlanRepositoryProtocol = SavedPlanRepository(),
        makeNewDraft: @escaping () -> ManualWorkoutDraft = { .empty }
    ) {
        self.repository = repository
        self.makeNewDraft = makeNewDraft
        repositoryStatus = repository.list()
    }

    var records: [SavedPlanRecord] {
        guard case let .available(records) = repositoryStatus.canonical else { return [] }
        return records
    }

    var canMutate: Bool {
        guard repositoryStatus.staging == .absent else { return false }
        return switch repositoryStatus.canonical {
        case .empty, .available:
            true
        case .protectedDataUnavailable,
             .readFailure,
             .corruptData,
             .partialWriteDetected,
             .unsupportedStoreVersion,
             .unsupportedPlanVersion:
            false
        }
    }

    var isEditorPresented: Bool { draft != nil }

    func reload() {
        repositoryStatus = repository.list()
    }

    func beginCreate() {
        guard canMutate else { return }
        editingRecordID = nil
        draft = makeNewDraft()
        clearTransientResults()
    }

    func beginEdit(_ record: SavedPlanRecord) {
        guard canMutate else { return }
        editingRecordID = record.id
        draft = ManualWorkoutDraft(plan: record.plan)
        clearTransientResults()
    }

    func addStep() {
        guard var draft else { return }
        if draft.steps.last?.kind == .coolDown {
            draft.steps.insert(
                ManualWorkoutStepDraft(kind: .recovery),
                at: draft.steps.index(before: draft.steps.endIndex)
            )
        } else {
            let kind: WorkoutStepKind
            switch draft.steps.count {
            case 0: kind = .warmUp
            case 1: kind = .interval
            default: kind = .coolDown
            }
            draft.steps.append(ManualWorkoutStepDraft(kind: kind))
        }
        self.draft = draft
        clearValidationResults()
    }

    func deleteSteps(at offsets: IndexSet) {
        guard var draft else { return }
        draft.steps.remove(atOffsets: offsets)
        self.draft = draft
        clearValidationResults()
    }

    func moveSteps(from offsets: IndexSet, to destination: Int) {
        guard var draft else { return }
        draft.steps.move(fromOffsets: offsets, toOffset: destination)
        self.draft = draft
        clearValidationResults()
    }

    func draftDidChange() {
        guard preview == nil else { return }
        inputIssues = []
        validationIssues = []
        saveError = nil
    }

    func validateForPreview(
        against capabilities: WorkoutPlanCapabilities,
        locale: Locale = .autoupdatingCurrent
    ) {
        guard let draft else { return }
        clearTransientResults()

        switch ManualWorkoutDraftParser.parse(draft, locale: locale) {
        case let .failure(failure):
            inputIssues = failure.issues
        case let .success(plan):
            switch WorkoutPlanValidator.validate(plan, against: capabilities) {
            case let .failure(failure):
                validationIssues = failure.issues
            case let .success(validatedPlan):
                preview = WorkoutPlanPreview(validatedPlan: validatedPlan)
            }
        }
    }

    func returnToEditing() {
        preview = nil
        saveError = nil
    }

    func confirmSave() {
        guard canMutate, let preview else { return }
        saveError = nil
        do {
            if let editingRecordID {
                _ = try repository.replace(id: editingRecordID, with: preview.validatedPlan)
            } else {
                _ = try repository.create(preview.validatedPlan)
            }
            repositoryStatus = repository.list()
            cancelEditor()
        } catch {
            saveError = Self.message(for: error, editing: editingRecordID != nil)
            repositoryStatus = repository.list()
        }
    }

    func cancelEditor() {
        draft = nil
        editingRecordID = nil
        clearTransientResults()
    }

    private func clearValidationResults() {
        preview = nil
        inputIssues = []
        validationIssues = []
        saveError = nil
    }

    private func clearTransientResults() {
        clearValidationResults()
    }

    private static func message(for error: Error, editing: Bool) -> String {
        guard let failure = error as? SavedPlanMutationFailure else {
            return "The plan could not be \(editing ? "updated" : "saved"). Existing plans were left unchanged. Try again."
        }
        switch failure {
        case .recordNotFound:
            return "This saved plan is no longer available to edit. Existing plans were left unchanged."
        case .blocked:
            return "Saved-plan storage is not currently writable. Existing plans were left unchanged. Return to Plans and retry after the storage issue is resolved."
        case let .writeFailed(stage):
            return "The plan could not be \(editing ? "updated" : "saved") during \(stage.displayName). Existing plans were left unchanged. Try again."
        }
    }
}

private extension SavedPlanMutationFailure.WriteStage {
    var displayName: String {
        switch self {
        case .encoding: "plan encoding"
        case .directoryPreparation: "storage preparation"
        case .fileProtection: "file protection"
        case .backupExclusion: "backup exclusion"
        case .stagingWrite: "the protected staging write"
        case .stagingValidation: "staging validation"
        case .synchronization: "file synchronisation"
        case .atomicReplacement: "the atomic replacement"
        }
    }
}
