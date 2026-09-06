import SwiftUI

struct PlansView: View {
    @ObservedObject var viewModel: PlansViewModel
    let capabilities: WorkoutPlanCapabilities
    var beginImport: (() -> Void)? = nil

    var body: some View {
        Group {
            switch viewModel.repositoryStatus.canonical {
            case .empty:
                emptyView
            case let .available(records):
                availableView(records)
            case .protectedDataUnavailable:
                unavailableView(
                    title: "Plans are locked",
                    description: "Unlock this iPhone, then retry. PacePrompt will not treat protected data as an empty plan list."
                )
            case .readFailure:
                unavailableView(
                    title: "Plans could not be read",
                    description: "The saved-plan file was preserved. Check storage access, then retry."
                )
            case .corruptData:
                unavailableView(
                    title: "Saved plans are corrupt",
                    description: "PacePrompt preserved the stored bytes and disabled changes. Recovery is outside this slice."
                )
            case .partialWriteDetected:
                unavailableView(
                    title: "An incomplete write was detected",
                    description: "PacePrompt preserved the stored files and disabled changes. Recovery is outside this slice."
                )
            case let .unsupportedStoreVersion(version):
                unavailableView(
                    title: "Saved-plan version is unsupported",
                    description: "Store version \(version) needs a compatible PacePrompt version. No data was changed."
                )
            case let .unsupportedPlanVersion(_, version):
                unavailableView(
                    title: "A workout version is unsupported",
                    description: "Workout schema version \(version) needs a compatible PacePrompt version. No data was changed."
                )
            }
        }
        .navigationTitle("Plans")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let beginImport {
                    Button("Import workout", action: beginImport)
                        .disabled(!viewModel.canMutate)
                        .accessibilityIdentifier("plans.import")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.beginCreate()
                } label: {
                    Label("New plan", systemImage: "plus")
                }
                .disabled(!viewModel.canMutate)
                .accessibilityIdentifier("plans.new")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isEditorPresented },
                set: { if !$0 { viewModel.cancelEditor() } }
            )
        ) {
            PlanEditorView(viewModel: viewModel, capabilities: capabilities)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            if viewModel.repositoryStatus.staging != .absent {
                repositoryMutationWarning
            }
            ContentUnavailableView {
                Label("No saved plans", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Create a walking or running interval plan, review every target, then confirm it before saving.")
            } actions: {
                Button("Create plan") {
                    viewModel.beginCreate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canMutate)
                .accessibilityIdentifier("plans.create-empty")
            }
        }
        .padding()
    }

    private func availableView(_ records: [SavedPlanRecord]) -> some View {
        List {
            if viewModel.repositoryStatus.staging != .absent {
                Section { repositoryMutationWarning }
            }
            Section("Saved plans") {
                ForEach(records, id: \.id) { record in
                    Button {
                        viewModel.beginEdit(record)
                    } label: {
                        SavedPlanRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canMutate)
                    .accessibilityIdentifier("plans.record.\(record.id.uuidString)")
                }
            }
        }
    }

    private var repositoryMutationWarning: some View {
        Label(
            viewModel.repositoryStatus.staging == .staleArtifactPresent
                ? "A stale staging file was detected. Saved plans remain readable, but changes are disabled."
                : "Staging-file status is unavailable. Changes are disabled.",
            systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.orange)
        .accessibilityIdentifier("plans.staging-warning")
    }

    private func unavailableView(title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(description)
        } actions: {
            Button("Retry") { viewModel.reload() }
                .accessibilityIdentifier("plans.retry")
        }
    }
}

private struct SavedPlanRow: View {
    let record: SavedPlanRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.plan.suggestedName)
                .font(.headline)
            Text("\(record.plan.activity.displayName) · \(record.plan.steps.count) steps · \(totalSeconds) seconds")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var totalSeconds: String {
        let total = record.plan.steps.reduce(Decimal.zero) {
            $0 + Decimal($1.duration.value)
        }
        return PlanValueFormatter.localizedText(total)
    }
}

private struct PlanEditorView: View {
    @ObservedObject var viewModel: PlansViewModel
    let capabilities: WorkoutPlanCapabilities

    var body: some View {
        NavigationStack {
            Group {
                if let preview = viewModel.preview {
                    PlanPreviewView(viewModel: viewModel, preview: preview)
                } else {
                    PlanEntryView(viewModel: viewModel, capabilities: capabilities)
                }
            }
            .navigationTitle(viewModel.editingRecordID == nil ? "New plan" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancelEditor() }
                        .accessibilityIdentifier("plan.cancel")
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct PlanEntryView: View {
    @ObservedObject var viewModel: PlansViewModel
    let capabilities: WorkoutPlanCapabilities

    private var draft: Binding<ManualWorkoutDraft> {
        Binding(
            get: { viewModel.draft ?? .empty },
            set: { viewModel.draft = $0 }
        )
    }

    var body: some View {
        Form {
            Section("Workout") {
                TextField("Plan name", text: draft.suggestedName)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("plan.name")
                Picker("Activity", selection: draft.activity) {
                    ForEach(WorkoutActivity.allCases, id: \.self) { activity in
                        Text(activity.displayName).tag(activity)
                    }
                }
                .accessibilityIdentifier("plan.activity")
            }

            Section("Ordered steps") {
                ForEach(Array(draft.wrappedValue.steps.indices), id: \.self) { index in
                    StepEntryView(index: index, step: draft.steps[index])
                }
                .onDelete(perform: viewModel.deleteSteps)
                .onMove(perform: viewModel.moveSteps)

                Button {
                    viewModel.addStep()
                } label: {
                    Label("Add step", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("plan.add-step")
            }

            if !viewModel.inputIssues.isEmpty || !viewModel.validationIssues.isEmpty {
                Section("Fix before preview") {
                    ForEach(Array(viewModel.inputIssues.enumerated()), id: \.offset) { _, issue in
                        ValidationIssueRow(message: issue.message)
                    }
                    ForEach(Array(viewModel.validationIssues.enumerated()), id: \.offset) { _, issue in
                        ValidationIssueRow(message: issue.message)
                    }
                }
                .accessibilityIdentifier("plan.validation-errors")
            }

            Section {
                Button("Review exact plan") {
                    viewModel.validateForPreview(against: capabilities)
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("plan.review")
            } footer: {
                Text("Review validates the complete plan against the treadmill capability state currently shown in Settings. It does not save anything.")
            }
        }
        .toolbar { EditButton() }
        .onChange(of: viewModel.draft) { _, _ in
            viewModel.draftDidChange()
        }
    }
}

private struct StepEntryView: View {
    let index: Int
    @Binding var step: ManualWorkoutStepDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step \(index + 1)")
                .font(.headline)
            Picker("Type", selection: $step.kind) {
                ForEach(WorkoutStepKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .accessibilityIdentifier("plan.step.\(index).kind")
            TextField("Label", text: $step.label)
                .accessibilityIdentifier("plan.step.\(index).label")
            TextField("Duration (seconds)", text: $step.durationSeconds)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("plan.step.\(index).duration")
            TextField("Speed (km/h)", text: $step.speedKilometresPerHour)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("plan.step.\(index).speed")
            TextField("Inclination (%)", text: $step.inclinationPercent)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("plan.step.\(index).inclination")
        }
        .padding(.vertical, 4)
    }
}

private struct ValidationIssueRow: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .foregroundStyle(.red)
    }
}

struct PlanPreviewView: View {
    @ObservedObject var viewModel: PlansViewModel
    let preview: WorkoutPlanPreview
    var onConfirm: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        Form {
            Section("Complete plan") {
                LabeledContent("Plan format", value: "Version \(preview.plan.schemaVersion)")
                LabeledContent("Name", value: preview.plan.suggestedName)
                LabeledContent("Activity", value: preview.plan.activity.displayName)
            }

            Section("Derived totals") {
                LabeledContent(
                    "Duration",
                    value: "\(PlanValueFormatter.localizedText(preview.totalDurationSeconds)) seconds"
                )
                LabeledContent(
                    "Estimated distance",
                    value: "\(PlanValueFormatter.estimatedDistanceText(preview.estimatedDistanceKilometres)) km"
                )
                LabeledContent("Steps", value: preview.plan.steps.count.formatted())
            }

            Section("Exact ordered steps") {
                ForEach(Array(preview.plan.steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(index + 1). \(step.kind.displayName): \(step.label)")
                            .font(.headline)
                        Text("\(step.duration.value.formatted()) seconds · \(PlanValueFormatter.localizedText(step.targetSpeed.value)) km/h · \(PlanValueFormatter.localizedText(step.targetInclination.value))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let saveError = viewModel.saveError {
                Section("Save failed") {
                    ValidationIssueRow(message: saveError)
                }
                .accessibilityIdentifier("plan.save-error")
            }

            Section {
                Button("Back to edit") { if let onBack { onBack() } else { viewModel.returnToEditing() } }
                    .accessibilityIdentifier("plan.back-to-edit")
                Button(viewModel.editingRecordID == nil ? "Confirm and save" : "Confirm and update") {
                    if let onConfirm { onConfirm() } else { viewModel.confirmSave() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canMutate)
                .accessibilityIdentifier("plan.confirm-save")
            } footer: {
                Text("Only this separate confirmation action writes the validated plan to local storage.")
            }
        }
    }
}

private extension WorkoutActivity {
    static var allCases: [WorkoutActivity] { [.indoorWalking, .indoorRunning] }

    var displayName: String {
        switch self {
        case .indoorWalking: "Indoor walking"
        case .indoorRunning: "Indoor running"
        }
    }
}

private extension WorkoutStepKind {
    static var allCases: [WorkoutStepKind] { [.warmUp, .interval, .recovery, .coolDown] }

    var displayName: String {
        switch self {
        case .warmUp: "Warm-up"
        case .interval: "Interval"
        case .recovery: "Recovery"
        case .coolDown: "Cool-down"
        }
    }
}
