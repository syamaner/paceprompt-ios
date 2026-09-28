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
    @Published var canStop = false
    @Published var canPrepareNext = false
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
            self.canStop = self.lifecycle.canStop; self.canPrepareNext = self.lifecycle.canPrepareNext
        }
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.lifecycle.tick(); self?.adapter.publishMetrics() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func launch(_ configuration: HKWorkoutConfiguration) async {
        guard configuration.locationType == .indoor, [.walking, .running].contains(configuration.activityType) else { return }
        if lifecycle.journal == nil || [.saved, .discarded, .retired].contains(lifecycle.journal?.phase) {
            heartRate = nil; activeEnergy = nil; elapsed = 0
        }
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmStop = false
    @State private var confirmNext = false
    @StateObject private var model = WatchWorkoutModel.shared
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 12) {
                    Text("PacePrompt").font(.headline)
                    Text(model.status).accessibilityIdentifier("watch-recording-state")
                    if model.canEnd {
                        Button("End recording & save") { Task { await model.lifecycle.endWorkout() } }
                            .accessibilityIdentifier("watch-end-recording")
                    }
                    if model.canStop {
                        Button("Stop recording", role: .destructive) { confirmStop = true }
                            .accessibilityIdentifier("watch-stop-recording")
                    }
                    if model.canPrepareNext {
                        Button("Prepare next workout") { confirmNext = true }
                            .accessibilityIdentifier("watch-prepare-next")
                    }
                    if model.canEnd || model.canStop || model.canPrepareNext {
                        Text("Recording controls only. Stop the treadmill at its console.").font(.caption2)
                    }
                    Text(Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit().accessibilityLabel("Recording elapsed time")
                    Text(model.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "Heart rate unavailable")
                    Text(model.activeEnergy.map { "\(Int($0.rounded())) kcal estimated" } ?? "Active energy unavailable")
                    Text("Active energy is calculated by HealthKit.").font(.caption2)

                }.padding()
            }
            .task { await model.lifecycle.foreground() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.lifecycle.foreground(); model.adapter.publishMetrics() } }
            }
            .confirmationDialog("Stop Watch recording?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop recording", role: .destructive) { Task { await model.lifecycle.forceStop() } }
            } message: {
                Text("Stops Health recording only. A save already in progress may still complete. The treadmill keeps moving until you stop it at its console.")
            }
            .confirmationDialog("Prepare a new workout?", isPresented: $confirmNext, titleVisibility: .visible) {
                Button("Keep previous outcome and continue") { model.lifecycle.prepareNextWorkout() }
            } message: {
                Text("The previous save result stays uncertain and is retained. Check Health for it. This will not retry or replace that workout.")
            }
        }
    }
}
