import SwiftUI

struct PlanningProfileSelectorRow: View {
    @ObservedObject var model: PlanningProfilesViewModel
    @State private var choosing = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Button { choosing = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Treadmill profile").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.authoringSelectionName).font(.headline)
                        if let record = model.selectedProfile {
                            PlanningProfileSummary(snapshot: record.snapshot)
                            if let warning = model.warning(record.snapshot) {
                                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            }
                        } else {
                            Text("You can save the plan now. The connected treadmill is checked before your workout.").font(.footnote)
                        }
                        if model.store == nil, let failure = model.failure {
                            Label(failure.message, systemImage: "exclamationmark.triangle").font(.footnote)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").accessibilityHidden(true)
                }
            }.foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.25)) }
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
            .accessibilityHint("Choose saved treadmill settings for planning. The connected treadmill is checked again before a workout.")
            .accessibilityIdentifier("planning.selector")
            .sheet(isPresented: $choosing) {
                PlanningProfilePicker(model: model)
                    .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            }
    }
}

struct OptionalPlanningProfileSelector: View {
    let model: PlanningProfilesViewModel?
    var body: some View {
        if let model {
            PlanningProfileSelectorRow(model: model)
            Text("Saved treadmill settings for planning. The connected treadmill is checked before your workout.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PlanningProfilePicker: View {
    @ObservedObject var model: PlanningProfilesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: String?
    init(model: PlanningProfilesViewModel) {
        self.model = model
        _candidate = State(initialValue: model.selectedProfile?.id)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice(id: nil) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No treadmill selected").font(.headline)
                            Text("Create a plan without checking treadmill limits yet.").font(.footnote)
                        }
                    }
                    ForEach(model.records) { record in
                        choice(id: record.id) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(record.name).font(.headline)
                                PlanningProfileSummary(snapshot: record.snapshot)
                                if model.currentProfileID == record.id {
                                    Label("Current treadmill", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.mint)
                                }
                                if let warning = model.warning(record.snapshot) {
                                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                if let failure = model.failure {
                    Section {
                        Label(failure.message, systemImage: "exclamationmark.triangle")
                        Button("Reload saved profiles") { model.reload() }
                    }
                } else if model.records.isEmpty {
                    Section { Label("No saved treadmill profiles", systemImage: "tray") }
                }
                Section {
                    NavigationLink("Manage saved profiles") { PlanningProfilesView(model: model, setupAvailableByDismissal: false, allowsPlanningSelection: false) }
                        .frame(minHeight: 44)
                } footer: {
                    Text("Saved profiles help you plan. The connected treadmill is checked again before your workout.")
                }
            }.navigationTitle("Treadmill profile").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { if model.commitAuthoringSelection(candidate) { dismiss() } }
                            .accessibilityIdentifier("planning.picker.done")
                    }
                }
        }
    }
    private func choice<Content: View>(id: String?, @ViewBuilder content: () -> Content) -> some View {
        Button { candidate = id } label: {
            HStack(alignment: .top, spacing: 12) {
                content().frame(maxWidth: .infinity, alignment: .leading)
                if candidate == id { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }.accessibilityElement(children: .combine)
            .accessibilityAddTraits(candidate == id ? .isSelected : [])
            .accessibilityIdentifier(id == nil ? "planning.picker.none" : "planning.picker.profile.\(id!)")
    }
}

struct PlanningProfileManualIncrementControls: View {
    @ObservedObject var model: PlanningProfilesViewModel
    @Binding var speed: String
    @Binding var inclination: String
    let stepNumber: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls("speed", unit: "km/h", value: $speed,
                     increment: model.selectedProfile.map { Decimal($0.snapshot.speed.incrementHundredthsKph) / 100 } ?? Decimal(string: "0.01")!)
            controls("inclination", unit: "%", value: $inclination,
                     increment: model.selectedProfile.map { Decimal($0.snapshot.inclination.incrementTenthsPercent) / 10 } ?? Decimal(string: "0.1")!)
            Text("Use the buttons to adjust by the shown amount, or type a value. Saved limits do not change your draft.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func controls(_ title: String, unit: String, value: Binding<String>, increment: Decimal) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("\(title.capitalized) increment \(PlanValueFormatter.domainText(increment)) \(unit)").font(.caption)
                Spacer()
                adjustment(title, value: value, by: -increment, symbol: "minus", action: "Decrease")
                adjustment(title, value: value, by: increment, symbol: "plus", action: "Increase")
            }
            VStack(alignment: .leading) {
                Text("\(title.capitalized) increment \(PlanValueFormatter.domainText(increment)) \(unit)").font(.caption)
                HStack {
                    adjustment(title, value: value, by: -increment, symbol: "minus", action: "Decrease")
                    adjustment(title, value: value, by: increment, symbol: "plus", action: "Increase")
                }
            }
        }
    }
    private func adjustment(_ title: String, value: Binding<String>, by increment: Decimal, symbol: String, action: String) -> some View {
        Button {
            if let changed = ManualWorkoutDraftParser.incrementText(value.wrappedValue, by: increment) { value.wrappedValue = changed }
        } label: { Image(systemName: symbol).frame(minWidth: 44, minHeight: 44) }
            .buttonStyle(.bordered).accessibilityLabel("\(action) step \(stepNumber) \(title)")
            .disabled(ManualWorkoutDraftParser.incrementText(value.wrappedValue, by: increment) == nil)
    }
}


extension HistoricalPlanCompatibility.Mismatch {
        var message: String {
            "Step \(stepIndex + 1) \(target): \(PlanValueFormatter.domainText(value)) \(unit). Saved range \(PlanValueFormatter.domainText(minimum))–\(PlanValueFormatter.domainText(maximum)) \(unit); increment \(PlanValueFormatter.domainText(increment)) \(unit), starting at \(PlanValueFormatter.domainText(minimum)) \(unit). \(outOfRange ? "Outside saved range." : "Not aligned with saved increment.")"
        }
        var unit: String { target == "speed" ? "km/h" : "%" }
}

struct HistoricalPlanCompatibilityCard: View {
    @ObservedObject var plans: PlansViewModel
    let profiles: PlanningProfilesViewModel?
    @AccessibilityFocusState private var verdictFocused: Bool
    @State private var choosingProfile = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if let review = plans.historicalReview {
            VStack(alignment: .leading, spacing: 12) {
                Label(review.title, systemImage: review.isMismatch ? "exclamationmark.triangle" : (review.profile == nil ? "questionmark.circle" : "checkmark.circle"))
                    .font(.headline).foregroundStyle(review.isMismatch ? Color.orange : Color.primary)
                    .accessibilityIdentifier("planning.compatibility.verdict")
                    .accessibilityFocused($verdictFocused)
                if let profile = review.profile {
                    Text("Checked against saved settings for \(profile.name). The connected treadmill has not been checked yet.")
                    Text("Last confirmed \(PlanningProfileSnapshot.date(profile.snapshot.observedAt)?.formatted(date: .long, time: .omitted) ?? "date unavailable")")
                } else {
                    Text("Connect a treadmill before your workout to check its speed and incline settings.")
                    if case .unavailable(let message) = review.selection {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    if profiles != nil {
                        Button("Choose a treadmill profile") { choosingProfile = true }
                            .frame(minHeight: 44).accessibilityIdentifier("planning.preview.choose-profile")
                    }
                }
                Text("The connected treadmill will be checked before your workout.").font(.footnote)
                if let warning = review.ageWarning {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                ForEach(review.mismatches) { issue in
                    VStack(alignment: .leading, spacing: 8) {
                        let step = review.plan.steps[issue.stepIndex]
                        Text("Step \(issue.stepIndex + 1) · \(step.kind.displayName) · \(step.duration.value) seconds").font(.subheadline.weight(.semibold))
                        Text(issue.message).accessibilityIdentifier("planning.compatibility.\(issue.id)")
                    }.accessibilityElement(children: .contain)
                }
                ForEach(Array(Set(review.mismatches.map(\.stepIndex))).sorted(), id: \.self) { index in
                    Button("Edit step \(index + 1)") { plans.editHistoricalStep(index) }
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("planning.edit-step.\(index)")
                }
            }.fixedSize(horizontal: false, vertical: true).padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(review.isMismatch ? Color.orange : Color.secondary.opacity(0.3)) }
                .accessibilityElement(children: .contain)
                .onAppear { if review.isMismatch { verdictFocused = true } }
                .onChange(of: review) { _, value in if value.isMismatch { verdictFocused = true } }
                .sheet(isPresented: $choosingProfile) {
                    if let profiles {
                        PlanningProfilePicker(model: profiles)
                            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
                    }
                }
        }
    }
}

struct HistoricalPlanSaveButton: View {
    @ObservedObject var plans: PlansViewModel
    var onConfirm: ((HistoricalPlanCompatibility?) -> Void)? = nil
    @State private var acknowledgement: HistoricalPlanCompatibility?
    @State private var confirmingMismatch = false
    private var mismatch: Bool { plans.historicalReview?.isMismatch == true }
    var body: some View {
        Group {
            if mismatch { actionButton.buttonStyle(.bordered) }
            else { actionButton.buttonStyle(.borderedProminent) }
        }.disabled(!plans.canMutate)
            .confirmationDialog("Save despite different treadmill limits?", isPresented: $confirmingMismatch, titleVisibility: .visible) {
                Button("Confirm and save exact plan") { save(acknowledgement); acknowledgement = nil }
                Button("Cancel", role: .cancel) { acknowledgement = nil }
            } message: {
                Text((acknowledgement?.mismatches.map(\.message).joined(separator: "\n") ?? "") + "\nSaving does not change any target. The plan cannot begin until a live check passes.")
            }
    }
    private var actionButton: some View {
        Button(mismatch ? "Save plan anyway" : (plans.editingRecordID == nil ? "Confirm and save" : "Confirm and update")) {
            if mismatch {
                acknowledgement = plans.historicalReview
                confirmingMismatch = true
            } else { save(nil) }
        }.font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            .accessibilityIdentifier("plan.confirm-save")
            .accessibilityHint(mismatch ? "Review the settings that differ from your saved treadmill limits" : "Saves this plan on your iPhone")
    }
    private func save(_ acknowledgement: HistoricalPlanCompatibility?) {
        if let onConfirm { onConfirm(acknowledgement) } else { plans.confirmSave(acknowledging: acknowledgement) }
    }
}


struct HistoricalPlanPeakSummary: View {
    let review: HistoricalPlanCompatibility?
    var body: some View {
        if let review, let profile = review.profile, !review.isMismatch {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { speed(review, profile); inclination(review, profile) }
                VStack(alignment: .leading, spacing: 12) { speed(review, profile); inclination(review, profile) }
            }
        }
    }
    private func speed(_ review: HistoricalPlanCompatibility, _ profile: PlanningProfile) -> some View {
        fact("Peak speed", value: review.plan.steps.map(\.targetSpeed.value).max() ?? 0, unit: "km/h",
             minimum: Decimal(profile.snapshot.speed.minimumHundredthsKph) / 100, maximum: Decimal(profile.snapshot.speed.maximumHundredthsKph) / 100)
    }
    private func inclination(_ review: HistoricalPlanCompatibility, _ profile: PlanningProfile) -> some View {
        fact("Peak inclination", value: review.plan.steps.map(\.targetInclination.value).max() ?? 0, unit: "%",
             minimum: Decimal(profile.snapshot.inclination.minimumTenthsPercent) / 10, maximum: Decimal(profile.snapshot.inclination.maximumTenthsPercent) / 10)
    }
    private func fact(_ title: String, value: Decimal, unit: String, minimum: Decimal, maximum: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(PlanValueFormatter.localizedText(value)) \(unit)").font(.headline)
            Text("Within saved \(PlanValueFormatter.localizedText(minimum))–\(PlanValueFormatter.localizedText(maximum)) \(unit)").font(.footnote)
        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .combine)
    }
}
