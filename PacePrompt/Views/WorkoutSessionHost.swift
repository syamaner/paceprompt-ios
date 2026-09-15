import SwiftUI

enum WorkoutSessionStage: Equatable {
  case inactive
  case preparation
  case preflight
  case exercise
}

struct WorkoutSessionLimitDraft: Equatable {
  var maximumSpeed = ""
  var maximumInclination = ""
  var maximumStepSpeedChange = ""

  func ceilings(locale: Locale = .autoupdatingCurrent) -> WorkoutSessionCeilings? {
    guard let speed = Self.decimal(maximumSpeed, locale: locale),
      let inclination = Self.decimal(maximumInclination, locale: locale),
      let stepChange = Self.decimal(maximumStepSpeedChange, locale: locale)
    else { return nil }
    return .init(
      maximumSpeed: .init(value: speed, unit: .kilometresPerHour),
      maximumInclination: .init(value: inclination, unit: .percent),
      maximumStepSpeedChange: .init(value: stepChange, unit: .kilometresPerHour)
    )
  }

  private static func decimal(_ text: String, locale: Locale) -> Decimal? {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    if let grouping = locale.groupingSeparator,
      !grouping.isEmpty,
      grouping != locale.decimalSeparator,
      value.contains(grouping)
    {
      return nil
    }
    if let separator = locale.decimalSeparator, separator != ".", !separator.isEmpty {
      value = value.replacingOccurrences(of: separator, with: ".")
    }
    guard value.allSatisfy({ $0.isNumber || $0 == "." || $0 == "+" || $0 == "-" }) else {
      return nil
    }
    return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
  }
}

@MainActor
final class WorkoutSessionCoordinator: ObservableObject {
  @Published private(set) var stage: WorkoutSessionStage = .inactive
  @Published private(set) var selectedPlan: SavedPlanRecord?
  @Published var limits = WorkoutSessionLimitDraft()
  @Published private(set) var notice: String?
  @Published private(set) var revision = 0

  let binding: ProductionWorkoutExecutionBinding

  init(binding: ProductionWorkoutExecutionBinding) {
    self.binding = binding
    _ = binding.orchestrator.recoverInterruptedHistory()
  }

  var isPresented: Bool { stage != .inactive }

  var canLeaveExercise: Bool { exercisePresentation.allowsDismissal }

  var preflightPresentation: WorkoutPreflightPresentation? {
    guard let record = selectedPlan,
      let profile = binding.executionProfile,
      let ceilings = limits.ceilings(),
      case .success(let plan) = WorkoutPlanValidator.validate(
        record.plan,
        against: binding.currentCapability?.planCapabilities ?? .unavailable
      )
    else { return nil }
    return .init(
      context: .init(
        validatedPlan: plan,
        ceilings: ceilings,
        profile: profile,
        executionState: binding.orchestrator.state
      ),
      at: SystemWorkoutOrchestrationClock().read().monotonic,
      locale: .autoupdatingCurrent
    )
  }

  var exercisePresentation: WorkoutExercisePresentation {
    .init(
      context: .init(orchestrator: binding.orchestrator),
      at: SystemWorkoutOrchestrationClock().read().monotonic,
      locale: .autoupdatingCurrent
    )
  }

  func begin(_ record: SavedPlanRecord) {
    guard stage == .inactive else { return }
    selectedPlan = record
    limits = .init()
    notice = nil
    stage = .preparation
  }

  func cancelBeforeExercise() {
    guard stage == .preparation || stage == .preflight else { return }
    if stage == .preflight,
      case .preflight = binding.orchestrator.state.execution,
      binding.cancelPreflight()?.reducerDisposition != .accepted
    {
      notice = "The prepared workout could not be cancelled in its current local state."
      return
    }
    reset()
  }

  func prepareWorkout() {
    guard stage == .preparation, let record = selectedPlan else { return }
    guard binding.canExposeArming,
      let capability = binding.currentCapability,
      let ceilings = limits.ceilings()
    else {
      notice = binding.canExposeArming
        ? "Enter all three session limits as exact numbers."
        : "Connect the accepted FR30z and wait for its current profile checks to complete."
      return
    }
    guard case .success(let plan) = WorkoutPlanValidator.validate(
      record.plan,
      against: capability.planCapabilities
    ) else {
      notice = "This saved plan is not valid for the current treadmill capability snapshot."
      return
    }
    guard let result = binding.arm(plan: plan, ceilings: ceilings, sourcePlanID: record.id),
      result.reducerDisposition == .accepted
    else {
      notice =
        "The plan or session limits are outside the current treadmill range, grid, or maximum interval change."
      return
    }
    notice = nil
    stage = .preflight
    refresh()
  }

  func handlePreflight(_ intent: WorkoutPreflightIntent) {
    guard stage == .preflight else { return }
    guard intent == .beginWorkout,
      preflightPresentation?.canBeginWorkout == true,
      let result = binding.beginWorkout(),
      result.reducerDisposition == .accepted
    else { return }
    notice = nil
    stage = .exercise
    refresh()
  }

  func handleExercise(_ intent: WorkoutExerciseIntent) {
    guard stage == .exercise, let epoch = binding.epoch else { return }
    let result: WorkoutOrchestrationResult
    switch intent {
    case .setSpeed(let speed):
      result = binding.handle(.setSpeedOverride(epoch: epoch, speed))
    case .setInclination(let inclination):
      result = binding.handle(.setInclinationOverride(epoch: epoch, inclination))
    case .returnToPlan:
      result = binding.handle(.returnToPlan(epoch: epoch))
    case .confirmOperatorStationary:
      result = binding.handle(
        .humanConfirmsStationary(
          epoch: epoch,
          note: "Operator confirmed the treadmill stationary"
        )
      )
    case .endWorkout:
      result = binding.handle(.userEndsWorkout(epoch: epoch))
    }
    if case .rejected = result.reducerDisposition {
      notice = "That action is unavailable in the current workout state."
    } else {
      notice = nil
    }
    refresh()
  }

  func refresh() {
    binding.tick()
    revision &+= 1
  }

  func closeTerminalWorkout() {
    guard stage == .exercise, canLeaveExercise else { return }
    reset()
  }

  private func reset() {
    stage = .inactive
    selectedPlan = nil
    limits = .init()
    notice = nil
    revision &+= 1
  }
}

struct WorkoutSessionHost: View {
  @ObservedObject var treadmill: TreadmillSetupViewModel
  @ObservedObject var coordinator: WorkoutSessionCoordinator
  let showHistory: () -> Void

  private let refreshTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

  var body: some View {
    Group {
      switch coordinator.stage {
      case .inactive:
        EmptyView()
      case .preparation:
        preparation
      case .preflight:
        if let presentation = coordinator.preflightPresentation {
          WorkoutPreflightView(presentation: presentation, send: coordinator.handlePreflight)
            .overlay(alignment: .topLeading) { preflightCancelButton }
        } else {
          unavailablePreflight
            .overlay(alignment: .topLeading) { preflightCancelButton }
        }
      case .exercise:
        WorkoutExerciseView(
          presentation: coordinator.exercisePresentation,
          send: coordinator.handleExercise
        )
        .safeAreaInset(edge: .bottom) {
          terminalAction
        }
      }
    }
    .onReceive(refreshTimer) { _ in coordinator.refresh() }
  }

  private var preparation: some View {
    NavigationStack {
      Form {
        if let plan = coordinator.selectedPlan?.plan {
          Section("Workout") {
            LabeledContent("Plan", value: plan.suggestedName)
            LabeledContent("Activity", value: plan.activity.displayName)
            LabeledContent("Segments", value: plan.steps.count.formatted())
          }
        }

        Section("Treadmill") {
          LabeledContent("Connection", value: treadmill.connectionState.title)
          NavigationLink("Connect or inspect treadmill") {
            TreadmillSetupView(treadmill: treadmill)
          }
          Text(
            coordinator.binding.canExposeArming
              ? "The current connection matches the accepted FR30z production profile."
              : "Connect the accepted FR30z and wait for current capabilities and subscriptions."
          )
          .foregroundStyle(coordinator.binding.canExposeArming ? .green : .secondary)
          .accessibilityIdentifier("workout.prepare.connection-status")
        }

        Section {
          limitField(
            "Maximum speed",
            value: $coordinator.limits.maximumSpeed,
            prompt: "km/h",
            identifier: "workout.prepare.maximum-speed"
          )
          limitField(
            "Maximum inclination",
            value: $coordinator.limits.maximumInclination,
            prompt: "%",
            identifier: "workout.prepare.maximum-inclination"
          )
          limitField(
            "Maximum interval speed change",
            value: $coordinator.limits.maximumStepSpeedChange,
            prompt: "km/h",
            identifier: "workout.prepare.maximum-step-change"
          )
        } header: {
          Text("Session limits")
        } footer: {
          Text(
            "These exact limits must contain the complete plan and define the available manual adjustments. PacePrompt never substitutes the treadmill's advertised maximums."
          )
        }

        if let notice = coordinator.notice {
          Section {
            Label(notice, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
              .accessibilityIdentifier("workout.prepare.notice")
          }
        }

        Section {
          Button("Continue to preflight") { coordinator.prepareWorkout() }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("workout.prepare.continue")
        } footer: {
          Text(
            "This validates and prepares the local workout. No treadmill procedure is sent until after Begin workout and fresh physical-Start movement."
          )
        }
      }
      .navigationTitle("Prepare workout")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { coordinator.cancelBeforeExercise() }
            .accessibilityIdentifier("workout.prepare.cancel")
        }
      }
    }
  }

  private var unavailablePreflight: some View {
    ContentUnavailableView(
      "Preflight unavailable",
      systemImage: "exclamationmark.triangle.fill",
      description: Text("The selected plan or current treadmill profile changed.")
    )
  }

  private var preflightCancelButton: some View {
    Button("Cancel") { coordinator.cancelBeforeExercise() }
      .buttonStyle(.bordered)
      .padding(12)
      .accessibilityIdentifier("workout.preflight.cancel")
  }

  @ViewBuilder
  private var terminalAction: some View {
    if coordinator.canLeaveExercise {
      Button(
        coordinator.exercisePresentation.stage == .finished ? "View workout in History" : "Close workout"
      ) {
        let finished = coordinator.exercisePresentation.stage == .finished
        coordinator.closeTerminalWorkout()
        if finished { showHistory() }
      }
      .buttonStyle(.borderedProminent)
      .padding(12)
      .frame(maxWidth: .infinity)
      .background(.ultraThinMaterial)
      .accessibilityIdentifier("workout.terminal.close")
    }
  }

  private func limitField(
    _ title: String,
    value: Binding<String>,
    prompt: String,
    identifier: String
  ) -> some View {
    HStack {
      Text(title)
      Spacer(minLength: 12)
      TextField(prompt, text: value)
        .multilineTextAlignment(.trailing)
        .keyboardType(.decimalPad)
        .frame(maxWidth: 110)
        .accessibilityIdentifier(identifier)
    }
  }
}
