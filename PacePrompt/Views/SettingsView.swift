import SwiftUI

struct SettingsView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel
    @ObservedObject var credential: ImportCredentialStore

    var body: some View {
        List {
            Section("Connections") {
                NavigationLink {
                    TreadmillSetupView(treadmill: treadmill)
                } label: {
                    HStack {
                        Label("Treadmill", systemImage: "figure.run")
                        Spacer()
                        Text(treadmill.connectionState.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("Remote workout import") {
                NavigationLink("OpenRouter key") { ImportCredentialView(credential: credential) }
            }
            Section("Privacy") {
                Label("Saved plans stay local", systemImage: "iphone")
                Text("Saved plans stay on this device. Optional remote import sends workout text to OpenRouter and OpenAI only after a disclosure and your agreement for each request. A key is stored in this device’s Keychain. Remote processing has no zero-retention guarantee. No analytics or Health access is used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Current slice", value: "Plans and consented import")
                LabeledContent("FTMS control", value: "Disabled")
            }
        }
        .navigationTitle("Settings")
    }
}
