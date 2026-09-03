import SwiftUI

@main
struct PacePromptApp: App {
    @StateObject private var treadmill: TreadmillSetupViewModel
    @StateObject private var plans: PlansViewModel
    private let workoutCapabilitiesOverride: WorkoutPlanCapabilities?

    init() {
        _treadmill = StateObject(wrappedValue: TreadmillSetupViewModel())
#if DEBUG
        let configuration = PlansUITestConfiguration.current
        _plans = StateObject(
            wrappedValue: PlansViewModel(
                repository: configuration.repository ?? SavedPlanRepository(),
                makeNewDraft: configuration.makeNewDraft
            )
        )
        workoutCapabilitiesOverride = configuration.capabilities
#else
        _plans = StateObject(wrappedValue: PlansViewModel())
        workoutCapabilitiesOverride = nil
#endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(
                treadmill: treadmill,
                plans: plans,
                workoutCapabilitiesOverride: workoutCapabilitiesOverride
            )
        }
    }
}
