import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    HomeStatusCard(
                        presentation: treadmill.homePresentation.bluetooth,
                        identifier: "bluetooth",
                        perform: perform
                    )
                    HomeStatusCard(
                        presentation: treadmill.homePresentation.treadmill,
                        identifier: "treadmill",
                        perform: perform
                    )

                    NavigationLink {
                        TreadmillSetupView(treadmill: treadmill)
                    } label: {
                        Label("Set up treadmill", systemImage: "figure.run")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("home.setup")

                    Spacer(minLength: 24)
                    safetyCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("PacePrompt")
        .navigationBarTitleDisplayMode(.large)
    }

    private var safetyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(
                "This version cannot start, stop or control the treadmill. "
                    + "It reads capability and prepares plans only — the physical console "
                    + "and safety key remain authoritative."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Treadmill safety")
        .accessibilityValue(
            "PacePrompt cannot start, stop or control the treadmill. "
                + "Use the physical console and safety key."
        )
        .accessibilityIdentifier("home.safety")
    }

    private func perform(_ action: HomeStatusAction) {
        switch action {
        case .openSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        case .retryScan:
            treadmill.toggleScan()
        }
    }
}

private struct HomeStatusCard: View {
    let presentation: HomeStatusPresentation
    let identifier: String
    let perform: (HomeStatusAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: presentation.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColour)
                    .frame(width: 44, height: 44)
                    .background(statusColour.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.category.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Text(presentation.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(statusColour)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(presentation.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(presentation.category) status")
            .accessibilityValue("\(presentation.title). \(presentation.detail)")
            .accessibilityIdentifier("home.\(identifier).status")

            if let action = presentation.action {
                Button {
                    perform(action)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("home.\(identifier).action")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColour, lineWidth: presentation.tone == .failure ? 1 : 0.5)
        }
    }

    private var statusColour: Color {
        switch presentation.tone {
        case .positive: .green
        case .neutral: .secondary
        case .warning: .orange
        case .failure: .red
        }
    }

    private var borderColour: Color {
        presentation.tone == .failure
            ? .red.opacity(0.75)
            : Color(uiColor: .separator)
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
