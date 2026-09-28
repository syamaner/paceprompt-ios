import Foundation
import HealthKit

@MainActor final class WatchHealthKitAdapter: NSObject, WatchSessionOperations, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var source: HKLiveWorkoutDataSource?
    private var generation: UInt64 = 0
    private var stopVerified = false
    private let stopVerifier = WatchStopVerifier()
    private var startWaiter: CheckedContinuation<Date, Error>?
    private var pauseWaiter: CheckedContinuation<Date, Error>?
    private var resumeWaiter: CheckedContinuation<Void, Error>?
    private var endedSession: HKWorkoutSession?
    private(set) var ended = false
    private var discarded = false
    private var finishAttempted = false
    private(set) var collectionStarted = false
    private var preparedAssembly: WatchAssembly?
    var received: ((Data) async -> Void)?
    var paused: ((Bool) -> Void)?
    var disconnected: (() -> Void)?
    var failed: (() async -> Void)?
    var metrics: ((Double?, Double?, TimeInterval) -> Void)?

    private static let heart = HKQuantityType(.heartRate)
    private static let energy = HKQuantityType(.activeEnergyBurned)
    private static let distance = HKQuantityType(.distanceWalkingRunning)

    private func configuration(_ activity: String) -> HKWorkoutConfiguration {
        let c = HKWorkoutConfiguration(); c.activityType = activity == "indoorRunning" ? .running : .walking; c.locationType = .indoor; return c
    }
    private func configure(_ session: HKWorkoutSession) throws {
        let builder = session.associatedWorkoutBuilder()
        // Disable all unrelated automatic quantities before attaching the source.
        let source = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: session.workoutConfiguration)
        for type in source.typesToCollect where type != Self.heart && type != Self.energy { source.disableCollection(for: type) }
        source.disableCollection(for: Self.distance)
        guard !source.typesToCollect.contains(Self.distance) else { throw WatchStoreError.definite }
        self.session = session; self.builder = builder; self.source = source
        session.delegate = self; builder.delegate = self; builder.dataSource = source
        // Keep genuine pause/resume events. This setting is not an activity-suppression mechanism.
    }
    func resetForNewAttempt() throws {
        guard session == nil || session?.state == .ended || stopVerified else { throw WatchStoreError.ambiguous }
        generation &+= 1; stopVerified = false; stopVerifier.cancel()
        session?.delegate = nil; builder?.delegate = nil
        session = nil; builder = nil; source = nil; ended = false; discarded = false; finishAttempted = false; collectionStarted = false; preparedAssembly = nil
    }
    func authorize() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), Self.energy, Self.distance], read: [Self.heart, Self.energy])
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }
    func recoverPrimary() async throws -> WatchRecoveredRecording? {
        let token = generation
        let recovered = try await store.recoverActiveWorkoutSession()
        guard token == generation else { throw WatchStoreError.ambiguous }
        guard let primary = recovered else { return nil }
        session = primary; builder = primary.associatedWorkoutBuilder()
        guard let start = primary.startDate else { throw WatchStoreError.ambiguous }
        collectionStarted = true
        return .init(start: start, activity: primary.workoutConfiguration.activityType == .running ? "indoorRunning" : primary.workoutConfiguration.activityType == .walking ? "indoorWalking" : "unsupported",
                     indoor: primary.workoutConfiguration.locationType == .indoor)
    }
    func createPrimary(activity: String) throws {
        guard session == nil else { throw WatchStoreError.ambiguous }
        session = try HKWorkoutSession(healthStore: store, configuration: configuration(activity))
        builder = session!.associatedWorkoutBuilder()
    }
    func configureCollection() throws {
        guard let session else { throw WatchStoreError.ambiguous }; try configure(session)
    }
    func preparePrimary() { session?.prepare() }
    func mirrorPrimary() async throws { guard let session else { throw WatchStoreError.ambiguous }; try await session.startMirroringToCompanionDevice() }
    func startPrimary() async throws -> Date {
        guard let session, !collectionStarted, startWaiter == nil else { throw WatchStoreError.ambiguous }
        return try await withCheckedThrowingContinuation { continuation in
            startWaiter = continuation; session.startActivity(with: Date())
        }
    }
    func beginCollection(at date: Date) async throws {
        guard let builder, !ended else { throw WatchStoreError.ambiguous }
        collectionStarted = true; try await builder.beginCollection(at: date)
    }
    func pausePrimary() async throws -> Date {
        guard let session, !ended else { throw WatchStoreError.ambiguous }
        if session.state == .paused { return Date() }
        guard session.state == .running, pauseWaiter == nil else { throw WatchStoreError.ambiguous }
        return try await withCheckedThrowingContinuation { continuation in pauseWaiter = continuation; session.pause() }
    }
    func resumePrimary() async throws {
        guard let session, !ended else { throw WatchStoreError.ambiguous }
        if session.state == .running { return }
        guard session.state == .paused, resumeWaiter == nil else { throw WatchStoreError.ambiguous }
        try await withCheckedThrowingContinuation { continuation in resumeWaiter = continuation; session.resume() }
    }
    func endPrimary() {
        generation &+= 1; stopVerified = false
        stopVerifier.cancel()
        if ended, session == nil || WatchCallbackIdentity.accepts(session!, current: endedSession) { return }
        ended = true; endedSession = session; session?.end()
        startWaiter?.resume(throwing: WatchStoreError.ambiguous); startWaiter = nil
        pauseWaiter?.resume(throwing: WatchStoreError.ambiguous); pauseWaiter = nil
        resumeWaiter?.resume(throwing: WatchStoreError.ambiguous); resumeWaiter = nil
    }
    func stopPrimaryAndVerify() async throws {
        endPrimary()
        let token = generation
        try await stopVerifier.verify(probe: { [store] in
            try await store.recoverActiveWorkoutSession()
        }, isEnded: { ($0 as? HKWorkoutSession)?.state == .ended }, end: { [self] object in
            guard let active = object as? HKWorkoutSession else { return }
            session = active; active.delegate = self
            ended = true; endedSession = active; active.end()
        })
        guard token == generation else { throw WatchStoreError.ambiguous }
        stopVerified = true
    }
    func discardBuilder() throws {
        guard !finishAttempted, !discarded else { throw WatchStoreError.ambiguous }
        guard let builder else { throw WatchStoreError.ambiguous }
        discarded = true; builder.discardWorkout()
    }
    var sourceExcludesDistance: Bool { source?.typesToCollect.contains(Self.distance) == false }
    var hasDistance: Bool { builder?.statistics(for: Self.distance) != nil }
    var distanceAuthorized: Bool { store.authorizationStatus(for: Self.distance) == .sharingAuthorized }
    var activities: [WatchBuilderActivity] {
        builder?.workoutActivities.map { .init(start: $0.startDate, end: $0.endDate,
            activity: $0.workoutConfiguration.activityType == .walking ? "indoorWalking" : $0.workoutConfiguration.activityType == .running ? "indoorRunning" : "unsupported",
            indoor: $0.workoutConfiguration.locationType == .indoor) } ?? []
    }
    func endCollection(at date: Date) async throws {
        guard let builder else { throw WatchStoreError.ambiguous }; try await builder.endCollection(at: date)
    }
    func addActivity(_ interval: WatchInterval, summaryID: String, activity: String) async throws {
        guard let builder else { throw WatchStoreError.ambiguous }
        let value = HKWorkoutActivity(workoutConfiguration: configuration(activity), start: interval.startedAt, end: interval.endedAt,
                                      metadata: WatchHealthMetadata.interval(interval, summaryID: summaryID))
        try await builder.addWorkoutActivity(value)
    }
    func addDistance(metres: Decimal, summaryID: String, start: Date, end: Date) async throws {
        guard let builder else { throw WatchStoreError.ambiguous }
        let sample = HKQuantitySample(type: Self.distance, quantity: HKQuantity(unit: .meter(), doubleValue: NSDecimalNumber(decimal: metres).doubleValue),
                                      start: start, end: end, metadata: [HKMetadataKeySyncIdentifier: Self.namespace + "distance." + summaryID, HKMetadataKeySyncVersion: 1])
        try await builder.addSamples([sample])
    }
    func addMetadata(_ value: WatchAssembly, distanceIncluded: Bool) async throws {
        guard let builder else { throw WatchStoreError.ambiguous }
        let n = Self.namespace
        let metadata: [String: Any] = [n+"interchangeSchemaVersion": 1, n+"summaryID": value.summaryID, n+"ownership": "watchPrimary",
                                      n+"interchangeStatus": value.complete ? "complete" : "incomplete", n+"manifestRevision": NSNumber(value: value.revision),
                                      n+"intervalCount": value.intervals.count, n+"distanceProvenance": distanceIncluded ? "fr30zCumulativeDistanceDelta" : "unavailable",
                                      HKMetadataKeyIndoorWorkout: true, HKMetadataKeySyncIdentifier: n+"workout."+value.summaryID, HKMetadataKeySyncVersion: 1]
        try await builder.addMetadata(metadata)
    }
    func finishBuilder() async throws -> String? {
        guard let builder, !finishAttempted, !discarded else { throw WatchStoreError.ambiguous }
        finishAttempted = true
        guard let workout = try await builder.finishWorkout() else { throw WatchStoreError.ambiguous }
        return workout.uuid.uuidString.lowercased()
    }
    func send(_ data: Data) {
        guard !ended else { return }
        guard let session else { return }
        session.sendToRemoteWorkoutSession(data: data) { [weak self, weak session] success, _ in
            guard !success else { return }
            Task { @MainActor in
                guard let self, let session, WatchCallbackIdentity.accepts(session, current: self.session), !self.ended else { return }
                self.disconnected?()
            }
        }
    }
    func publishMetrics() {
        guard let builder, collectionStarted, !ended else { return }
        let heart = builder.statistics(for: Self.heart)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let energy = builder.statistics(for: Self.energy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        metrics?(heart.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }, energy.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }, builder.elapsedTime)
    }
    private static let namespace = "com.otherweather.PromptPace."
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, WatchCallbackIdentity.accepts(workoutSession, current: self.session) else { return }
            if toState == .running {
                self.startWaiter?.resume(returning: date); self.startWaiter = nil
                self.resumeWaiter?.resume(); self.resumeWaiter = nil; self.paused?(false)
            } else if toState == .paused {
                self.pauseWaiter?.resume(returning: date); self.pauseWaiter = nil; self.paused?(true)
            } else if toState == .ended {
                self.stopVerifier.observedEnded(workoutSession)
                if !self.ended { await self.failed?() }
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, WatchCallbackIdentity.accepts(workoutSession, current: self.session) else { return }
            self.endPrimary(); await self.failed?()
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for item in data { guard WatchCallbackIdentity.accepts(workoutSession, current: self.session) else { return }; await self.received?(item) }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, WatchCallbackIdentity.accepts(workoutSession, current: self.session) else { return }; self.disconnected?()
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { Task { @MainActor [weak self] in
        guard let self, WatchCallbackIdentity.accepts(workoutBuilder, current: self.builder) else { return }; self.publishMetrics()
    } }
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) { Task { @MainActor [weak self] in
        guard let self, WatchCallbackIdentity.accepts(workoutBuilder, current: self.builder) else { return }; self.publishMetrics()
    } }
}
