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
                    ManualPlanReviewView(viewModel: viewModel, preview: preview)
                } else {
                    PlanEntryView(viewModel: viewModel, capabilities: capabilities)
                }
            }
            .navigationTitle(
                viewModel.preview == nil
                    ? (viewModel.editorPresentation?.title ?? "Plan")
                    : "Review"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.preview == nil {
                        Button("Cancel") { viewModel.cancelEditor() }
                            .accessibilityIdentifier("plan.cancel")
                    } else {
                        Button {
                            viewModel.returnToEditing()
                        } label: {
                            Label("Back to edit", systemImage: "chevron.backward")
                        }
                        .accessibilityHint("Returns to the unchanged manual plan draft without saving")
                        .accessibilityIdentifier("plan.back-to-edit")
                    }
                }
                if viewModel.preview != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Cancel") { viewModel.cancelEditor() }
                            .accessibilityHint("Closes the plan editor without saving")
                            .accessibilityIdentifier("plan.cancel")
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct PlanEntryView: View {
    @ObservedObject var viewModel: PlansViewModel
    let capabilities: WorkoutPlanCapabilities
    @Environment(\.editMode) private var editMode

    private var draft: Binding<ManualWorkoutDraft> {
        Binding(
            get: { viewModel.draft ?? .empty },
            set: { viewModel.draft = $0 }
        )
    }

    private var presentation: ManualPlanEditorPresentation {
        viewModel.editorPresentation ?? ManualPlanEditorPresentation(
            draft: .empty,
            editing: false,
            inputIssues: [],
            validationIssues: []
        )
    }

    private var isReordering: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Plan name")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(presentation.planNameHasProblem ? .red : .secondary)
                        TextField("Plan name", text: draft.suggestedName)
                            .font(.headline)
                            .textInputAutocapitalization(.sentences)
                            .accessibilityLabel("Plan name")
                            .accessibilityHint("Enter a name for this manual plan")
                            .accessibilityIdentifier("plan.name")
                    }
                    Divider()
                    Picker("Indoor activity", selection: draft.activity) {
                        ForEach(WorkoutActivity.allCases, id: \.self) { activity in
                            Text(activity.displayName).tag(activity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Indoor activity")
                    .accessibilityValue(presentation.activity)
                    .accessibilityHint("Choose indoor walking or indoor running")
                    .accessibilityIdentifier("plan.activity")
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            presentation.planNameHasProblem ? Color.red : Color.secondary.opacity(0.2),
                            lineWidth: 1
                        )
                }
                .accessibilityElement(children: .contain)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(Array(draft.wrappedValue.steps.indices), id: \.self) { index in
                    StepEntryView(
                        presentation: presentation.steps[index],
                        step: draft.steps[index],
                        isReordering: isReordering,
                        moveUp: {
                            viewModel.moveSteps(from: IndexSet(integer: index), to: index - 1)
                        },
                        moveDown: {
                            viewModel.moveSteps(from: IndexSet(integer: index), to: index + 2)
                        },
                        delete: {
                            viewModel.deleteSteps(at: IndexSet(integer: index))
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete(perform: viewModel.deleteSteps)
                .onMove(perform: viewModel.moveSteps)

                Button {
                    viewModel.addStep()
                } label: {
                    Label("Add step", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Adds a new ordered step without changing existing values")
                .accessibilityIdentifier("plan.add-step")
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                HStack {
                    Text(presentation.orderedStepCount)
                    Spacer()
                    Button(isReordering ? "Done" : "Reorder") {
                        editMode?.wrappedValue = isReordering ? .inactive : .active
                    }
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                    .accessibilityHint(
                        isReordering
                            ? "Finishes reordering steps"
                            : "Shows controls to move or delete ordered steps"
                    )
                    .accessibilityIdentifier("plan.reorder")
                }
            }

            if !presentation.issues.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Fix before preview · \(presentation.issues.count)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(.red)
                        ForEach(Array(presentation.issues.enumerated()), id: \.offset) { index, issue in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(issue.context)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                                Text(issue.message)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(issue.context). \(issue.message)")
                            .accessibilityIdentifier("plan.validation.issue.\(index)")
                        }
                        Text("Invalid values are rejected. PacePrompt never clamps, repairs or replaces a target for you.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.red.opacity(0.8), lineWidth: 1)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("plan.validation-errors")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                Button("Review exact plan") {
                    viewModel.validateForPreview(against: capabilities)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.reviewActionEnabled)
                .accessibilityHint("Validates the draft without saving or contacting the treadmill")
                .accessibilityIdentifier("plan.review")
            } footer: {
                Text(presentation.reviewFooter)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: viewModel.draft) { _, _ in
            viewModel.draftDidChange()
        }
    }
}

private struct StepEntryView: View {
    let presentation: ManualPlanEditorStepPresentation
    @Binding var step: ManualWorkoutStepDraft
    let isReordering: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(presentation.order)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Picker("Step \(presentation.order) type", selection: $step.kind) {
                    ForEach(WorkoutStepKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .font(.headline)
                .pickerStyle(.menu)
                .accessibilityLabel("Step \(presentation.index + 1) type")
                .accessibilityValue(presentation.kindTitle)
                .accessibilityHint("Choose warm-up, interval, recovery or cool-down")
                .accessibilityIdentifier("plan.step.\(presentation.index).kind")
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            TextField("Step label", text: $step.label)
                .textInputAutocapitalization(.sentences)
                .padding(10)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(fieldBorder(.label), lineWidth: 1)
                }
                .accessibilityLabel("Step \(presentation.index + 1) label")
                .accessibilityValue(presentation.label)
                .accessibilityHint("Enter the exact label for this step")
                .accessibilityIdentifier("plan.step.\(presentation.index).label")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    exactField(
                        title: "Duration",
                        unit: "s",
                        value: $step.durationSeconds,
                        field: .duration,
                        keyboard: .numbersAndPunctuation
                    )
                    exactField(
                        title: "Speed",
                        unit: "km/h",
                        value: $step.speedKilometresPerHour,
                        field: .speed,
                        keyboard: .decimalPad
                    )
                    exactField(
                        title: "Inclination",
                        unit: "%",
                        value: $step.inclinationPercent,
                        field: .inclination,
                        keyboard: .numbersAndPunctuation
                    )
                }
                VStack(spacing: 10) {
                    exactField(
                        title: "Duration",
                        unit: "seconds",
                        value: $step.durationSeconds,
                        field: .duration,
                        keyboard: .numbersAndPunctuation
                    )
                    exactField(
                        title: "Speed",
                        unit: "km/h",
                        value: $step.speedKilometresPerHour,
                        field: .speed,
                        keyboard: .decimalPad
                    )
                    exactField(
                        title: "Inclination",
                        unit: "%",
                        value: $step.inclinationPercent,
                        field: .inclination,
                        keyboard: .numbersAndPunctuation
                    )
                }
            }

            if let problemSummary = presentation.problemSummary {
                Label(problemSummary, systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("plan.step.\(presentation.index).problem")
            }

            if isReordering {
                HStack(spacing: 12) {
                    Button(action: moveUp) {
                        Label("Move up", systemImage: "arrow.up")
                            .frame(minHeight: 32)
                    }
                    .disabled(!presentation.canMoveUp)
                    .accessibilityLabel("Move step \(presentation.index + 1) up")
                    .accessibilityHint("Moves this step one position earlier")
                    .accessibilityIdentifier("plan.step.\(presentation.index).move-up")

                    Button(action: moveDown) {
                        Label("Move down", systemImage: "arrow.down")
                            .frame(minHeight: 32)
                    }
                    .disabled(!presentation.canMoveDown)
                    .accessibilityLabel("Move step \(presentation.index + 1) down")
                    .accessibilityHint("Moves this step one position later")
                    .accessibilityIdentifier("plan.step.\(presentation.index).move-down")

                    Spacer(minLength: 0)

                    Button(role: .destructive, action: delete) {
                        Label("Delete", systemImage: "trash")
                            .frame(minHeight: 32)
                    }
                    .accessibilityLabel("Delete step \(presentation.index + 1)")
                    .accessibilityHint("Deletes this exact step from the draft")
                    .accessibilityIdentifier("plan.step.\(presentation.index).delete")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    presentation.hasProblem ? Color.red : Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(presentation.index + 1), \(presentation.kindTitle)")
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityIdentifier("plan.step.\(presentation.index).card")
    }

    @ViewBuilder
    private func exactField(
        title: String,
        unit: String,
        value: Binding<String>,
        field: ManualPlanStepField,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(presentation.problemFields.contains(field) ? .red : .secondary)
            HStack(spacing: 4) {
                TextField(title, text: value)
                    .keyboardType(keyboard)
                    .textFieldStyle(.plain)
                    .font(.body.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Step \(presentation.index + 1) \(title.lowercased())")
                    .accessibilityValue("\(value.wrappedValue) \(unit)")
                    .accessibilityHint("Enter the exact \(title.lowercased()) value")
                    .accessibilityIdentifier("plan.step.\(presentation.index).\(field.rawValue)")
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(9)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(fieldBorder(field), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldBorder(_ field: ManualPlanStepField) -> Color {
        presentation.problemFields.contains(field) ? .red : .clear
    }

    private var accent: Color {
        switch presentation.kind {
        case .warmUp, .coolDown: .secondary
        case .interval: .orange
        case .recovery: .cyan
        }
    }
}

private struct ValidationIssueRow: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .foregroundStyle(.red)
    }
}

private struct ManualPlanReviewView: View {
    @ObservedObject var viewModel: PlansViewModel
    let preview: WorkoutPlanPreview

    private var presentation: ManualPlanReviewPresentation {
        viewModel.reviewPresentation ?? ManualPlanReviewPresentation(
            preview: preview,
            editing: viewModel.editingRecordID != nil,
            canConfirm: viewModel.canMutate
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.name)
                        .font(.largeTitle.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan.review.name")
                    Label(presentation.activity, systemImage: presentation.activitySymbol)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                        .accessibilityIdentifier("plan.review.activity")
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        reviewFact(title: "Duration", value: presentation.totalDuration, identifier: "duration")
                        reviewFact(title: "Estimated distance", value: presentation.estimatedDistance, identifier: "distance")
                        reviewFact(title: "Steps", value: presentation.stepCount, identifier: "steps")
                    }
                    VStack(spacing: 8) {
                        reviewFact(title: "Duration", value: presentation.totalDuration, identifier: "duration")
                        reviewFact(title: "Estimated distance", value: presentation.estimatedDistance, identifier: "distance")
                        reviewFact(title: "Steps", value: presentation.stepCount, identifier: "steps")
                    }
                }

                Text("Exact plan · every step")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                ForEach(presentation.steps) { step in
                    ManualPlanReviewStepCard(step: step)
                }

                if let saveError = viewModel.saveError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Save failed", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(saveError)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.red.opacity(0.8), lineWidth: 1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("plan.save-error")
                }

                Button(presentation.confirmationTitle) {
                    viewModel.confirmSave()
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .buttonStyle(.borderedProminent)
                .disabled(!presentation.confirmationEnabled)
                .accessibilityHint("Writes this exact validated plan to local storage")
                .accessibilityIdentifier("plan.confirm-save")

                Text(presentation.confirmationFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan.review.capability-note")
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func reviewFact(title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.review.\(identifier)")
    }
}

private struct ManualPlanReviewStepCard: View {
    let step: ManualPlanReviewStepPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.targets)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.exactDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(step.duration)
                .font(.headline.monospacedDigit())
                .fixedSize()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step.id + 1), \(step.title)")
        .accessibilityValue(step.accessibilityValue)
        .accessibilityIdentifier("plan.review.step.\(step.id)")
    }

    private var accent: Color {
        switch step.kind {
        case .warmUp, .coolDown: .secondary
        case .interval: .orange
        case .recovery: .cyan
        }
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
