import SwiftUI

struct RootTabView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel
    @ObservedObject var plans: PlansViewModel
    @StateObject private var credential: ImportCredentialStore
    @StateObject private var importer: WorkoutImportViewModel
    @Environment(\.scenePhase) private var scenePhase
    let workoutCapabilitiesOverride: WorkoutPlanCapabilities?

    init(
        treadmill: TreadmillSetupViewModel,
        plans: PlansViewModel,
        workoutCapabilitiesOverride: WorkoutPlanCapabilities? = nil
    ) {
        let credential: ImportCredentialStore
        let generator: any WorkoutImportGenerating
#if DEBUG
        if ImportUITestConfiguration.enabled {
            credential = ImportUITestConfiguration.credential()
            generator = ImportUITestConfiguration.generator()
        } else {
            credential = ImportCredentialStore()
            generator = OpenRouterImportAdapter(credential: credential)
        }
#else
        credential = ImportCredentialStore()
        generator = OpenRouterImportAdapter(credential: credential)
#endif
        _credential = StateObject(wrappedValue: credential)
        _importer = StateObject(wrappedValue: WorkoutImportViewModel(generator: generator, plans: plans))
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
                    capabilities: capabilities,
                    beginImport: { importer.begin(capabilities: capabilities) }
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
                SettingsView(treadmill: treadmill, credential: credential)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .sheet(isPresented: Binding(get: { importer.isPresented }, set: { if !$0 { importer.cancel() } })) {
            WorkoutImportView(model: importer, plans: plans)
        }
        .onChange(of: capabilities) { _, value in importer.updateCapabilities(value) }
        .onChange(of: scenePhase) { _, phase in
            importer.setForeground(phase == .active)
            if phase != .active { credential.protectedDataLost() }
        }
        .onAppear { importer.setProtectedDataAvailable(UIApplication.shared.isProtectedDataAvailable) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            importer.setProtectedDataAvailable(false)
            credential.protectedDataLost()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            importer.setProtectedDataAvailable(true)
        }
    }

    private var capabilities: WorkoutPlanCapabilities {
        workoutCapabilitiesOverride ?? treadmill.workoutPlanCapabilities
    }
}
