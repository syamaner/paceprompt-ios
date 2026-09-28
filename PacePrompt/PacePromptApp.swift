import SwiftUI
import UIKit

@MainActor
final class ApplicationWorkoutDisplayWakeController: WorkoutDisplayWakeControlling {
  func setWorkoutKeepsScreenAwake(_ enabled: Bool) {
    UIApplication.shared.isIdleTimerDisabled = enabled
  }
}

@main
struct PacePromptApp: App {
  @StateObject private var treadmill: TreadmillSetupViewModel
  @StateObject private var plans: PlansViewModel
  @StateObject private var workoutSession: WorkoutSessionCoordinator
  private let workoutCapabilitiesOverride: WorkoutPlanCapabilities?
  #if DEBUG
    private let preflightUITestConfiguration: WorkoutPreflightUITestConfiguration?
    private let exerciseUITestConfiguration: WorkoutExerciseUITestConfiguration?
  #endif

  init() {
    let resolvedTreadmill: TreadmillSetupViewModel
    let resolvedPlans: PlansViewModel
    #if DEBUG
      resolvedTreadmill = HomeUITestConfiguration.makeTreadmill()
      let configuration = PlansUITestConfiguration.current
      resolvedPlans = PlansViewModel(
        repository: configuration.repository ?? SavedPlanRepository(),
        makeNewDraft: configuration.makeNewDraft
      )
      workoutCapabilitiesOverride = configuration.capabilities
      preflightUITestConfiguration = WorkoutPreflightUITestConfiguration.current
      exerciseUITestConfiguration = WorkoutExerciseUITestConfiguration.current
    #else
      resolvedTreadmill = TreadmillSetupViewModel()
      resolvedPlans = PlansViewModel()
      workoutCapabilitiesOverride = nil
    #endif
    #if DEBUG
      let uiTesting = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--paceprompt-") && $0.hasSuffix("-ui-testing") }
      let profiles = PlanningProfileUITestSupport.enabled ? PlanningProfileUITestSupport.model()
        : PlanningProfilesViewModel(repository: uiTesting ? MemoryPlanningProfileRepository() : FilePlanningProfileRepository(), identity: LocalPlanningProfileIdentity())
      resolvedTreadmill.attachPlanningProfiles(profiles, discoveryEnabled: !uiTesting)
    #else
      let profiles = PlanningProfilesViewModel(repository: FilePlanningProfileRepository(), identity: LocalPlanningProfileIdentity())
      resolvedTreadmill.attachPlanningProfiles(profiles)
    #endif
    guard let binding = resolvedTreadmill.executionBinding else {
      preconditionFailure("The production treadmill composition must include workout execution")
    }
    _treadmill = StateObject(wrappedValue: resolvedTreadmill)
    _plans = StateObject(wrappedValue: resolvedPlans)
    _workoutSession = StateObject(
      wrappedValue: WorkoutSessionCoordinator(
        binding: binding,
        displayWakeController: ApplicationWorkoutDisplayWakeController(),
        watchFactory: {
          let adapter = PhoneWatchSessionAdapter()
          let lifecycle = PhoneWatchLifecycle(port: adapter, reserve: { id in
            try WatchOwnershipStore().reserve(id)
            guard binding.orchestrator.reserveWatchAttempt(id: id) else { throw WatchStoreError.definite }
          }, makeID: UUID.init, monotonic: { ProcessInfo.processInfo.systemUptime })
          adapter.lifecycle = lifecycle
          return lifecycle
        }
      )
    )
  }

  var body: some Scene {
    WindowGroup {
      #if DEBUG
        if let exerciseUITestConfiguration {
          WorkoutExerciseUITestHost(configuration: exerciseUITestConfiguration)
        } else if let preflightUITestConfiguration {
          WorkoutPreflightUITestHost(configuration: preflightUITestConfiguration)
        } else {
          rootView
        }
      #else
        rootView
      #endif
    }
  }

  private var rootView: some View {
    RootTabView(
      treadmill: treadmill,
      plans: plans,
      workoutSession: workoutSession,
      workoutCapabilitiesOverride: workoutCapabilitiesOverride
    )
  }
}
