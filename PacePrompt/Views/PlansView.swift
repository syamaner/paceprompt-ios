import SwiftUI
import UIKit

struct PlansView: View {
    @ObservedObject var viewModel: PlansViewModel
    let capabilities: WorkoutPlanCapabilities
    var beginImport: (() -> Void)? = nil

    var body: some View {
        Group {
            switch viewModel.libraryPresentation.content {
            case .empty:
                emptyView
            case let .populated(rows):
                populatedView(rows)
            case let .blocked(status):
                blockedView(status)
            }
        }
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.beginExport()
                } label: {
                    Label("Export plans", systemImage: "square.and.arrow.up")
                }
                .disabled(!viewModel.canBeginExport)
                .accessibilityIdentifier("plans.export")
            }
            ToolbarItem(placement: .primaryAction) {
                if let beginImport {
                    Button(action: beginImport) {
                        Label("Import workout", systemImage: "square.and.arrow.down")
                    }
                        .disabled(!viewModel.libraryPresentation.canImport)
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
        .sheet(
            isPresented: Binding(
                get: { viewModel.isExportPresented },
                set: {
                    if !$0, viewModel.isExportPresented {
                        viewModel.cancelExport()
                    }
                }
            )
        ) {
            SavedPlanExportFlowView(viewModel: viewModel)
        }
        .alert(
            deletionConfirmationTitle,
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.cancelDeletion() } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeletion()
            }
            Button("Delete plan", role: .destructive) {
                viewModel.confirmDeletion()
            }
        } message: {
            if let record = viewModel.pendingDeletion {
                Text(PlansDeletionPresentation(record: record).message)
            }
        }
    }

    private var deletionConfirmationTitle: String {
        guard let record = viewModel.pendingDeletion else { return "Delete saved plan?" }
        return PlansDeletionPresentation(record: record).title
    }

    private var emptyView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let warning = viewModel.libraryPresentation.stagingWarning {
                    PlansStatusCard(status: warning)
                        .accessibilityIdentifier("plans.staging-warning")
                }

                ContentUnavailableView {
                    Label("No plans yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Build an indoor walking or running interval plan, review every exact target, and confirm before anything is saved to this device.")
                } actions: {
                    VStack(spacing: 12) {
                        Button("Create plan") {
                            viewModel.beginCreate()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!viewModel.libraryPresentation.canCreate)
                        .accessibilityIdentifier("plans.create-empty")

                        if let beginImport {
                            Button(action: beginImport) {
                                Label("Import workout", systemImage: "square.and.arrow.down")
                            }
                            .disabled(!viewModel.libraryPresentation.canImport)
                            .accessibilityIdentifier("plans.import-empty")
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func populatedView(_ rows: [PlansPlanRowPresentation]) -> some View {
        List {
            if let warning = viewModel.libraryPresentation.stagingWarning {
                Section {
                    PlansStatusCard(status: warning)
                        .accessibilityIdentifier("plans.staging-warning")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let deletionError = viewModel.deletionError {
                Section {
                    PlansStatusCard(
                        status: .init(
                            title: "Deletion failed",
                            detail: deletionError,
                            symbol: "exclamationmark.triangle.fill",
                            tone: .failure,
                            retryTitle: nil
                        )
                    )
                    Button("Dismiss") { viewModel.dismissDeletionError() }
                        .accessibilityIdentifier("plans.dismiss-deletion-error")
                }
                .accessibilityIdentifier("plans.deletion-error")
            }
            if let exportError = viewModel.exportError, !viewModel.isExportPresented {
                Section {
                    PlansStatusCard(
                        status: .init(
                            title: "Export failed",
                            detail: exportError,
                            symbol: "exclamationmark.triangle.fill",
                            tone: .failure,
                            retryTitle: nil
                        )
                    )
                    Button("Dismiss") { viewModel.dismissExportError() }
                        .accessibilityIdentifier("plans.dismiss-export-error")
                }
                .accessibilityIdentifier("plans.export-error")
            }
            Section {
                ForEach(rows) { row in
                    Button {
                        guard let record = viewModel.records.first(where: { $0.id == row.id }) else { return }
                        viewModel.beginEdit(record)
                    } label: {
                        SavedPlanRow(row: row)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(row.name)
                            .accessibilityValue(row.accessibilityValue)
                            .accessibilityHint("Opens the plan editor")
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canMutate)
                    .accessibilityIdentifier("plans.record.\(row.id.uuidString)")
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            guard let record = viewModel.records.first(where: { $0.id == row.id }) else { return }
                            viewModel.requestDeletion(of: record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(!viewModel.canMutate)
                        .accessibilityLabel("Delete \(row.name)")
                        .accessibilityIdentifier("plans.delete.\(row.id.uuidString)")
                    }
                }
            } footer: {
                Text("Swipe a plan to delete. Deletion asks for confirmation first.")
            }
        }
        .listStyle(.plain)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    private func blockedView(_ status: PlansStatusPresentation) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if let warning = viewModel.libraryPresentation.stagingWarning {
                    PlansStatusCard(status: warning)
                        .accessibilityIdentifier("plans.staging-warning")
                }
                PlansStatusCard(status: status) {
                    viewModel.reload()
                }
                .accessibilityIdentifier("plans.blocked")
            }
            .padding()
        }
    }
}

private struct PlansStatusCard: View {
    let status: PlansStatusPresentation
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: status.symbol)
                .foregroundStyle(tint)
                .font(.body)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(status.title)
                    .font(.headline)
                    .foregroundStyle(status.tone == .failure ? tint : .primary)
                Text(status.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let retryTitle = status.retryTitle, let retry {
                    Button(action: retry) {
                        Label(retryTitle, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("plans.retry")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var tint: Color {
        switch status.tone {
        case .neutral: .secondary
        case .warning: .orange
        case .failure: .red
        }
    }

    private var border: Color {
        status.tone == .neutral ? Color.secondary.opacity(0.25) : tint.opacity(0.8)
    }
}

private struct SavedPlanExportFlowView: View {
    @ObservedObject var viewModel: PlansViewModel

    var body: some View {
        NavigationStack {
            Group {
                if let preview = viewModel.exportPreview {
                    exportPreview(preview)
                } else {
                    exportSelection
                }
            }
            .navigationTitle(viewModel.exportPreview == nil ? "Export saved plans" : "Review export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancelExport() }
                        .accessibilityIdentifier("export.cancel")
                }
            }
        }
        .interactiveDismissDisabled()
        .sheet(item: shareArtifactBinding) { artifact in
            SavedPlanActivityView(url: artifact.url) {
                viewModel.completeSharing()
            }
        }
    }

    private var shareArtifactBinding: Binding<SavedPlanExportArtifact?> {
        Binding(
            get: { viewModel.shareArtifact },
            set: { if $0 == nil, viewModel.shareArtifact != nil { viewModel.completeSharing() } }
        )
    }

    private var exportSelection: some View {
        Form {
            Section("Choose plans") {
                ForEach(viewModel.records, id: \.id) { record in
                    Button {
                        viewModel.toggleExportSelection(record)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.plan.suggestedName)
                                    .foregroundStyle(.primary)
                                Text(record.plan.activity.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(
                                systemName: viewModel.selectedExportRecordIDs.contains(record.id)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(
                        "\(record.plan.suggestedName), \(viewModel.selectedExportRecordIDs.contains(record.id) ? "selected" : "not selected")"
                    )
                    .accessibilityIdentifier("export.select.\(record.id.uuidString)")
                }
            }

            exportErrorSection

            Section {
                Button("Review exact export") { viewModel.reviewExport() }
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.canPreviewExport)
                    .accessibilityIdentifier("export.review")
            } footer: {
                Text("No file is created until you review these choices and separately choose Share.")
            }
        }
    }

    private func exportPreview(_ preview: SavedPlanExportPreview) -> some View {
        Form {
            Section("Exact export") {
                LabeledContent("Filename", value: preview.fileName)
                LabeledContent("Category", value: preview.category)
                LabeledContent("Records", value: preview.recordCount.formatted())
            }

            Section("Included fields") {
                ForEach(preview.includedFields, id: \.self) { field in
                    Text(field)
                }
            }

            Section("Selected plans") {
                ForEach(preview.records, id: \.id) { record in
                    Text(record.plan.suggestedName)
                }
            }

            exportErrorSection

            Section {
                Button("Back to selection") { viewModel.returnToExportSelection() }
                    .accessibilityIdentifier("export.back")
                Button("Share JSON copy") { viewModel.prepareExportForSharing() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("export.share")
            } footer: {
                Text("Sharing creates a temporary protected copy. PacePrompt removes it when the share sheet finishes or is cancelled. Your saved plans are not changed.")
            }
        }
    }

    @ViewBuilder
    private var exportErrorSection: some View {
        if let exportError = viewModel.exportError {
            Section("Export failed") {
                ValidationIssueRow(message: exportError)
            }
            .accessibilityIdentifier("export.error")
        }
    }
}

private struct SavedPlanActivityView: UIViewControllerRepresentable {
    let url: URL
    let completion: @MainActor () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in completion() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SavedPlanRow: View {
    let row: PlansPlanRowPresentation

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 7) {
                        Label(row.activity, systemImage: row.activitySymbol)
                        Text("·")
                        Text(row.stepCount)
                        Text("·")
                        Text(row.duration)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Label(row.activity, systemImage: row.activitySymbol)
                        Text("\(row.stepCount) · \(row.duration)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
        .contentShape(Rectangle())
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
