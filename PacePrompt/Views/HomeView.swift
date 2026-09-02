import SwiftUI

struct HomeView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel

    var body: some View {
        List {
            Section {
                StatusRow(
                    title: "Bluetooth",
                    value: treadmill.availability.title,
                    symbol: treadmill.availability.isAvailable
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle.fill",
                    colour: treadmill.availability.isAvailable ? .green : .orange
                )

                StatusRow(
                    title: "Treadmill",
                    value: treadmill.connectionState.title,
                    symbol: connectionSymbol,
                    colour: connectionColour
                )

                if let detail = treadmill.connectionState.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Readiness")
            } footer: {
                Text("PacePrompt cannot start or control the treadmill in this version.")
            }

            Section {
                NavigationLink {
                    TreadmillSetupView(treadmill: treadmill)
                } label: {
                    Label("Set up treadmill", systemImage: "figure.run")
                }
            }
        }
        .navigationTitle("PacePrompt")
    }

    private var connectionSymbol: String {
        switch treadmill.connectionState {
        case .scanning:
            "dot.radiowaves.left.and.right"
        case .connecting, .discovering:
            "arrow.triangle.2.circlepath"
        case .connected:
            "checkmark.circle.fill"
        case .failed:
            "xmark.octagon.fill"
        case .disconnected:
            "bolt.slash.fill"
        case .idle:
            "circle.dashed"
        }
    }

    private var connectionColour: Color {
        switch treadmill.connectionState {
        case .connected:
            .green
        case .failed, .disconnected:
            .red
        case .scanning, .connecting, .discovering:
            .blue
        case .idle:
            .secondary
        }
    }
}
struct StatusRow: View {
    let title: String
    let value: String
    let symbol: String
    let colour: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
                .foregroundStyle(colour)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
