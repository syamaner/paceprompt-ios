import SwiftUI

struct WorkoutExerciseView: View {
  let presentation: WorkoutExercisePresentation
  let send: (WorkoutExerciseIntent) -> Void
  var reduceMotionOverride: Bool? = nil

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var showingPlan = false
  @State private var showingEndConfirmation = false
  @State private var showingStationaryConfirmation = false

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        Group {
          if geometry.size.width > geometry.size.height
            && !dynamicTypeSize.isAccessibilitySize
          {
            landscapeLayout
          } else {
            portraitLayout
          }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minHeight: geometry.size.height)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
    }
    .background(WorkoutExercisePalette.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
    .interactiveDismissDisabled(!presentation.allowsDismissal)
    .accessibilityIdentifier("exercise.screen")
    .sheet(isPresented: $showingPlan) {
      planSheet
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
  }

  private var portraitLayout: some View {
    VStack(spacing: 16) {
      header
        .accessibilitySortPriority(100)
      progressRegion
        .accessibilitySortPriority(90)
      evidenceBoundary
        .accessibilitySortPriority(80)
      HStack(alignment: .top, spacing: 12) {
        axisCard(presentation.speed, tint: .yellow, speed: true)
        axisCard(presentation.inclination, tint: .cyan, speed: false)
      }
      .accessibilitySortPriority(70)
      actionRegion
        .accessibilitySortPriority(60)
    }
    .frame(maxWidth: 720)
  }

  private var landscapeLayout: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 14) {
        header
        progressRegion
        evidenceBoundary
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .accessibilitySortPriority(100)

      HStack(alignment: .top, spacing: 12) {
        axisCard(presentation.speed, tint: .yellow, speed: true)
        axisCard(presentation.inclination, tint: .cyan, speed: false)
      }
      .frame(maxWidth: .infinity)
      .accessibilitySortPriority(80)

      actionRegion
        .frame(width: 190)
        .accessibilitySortPriority(60)
    }
    .frame(maxWidth: 1_200)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      Label {
        VStack(alignment: .leading, spacing: 3) {
          Text(presentation.status.title)
            .font(.headline)
          Text(presentation.status.detail)
            .font(.caption)
            .foregroundStyle(WorkoutExercisePalette.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      } icon: {
        Image(systemName: presentation.status.symbol)
          .foregroundStyle(statusTint)
          .symbolEffect(
            .pulse,
            options: .repeating,
            isActive: presentation.stage == .checking && !shouldReduceMotion
          )
          .accessibilityHidden(true)
      }
      Spacer(minLength: 8)
      Button {
        showingPlan = true
      } label: {
        Label("Full plan", systemImage: "list.bullet.rectangle")
          .font(.subheadline.weight(.semibold))
          .frame(minHeight: 44)
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("exercise.plan.open")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("exercise.status")
    .accessibilityValue("\(presentation.status.title). \(presentation.status.detail)")
  }

  private var progressRegion: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(presentation.currentInterval)
        .font(.subheadline.weight(.bold))
        .tracking(0.9)
        .textCase(.uppercase)
        .foregroundStyle(statusTint)
        .accessibilityIdentifier("exercise.interval")

      Text(presentation.countdown)
        .font(.system(size: 76, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.55)
        .lineLimit(1)
        .monospacedDigit()
        .accessibilityLabel("Time remaining in current interval")
        .accessibilityValue(presentation.countdown)
        .accessibilityIdentifier("exercise.countdown")

      ProgressView(value: presentation.overallProgress)
        .tint(.blue)
        .accessibilityLabel("Overall workout progress")
        .accessibilityValue(presentation.overallProgressLabel)
        .accessibilityIdentifier("exercise.progress")

      Text(presentation.nextInterval)
        .font(.subheadline)
        .foregroundStyle(WorkoutExercisePalette.muted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("exercise.next")

      HStack(alignment: .top, spacing: 18) {
        metric(title: "Elapsed active", value: presentation.elapsedActiveTime)
        metric(
          title: "Distance",
          value: presentation.distance,
          detail: presentation.distanceDetail
        )
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("exercise.progress-region")
  }

  private var evidenceBoundary: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label("Evidence, not assumptions", systemImage: "shield.lefthalf.filled")
        .font(.caption.weight(.bold))
        .foregroundStyle(WorkoutExercisePalette.muted)
      Text(
        "Actual is treadmill reported. Planned is the segment target. Effective includes any current-segment override."
      )
      .font(.caption)
      .foregroundStyle(WorkoutExercisePalette.muted)
      .fixedSize(horizontal: false, vertical: true)
      if let restorationDetail = presentation.restorationDetail {
        Text(restorationDetail)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.yellow)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("exercise.restoration")
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(WorkoutExercisePalette.surface, in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("exercise.evidence-boundary")
  }

  private func axisCard(
    _ axis: WorkoutExerciseAxisPresentation,
    tint: Color,
    speed: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(axis.title)
          .font(.caption.weight(.bold))
          .tracking(1.1)
          .foregroundStyle(tint)
          .textCase(.uppercase)
        Spacer(minLength: 4)
        if axis.isOverridden {
          Text("Override")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.yellow.opacity(0.18), in: Capsule())
            .accessibilityIdentifier("exercise.\(speed ? "speed" : "inclination").override")
        }
      }

      valueRow(label: "Actual", value: axis.actual, emphasis: true)
      valueRow(label: "Planned", value: axis.planned)
      valueRow(label: "Effective", value: axis.effective)

      Label(axis.evidence.label, systemImage: axis.evidence.symbol)
        .font(.caption.weight(.semibold))
        .foregroundStyle(evidenceTint(axis.evidence))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
          "exercise.\(speed ? "speed" : "inclination").evidence"
        )
      Text(axis.evidenceDetail)
        .font(.caption2)
        .foregroundStyle(WorkoutExercisePalette.muted)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        adjustmentButton(
          symbol: "minus",
          label: axis.decrementLabel,
          target: axis.decrementTarget,
          speed: speed,
          tint: tint
        )
        adjustmentButton(
          symbol: "plus",
          label: axis.incrementLabel,
          target: axis.incrementTarget,
          speed: speed,
          tint: tint
        )
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(WorkoutExercisePalette.surface, in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(WorkoutExercisePalette.border, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("exercise.\(speed ? "speed" : "inclination")")
  }

  private func adjustmentButton(
    symbol: String,
    label: String,
    target: Decimal?,
    speed: Bool,
    tint: Color
  ) -> some View {
    Button {
      guard let target else { return }
      if speed {
        send(.setSpeed(.init(value: target, unit: .kilometresPerHour)))
      } else {
        send(.setInclination(.init(value: target, unit: .percent)))
      }
    } label: {
      Image(systemName: symbol)
        .font(.title2.weight(.bold))
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(target == nil ? WorkoutExercisePalette.muted : Color.white)
    .background(
      target == nil ? WorkoutExercisePalette.disabled : tint.opacity(0.18),
      in: RoundedRectangle(cornerRadius: 13)
    )
    .disabled(target == nil)
    .accessibilityLabel(label)
    .accessibilityHint(
      "Changes only the current segment effective target within the machine increment and session ceiling."
    )
    .accessibilityIdentifier(
      "exercise.\(speed ? "speed" : "inclination").\(symbol)"
    )
  }

  private var actionRegion: some View {
    VStack(spacing: 12) {
      if let overrideLabel = presentation.overrideLabel {
        Label(overrideLabel, systemImage: "slider.horizontal.3")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.yellow)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("exercise.override-state")
      }

      if presentation.canReturnToPlan {
        Button("Return to plan") { send(.returnToPlan) }
          .exerciseActionStyle(tint: .blue)
          .accessibilityIdentifier("exercise.return-to-plan")
      }

      if presentation.canConfirmOperatorStationary {
        VStack(alignment: .leading, spacing: 8) {
          Text("Operator-confirmed stationary fallback")
            .font(.caption.weight(.bold))
          Text(
            "Use only after directly observing that the treadmill is stationary. Never infer this from silence or stale data."
          )
          .font(.caption2)
          .foregroundStyle(WorkoutExercisePalette.muted)
          .fixedSize(horizontal: false, vertical: true)
          Button("I observed the treadmill stationary") {
            showingStationaryConfirmation = true
          }
          .exerciseActionStyle(tint: .orange)
          .accessibilityIdentifier("exercise.confirm-stationary")

          if showingStationaryConfirmation {
            confirmationPanel(
              title: "Operator-confirmed stationary",
              message:
                "Confirm only after directly observing that the treadmill is stationary. Silence, stale telemetry and disconnection are not stationary evidence.",
              actionTitle: "Confirm treadmill is stationary",
              tint: .orange
            ) {
              showingStationaryConfirmation = false
              send(.confirmOperatorStationary)
            } cancel: {
              showingStationaryConfirmation = false
            }
          }
        }
        .padding(12)
        .background(WorkoutExercisePalette.surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exercise.stationary-fallback")
      }

      if presentation.canEndWorkout {
        Button("End workout") { showingEndConfirmation = true }
          .exerciseActionStyle(tint: .red)
          .accessibilityHint("Confirms and saves the local app attempt. Sends no FTMS Stop.")
          .accessibilityIdentifier("exercise.end")

        if showingEndConfirmation {
          confirmationPanel(
            title: "End workout?",
            message:
              "This sends no FTMS Stop. The treadmill remains under physical-console control.",
            actionTitle: "End and save local attempt",
            tint: .red
          ) {
            showingEndConfirmation = false
            send(.endWorkout)
          } cancel: {
            showingEndConfirmation = false
          }
        }
      }

      Label(
        "Start and Stop remain on the physical treadmill console",
        systemImage: "hand.raised.fill"
      )
      .font(.caption)
      .foregroundStyle(WorkoutExercisePalette.muted)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("exercise.console-authority")

      Text(
        shouldReduceMotion
          ? "Reduced motion: static status" : "Status changes use a gentle pulse only"
      )
      .font(.caption2)
      .foregroundStyle(WorkoutExercisePalette.muted)
      .accessibilityIdentifier("exercise.motion")
      .accessibilityValue(shouldReduceMotion ? "Static guidance" : "Gentle pulse")
    }
    .frame(maxWidth: .infinity)
  }

  private var planSheet: some View {
    NavigationStack {
      List(presentation.plan) { step in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("\(step.index + 1). \(step.label)")
              .font(.headline)
            Spacer()
            if step.isCurrent {
              Text("Current")
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
            }
          }
          Text("\(step.duration) - \(step.speed) - \(step.inclination)")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exercise.plan.step.\(step.index)")
      }
      .navigationTitle(presentation.planName)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { showingPlan = false }
        }
      }
      .accessibilityIdentifier("exercise.plan.sheet")
    }
  }

  private func confirmationPanel(
    title: String,
    message: String,
    actionTitle: String,
    tint: Color,
    action: @escaping () -> Void,
    cancel: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      Text(message)
        .font(.caption)
        .foregroundStyle(WorkoutExercisePalette.muted)
        .fixedSize(horizontal: false, vertical: true)
      Button(actionTitle, action: action)
        .exerciseActionStyle(tint: tint)
      Button("Cancel", role: .cancel, action: cancel)
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .padding(12)
    .background(WorkoutExercisePalette.surface, in: RoundedRectangle(cornerRadius: 14))
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(tint.opacity(0.8), lineWidth: 1)
    )
  }

  private func metric(title: String, value: String, detail: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(WorkoutExercisePalette.muted)
      Text(value)
        .font(.headline.monospacedDigit())
      if let detail {
        Text(detail)
          .font(.caption2)
          .foregroundStyle(WorkoutExercisePalette.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func valueRow(label: String, value: String, emphasis: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .font(.caption)
        .foregroundStyle(WorkoutExercisePalette.muted)
      Spacer(minLength: 5)
      Text(value)
        .font(
          emphasis
            ? .title2.monospacedDigit().weight(.bold)
            : .subheadline.monospacedDigit().weight(.semibold)
        )
        .minimumScaleFactor(0.65)
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }

  private var statusTint: Color {
    switch presentation.status.tone {
    case .neutral: WorkoutExercisePalette.muted
    case .active: .green
    case .warning: .yellow
    case .failure: .red
    }
  }

  private func evidenceTint(_ evidence: WorkoutExerciseEvidenceStage) -> Color {
    switch evidence {
    case .confirmed: .green
    case .failed: .red
    case .stale, .observing, .attAccepted, .ftmsAcknowledged: .yellow
    case .requested, .submitted, .unknown: WorkoutExercisePalette.muted
    }
  }

  private var shouldReduceMotion: Bool {
    reduceMotionOverride ?? reduceMotion
  }

}

private enum WorkoutExercisePalette {
  static let background = Color(red: 0.045, green: 0.047, blue: 0.055)
  static let surface = Color(red: 0.095, green: 0.098, blue: 0.115)
  static let border = Color.white.opacity(0.19)
  static let muted = Color.white.opacity(0.72)
  static let disabled = Color.white.opacity(0.08)
}

extension View {
  fileprivate func exerciseActionStyle(tint: Color) -> some View {
    font(.headline)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 56)
      .background(tint.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
      .contentShape(RoundedRectangle(cornerRadius: 14))
  }
}
