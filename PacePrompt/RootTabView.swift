import SwiftUI

struct RootTabView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(treadmill: treadmill)
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                PlansView()
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
