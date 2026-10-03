import SwiftUI

struct PlanningProfileSummary: View {
    let snapshot: PlanningProfileSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Speed \(speed(snapshot.speed.minimumHundredthsKph))–\(speed(snapshot.speed.maximumHundredthsKph)) km/h · Inclination \(inclination(snapshot.inclination.minimumTenthsPercent))–\(inclination(snapshot.inclination.maximumTenthsPercent)) %")
                .fixedSize(horizontal: false, vertical: true)
            Text("Last confirmed \(PlanningProfileSnapshot.date(snapshot.observedAt)?.formatted(date: .long, time: .omitted) ?? "date unavailable")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func speed(_ value: Int) -> String { String(format: "%.2f", Double(value) / 100) }
    private func inclination(_ value: Int) -> String { String(format: "%.1f", Double(value) / 10) }
}

struct PlanningProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: PlanningProfilesViewModel
    var setupAvailableByDismissal = true
    var allowsPlanningSelection = true
    var body: some View {
        List {
            Section {
                Text("Use saved treadmill limits to plan your workout. The connected treadmill is checked again before you begin.")
                Text(model.selectedName).accessibilityIdentifier("profiles.selection")
            }
            if let failure = model.failure {
                Section {
                    Label(failure.message, systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("profiles.failure")
                    Button("Reload saved profiles") { model.reload() }.frame(minHeight: 44)
                }
            }
            if model.failure == nil && model.records.isEmpty {
                Section {
                    Label("No saved treadmill profiles", systemImage: "tray")
                    Text("Connect a treadmill in setup to read its complete speed and inclination capabilities. A profile is saved only after the read succeeds.")
                    if setupAvailableByDismissal {
                        Button("Set up treadmill") { dismiss() }.frame(minHeight: 44)
                    } else {
                        Text("Close the picker, then open Home → Set up treadmill to connect explicitly.")
                    }
                }.accessibilityIdentifier("profiles.empty")
            } else {
                Section("Saved treadmill profiles") {
                    ForEach(model.records) { record in
                        NavigationLink {
                            PlanningProfileDetailView(model: model, profileID: record.id, allowsPlanningSelection: allowsPlanningSelection)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(record.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                PlanningProfileSummary(snapshot: record.snapshot)
                                if model.currentProfileID == record.id {
                                    Label("Current treadmill", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.mint)
                                }
                                if model.selectedProfile?.id == record.id {
                                    Label("Selected for planning", systemImage: "checkmark.circle")
                                }
                                if let warning = model.warning(record.snapshot) {
                                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                                }
                            }.frame(minHeight: 44).accessibilityElement(children: .combine)
                        }.accessibilityIdentifier("profiles.record.\(record.id)")
                    }
                }
            }
            Section("Treadmill check") { Text(model.discoveryStatus) }
        }.navigationTitle("Saved treadmills")
    }
}

struct PlanningProfileDetailView: View {
    @ObservedObject var model: PlanningProfilesViewModel
    let profileID: String
    var beginRenaming = false
    var allowsPlanningSelection = true
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PlanningProfile?
    @State private var name = ""
    @State private var deleting: PlanningProfile?
    @FocusState private var nameFocused: Bool
    private var record: PlanningProfile? { model.records.first { $0.id == profileID } }
    var body: some View {
        List {
            if let record {
                Section("Name") {
                    if editing != nil {
                        TextField("Treadmill name", text: $name).focused($nameFocused)
                            .accessibilityIdentifier("profiles.name")
                        Button("Save name") {
                            if let editing, model.rename(editing, to: name) { self.editing = nil; nameFocused = false }
                        }.frame(minHeight: 44).accessibilityIdentifier("profiles.rename.save")
                        Button("Cancel rename") { editing = nil; nameFocused = false }.frame(minHeight: 44)
                    } else {
                        Text(record.name).fixedSize(horizontal: false, vertical: true)
                        Button("Rename") { editing = record; name = record.name; nameFocused = true }
                            .frame(minHeight: 44).accessibilityIdentifier("profiles.rename")
                    }
                }
                Section("Planning selection") {
                    if model.selectedProfile?.id == record.id {
                        Label("Selected for planning", systemImage: "checkmark.circle")
                            .accessibilityIdentifier("profiles.selected")
                    } else if allowsPlanningSelection {
                        Button("Use for planning") { model.commitAuthoringSelection(record.id) }
                            .frame(minHeight: 44).accessibilityIdentifier("profiles.select")
                    } else {
                        Text("Return to the picker to choose this profile, then tap Done.")
                    }
                    if model.currentProfileID == record.id {
                        Label("Current treadmill — connected", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.mint)
                    }
                    Text("This uses previously saved treadmill settings. The connected treadmill is checked again before you begin.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Saved capabilities") {
                    PlanningProfileSummary(snapshot: record.snapshot)
                    Text("Speed increment \(String(format: "%.2f", Double(record.snapshot.speed.incrementHundredthsKph) / 100)) km/h")
                    Text("Inclination increment \(String(format: "%.1f", Double(record.snapshot.inclination.incrementTenthsPercent) / 10)) %")
                    if let warning = model.warning(record.snapshot) { Label(warning, systemImage: "exclamationmark.triangle") }
                    Text("Saved settings help you plan. They do not confirm that a treadmill is ready now.")
                }
                if let failure = model.failure { Section { Label(failure.message, systemImage: "exclamationmark.triangle") } }
                Section {
                    Button("Delete profile", role: .destructive) { deleting = record }
                        .frame(minHeight: 44).accessibilityIdentifier("profiles.delete")
                }
            } else {
                Text(model.failure?.message ?? "This saved profile is no longer available.")
            }
        }.navigationTitle(record?.name ?? "Treadmill profile")
            .onAppear {
                if beginRenaming, editing == nil, let record {
                    editing = record; name = record.name; nameFocused = true
                }
            }
            .alert("Delete \(deleting?.name ?? "profile")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Cancel", role: .cancel) { deleting = nil }
                Button("Delete profile", role: .destructive) {
                    if let deleting, model.delete(deleting) { dismiss() }
                    deleting = nil
                }
            } message: {
                Text("Plans and history are unaffected. If selected, this profile returns to No treadmill selected. The treadmill connection and any active workout are unchanged.")
            }
    }
}

struct PlanningProfileDiscoveryPresentation: ViewModifier {
    @ObservedObject var model: PlanningProfilesViewModel
    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { model.review != nil || model.createdProfileID != nil }, set: {
            if !$0 { model.keepSaved(); model.dismissCreated() }
        })) {
            NavigationStack {
                List {
                    if let review = model.review {
                        Section {
                            Label("Treadmill capabilities changed", systemImage: "exclamationmark.triangle")
                            Text("Review newly read ranges before replacing the saved profile. Keeping it does not change live execution checks.")
                        }
                        Section(review.profile.name) {
                            PlanningProfileCapabilityComparison(saved: review.profile.snapshot, newlyRead: review.snapshot)
                            Text("Read just now: \(PlanningProfileSnapshot.date(review.snapshot.observedAt)?.formatted(date: .long, time: .shortened) ?? "date unavailable")")
                            Text("Your saved profile is unchanged. Updating it changes the limits used for planning; the connected treadmill is still checked before each workout.")
                        }
                        Section {
                            Button("Update profile") { model.updateReviewed() }.frame(minHeight: 44)
                            Button("Keep saved profile") { model.keepSaved() }.frame(minHeight: 44)
                        }
                    } else if let id = model.createdProfileID, let record = model.records.first(where: { $0.id == id }) {
                        Section {
                            Text("Treadmill profile saved").font(.headline)
                            if model.currentProfileID == id {
                                Label("Currently connected", systemImage: "checkmark.circle").foregroundStyle(.mint)
                            } else {
                                Label("Disconnected — profile remains saved", systemImage: "antenna.radiowaves.left.and.right.slash")
                            }
                            Label("Capability read completed", systemImage: "checkmark.circle").foregroundStyle(.mint)
                            Label("Saved for future planning", systemImage: "tray")
                            Text("Stored on this iPhone. Saving does not start or control the treadmill.")
                            Text(record.name).font(.headline)
                            PlanningProfileSummary(snapshot: record.snapshot)
                            Text("You can plan with these saved settings while disconnected. The treadmill is checked again before you begin a workout.")
                        }
                        Section {
                            Button("Use for planning") { if model.selectCreated(id) { model.dismissCreated() } }.frame(minHeight: 44)
                            NavigationLink("Rename") { PlanningProfileDetailView(model: model, profileID: id, beginRenaming: true) }.frame(minHeight: 44)
                            Button("Done") { model.dismissCreated() }.frame(minHeight: 44)
                        }
                    }
                    if let failure = model.failure { Section { Label(failure.message, systemImage: "exclamationmark.triangle") } }
                }.navigationTitle("Treadmill profile")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.keepSaved(); model.dismissCreated() } } }
            }
        }
    }
}

struct OptionalPlanningProfileDiscoveryPresentation: ViewModifier {
    let model: PlanningProfilesViewModel?
    @ViewBuilder func body(content: Content) -> some View {
        if let model { content.modifier(PlanningProfileDiscoveryPresentation(model: model)) }
        else { content }
    }
}

private struct PlanningProfileCapabilityComparison: View {
    let saved: PlanningProfileSnapshot
    let newlyRead: PlanningProfileSnapshot
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            comparison("Speed", old: speed(saved.speed), new: speed(newlyRead.speed), changed: saved.speed.minimumHundredthsKph != newlyRead.speed.minimumHundredthsKph || saved.speed.maximumHundredthsKph != newlyRead.speed.maximumHundredthsKph)
            comparison("Speed increment", old: String(format: "%.2f km/h", Double(saved.speed.incrementHundredthsKph) / 100), new: String(format: "%.2f km/h", Double(newlyRead.speed.incrementHundredthsKph) / 100), changed: saved.speed.incrementHundredthsKph != newlyRead.speed.incrementHundredthsKph)
            comparison("Inclination", old: inclination(saved.inclination), new: inclination(newlyRead.inclination), changed: saved.inclination.minimumTenthsPercent != newlyRead.inclination.minimumTenthsPercent || saved.inclination.maximumTenthsPercent != newlyRead.inclination.maximumTenthsPercent)
            comparison("Inclination increment", old: String(format: "%.1f %%", Double(saved.inclination.incrementTenthsPercent) / 10), new: String(format: "%.1f %%", Double(newlyRead.inclination.incrementTenthsPercent) / 10), changed: saved.inclination.incrementTenthsPercent != newlyRead.inclination.incrementTenthsPercent)
        }
    }
    private func speed(_ value: PlanningProfileSnapshot.Speed) -> String {
        String(format: "%.2f–%.2f km/h", Double(value.minimumHundredthsKph) / 100, Double(value.maximumHundredthsKph) / 100)
    }
    private func inclination(_ value: PlanningProfileSnapshot.Inclination) -> String {
        String(format: "%.1f–%.1f %%", Double(value.minimumTenthsPercent) / 10, Double(value.maximumTenthsPercent) / 10)
    }
    @ViewBuilder private func comparison(_ title: String, old: String, new: String, changed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if changed { Label("\(title) changed", systemImage: "arrow.triangle.2.circlepath").fontWeight(.semibold) }
            else { Text(title).font(.headline) }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                VStack(alignment: .leading) { Text("Saved").font(.caption); Text(old) }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading) { Text("Newly read").font(.caption); Text(new).fontWeight(changed ? .semibold : .regular) }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
}
