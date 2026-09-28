import SwiftUI
import WatchKit
import HealthKit

@MainActor final class WatchWorkoutModel: ObservableObject {
    static let shared = WatchWorkoutModel()
    @Published var status = "Start a Watch-assisted workout on iPhone."
    @Published var heartRate: Double?
    @Published var activeEnergy: Double?
    @Published var elapsed: TimeInterval = 0
    @Published var canEnd = false
    let adapter = WatchHealthKitAdapter()
    lazy var recording = WatchRecordingAdapter(operations: adapter)
    lazy var lifecycle = WatchWorkoutLifecycle(store: ProtectedWatchJournal(), recording: recording,
        now: Date.init, monotonic: { ProcessInfo.processInfo.systemUptime }, send: { [weak self] in self?.adapter.send($0) })
    private var timer: Timer?
    init() {
        adapter.received = { [weak self] in await self?.lifecycle.receive($0) }
        adapter.paused = { [weak self] in self?.lifecycle.recordingState(paused: $0) }
        adapter.disconnected = { [weak self] in self?.lifecycle.disconnected() }
        adapter.failed = { [weak self] in await self?.lifecycle.failed() }
        adapter.metrics = { [weak self] heart, energy, time in self?.heartRate = heart; self?.activeEnergy = energy; self?.elapsed = time }
        lifecycle.changed = { [weak self] in
            guard let self else { return }; self.status = self.lifecycle.display; self.canEnd = self.lifecycle.canEnd
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.lifecycle.tick(); self?.adapter.publishMetrics() }
        }
    }
    func launch(_ configuration: HKWorkoutConfiguration) async {
        guard configuration.locationType == .indoor, [.walking, .running].contains(configuration.activityType) else { return }
        await lifecycle.launch(activity: configuration.activityType == .running ? "indoorRunning" : "indoorWalking")
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await WatchWorkoutModel.shared.launch(workoutConfiguration) }
    }
    func handleActiveWorkoutRecovery() { Task { @MainActor in await WatchWorkoutModel.shared.lifecycle.recover() } }
}

@main struct PacePromptWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var delegate
    @StateObject private var model = WatchWorkoutModel.shared
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 12) {
                    Text("PacePrompt").font(.headline)
                    Text(model.status).accessibilityIdentifier("watch-recording-state")
                    Text(Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit().accessibilityLabel("Recording elapsed time")
                    Text(model.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "Heart rate unavailable")
                    Text(model.activeEnergy.map { "\(Int($0.rounded())) kcal estimated" } ?? "Active energy unavailable")
                    Text("Active energy is calculated by HealthKit.").font(.caption2)
                    if model.canEnd {
                        Button("End recording", role: .destructive) { Task { await model.lifecycle.endWorkout() } }
                        Text("This does not stop the treadmill. Use its console and safety key.").font(.caption2)
                    }
                }.padding()
            }
            .task { await model.lifecycle.recover() }
        }
    }
}
