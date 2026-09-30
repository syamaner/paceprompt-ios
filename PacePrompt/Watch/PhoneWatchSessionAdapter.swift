import Foundation
import HealthKit

@MainActor final class PhoneWatchSessionAdapter: NSObject, PhoneWatchPort, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private var mirror: HKWorkoutSession?
    private var timer: Timer?
    weak var lifecycle: PhoneWatchLifecycle? {
        didSet {
            if oldValue !== lifecycle { mirror?.delegate = nil; mirror = nil }
        }
    }
    override init() {
        super.init()
        // Finish handoff retries must survive dismissal of the workout screen.
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.lifecycle?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                guard let self, let lifecycle = self.lifecycle else { return }
                let activity = session.workoutConfiguration.activityType == .running ? "indoorRunning" : session.workoutConfiguration.activityType == .walking ? "indoorWalking" : "unsupported"
                guard lifecycle.acceptsMirror(activity: activity, indoor: session.workoutConfiguration.locationType == .indoor, start: session.startDate) else { return }
                if self.mirror === session { return }
                self.mirror?.delegate = nil
                self.mirror = session; session.delegate = self; self.lifecycle?.mirrorConnected()
            }
        }
    }
    func launch(activity: String) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity == "indoorRunning" ? .running : .walking
        configuration.locationType = .indoor
        try await healthStore.startWatchApp(toHandle: configuration)
    }
    func send(_ data: Data) {
        guard let mirror else { return }
        mirror.sendToRemoteWorkoutSession(data: data) { [weak self, weak mirror] success, _ in
            guard !success else { return } // Success is still not an application ack.
            Task { @MainActor in
                guard let self, let mirror, WatchCallbackIdentity.accepts(mirror, current: self.mirror) else { return }
                self.lifecycle?.disconnect()
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended { Task { @MainActor [weak self] in
            guard let self, WatchCallbackIdentity.accepts(workoutSession, current: self.mirror) else { return }; self.mirror = nil; self.lifecycle?.primaryEnded()
        } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, WatchCallbackIdentity.accepts(workoutSession, current: self.mirror) else { return }; self.mirror = nil; self.lifecycle?.disconnect()
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor [weak self] in
            guard let self, WatchCallbackIdentity.accepts(workoutSession, current: self.mirror) else { return }; for message in data { self.lifecycle?.receive(message) }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, WatchCallbackIdentity.accepts(workoutSession, current: self.mirror) else { return }; self.mirror = nil; self.lifecycle?.disconnect()
        }
    }
}
