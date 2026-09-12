import SwiftUI

@main
struct PacePromptApp: App {
    @StateObject private var treadmill: TreadmillSetupViewModel
    @StateObject private var plans: PlansViewModel
    private let workoutCapabilitiesOverride: WorkoutPlanCapabilities?
#if DEBUG
    private let preflightUITestConfiguration: WorkoutPreflightUITestConfiguration?
#endif

    init() {
#if DEBUG
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
#else
        _treadmill = StateObject(wrappedValue: TreadmillSetupViewModel())
        _plans = StateObject(wrappedValue: PlansViewModel())
        workoutCapabilitiesOverride = nil
#endif
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let preflightUITestConfiguration {
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
