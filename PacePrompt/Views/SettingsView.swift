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
            Section("During workouts") {
                Label("Keep Screen Awake is automatic", systemImage: "sun.max.fill")
                Text(
                    "After you choose Begin workout, PacePrompt keeps the display awake until "
                        + "that exercise finishes, fails or is interrupted. You can still lock "
                        + "the iPhone with the side button."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.screen-awake")
                Label("Use Guided Access for single-app use", systemImage: "lock.iphone")
                Text(
                    "To prevent switching to another app during a workout, turn on Guided Access "
                        + "in iPhone Settings under Accessibility, then triple-click the side "
                        + "button in PacePrompt. Guided Access remains controlled by you and your "
                        + "passcode or Face ID."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.guided-access")
            }
            Section("Privacy") {
                Label("Saved plans stay local", systemImage: "iphone")
                Text("Saved plans stay on this device. Optional remote import sends workout text to OpenRouter and OpenAI only after a disclosure and your agreement for each request. A key is stored in this device’s Keychain. Remote processing has no zero-retention guarantee. No analytics are used. The iPhone does not read Health data and saves iPhone-only workouts only after you choose Save to Apple Health. If you choose Apple Watch recording, the Watch separately reads available heart rate and active energy and saves its workout, execution intervals and available treadmill distance. iPhone saving stays disabled for that attempt. Workouts without usable step details are not saved; heart rate and calorie samples may still remain in Apple Health.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.privacy")
            }

            Section("About") {
                LabeledContent(
                    "Available features",
                    value: "Saved plans, workouts and Health export"
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Available features")
                .accessibilityValue("Saved plans, workouts and Health export")
                .accessibilityIdentifier("settings.current-slice")
                LabeledContent("Treadmill adjustments", value: "Speed and incline during workouts")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Treadmill adjustments")
                    .accessibilityValue("Speed and incline during workouts")
                    .accessibilityIdentifier("settings.ftms-control")
            }
        }
        .navigationTitle("Settings")
    }
}
