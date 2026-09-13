import SwiftUI

@main
struct PacePromptApp: App {
  @StateObject private var treadmill: TreadmillSetupViewModel
  @StateObject private var plans: PlansViewModel
  #if PACEPROMPT_ISSUE62_PROOF
    @StateObject private var issue62Proof: Issue62WorkoutProofCoordinator
  #endif
  private let workoutCapabilitiesOverride: WorkoutPlanCapabilities?
  #if DEBUG
    private let preflightUITestConfiguration: WorkoutPreflightUITestConfiguration?
    private let exerciseUITestConfiguration: WorkoutExerciseUITestConfiguration?
  #endif

  init() {
    #if PACEPROMPT_ISSUE62_PROOF
      let client = FTMSClient()
      let authority = Issue62WorkoutProofSessionAuthority()
      let binding = ProductionWorkoutExecutionBinding(client: client, authority: authority)
      let treadmill = TreadmillSetupViewModel(client: client, executionBinding: binding)
      _treadmill = StateObject(wrappedValue: treadmill)
      _plans = StateObject(wrappedValue: PlansViewModel())
      _issue62Proof = StateObject(
        wrappedValue: Issue62WorkoutProofCoordinator(
          treadmill: treadmill,
          binding: binding,
          authority: authority
        )
      )
      workoutCapabilitiesOverride = nil
      #if DEBUG
        preflightUITestConfiguration = nil
        exerciseUITestConfiguration = nil
      #endif
    #elseif DEBUG
      _treadmill = StateObject(wrappedValue: HomeUITestConfiguration.makeTreadmill())
      let configuration = PlansUITestConfiguration.current
      _plans = StateObject(
        wrappedValue: PlansViewModel(
          repository: configuration.repository ?? SavedPlanRepository(),
          makeNewDraft: configuration.makeNewDraft
        )
      )
      workoutCapabilitiesOverride = configuration.capabilities
      preflightUITestConfiguration = WorkoutPreflightUITestConfiguration.current
      exerciseUITestConfiguration = WorkoutExerciseUITestConfiguration.current
    #else
      _treadmill = StateObject(wrappedValue: TreadmillSetupViewModel())
      _plans = StateObject(wrappedValue: PlansViewModel())
      workoutCapabilitiesOverride = nil
    #endif
  }

  var body: some Scene {
    WindowGroup {
      #if PACEPROMPT_ISSUE62_PROOF
        Issue62WorkoutProofHost(treadmill: treadmill, coordinator: issue62Proof)
      #elseif DEBUG
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
      workoutCapabilitiesOverride: workoutCapabilitiesOverride
    )
  }
}
