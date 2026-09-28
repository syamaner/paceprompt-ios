import Foundation
import HealthKit

@MainActor final class PhoneWatchSessionAdapter: NSObject, PhoneWatchPort, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private var mirror: HKWorkoutSession?
    weak var lifecycle: PhoneWatchLifecycle?
    override init() {
        super.init()
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                guard let self, self.mirror == nil, self.lifecycle?.phase == .binding else { return }
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
        mirror.sendToRemoteWorkoutSession(data: data) { _, _ in /* Transport completion is not an application ack. */ }
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
