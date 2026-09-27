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
                            Text("You can create and save the plan now. Live compatibility is checked before execution.").font(.footnote)
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
            .accessibilityHint("Choose historical planning information. This does not establish execution readiness.")
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
            Text("Saved planning information. Live compatibility is checked before execution.")
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
                            Text("Create a plan without equipment validation.").font(.footnote)
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
                    NavigationLink("Manage saved profiles") { PlanningProfilesView(model: model, setupAvailableByDismissal: false) }
                        .frame(minHeight: 44)
                } footer: {
                    Text("Saved profiles record historical planning information. Live compatibility is checked before execution.")
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
            Text("Increments guide editing; enter any exact target directly. Saved ranges never clamp your draft.")
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
