import SwiftUI

struct WorkoutExerciseView: View {
  let presentation: WorkoutExercisePresentation
  let send: (WorkoutExerciseIntent) -> Void
  var reduceMotionOverride: Bool? = nil

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showingPlan = false

  var body: some View {
    GeometryReader { geometry in
      if geometry.size.width > geometry.size.height {
        landscapeLayout
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .frame(width: geometry.size.width, height: geometry.size.height)
      } else {
        ScrollView {
          Group {
            portraitLayout
          }
          .padding(.horizontal, 18)
          .padding(.vertical, 14)
          .frame(minHeight: geometry.size.height)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
    }
    .background(WorkoutExercisePalette.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
    .interactiveDismissDisabled(!presentation.allowsDismissal)
    .exerciseLayoutMarker("exercise.screen", label: "Exercise screen")
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
          .exerciseLayoutMarker("exercise.speed", label: "Speed controls")
        axisCard(presentation.inclination, tint: .cyan, speed: false)
          .exerciseLayoutMarker("exercise.inclination", label: "Inclination controls")
      }
      .accessibilitySortPriority(70)
      actionRegion
        .accessibilitySortPriority(60)
    }
    .frame(maxWidth: 720)
  }

  private var landscapeLayout: some View {
    GeometryReader { geometry in
      let columnSpacing: CGFloat = 12
      let availableWidth = max(0, geometry.size.width - columnSpacing)
      let leftWidth = availableWidth * 0.57
      let rightWidth = availableWidth - leftWidth
      let rowSpacing: CGFloat = 10
      let availableHeight = max(0, geometry.size.height - rowSpacing)
      let axisHeight = availableHeight * 0.72
      let actionHeight = availableHeight - axisHeight
      let cardSpacing: CGFloat = 10
      let cardWidth = max(0, (rightWidth - cardSpacing) / 2)

      HStack(alignment: .top, spacing: columnSpacing) {
        landscapePlanRegion
          .frame(width: leftWidth, height: geometry.size.height, alignment: .topLeading)
          .accessibilitySortPriority(100)
          .exerciseLayoutMarker("exercise.landscape.left", label: "Plan and timer region")

        VStack(spacing: rowSpacing) {
          HStack(alignment: .top, spacing: cardSpacing) {
            axisCard(presentation.speed, tint: .yellow, speed: true, compact: true)
              .frame(width: cardWidth)
              .exerciseLayoutMarker("exercise.speed", label: "Speed controls")
            axisCard(
              presentation.inclination,
              tint: .cyan,
              speed: false,
              compact: true
            )
            .frame(width: cardWidth)
            .exerciseLayoutMarker("exercise.inclination", label: "Inclination controls")
          }
          .frame(width: rightWidth, height: axisHeight, alignment: .top)
          .accessibilitySortPriority(80)
          .exerciseLayoutMarker("exercise.landscape.axes", label: "Adjustment cards region")

          landscapeActionRegion
            .frame(width: rightWidth, height: actionHeight)
            .accessibilitySortPriority(60)
            .exerciseLayoutMarker("exercise.landscape.actions", label: "Workout actions region")
        }
        .frame(width: rightWidth, height: geometry.size.height, alignment: .top)
        .exerciseLayoutMarker("exercise.landscape.right", label: "Controls region")
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
      .exerciseLayoutMarker("exercise.landscape", label: "Landscape exercise layout")
    }
  }

  private var landscapePlanRegion: some View {
    VStack(alignment: .leading, spacing: 7) {
      statusSummary
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exercise.status")
        .accessibilityValue("\(presentation.status.title). \(presentation.status.detail)")

      Text(presentation.currentInterval)
        .font(.subheadline.weight(.bold))
        .tracking(0.9)
        .textCase(.uppercase)
        .foregroundStyle(statusTint)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityIdentifier("exercise.interval")

      Text(presentation.countdown)
        .font(.system(size: 76, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.7)
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
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .accessibilityIdentifier("exercise.next")

      landscapeEvidenceBoundary

      Spacer(minLength: 0)

      HStack(alignment: .bottom, spacing: 12) {
        metric(title: "Elapsed active", value: presentation.elapsedActiveTime)
        metric(
          title: "Distance",
          value: presentation.distance,
          detail: presentation.distanceDetail
        )
        fullPlanButton(minimumHeight: 48)
          .fixedSize(horizontal: true, vertical: false)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("exercise.progress-region")
  }

  private var landscapeEvidenceBoundary: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(
        "Treadmill shows the reported value. Plan shows the original setting. Your setting includes changes for this step."
      )
      .font(.caption2)
      .foregroundStyle(WorkoutExercisePalette.muted)
      .lineLimit(2)
      .minimumScaleFactor(0.8)
      if let restorationDetail = presentation.restorationDetail {
        Text(restorationDetail)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.yellow)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
          .accessibilityIdentifier("exercise.restoration")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("exercise.evidence-boundary")
  }

  private var landscapeActionRegion: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 3) {
        Label(
          "Start and Stop remain on the physical treadmill console",
          systemImage: "hand.raised.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(WorkoutExercisePalette.muted)
        .lineLimit(3)
        .minimumScaleFactor(0.75)
        .accessibilityIdentifier("exercise.console-authority")

        if let overrideLabel = presentation.overrideLabel {
          Text(overrideLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.yellow)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityIdentifier("exercise.override-state")
        } else {
          Text(
            shouldReduceMotion
              ? "Animation off" : "Gentle status animation"
          )
          .font(.caption2)
          .foregroundStyle(WorkoutExercisePalette.muted)
          .lineLimit(2)
          .minimumScaleFactor(0.75)
          .accessibilityIdentifier("exercise.motion")
          .accessibilityValue(shouldReduceMotion ? "Static guidance" : "Gentle pulse")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if presentation.canConfirmOperatorStationary {
        Button(stationaryActionTitle) { stationaryAction() }
        .landscapeExerciseActionStyle(tint: .orange)
        .accessibilityIdentifier("exercise.confirm-stationary")
          .accessibilityHint("Only activate after you have seen the belt stop. A missing treadmill update does not mean it has stopped.")
      } else {
        if presentation.canReturnToPlan {
          Button("Return to plan") { send(.returnToPlan) }
            .landscapeExerciseActionStyle(tint: .blue)
            .accessibilityIdentifier("exercise.return-to-plan")
        }

        if presentation.canEndWorkout {
          Button("End workout") { send(.endWorkout) }
            .landscapeExerciseActionStyle(tint: .red)
            .accessibilityHint("Finishes the workout after the treadmill has stopped. Use the console to stop the belt.")
            .accessibilityIdentifier("exercise.end")
        }
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WorkoutExercisePalette.surface, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(WorkoutExercisePalette.border, lineWidth: 1)
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      statusSummary
      Spacer(minLength: 8)
      fullPlanButton(minimumHeight: 44)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("exercise.status")
    .accessibilityValue("\(presentation.status.title). \(presentation.status.detail)")
  }

  private var statusSummary: some View {
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
  }

  private func fullPlanButton(minimumHeight: CGFloat) -> some View {
    Button {
      showingPlan = true
    } label: {
      Label("Full plan", systemImage: "list.bullet.rectangle")
        .font(.subheadline.weight(.semibold))
        .frame(minHeight: minimumHeight)
    }
    .buttonStyle(.bordered)
    .accessibilityIdentifier("exercise.plan.open")
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
      Label("Your settings and treadmill readings", systemImage: "shield.lefthalf.filled")
        .font(.caption.weight(.bold))
        .foregroundStyle(WorkoutExercisePalette.muted)
      Text(
        "Treadmill shows the reported value. Plan shows the original setting. Your setting includes changes for this step."
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
    speed: Bool,
    compact: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: compact ? 5 : 12) {
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

      valueRow(label: "Treadmill", value: axis.actual, emphasis: true, compact: compact)
      valueRow(label: "Plan", value: axis.planned, compact: compact)
      valueRow(label: "Your setting", value: axis.effective, compact: compact)

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
        .lineLimit(compact ? 3 : nil)
        .minimumScaleFactor(compact ? 0.75 : 1)
        .fixedSize(horizontal: false, vertical: !compact)

      HStack(spacing: 10) {
        adjustmentButton(
          symbol: "minus",
          label: axis.decrementLabel,
          target: axis.decrementTarget,
          speed: speed,
          tint: tint,
          compact: compact
        )
        adjustmentButton(
          symbol: "plus",
          label: axis.incrementLabel,
          target: axis.incrementTarget,
          speed: speed,
          tint: tint,
          compact: compact
        )
      }
    }
    .padding(compact ? 10 : 14)
    .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil, alignment: .topLeading)
    .background(WorkoutExercisePalette.surface, in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(WorkoutExercisePalette.border, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private func adjustmentButton(
    symbol: String,
    label: String,
    target: Decimal?,
    speed: Bool,
    tint: Color,
    compact: Bool = false
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
        .frame(maxWidth: .infinity, minHeight: compact ? 48 : 56)
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
      "Changes this step only, using the settings supported by the connected treadmill."
    )
    .accessibilityIdentifier(
      "exercise.\(speed ? "speed" : "inclination").\(symbol)"
    )
  }

  private var stationaryActionTitle: String {
    presentation.canConfirmStationaryAndEnd ? "Treadmill stopped — end workout" : "I can see the belt has stopped"
  }

  private func stationaryAction() {
    if presentation.canConfirmStationaryAndEnd { send(.confirmStationaryAndEndWorkout) }
    else { send(.confirmOperatorStationary) }
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
          Text(presentation.canConfirmStationaryAndEnd ? "Finish your workout" : "Confirm the treadmill is stopped")
            .font(.caption.weight(.bold))
          Text(
            "Stop the treadmill at its console. Only tap below once you have seen the belt stop."
          )
          .font(.caption2)
          .foregroundStyle(WorkoutExercisePalette.muted)
          .fixedSize(horizontal: false, vertical: true)
          Button(stationaryActionTitle) { stationaryAction() }
          .exerciseActionStyle(tint: .orange)
          .accessibilityIdentifier("exercise.confirm-stationary")
          .accessibilityHint("Only activate after you have seen the belt stop. A missing treadmill update does not mean it has stopped.")


        }
        .padding(12)
        .background(WorkoutExercisePalette.surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exercise.stationary-fallback")
      }

      if presentation.canEndWorkout {
        Button("End workout") { send(.endWorkout) }
          .exerciseActionStyle(tint: .red)
          .accessibilityHint("Finishes the workout after the treadmill has stopped. Use the console to stop the belt.")
          .accessibilityIdentifier("exercise.end")
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
          ? "Animation off" : "Gentle status animation"
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

  private func valueRow(
    label: String,
    value: String,
    emphasis: Bool = false,
    compact: Bool = false
  ) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .font(.caption)
        .foregroundStyle(WorkoutExercisePalette.muted)
      Spacer(minLength: 5)
      Text(value)
        .font(
          emphasis
            ? (compact
              ? .title3.monospacedDigit().weight(.bold)
              : .title2.monospacedDigit().weight(.bold))
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
  fileprivate func exerciseLayoutMarker(_ identifier: String, label: String) -> some View {
    // Group real controls without an overlapping accessible geometry leaf.
    ZStack {
      // Preserve the wrapper's identity independently of nested region identifiers.
      Color.clear
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      self
    }
    .contentShape(.accessibility, Rectangle())
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier)
  }

  fileprivate func exerciseActionStyle(tint: Color) -> some View {
    font(.headline)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 56)
      .background(tint.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
      .contentShape(RoundedRectangle(cornerRadius: 14))
  }

  fileprivate func landscapeExerciseActionStyle(tint: Color) -> some View {
    font(.caption.weight(.semibold))
      .foregroundStyle(.white)
      .lineLimit(2)
      .minimumScaleFactor(0.75)
      .frame(maxWidth: .infinity, minHeight: 48)
      .padding(.horizontal, 6)
      .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(tint.opacity(0.9), lineWidth: 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: 12))
  }
}
