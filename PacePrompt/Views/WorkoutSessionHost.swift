import SwiftUI

enum WorkoutSessionStage: Equatable {
  case inactive
  case preparation
  case preflight
  case exercise
}

@MainActor
protocol WorkoutDisplayWakeControlling: AnyObject {
  func setWorkoutKeepsScreenAwake(_ enabled: Bool)
}

struct WorkoutDisplayWakePolicy {
  static func shouldKeepScreenAwake(
    sessionStage: WorkoutSessionStage,
    exerciseStage: WorkoutExerciseStage
  ) -> Bool {
    guard sessionStage == .exercise else { return false }
    switch exerciseStage {
    case .finished, .failed, .interrupted:
      return false
    case .waiting, .applying, .running, .override, .checking, .paused, .restoring,
      .awaitingPhysicalStop, .readyToEnd, .ending:
      return true
    }
  }
}

@MainActor
final class WorkoutSessionCoordinator: ObservableObject {
  @Published private(set) var stage: WorkoutSessionStage = .inactive
  @Published private(set) var selectedPlan: SavedPlanRecord?
  @Published private(set) var notice: String?
  @Published private(set) var revision = 0
  @Published private(set) var liveFailure: LivePreflightFailure?
  @Published var useAppleWatch = false
  @Published private(set) var watchStatus: String?
  private let watchFactory: (() -> PhoneWatchLifecycle)?
  private var watch: PhoneWatchLifecycle?
  var watchAvailable: Bool { watchFactory != nil }

  private enum PendingRead { case preparation, begin }
  private var pendingRead: PendingRead?

  let binding: ProductionWorkoutExecutionBinding
  private let displayWakeController: any WorkoutDisplayWakeControlling
  private var displayWakeIsEnabled: Bool?

  init(
    binding: ProductionWorkoutExecutionBinding,
    displayWakeController: any WorkoutDisplayWakeControlling,
    watchFactory: (() -> PhoneWatchLifecycle)? = nil
  ) {
    self.watchFactory = watchFactory
    self.binding = binding
    self.displayWakeController = displayWakeController
    displayWakeIsEnabled = false
    displayWakeController.setWorkoutKeepsScreenAwake(false)
    _ = binding.orchestrator.recoverInterruptedHistory()
    binding.capabilityReadObserver = { [weak self] in self?.completeCapabilityRead() }
    binding.executionStateObserver = { [weak self] _ in
      self?.projectWatchExecution()
      self?.synchronizeDisplayWakePolicy()
      if self?.stage == .preflight, self?.pendingRead == nil { self?.completeCapabilityRead() }
    }
  }

  var isPresented: Bool { stage != .inactive }

  var canLeaveExercise: Bool { exercisePresentation.allowsDismissal }

  var preflightPresentation: WorkoutPreflightPresentation? {
    guard liveFailure == nil, pendingRead == nil, let record = selectedPlan,
      let profile = binding.executionProfile,
      case .success(let plan) = WorkoutPlanValidator.validate(
        record.plan,
        against: binding.currentCapability?.planCapabilities ?? .unavailable
      )
    else { return nil }
    return .init(
      context: .init(
        validatedPlan: plan,
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
    watch = watchFactory?()
    watch?.changed = { [weak self] in self?.watchStatus = self?.watch?.status }
    watch?.bound = { [weak self] _ in
      guard let self, self.stage == .preflight else { return }
      self.requestCapabilityRead(.begin)
    }
    watchStatus = nil
    notice = nil
    stage = .preparation
  }

  func cancelBeforeExercise() {
    guard stage == .preparation || stage == .preflight else { return }
    watch?.cancel()
    pendingRead = nil
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
    guard stage == .preparation, selectedPlan != nil else { return }
    notice = nil
    stage = .preflight
    requestCapabilityRead(.preparation)
  }

  private func requestCapabilityRead(_ action: PendingRead) {
    pendingRead = action
    if let plan = selectedPlan?.plan {
      liveFailure = .init(plan: plan, reason: "Reading current treadmill capabilities. Execution remains blocked.", issues: [], readComplete: false)
    }
    binding.readCapabilitiesForPreflight()
  }

  private func completeCapabilityRead() {
    guard stage == .preflight, let record = selectedPlan else { return }
    guard case .reading = binding.preflightRead else {
      let action = pendingRead
      pendingRead = nil
      liveFailure = LivePreflightFailure.review(record.plan, read: binding.preflightRead, epoch: binding.epoch)
      if liveFailure == nil && !binding.canExposeArming {
        liveFailure = .init(plan: record.plan, reason: "Current capability or subscriptions do not match the accepted FR30z execution profile. No control authority is granted.", issues: [], readComplete: true)
      }
      if liveFailure == nil, action == nil, binding.orchestrator.state.armedWorkout == nil {
        liveFailure = .init(plan: record.plan, reason: "A new deliberate preparation is required. Choose another treadmill to return to setup.", issues: [], readComplete: true)
      }
      if liveFailure == nil, let action {
        switch action {
        case .preparation:
          guard let capability = binding.currentCapability,
            case .success(let plan) = WorkoutPlanValidator.validate(record.plan, against: capability.planCapabilities),
            let result = binding.arm(plan: plan, sourcePlanID: record.id), result.reducerDisposition == .accepted else {
              liveFailure = .init(plan: record.plan, reason: "The exact plan fails current capability range or increment validation.", issues: [], readComplete: true)
              revision &+= 1; return
          }
        case .begin:
          if useAppleWatch, let watch, watch.phase != .bound {
            if watch.phase == .idle { Task { await watch.start(activity: record.plan.activity.rawValue) } }
            revision &+= 1
            return
          }
          guard preflightPresentation?.canBeginWorkout == true,
            let result = binding.beginWorkout(), result.reducerDisposition == .accepted else {
              liveFailure = .init(plan: record.plan, reason: "Current execution readiness changed. Begin a new deliberate preparation.", issues: [], readComplete: true)
              revision &+= 1; return
          }
          stage = .exercise
        }
      }
      synchronizeDisplayWakePolicy()
      revision &+= 1
      return
    }
  }

  func handlePreflight(_ intent: WorkoutPreflightIntent) {
    guard stage == .preflight, intent == .beginWorkout,
      preflightPresentation?.canBeginWorkout == true else { return }
    requestCapabilityRead(.begin)
  }

  func chooseAnotherTreadmill() {
    guard stage == .preflight else { return }
    let record = selectedPlan
    cancelBeforeExercise()
    guard stage == .inactive, let record else { return }
    begin(record)
    notice = "Choose and connect a treadmill explicitly, then Continue for a fresh read."
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

  func applicationBecameActive() {
    watch?.foreground()
    projectWatchExecution()
  }

  func refresh() {
    binding.tick()
    watch?.tick()
    projectWatchExecution()
    synchronizeDisplayWakePolicy()
    revision &+= 1
  }

  private func projectWatchExecution() {
    guard useAppleWatch, let watch, [.bound, .reconnecting].contains(watch.phase) else { return }
    let orchestrator = binding.orchestrator
    let reading = SystemWorkoutOrchestrationClock().read()
    if case let .fresh(sample) = orchestrator.state.telemetry {
      let observedAt = reading.wallClock.addingTimeInterval(sample.receivedAt.seconds - reading.monotonic.seconds)
      switch orchestrator.state.execution {
      case .paused: watch.requestRecording("paused", observedAt: observedAt)
      case .runningSegment: watch.requestRecording("running", observedAt: observedAt)
      default: break
      }
    }
    watch.update(intervals: WatchExecutionProjection.intervals(orchestrator.watchClosedIntervals),
                 outcome: WatchExecutionProjection.outcome(orchestrator.lastPersistedSummary),
                 distance: WatchExecutionProjection.distance(orchestrator.lastPersistedSummary))
  }

  func closeTerminalWorkout() {
    guard stage == .exercise, canLeaveExercise else { return }
    reset()
  }

  private func reset() {
    stage = .inactive
    pendingRead = nil
    liveFailure = nil
    selectedPlan = nil
    useAppleWatch = false
    notice = nil
    synchronizeDisplayWakePolicy()
    revision &+= 1
  }

  private func synchronizeDisplayWakePolicy() {
    let shouldKeepScreenAwake = WorkoutDisplayWakePolicy.shouldKeepScreenAwake(
      sessionStage: stage,
      exerciseStage: exercisePresentation.stage
    )
    guard displayWakeIsEnabled != shouldKeepScreenAwake else { return }
    displayWakeIsEnabled = shouldKeepScreenAwake
    displayWakeController.setWorkoutKeepsScreenAwake(shouldKeepScreenAwake)
  }
}

struct WorkoutSessionHost: View {
  @ObservedObject var treadmill: TreadmillSetupViewModel
  @ObservedObject var coordinator: WorkoutSessionCoordinator
  let showHistory: () -> Void
  let editPlan: (SavedPlanRecord) -> Void
  @State private var choosingTreadmill = false

  private let refreshTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

  var body: some View {
    Group {
      switch coordinator.stage {
      case .inactive:
        EmptyView()
      case .preparation:
        preparation
      case .preflight:
        if let failure = coordinator.liveFailure {
          LivePreflightFailureView(failure: failure, treadmillName: treadmill.connectionState.title, cancel: coordinator.cancelBeforeExercise, edit: {
            let record = coordinator.selectedPlan
            coordinator.cancelBeforeExercise()
            if coordinator.stage == .inactive, let record { editPlan(record) }
          }, chooseTreadmill: {
            coordinator.chooseAnotherTreadmill()
            if coordinator.stage == .preparation { choosingTreadmill = true }
          })
        } else if let presentation = coordinator.preflightPresentation {
          WorkoutPreflightView(presentation: presentation, send: coordinator.handlePreflight, useAppleWatch: coordinator.useAppleWatch)
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
    .sheet(isPresented: $choosingTreadmill) {
      NavigationStack { TreadmillSetupView(treadmill: treadmill).toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { choosingTreadmill = false } }
      } }
    }
    .safeAreaInset(edge: .top) {
      if let status = coordinator.watchStatus { Text(status).font(.caption).padding().accessibilityIdentifier("watch-workout-status") }
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

        if coordinator.watchAvailable {
          Section("Apple Watch") {
            Toggle("Record workout on Apple Watch", isOn: $coordinator.useAppleWatch)
            Text("Apple Watch saves the workout, available heart rate and estimated active energy. iPhone saving stays disabled for this attempt, even if the connection is lost.")
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

        Section("Live capability bounds") {
          Text("Continue reads current treadmill ranges and increments. Every exact plan target and manual adjustment must fit that evidence.")
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

}
