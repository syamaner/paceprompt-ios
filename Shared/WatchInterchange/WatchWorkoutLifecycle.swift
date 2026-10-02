import Foundation

struct WatchWorkoutJournal: Codable, Equatable {
    enum Phase: String, Codable { case creating, unbound, starting, recording, assembling, finishing, saved, discarded, ambiguous, retired }
    var formatVersion: Int
    let activity: String
    var attemptID: String?
    var phase: Phase
    var summaryID: String?
    var startedAt: Date?
    var manifest: WatchWireMessage?
    var incomplete = false
    var confirmed = false
    var lastSequence: Int64 = 0
    var prepareSequence: Int64?
    var preparedEnd: Date?
    var savedWorkoutID: String?
    var sourceExclusionEstablished = false
    var paused = false
    var failedSaveStage: WatchSaveStage?
    init(activity: String, attemptID: String? = nil) { formatVersion = 2; self.activity = activity; self.attemptID = attemptID; phase = .creating }
}

struct WatchAssembly: Equatable {
    let summaryID: String
    let activity: String
    let start: Date
    let end: Date
    let intervals: [WatchInterval]
    let revision: Int64
    let complete: Bool
    let distance: WatchDistance
}

enum WatchSaveStage: String, Codable { case stopActivity, assemblyValidation, endCollection, activities, distance, metadata, finish, receiptPersistence }

enum WatchStoreError: Error { case definite, ambiguous }

@MainActor protocol WatchJournalStore {
    func load() throws -> WatchWorkoutJournal?
    func save(_ journal: WatchWorkoutJournal) throws
    func containsRetiredIdentity(_ summaryID: String) throws -> Bool
    func archive(_ journal: WatchWorkoutJournal) throws
}

// This port deliberately has no treadmill, History or phone Health-save operations.
@MainActor protocol WatchRecordingPort: AnyObject {
    var finalizationStage: WatchSaveStage? { get }
    func cancelSavedCleanup()
    func cleanupSaved(activity: String, start: Date) async throws
    func completeSaved()
    func prepare(activity: String) async throws
    func recover(activity: String) async throws -> (start: Date, sourceExclusion: Bool)
    func begin() async throws -> Date
    func pause() async throws -> Date
    func resume() async throws
    func end()
    func discard() throws
    func assemble(_ value: WatchAssembly) async throws
    func finish() async throws -> String
    func stopAndVerify() async throws
    func releaseStopped() throws
}

@MainActor final class WatchWorkoutLifecycle {
    private let store: any WatchJournalStore
    private let recording: any WatchRecordingPort
    private let now: () -> Date
    private let monotonic: () -> TimeInterval
    private let send: (Data) -> Void
    private let makeID: () -> UUID
    private var generation: UInt64 = 0
    private var recoveryGeneration: UInt64?
    private var operationDeadline: TimeInterval?
    private(set) var stopping = false
    private(set) var stopVerified = false
    private var recoveryRequired = false
    private var savedCleanupVerified = false
    private var budget = WatchSendBudget()
    private var startupDeadline: TimeInterval?
    private var recordingAttached = false
    private var pauseInFlight = false
    private var resumeInFlight = false
    private var desiredRecordingState: String?
    var canEnd: Bool { !stopping && recordingAttached && journal?.prepareSequence == nil && [.unbound, .recording].contains(journal?.phase) }
    var canStop: Bool { !stopping && !stopVerified && (recoveryRequired || journal.map { ![.saved, .discarded, .retired].contains($0.phase) } == true) }
    var canPrepareNext: Bool { !stopping && stopVerified && journal != nil }
    private var pendingBind: WatchWireMessage?
    private var endDeadline: TimeInterval?
    private(set) var journal: WatchWorkoutJournal?
    private(set) var display = "Start a Watch-assisted workout on iPhone."
    var changed: (() -> Void)?

    init(store: any WatchJournalStore, recording: any WatchRecordingPort,
         now: @escaping () -> Date, monotonic: @escaping () -> TimeInterval, send: @escaping (Data) -> Void, makeID: @escaping () -> UUID = UUID.init) {
        self.store = store; self.recording = recording; self.now = now; self.monotonic = monotonic; self.send = send; self.makeID = makeID
    }
    private func persist(_ value: WatchWorkoutJournal) -> Bool {
        do { try store.save(value); journal = value; changed?(); return true }
        catch {
            recoveryRequired = true; journal = value; journal?.phase = .ambiguous
            display = "Save result uncertain. No replacement workout will be created."; changed?(); return false
        }
    }
    func launch(activity: String) async {
        guard recoveryGeneration == nil, journal == nil || [.saved, .discarded, .retired].contains(journal!.phase), ["indoorWalking", "indoorRunning"].contains(activity) else { return }
        do {
            if let previous = try store.load() {
                journal = previous
                guard [.saved, .discarded, .retired].contains(previous.phase) else {
                    await recoverLoaded(previous); return
                }
                if previous.phase == .saved, !savedCleanupVerified {
                    guard await cleanUpSaved(previous) else { return }
                }
            }
        } catch { display = "Protected workout state is unavailable."; changed?(); return }
        generation &+= 1; let token = generation
        savedCleanupVerified = false
        stopVerified = false; stopping = false; recoveryRequired = false; operationDeadline = nil
        budget = WatchSendBudget(); pendingBind = nil; endDeadline = nil; recordingAttached = false; pauseInFlight = false; resumeInFlight = false; desiredRecordingState = nil
        let value = WatchWorkoutJournal(activity: activity, attemptID: makeID().uuidString.lowercased())
        guard persist(value) else { return }
        startupDeadline = monotonic() + 30
        display = "Connecting to iPhone…"; changed?()
        do {
            try await recording.prepare(activity: activity)
            guard acceptCompletion(token) else { return }
            guard var current = journal, current.phase == .creating else { recording.end(); return }
            recordingAttached = true
            current.phase = .unbound
            guard persist(current) else { recording.end(); return }
            if let message = pendingBind { pendingBind = nil; await bind(message) }
        } catch { if acceptCompletion(token) { failBeforeFinish(error) } }
    }
    func recover() async {
        guard journal == nil else { return }
        do { if let value = try store.load() { await recoverLoaded(value) } }
        catch { quarantine() }
    }
    private func recoverLoaded(_ original: WatchWorkoutJournal) async {
        let value = original; journal = value
        guard [1, 2].contains(value.formatVersion) else { quarantine(); return }
        if value.phase == .retired { display = "Ready. Start a new workout on iPhone."; changed?(); return }
        if value.phase == .saved { _ = await cleanUpSaved(value); return }
        if value.phase == .discarded {
            display = emptyDiscardDisplay
            changed?(); return
        }
        generation &+= 1; let token = generation
        recoveryGeneration = token
        defer { if recoveryGeneration == token { recoveryGeneration = nil } }
        operationDeadline = monotonic() + 15
        display = "Checking previous Watch recording…"; changed?()
        do {
            guard value.phase == .recording, value.summaryID != nil, let start = value.startedAt,
                  value.sourceExclusionEstablished else { throw WatchStoreError.ambiguous }
            let recovered = try await recording.recover(activity: value.activity)
            guard acceptCompletion(token) else { return }; operationDeadline = nil
            recordingAttached = true
            guard WatchWire.timestamp(recovered.start) == start, recovered.sourceExclusion else { throw WatchStoreError.ambiguous }
            // Native callbacks may have persisted pause/disconnection state while
            // recovery was suspended. Never replace it with the pre-await snapshot.
            guard var current = journal, current.phase == .recording,
                  current.summaryID == value.summaryID, current.startedAt == start else { throw WatchStoreError.ambiguous }
            current.incomplete = current.incomplete || !current.confirmed
            guard persist(current) else { recording.end(); return }
            recoveryGeneration = nil
            display = "Recovered recording. End on Watch when finished."; changed?()
            if current.prepareSequence != nil || current.confirmed { await endWorkout() }
        } catch { guard acceptCompletion(token) else { return }; operationDeadline = nil; quarantine(); recording.end(); recordingAttached = false; changed?() }
    }
    private func cleanUpSaved(_ value: WatchWorkoutJournal) async -> Bool {
        guard recoveryGeneration == nil, let start = value.startedAt, value.savedWorkoutID != nil else {
            display = "Workout saved. Previous recording could not be checked."; changed?(); return false
        }
        generation &+= 1; let token = generation
        recoveryGeneration = token; operationDeadline = monotonic() + 15
        defer { if recoveryGeneration == token { recoveryGeneration = nil } }
        display = "Workout saved. Closing previous recording…"; changed?()
        do {
            try await recording.cleanupSaved(activity: value.activity, start: start)
            guard acceptCompletion(token) else { return false }
            operationDeadline = nil; savedCleanupVerified = true
            display = "Workout saved on Apple Watch."; changed?(); return true
        } catch {
            guard acceptCompletion(token) else { return false }
            operationDeadline = nil
            display = "Workout saved. Previous recording could not be closed. Reopen the Watch app to try again."; changed?(); return false
        }
    }
    func receive(_ data: Data) async {
        await tick()
        guard recoveryGeneration == nil else { return }
        guard let current = journal, [.creating, .unbound, .starting, .recording].contains(current.phase) else { return }
        let message: WatchWireMessage
        do { message = try WatchWire.decode(data) }
        catch { latchIncomplete(); return }
        if message.kind == .bind {
            if current.phase == .creating {
                if pendingBind == nil { pendingBind = message } else if pendingBind != message { latchIncomplete() }
            } else { await bind(message) }
            return
        }
        guard current.summaryID == message.summaryID else { latchIncomplete(); return }
        guard current.phase == .recording else { latchIncomplete(); return }
        switch message.kind {
        case .manifest: applyManifest(message)
        case .recordingState:
            guard current.prepareSequence == nil, let seq = message.sequence, seq > current.lastSequence else { return }
            var value = current; value.lastSequence = seq
            guard persist(value) else { return }
            desiredRecordingState = message.state
            await reconcileRecordingRequest()
        case .prepareEnd: await prepareEnd(message)
        case .finalize:
            guard let m = current.manifest, m.final == true, message.revision == m.revision,
                  current.preparedEnd == m.workoutEnd, current.prepareSequence != nil else { latchIncomplete(); return }
            var value = current; value.confirmed = true
            guard persist(value) else { return }
            await endWorkout()
        case .bind, .bound, .ack, .endPrepared: latchIncomplete()
        }
    }
    private func bind(_ m: WatchWireMessage) async {
        guard var value = journal, m.workoutActivity == value.activity else { latchIncomplete(); return }
        if let id = value.summaryID {
            guard id == m.summaryID else { latchIncomplete(); return }
            if value.phase == .recording, let date = value.startedAt {
                var response = WatchWireMessage(.bound, summaryID: id); response.workoutStart = date; transmit(response)
            }
            return
        }
        guard value.phase == .unbound else { return }
        do {
            guard try !store.containsRetiredIdentity(m.summaryID) else { latchIncomplete(); return }
        } catch { quarantine(); recording.end(); return }
        value.summaryID = m.summaryID; value.phase = .starting
        guard persist(value) else { recording.end(); return }
        let token = generation
        do {
            let start = try await recording.begin()
            guard acceptCompletion(token) else { return }
            guard var current = journal, current.phase == .starting else { recording.end(); return }
            current.startedAt = WatchWire.timestamp(start); current.phase = .recording; current.sourceExclusionEstablished = true
            guard persist(current) else { recording.end(); return }
            startupDeadline = nil; display = "Recording on Apple Watch"; changed?()
            var response = WatchWireMessage(.bound, summaryID: m.summaryID); response.workoutStart = current.startedAt; transmit(response)
        } catch { if acceptCompletion(token) { failBeforeFinish(error) } }
    }
    private func applyManifest(_ m: WatchWireMessage) {
        guard var value = journal, m.workoutStart == value.startedAt, m.workoutActivity == value.activity else { latchIncomplete(); return }
        if let old = value.manifest {
            if m.revision! < old.revision! { acknowledge(); return }
            if m.revision == old.revision {
                if m != old { latchIncomplete() }; acknowledge(); return
            }
            guard old.final != true, m.intervals!.starts(with: old.intervals!) else { latchIncomplete(); return }
        }
        if m.final == true {
            guard value.prepareSequence != nil, m.workoutEnd == value.preparedEnd else { latchIncomplete(); return }
        }
        value.manifest = m
        guard persist(value) else { return }
        acknowledge()
    }
    private func acknowledge() {
        guard let value = journal, let id = value.summaryID else { return }
        var m = WatchWireMessage(.ack, summaryID: id); m.revision = value.manifest?.revision ?? 0; transmit(m)
    }
    private func prepareEnd(_ m: WatchWireMessage) async {
        guard var value = journal, let seq = m.sequence else { return }
        if let existing = value.prepareSequence {
            if existing == seq { sendPrepared() }; return
        }
        guard seq > value.lastSequence else { return }
        value.lastSequence = seq; value.prepareSequence = seq
        endDeadline = monotonic() + 5
        display = "Ending workout…"
        desiredRecordingState = nil
        guard persist(value) else { recording.end(); return }
        if pauseInFlight || resumeInFlight { return } // Complete the pending transition before establishing the end boundary.
        await establishPreparedEnd(sequence: seq)
    }
    private func establishPreparedEnd(sequence seq: Int64) async {
        guard let value = journal, value.phase == .recording, value.preparedEnd == nil else { return }
        let token = generation
        do {
            pauseInFlight = !value.paused
            let end = value.paused ? now() : try await recording.pause()
            guard acceptCompletion(token) else { return }
            pauseInFlight = false
            guard var current = journal, current.phase == .recording, current.prepareSequence == seq else { return }
            current.preparedEnd = WatchWire.timestamp(end); current.paused = true
            guard persist(current) else { return }; sendPrepared()
        } catch { if acceptCompletion(token) { pauseInFlight = false; latchIncomplete() } }
    }
    private func reconcileRecordingRequest() async {
        guard !pauseInFlight, !resumeInFlight, var value = journal, value.phase == .recording,
              value.prepareSequence == nil, let desired = desiredRecordingState else { return }
        if (desired == "paused") == value.paused { desiredRecordingState = nil; return }
        let token = generation
        if desired == "running" {
            resumeInFlight = true
            do {
                try await recording.resume(); guard acceptCompletion(token) else { return }; resumeInFlight = false
                guard var current = journal, current.phase == .recording else { return }
                current.paused = false
                guard persist(current) else { return }
                if let sequence = current.prepareSequence { await establishPreparedEnd(sequence: sequence) }
                else {
                    if desiredRecordingState == "running" { desiredRecordingState = nil }
                    await reconcileRecordingRequest()
                }
            } catch { if acceptCompletion(token) { resumeInFlight = false; latchIncomplete() } }
            return
        }
        pauseInFlight = true
        do {
            let date = try await recording.pause()
            guard acceptCompletion(token) else { return }
            pauseInFlight = false
            guard let current = journal, current.phase == .recording else { return }
            value = current; value.paused = true
            if value.prepareSequence != nil, value.preparedEnd == nil { value.preparedEnd = WatchWire.timestamp(date) }
            guard persist(value) else { return }
            if value.prepareSequence != nil { sendPrepared() }
            else {
                if desiredRecordingState == "paused" { desiredRecordingState = nil }
                await reconcileRecordingRequest()
            }
        } catch { if acceptCompletion(token) { pauseInFlight = false; latchIncomplete() } }
    }
    private func sendPrepared() {
        guard let value = journal, let id = value.summaryID, let seq = value.prepareSequence, let end = value.preparedEnd else { return }
        var m = WatchWireMessage(.endPrepared, summaryID: id); m.sequence = seq; m.workoutEnd = end; transmit(m)
    }
    func recordingState(paused: Bool) {
        guard !stopping, !stopVerified, var value = journal, value.phase == .recording else { return }
        value.paused = paused
        if value.prepareSequence == nil { display = paused ? "Recording paused on Apple Watch." : "Recording on Apple Watch" }
        _ = persist(value)
    }
    func disconnected() {
        guard let phase = journal?.phase, [.creating, .unbound, .starting, .recording].contains(phase) else { return }
        if journal?.confirmed != true { latchIncomplete() }
        guard journal?.phase != .ambiguous else { return }
        display = phase == .recording ? "iPhone disconnected. Recording continues until you end it." : "iPhone disconnected. Recording start is unavailable or uncertain."
        changed?()
    }
    func failed() async {
        // A late native failure must not cancel stop proof, overwrite a receipt,
        // or re-enter an already-running save.
        guard !stopping, !stopVerified, let phase = journal?.phase,
              [.creating, .unbound, .starting, .recording].contains(phase) else { return }
        latchIncomplete(); await endWorkout()
    }
    func foreground() async {
        if let value = journal, value.phase == .saved, !savedCleanupVerified, recoveryGeneration == nil {
            _ = await cleanUpSaved(value)
        } else { await recover() }
        await tick()
        if recoveryGeneration == nil, let value = journal, value.phase == .recording, let id = value.summaryID, let start = value.startedAt {
            var response = WatchWireMessage(.bound, summaryID: id); response.workoutStart = start; transmit(response)
            acknowledge()
        }
    }
    func forceStop() async {
        guard canStop else { return }
        generation &+= 1; let token = generation
        recoveryGeneration = nil
        stopping = true; stopVerified = false
        startupDeadline = nil; endDeadline = nil; operationDeadline = monotonic() + 15
        pendingBind = nil; pauseInFlight = false; resumeInFlight = false; desiredRecordingState = nil
        quarantine(); recording.end(); recordingAttached = false
        display = "Stopping Watch recording…"; changed?()
        do {
            try await recording.stopAndVerify()
            guard acceptCompletion(token) else { return }
            stopping = false; stopVerified = true; operationDeadline = nil
            display = saveOutcomeIsUncertain ? "Recording stopped. Previous save result remains uncertain. Check Health before preparing a new workout." : "Recording stopped. Workout was not saved. You can prepare your next workout."
        } catch {
            guard acceptCompletion(token) else { return }
            stopping = false; operationDeadline = nil
            display = "Stop could not be verified. Try Stop recording again."
        }
        changed?()
    }
    func prepareNextWorkout() {
        guard canPrepareNext, var value = journal else { return }
        do {
            try store.archive(value)
            try recording.releaseStopped()
            value.formatVersion = 2; value.phase = .retired
            try store.save(value)
            generation &+= 1; journal = value; stopVerified = false; recoveryRequired = false
            display = "Ready. Previous outcome retained. Start a new workout on iPhone."
        } catch { display = "Recovery could not be saved. Previous outcome retained; try again when Watch is unlocked." }
        changed?()
    }
    private func expireOperation() {
        generation &+= 1; recoveryGeneration = nil; operationDeadline = nil; stopping = false; stopVerified = false
        if journal?.phase == .saved {
            recording.cancelSavedCleanup(); savedCleanupVerified = false
            display = "Workout saved. Closing previous recording timed out. Reopen the Watch app to try again."; changed?(); return
        }
        recordSaveFailureStage(); quarantine(); recording.end(); recordingAttached = false
        display = "Watch operation timed out. Use Stop recording to recover."; changed?()
    }
    private func acceptCompletion(_ token: UInt64) -> Bool {
        guard token == generation else { return false }
        if let deadline = operationDeadline, monotonic() >= deadline { expireOperation(); return false }
        if let deadline = startupDeadline, monotonic() >= deadline,
           [.creating, .starting].contains(journal?.phase) {
            startupDeadline = nil; expireOperation(); return false
        }
        return true
    }
    func tick() async {
        if let deadline = operationDeadline, monotonic() >= deadline {
            expireOperation()
        }
        if let deadline = startupDeadline, monotonic() >= deadline {
            startupDeadline = nil; generation &+= 1
            if journal?.phase == .unbound { discard() } else if [.creating, .starting].contains(journal?.phase) { quarantine(); recording.end() }
        }
        if let deadline = endDeadline, monotonic() >= deadline, journal?.phase == .recording {
            latchIncomplete(); await endWorkout()
        }
    }
    func endWorkout() async {
        if journal?.phase == .ambiguous || journal?.phase == .starting {
            quarantine(); recording.end(); recordingAttached = false; changed?(); return
        }
        if journal?.phase == .unbound { discard(); return }
        guard recordingAttached else { return }
        guard var value = journal, value.phase == .recording, let id = value.summaryID, let start = value.startedAt else { return }
        let end = value.preparedEnd ?? WatchWire.timestamp(now())
        let all = value.manifest?.intervals ?? []
        let prefix = Array(all.prefix { $0.startedAt >= start && $0.endedAt <= end })
        if prefix.isEmpty { discard(); return }
        let complete = value.confirmed && !value.incomplete && value.manifest?.final == true && prefix == all
            && ["completed", "stoppedByUser"].contains(value.manifest?.localOutcome ?? "")
        let assembly = WatchAssembly(summaryID: id, activity: value.activity, start: start, end: end,
                                     intervals: prefix, revision: value.manifest?.revision ?? 0, complete: complete,
                                     distance: value.confirmed && value.sourceExclusionEstablished ? value.manifest?.distance ?? .unavailable : .unavailable)
        let token = generation
        operationDeadline = monotonic() + 15
        display = "Saving workout…"
        value.phase = .assembling
        guard persist(value) else { recording.end(); return }
        recordingAttached = false; startupDeadline = nil; endDeadline = nil
        do {
            try await recording.assemble(assembly)
            guard acceptCompletion(token) else { return }
            guard var current = journal, current.phase == .assembling else { return }
            current.phase = .finishing
            guard persist(current) else { recording.end(); return }
            let receipt = try await recording.finish()
            guard acceptCompletion(token) else { return }; operationDeadline = nil
            guard UUID(uuidString: receipt) != nil else { throw WatchStoreError.ambiguous }
            current.phase = .saved; current.savedWorkoutID = receipt
            current.failedSaveStage = nil
            guard persist(current) else { journal?.failedSaveStage = .receiptPersistence; quarantine(); recording.end(); return }
            recording.completeSaved()
            display = complete ? "Workout saved on Apple Watch." : "Workout saved with incomplete intervals."; changed?()
        } catch {
            guard acceptCompletion(token) else { return }
            operationDeadline = nil; recordSaveFailureStage()
            if journal?.phase == .finishing { quarantine(); recording.end() }
            else { failBeforeFinish(error) }
        }
    }
    private func discard() {
        guard var value = journal, ![.discarded, .saved, .finishing, .ambiguous, .retired].contains(value.phase) else { return }
        // Persist intent first. Recovery of an interrupted discard remains ambiguous, never retries finish.
        value.phase = .assembling
        guard persist(value) else { recording.end(); return }
        recording.end(); recordingAttached = false
        do {
            try recording.discard(); value.phase = .discarded
            guard persist(value) else { return }
            display = emptyDiscardDisplay; changed?()
        } catch { quarantine() }
    }
    private func failBeforeFinish(_ error: Error) {
        if case WatchStoreError.definite = error { discard() } else { quarantine(); recording.end() }
    }
    private func recordSaveFailureStage() {
        guard var value = journal, [.assembling, .finishing].contains(value.phase) else { return }
        value.failedSaveStage = recording.finalizationStage
        _ = persist(value)
    }
    private var emptyDiscardDisplay: String {
        journal?.failedSaveStage == nil ? "Workout not saved: no execution intervals were received or usable." : "Workout was not saved because recording could not finish."
    }
    private var saveOutcomeIsUncertain: Bool {
        guard let stage = journal?.failedSaveStage else { return true }
        return [.finish, .receiptPersistence].contains(stage)
    }
    private func quarantine() {
        recoveryRequired = true
        if var value = journal { value.phase = .ambiguous; _ = persist(value) }
        display = saveOutcomeIsUncertain ? "Save result uncertain. No replacement workout will be created." : "Workout was not saved. Stop recording, then prepare your next workout."
        changed?()
    }
    private func latchIncomplete() { if var value = journal { value.incomplete = true; _ = persist(value) } }
    private func transmit(_ message: WatchWireMessage) {
        do { let data = try WatchWire.encode(message); if budget.accept(message, bytes: data.count, now: monotonic()) { send(data) } }
        catch { latchIncomplete() }
    }
}
