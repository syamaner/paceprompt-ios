import SwiftUI

struct WorkoutPreflightView: View {
    let presentation: WorkoutPreflightPresentation
    let send: (WorkoutPreflightIntent) -> Void
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if presentation.isWaitingForPhysicalStart {
                waitingView
            } else {
                preflightView
            }
        }
        .background(WorkoutPreflightPalette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var preflightView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                planHeader
                    .accessibilitySortPriority(100)

                readinessCard
                    .accessibilitySortPriority(90)

                ceilingsCard
                    .accessibilitySortPriority(80)

                healthCard
                    .accessibilitySortPriority(70)

                if let activity = presentation.confirmations.first(where: { $0.kind == .activity }) {
                    confirmationCard(
                        title: "Activity type",
                        confirmation: activity,
                        identifier: "preflight.activity"
                    )
                    .accessibilitySortPriority(60)
                }

                safetyCard
                    .accessibilitySortPriority(50)

                Text("The operator starts and stops the belt using the physical treadmill console. The console and safety key remain authoritative throughout the workout.")
                    .font(.subheadline)
                    .foregroundStyle(WorkoutPreflightPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("preflight.console-guidance")
                    .accessibilitySortPriority(20)

                Button("Begin workout") {
                    send(.beginWorkout)
                }
                .font(.headline)
                .foregroundStyle(WorkoutPreflightPalette.buttonText)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    presentation.canBeginWorkout
                        ? WorkoutPreflightPalette.primaryAction
                        : WorkoutPreflightPalette.disabledAction,
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .contentShape(RoundedRectangle(cornerRadius: 15))
                .disabled(!presentation.canBeginWorkout)
                .accessibilityHint(
                    presentation.canBeginWorkout
                        ? "Requests treadmill control for this app attempt. It does not start the belt."
                        : "Unavailable until every current readiness guard and confirmation passes."
                )
                .accessibilityIdentifier("preflight.begin")
                .accessibilitySortPriority(10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("preflight.screen")
    }

    private var planHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preflight")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WorkoutPreflightPalette.muted)
                Spacer(minLength: 16)
                Label("Current checks", systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .labelStyle(CompactStatusLabelStyle())
            }
            Text(presentation.planName)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.planTotals)
                .font(.title3.monospacedDigit())
                .foregroundStyle(WorkoutPreflightPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan \(presentation.planName)")
        .accessibilityValue(presentation.planTotals)
        .accessibilityIdentifier("preflight.plan")
    }

    private var readinessCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: presentation.status.symbol)
                .font(.title3)
                .foregroundStyle(statusTint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Reebok FR30z")
                    .font(.headline)
                Text(presentation.status.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusTint)
                Text(presentation.status.detail)
                    .font(.subheadline)
                    .foregroundStyle(WorkoutPreflightPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .preflightCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reebok FR30z readiness")
        .accessibilityValue("\(presentation.status.title). \(presentation.status.detail)")
        .accessibilityIdentifier("preflight.treadmill")
    }

    private var ceilingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enforced this session")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(WorkoutPreflightPalette.muted)
                .textCase(.uppercase)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ceiling(title: "Speed ceiling", value: presentation.speedCeiling, tint: .yellow)
                    ceiling(title: "Incline ceiling", value: presentation.inclinationCeiling, tint: .cyan)
                    ceiling(title: "Max step", value: presentation.maximumStepSpeedChange, tint: .white)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ceiling(title: "Speed ceiling", value: presentation.speedCeiling, tint: .yellow)
                    ceiling(title: "Incline ceiling", value: presentation.inclinationCeiling, tint: .cyan)
                    ceiling(title: "Max interval speed change", value: presentation.maximumStepSpeedChange, tint: .white)
                }
            }
        }
        .preflightCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conservative session ceilings")
        .accessibilityValue(
            "Speed \(presentation.speedCeiling), inclination \(presentation.inclinationCeiling), maximum interval speed change \(presentation.maximumStepSpeedChange)"
        )
        .accessibilityIdentifier("preflight.ceilings")
    }

    private var healthCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Apple Health")
                    .font(.headline)
                Text("Ready for a later deliberate save")
                    .font(.subheadline.weight(.semibold))
                Text("No permission is requested and no workout or health data is saved on this screen.")
                    .font(.subheadline)
                    .foregroundStyle(WorkoutPreflightPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .preflightCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preflight.health")
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Operator safety checks")
                .font(.headline)
            Text("Confirm each current physical condition before PacePrompt can request control.")
                .font(.subheadline)
                .foregroundStyle(WorkoutPreflightPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            ForEach(presentation.confirmations.filter { $0.kind != .activity }) { confirmation in
                confirmationButton(confirmation)
                if confirmation.kind != .physicallyStationary {
                    Divider()
                        .overlay(WorkoutPreflightPalette.border)
                }
            }
        }
        .preflightCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preflight.safety")
    }

    private func confirmationCard(
        title: String,
        confirmation: WorkoutPreflightConfirmationPresentation,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            confirmationButton(confirmation)
        }
        .preflightCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func confirmationButton(
        _ confirmation: WorkoutPreflightConfirmationPresentation
    ) -> some View {
        Button {
            send(.setConfirmation(confirmation.kind, !confirmation.isConfirmed))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: confirmation.isConfirmed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(confirmation.isConfirmed ? Color.green : WorkoutPreflightPalette.muted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(confirmation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(confirmation.detail)
                        .font(.caption)
                        .foregroundStyle(WorkoutPreflightPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!presentation.canEditConfirmations)
        .accessibilityLabel(confirmation.title)
        .accessibilityValue(confirmation.isConfirmed ? "Confirmed" : "Not confirmed")
        .accessibilityHint(
            presentation.canEditConfirmations
                ? "Double tap to \(confirmation.isConfirmed ? "clear" : "confirm")."
                : "Confirmation is locked until current system readiness passes."
        )
        .accessibilityIdentifier("preflight.confirmation.\(confirmation.kind.rawValue)")
    }

    private func ceiling(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(WorkoutPreflightPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waitingView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 20)

                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 74, weight: .regular))
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse, options: .repeating, isActive: !shouldReduceMotion)
                        .accessibilityLabel("Waiting for physical treadmill Start")
                        .accessibilityValue(shouldReduceMotion ? "Static guidance" : "Gentle pulse")
                        .accessibilityIdentifier("preflight.waiting.motion")
                        .accessibilitySortPriority(100)

                    VStack(spacing: 10) {
                        Text("Press Start on the treadmill")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("preflight.waiting.title")
                        Text("Use the physical treadmill console to start the belt. Use that console to stop it at any time.")
                            .font(.title3)
                            .foregroundStyle(WorkoutPreflightPalette.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(90)

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Planned first segment")
                                .font(.caption.weight(.bold))
                                .tracking(1.1)
                                .foregroundStyle(WorkoutPreflightPalette.muted)
                                .textCase(.uppercase)
                            Text(presentation.initialStepLabel)
                                .font(.title2.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                plannedValue(title: "Initial speed", value: presentation.initialSpeed, tint: .yellow)
                                plannedValue(title: "Initial inclination", value: presentation.initialInclination, tint: .cyan)
                            }
                            VStack(spacing: 12) {
                                plannedValue(title: "Initial speed", value: presentation.initialSpeed, tint: .yellow)
                                plannedValue(title: "Initial inclination", value: presentation.initialInclination, tint: .cyan)
                            }
                        }

                        Text("Planned only - neither target has been submitted, acknowledged, reached or observed.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WorkoutPreflightPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("preflight.waiting.target-boundary")
                    }
                    .preflightCard()
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("preflight.waiting.targets")
                    .accessibilitySortPriority(80)

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: presentation.status.symbol)
                            .foregroundStyle(statusTint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(presentation.status.title)
                                .font(.headline)
                            Text(presentation.status.detail)
                                .font(.subheadline)
                                .foregroundStyle(WorkoutPreflightPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .preflightCard()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Reebok FR30z readiness")
                    .accessibilityValue("\(presentation.status.title). \(presentation.status.detail)")
                    .accessibilityIdentifier("preflight.treadmill")
                    .accessibilitySortPriority(70)

                    Label {
                        Text("Keep the console and safety key immediately reachable. PacePrompt is waiting for fresh treadmill-reported movement; waiting is not proof that the belt is moving.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.yellow)
                    }
                    .font(.subheadline)
                    .foregroundStyle(WorkoutPreflightPalette.muted)
                    .accessibilityIdentifier("preflight.waiting.safety")
                    .accessibilitySortPriority(60)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 640)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("preflight.waiting.screen")
    }

    private func plannedValue(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(WorkoutPreflightPalette.muted)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WorkoutPreflightPalette.strongSurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var statusTint: Color {
        switch presentation.status.tone {
        case .neutral:
            WorkoutPreflightPalette.muted
        case .warning:
            .yellow
        case .ready:
            .green
        case .failure:
            .red
        }
    }

    private var shouldReduceMotion: Bool {
        reduceMotionOverride ?? reduceMotion
    }
}

private struct CompactStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 7))
            configuration.title
        }
    }
}

private enum WorkoutPreflightPalette {
    static let background = Color(red: 0.045, green: 0.047, blue: 0.055)
    static let surface = Color(red: 0.095, green: 0.098, blue: 0.115)
    static let strongSurface = Color(red: 0.125, green: 0.13, blue: 0.15)
    static let border = Color.white.opacity(0.19)
    static let muted = Color.white.opacity(0.72)
    static let primaryAction = Color.white
    static let disabledAction = Color.white.opacity(0.3)
    static let buttonText = Color.black.opacity(0.9)
}

private extension View {
    func preflightCard() -> some View {
        padding(16)
            .background(WorkoutPreflightPalette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(WorkoutPreflightPalette.border, lineWidth: 1)
            }
    }
}
