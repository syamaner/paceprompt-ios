import SwiftUI

struct RootTabView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel
    @ObservedObject var plans: PlansViewModel
    let workoutCapabilitiesOverride: WorkoutPlanCapabilities?

    init(
        treadmill: TreadmillSetupViewModel,
        plans: PlansViewModel,
        workoutCapabilitiesOverride: WorkoutPlanCapabilities? = nil
    ) {
        self.treadmill = treadmill
        self.plans = plans
        self.workoutCapabilitiesOverride = workoutCapabilitiesOverride
    }

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(treadmill: treadmill)
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                PlansView(
                    viewModel: plans,
                    capabilities: workoutCapabilitiesOverride ?? treadmill.workoutPlanCapabilities
                )
            }
            .tabItem {
                Label("Plans", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                SettingsView(treadmill: treadmill)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
