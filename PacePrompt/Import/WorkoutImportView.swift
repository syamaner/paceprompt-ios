import SwiftUI

struct WorkoutImportView: View {
    @ObservedObject var model: WorkoutImportViewModel
    @ObservedObject var plans: PlansViewModel

    var body: some View {
        NavigationStack {
            Group {
                if let preview = plans.preview {
                    PlanPreviewView(viewModel: plans, preview: preview,
                                    onConfirm: model.confirmSave, onBack: model.returnToInput)
                } else {
                    Form {
                        Section("Workout text") {
                            TextEditor(text: $model.text)
                                .frame(minHeight: 160)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("import.text")
                            Text("Use a non-personal workout description. State the activity and every step's duration, speed, inclination and units.")
                                .font(.footnote)
                        }
                        if let feedback = model.feedback { Section { Text(feedback) } }
                        if !model.validationIssues.isEmpty {
                            Section("Local validation") {
                                ForEach(Array(model.validationIssues.enumerated()), id: \.offset) { _, issue in
                                    Text(issue.message)
                                }
                            }
                        }
                        if model.isSending { ProgressView("Waiting for remote import…") }
                        else {
                            Button("Review remote-send disclosure", action: model.reviewDisclosure)
                                .disabled(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("import.disclosure")
                        }
                    }
                }
            }
            .navigationTitle("Import workout")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: model.cancel) } }
            .sheet(isPresented: Binding(get: { model.disclosure != nil }, set: { if !$0 { model.dismissDisclosure() } })) {
                NavigationStack {
                    Form {
                        Section("Send this workout text remotely?") {
                            Text("Your entered workout text will leave this device and be processed by OpenRouter and OpenAI using openai/gpt-5.6-sol, to produce an untrusted structured workout proposal.")
                            Text("We send the exact text below, en-GB locale, the supported unit vocabulary, the fixed versioned instructions, schema and eleven examples, and only your current speed/inclination capability states. Capability ranges remain on this device.")
                            Text("Your stored OpenRouter key authenticates this request. No saved plans, workout history, health data or device identifiers are sent. Remote processing has no zero-retention guarantee; account logging and provider retention policies apply.")
                            Text("PacePrompt validates the proposal locally. You must review the exact plan and separately confirm before it is saved. A request can incur charges on your OpenRouter account.")
                        }
                        if let disclosure = model.disclosure {
                            Section("Exact entered text") { Text(disclosure.text) }
                            Section("Capability states sent") {
                                LabeledContent("Speed targets", value: capabilityDescription(disclosure.capabilities.speed))
                                LabeledContent("Inclination targets", value: capabilityDescription(disclosure.capabilities.inclination))
                            }
                        }
                        Button("I agree — send this request", action: model.consentAndSend)
                            .accessibilityIdentifier("import.consent")
                    }
                    .navigationTitle("Remote-send disclosure")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: model.dismissDisclosure) } }
                }
            }
        }
    }

    private func capabilityDescription<T>(_ capability: WorkoutTargetCapability<T>) -> String {
        switch capability {
        case .unknown: "Unknown"
        case .unsupported: "Unsupported"
        case .supported: "Supported"
        }
    }
}

struct ImportCredentialView: View {
    @ObservedObject var credential: ImportCredentialStore
    @State private var editing = false
    @State private var replacing = false
    @State private var confirmDelete = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section("OpenRouter credential") {
                Text("Credential: \(credential.state.rawValue)")
                Text("Stored only in this device's Keychain and accessible while unlocked. It is not synchronised. Storing a key sends no request.")
                    .font(.footnote)
                if credential.state == .failed {
                    Text("The credential operation failed. A failed replacement preserves the previous key; a failed deletion does not confirm removal.")
                }
                if editing {
                    SecureField("OpenRouter key", text: $credential.entry)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                    Button(replacing ? "Confirm replacement" : "Save key") {
                        credential.save(replacing: replacing); editing = false
                    }
                    Button("Cancel") { credential.cancelEntry(); editing = false }
                } else {
                    if credential.state == .absent {
                        Button("Add key") { replacing = false; editing = true }
                    } else {
                        Button("Replace key") { replacing = true; credential.beginReplacement(); editing = true }
                        Button("Delete key", role: .destructive) { confirmDelete = true }
                    }
                    Button("Refresh credential status", action: credential.refresh)
                }
            }
        }
        .navigationTitle("Remote import key")
        .onAppear(perform: credential.refresh)
        .onDisappear { credential.cancelEntry(); editing = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { credential.protectedDataLost(); editing = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            credential.protectedDataLost(); editing = false
        }
        .confirmationDialog("Delete the stored OpenRouter key?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete key", role: .destructive, action: credential.delete)
            Button("Cancel", role: .cancel) {}
        }
    }
}
