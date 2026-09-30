import SwiftUI
import Combine

struct RootTabView: View {
    private enum Tab: Hashable {
        case home
        case plans
        case history
        case settings
    }

    @ObservedObject var treadmill: TreadmillSetupViewModel
    @ObservedObject var plans: PlansViewModel
    @ObservedObject var workoutSession: WorkoutSessionCoordinator
    @StateObject private var credential: ImportCredentialStore
    @StateObject private var importer: WorkoutImportViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .home
    @State private var pendingPlanEdit: SavedPlanRecord?
    let workoutCapabilitiesOverride: WorkoutPlanCapabilities?

    init(
        treadmill: TreadmillSetupViewModel,
        plans: PlansViewModel,
        workoutSession: WorkoutSessionCoordinator,
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
        self.workoutSession = workoutSession
        self.workoutCapabilitiesOverride = workoutCapabilitiesOverride
        plans.configureHistoricalSelection { [weak profiles = treadmill.planningProfiles] reload in
            profiles?.historicalSelection(reload: reload) ?? .none
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(treadmill: treadmill)
            }
            .tag(Tab.home)
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                PlansView(
                    viewModel: plans,
                    capabilities: capabilities,
                    profiles: treadmill.planningProfiles,
                    beginImport: { importer.begin(capabilities: capabilities) },
                    beginWorkout: workoutSession.begin
                )
            }
            .tag(Tab.plans)
            .tabItem {
                Label("Plans", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                HistoryView()
            }
            .tag(Tab.history)
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                SettingsView(treadmill: treadmill, credential: credential)
            }
            .tag(Tab.settings)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .sheet(isPresented: Binding(get: { importer.isPresented }, set: { if !$0 { importer.cancel() } })) {
            WorkoutImportView(model: importer, plans: plans, profiles: treadmill.planningProfiles)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { workoutSession.isPresented },
                set: { if !$0 { workoutSession.cancelBeforeExercise() } }
            ),
            onDismiss: {
                if let record = pendingPlanEdit { plans.beginEdit(record); pendingPlanEdit = nil }
            }
        ) {
            WorkoutSessionHost(
                treadmill: treadmill,
                coordinator: workoutSession,
                showHistory: { selectedTab = .history },
                editPlan: { record in pendingPlanEdit = record; selectedTab = .plans }
            )
        }
        .onReceive(treadmill.planningProfiles?.objectWillChange.eraseToAnyPublisher() ?? Empty<Void, Never>().eraseToAnyPublisher()) { _ in
            Task { @MainActor in plans.refreshHistoricalReview() }
        }
        .onChange(of: capabilities) { _, value in importer.updateCapabilities(value) }
        .onChange(of: scenePhase) { _, phase in
            importer.setForeground(phase == .active)
            treadmill.setApplicationActivity(captureActivity(for: phase))
            if phase == .active { workoutSession.applicationBecameActive() }
            if phase != .active { credential.protectedDataLost() }
        }
        .onAppear {
            let protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
            importer.setProtectedDataAvailable(protectedDataAvailable)
            treadmill.setProtectedDataAvailable(protectedDataAvailable)
            treadmill.setApplicationActivity(captureActivity(for: scenePhase))
            #if DEBUG
            treadmill.activateUITestScenarioIfNeeded()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            importer.setProtectedDataAvailable(false)
            treadmill.setProtectedDataAvailable(false)
            credential.protectedDataLost()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            importer.setProtectedDataAvailable(true)
            treadmill.setProtectedDataAvailable(true)
            if scenePhase == .active { workoutSession.applicationBecameActive() }
        }
    }

    private var capabilities: WorkoutPlanCapabilities {
        workoutCapabilitiesOverride ?? treadmill.workoutPlanCapabilities
    }

    private func captureActivity(for phase: ScenePhase) -> FTMSApplicationActivity {
        switch phase {
        case .active: .active
        case .inactive: .inactive
        case .background: .background
        @unknown default: .unknown
        }
    }
}
