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
    @Published private(set) var pendingDeletion: SavedPlanRecord?
    @Published private(set) var deletionError: String?
    @Published private(set) var isExportPresented = false
    @Published private(set) var selectedExportRecordIDs: Set<UUID> = []
    @Published private(set) var exportPreview: SavedPlanExportPreview?
    @Published private(set) var shareArtifact: SavedPlanExportArtifact?
    @Published private(set) var exportError: String?

    private let repository: any SavedPlanRepositoryProtocol
    private let exporter: any SavedPlanExporting
    private let makeNewDraft: () -> ManualWorkoutDraft
    private let now: () -> Date

    init(
        repository: any SavedPlanRepositoryProtocol = SavedPlanRepository(),
        exporter: any SavedPlanExporting = SavedPlanExporter(),
        makeNewDraft: @escaping () -> ManualWorkoutDraft = { .empty },
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.exporter = exporter
        self.makeNewDraft = makeNewDraft
        self.now = now
        repositoryStatus = repository.list()
    }

    var records: [SavedPlanRecord] {
        guard case let .available(records) = repositoryStatus.canonical else { return [] }
        return records
    }

    var libraryPresentation: PlansLibraryPresentation {
        PlansLibraryPresentation(status: repositoryStatus)
    }

    var canMutate: Bool {
        libraryPresentation.canCreate
    }

    var isEditorPresented: Bool { draft != nil }

    var canBeginExport: Bool {
        libraryPresentation.canExport
    }

    var canPreviewExport: Bool {
        isExportPresented && !selectedExportRecordIDs.isEmpty
    }

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

    func requestDeletion(of record: SavedPlanRecord) {
        guard canMutate, records.contains(where: { $0.id == record.id }) else { return }
        pendingDeletion = record
        deletionError = nil
    }

    func cancelDeletion() {
        pendingDeletion = nil
    }

    func confirmDeletion() {
        guard let pendingDeletion else { return }
        self.pendingDeletion = nil
        deletionError = nil

        guard canMutate else {
            deletionError = "Deletion was not confirmed because saved-plan storage is not writable. No plan was removed from this list. Resolve the storage issue and retry."
            return
        }

        do {
            try repository.delete(id: pendingDeletion.id)
            repositoryStatus = repository.list()
        } catch {
            deletionError = Self.deletionMessage(for: error)
        }
    }

    func dismissDeletionError() {
        deletionError = nil
    }

    func beginExport() {
        guard canBeginExport else { return }
        isExportPresented = true
        selectedExportRecordIDs = []
        exportPreview = nil
        shareArtifact = nil
        exportError = nil
    }

    func toggleExportSelection(_ record: SavedPlanRecord) {
        guard isExportPresented,
              exportPreview == nil,
              records.contains(where: { $0.id == record.id }) else {
            return
        }
        if selectedExportRecordIDs.contains(record.id) {
            selectedExportRecordIDs.remove(record.id)
        } else {
            selectedExportRecordIDs.insert(record.id)
        }
        exportError = nil
    }

    func reviewExport() {
        exportError = nil
        guard canPreviewExport,
              repositoryStatus.staging == .absent,
              case let .available(currentRecords) = repositoryStatus.canonical else {
            exportError = "Saved plans are not currently available for structured export. No file was created."
            return
        }

        let selectedRecords = currentRecords.filter { selectedExportRecordIDs.contains($0.id) }
        guard selectedRecords.count == selectedExportRecordIDs.count else {
            exportError = "A selected plan is no longer available. Review the current saved plans and select them again. No file was created."
            return
        }

        exportPreview = SavedPlanExportPreview(
            createdAt: now(),
            fileName: SavedPlanExportSchema.fileName,
            records: selectedRecords
        )
    }

    func returnToExportSelection() {
        exportPreview = nil
        exportError = nil
    }

    func prepareExportForSharing() {
        exportError = nil
        guard let exportPreview else { return }

        let latestStatus = repository.list()
        repositoryStatus = latestStatus
        guard latestStatus.staging == .absent,
              case let .available(currentRecords) = latestStatus.canonical,
              currentRecords.filter({ selectedExportRecordIDs.contains($0.id) }) == exportPreview.records else {
            self.exportPreview = nil
            exportError = "Saved plans changed or became unavailable after preview. Review the current records again. No file was created."
            return
        }

        do {
            shareArtifact = try exporter.prepare(exportPreview)
        } catch {
            exportError = Self.exportMessage(for: error)
        }
    }

    func completeSharing() {
        guard let shareArtifact else { return }
        self.shareArtifact = nil
        do {
            try exporter.cleanup(shareArtifact)
            clearExportFlow()
        } catch {
            clearExportFlow(preservingError: Self.exportMessage(for: error))
        }
    }

    func cancelExport() {
        guard let shareArtifact else {
            clearExportFlow()
            return
        }
        self.shareArtifact = nil
        do {
            try exporter.cleanup(shareArtifact)
            clearExportFlow()
        } catch {
            clearExportFlow(preservingError: Self.exportMessage(for: error))
        }
    }

    func dismissExportError() {
        exportError = nil
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

    // Production import supplies a mapped but unvalidated plan. The existing
    // validator, preview value and explicit confirmation own persistence.
    func reviewImportedPlan(_ plan: WorkoutPlan, against capabilities: WorkoutPlanCapabilities)
        -> Result<Void, WorkoutPlanValidationFailure> {
        cancelEditor()
        switch WorkoutPlanValidator.validate(plan, against: capabilities) {
        case let .failure(failure): return .failure(failure)
        case let .success(validated):
            preview = WorkoutPlanPreview(validatedPlan: validated)
            return .success(())
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

    private func clearExportFlow(preservingError error: String? = nil) {
        isExportPresented = false
        selectedExportRecordIDs = []
        exportPreview = nil
        shareArtifact = nil
        exportError = error
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

    private static func deletionMessage(for error: Error) -> String {
        guard let failure = error as? SavedPlanMutationFailure else {
            return "Deletion was not confirmed. The existing plan remains listed. Try again."
        }
        switch failure {
        case .recordNotFound:
            return "Deletion was not confirmed because this saved plan is no longer available. No other plan was deleted."
        case .blocked:
            return "Deletion was not confirmed because saved-plan storage is not writable. No plan was removed from this list. Resolve the storage issue and retry."
        case let .writeFailed(stage):
            return "Deletion was not confirmed during \(stage.displayName). The existing plan remains listed. Try again."
        }
    }

    private static func exportMessage(for error: Error) -> String {
        guard let failure = error as? SavedPlanExportFailure else {
            return "The export file could not be prepared. Saved plans were left unchanged. Try again."
        }
        switch failure {
        case .noRecords:
            return "Choose at least one saved plan before exporting. No file was created."
        case .encoding:
            return "The selected plans could not be encoded. Saved plans were left unchanged and no file was shared."
        case .directoryPreparation:
            return "Protected temporary storage could not be prepared. Saved plans were left unchanged and no file was shared."
        case .previousArtifactCleanup:
            return "A previous temporary export could not be removed, so it was not replaced or shared."
        case .protectedWrite:
            return "The export could not be written to protected temporary storage. Saved plans were left unchanged."
        case .fileProtection:
            return "Complete file protection could not be verified, so the temporary export was not shared."
        case .cleanup:
            return "The temporary export could not be removed after sharing. Retry export cleanup before creating another copy."
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
