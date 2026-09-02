import SwiftUI

struct SettingsView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel

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

            Section("Privacy") {
                Label("Local only", systemImage: "iphone")
                Text("No account, analytics, cloud service, Health access or API key is used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Current slice", value: "Capability explorer")
                LabeledContent("FTMS control", value: "Disabled")
            }
        }
        .navigationTitle("Settings")
    }
}
