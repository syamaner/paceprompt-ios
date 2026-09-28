import Foundation

struct WatchWorkoutJournal: Codable, Equatable {
    enum Phase: String, Codable { case creating, unbound, starting, recording, assembling, finishing, saved, discarded, ambiguous }
    let formatVersion: Int
    let activity: String
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
    init(activity: String) { formatVersion = 1; self.activity = activity; phase = .creating }
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

enum WatchStoreError: Error { case definite, ambiguous }

@MainActor protocol WatchJournalStore {
    func load() throws -> WatchWorkoutJournal?
    func save(_ journal: WatchWorkoutJournal) throws
}

// This port deliberately has no treadmill, History or phone Health-save operations.
@MainActor protocol WatchRecordingPort: AnyObject {
    func prepare(activity: String) async throws
    func recover(activity: String) async throws -> (start: Date, sourceExclusion: Bool)
    func begin() async throws -> Date
    func pause() async throws -> Date
    func resume() async throws
    func end()
    func discard() throws
    func assemble(_ value: WatchAssembly) async throws
    func finish() async throws -> String
}

@MainActor final class WatchWorkoutLifecycle {
    private let store: any WatchJournalStore
    private let recording: any WatchRecordingPort
    private let now: () -> Date
    private let monotonic: () -> TimeInterval
    private let send: (Data) -> Void
    private var budget = WatchSendBudget()
    private var startupDeadline: TimeInterval?
    private var recordingAttached = false
    private var pauseInFlight = false
    private var resumeInFlight = false
    private var desiredRecordingState: String?
    var canEnd: Bool { recordingAttached && [.unbound, .starting, .recording, .ambiguous].contains(journal?.phase) }
    private var pendingBind: WatchWireMessage?
    private var endDeadline: TimeInterval?
    private(set) var journal: WatchWorkoutJournal?
    private(set) var display = "Start a Watch-assisted workout on iPhone."
    var changed: (() -> Void)?

    init(store: any WatchJournalStore, recording: any WatchRecordingPort,
         now: @escaping () -> Date, monotonic: @escaping () -> TimeInterval, send: @escaping (Data) -> Void) {
        self.store = store; self.recording = recording; self.now = now; self.monotonic = monotonic; self.send = send
    }
    private func persist(_ value: WatchWorkoutJournal) -> Bool {
        do { try store.save(value); journal = value; changed?(); return true }
        catch {
            journal = value; journal?.phase = .ambiguous
            display = "Save result uncertain. No replacement workout will be created."; changed?(); return false
        }
    }
    func launch(activity: String) async {
        guard journal == nil || [.saved, .discarded].contains(journal!.phase), ["indoorWalking", "indoorRunning"].contains(activity) else { return }
        do {
            if let previous = try store.load() {
                journal = previous
                guard [.saved, .discarded].contains(previous.phase) else {
                    await recoverLoaded(previous); return
                }
            }
        } catch { display = "Protected workout state is unavailable."; changed?(); return }
        budget = WatchSendBudget(); pendingBind = nil; endDeadline = nil; recordingAttached = false; pauseInFlight = false; resumeInFlight = false; desiredRecordingState = nil
        let value = WatchWorkoutJournal(activity: activity)
        guard persist(value) else { return }
        startupDeadline = monotonic() + 30
        display = "Connecting to iPhone…"; changed?()
        do {
            try await recording.prepare(activity: activity)
            guard var current = journal, current.phase == .creating else { recording.end(); return }
            recordingAttached = true
            current.phase = .unbound
            guard persist(current) else { recording.end(); return }
            if let message = pendingBind { pendingBind = nil; await bind(message) }
        } catch { failBeforeFinish(error) }
    }
    func recover() async {
        guard journal == nil else { return }
        do { if let value = try store.load() { await recoverLoaded(value) } }
        catch { quarantine() }
    }
    private func recoverLoaded(_ original: WatchWorkoutJournal) async {
        var value = original; journal = value
        guard value.formatVersion == 1 else { quarantine(); return }
        if [.saved, .discarded].contains(value.phase) {
            display = value.phase == .saved ? "Workout saved on Apple Watch." : "Workout not saved: no execution intervals were received or usable."
            changed?(); return
        }
        do {
            guard value.phase == .recording, value.summaryID != nil, let start = value.startedAt,
                  value.sourceExclusionEstablished else { throw WatchStoreError.ambiguous }
            let recovered = try await recording.recover(activity: value.activity)
            recordingAttached = true
            guard WatchWire.timestamp(recovered.start) == start, recovered.sourceExclusion else { throw WatchStoreError.ambiguous }
            value.incomplete = value.incomplete || !value.confirmed
            guard persist(value) else { recording.end(); return }
            display = "Recovered recording. End on Watch when finished."; changed?()
            if value.prepareSequence != nil || value.confirmed { await endWorkout() }
        } catch { quarantine(); recording.end(); recordingAttached = false; changed?() }
    }
    func receive(_ data: Data) async {
        await tick()
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
        value.summaryID = m.summaryID; value.phase = .starting
        guard persist(value) else { recording.end(); return }
        do {
            let start = try await recording.begin()
            guard var current = journal, current.phase == .starting else { recording.end(); return }
            current.startedAt = WatchWire.timestamp(start); current.phase = .recording; current.sourceExclusionEstablished = true
            guard persist(current) else { recording.end(); return }
            startupDeadline = nil; display = "Recording on Apple Watch"; changed?()
            var response = WatchWireMessage(.bound, summaryID: m.summaryID); response.workoutStart = current.startedAt; transmit(response)
        } catch { failBeforeFinish(error) }
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
        desiredRecordingState = nil
        guard persist(value) else { recording.end(); return }
        if pauseInFlight || resumeInFlight { return } // Complete the pending transition before establishing the end boundary.
        await establishPreparedEnd(sequence: seq)
    }
    private func establishPreparedEnd(sequence seq: Int64) async {
        guard let value = journal, value.phase == .recording, value.preparedEnd == nil else { return }
        do {
            pauseInFlight = !value.paused
            let end = value.paused ? now() : try await recording.pause()
            pauseInFlight = false
            guard var current = journal, current.phase == .recording, current.prepareSequence == seq else { return }
            current.preparedEnd = WatchWire.timestamp(end); current.paused = true
            guard persist(current) else { return }; sendPrepared()
        } catch { pauseInFlight = false; latchIncomplete() }
    }
    private func reconcileRecordingRequest() async {
        guard !pauseInFlight, !resumeInFlight, var value = journal, value.phase == .recording,
              value.prepareSequence == nil, let desired = desiredRecordingState else { return }
        if (desired == "paused") == value.paused { desiredRecordingState = nil; return }
        if desired == "running" {
            resumeInFlight = true
            do {
                try await recording.resume(); resumeInFlight = false
                guard var current = journal, current.phase == .recording else { return }
                current.paused = false
                guard persist(current) else { return }
                if let sequence = current.prepareSequence { await establishPreparedEnd(sequence: sequence) }
                else {
                    if desiredRecordingState == "running" { desiredRecordingState = nil }
                    await reconcileRecordingRequest()
                }
            } catch { resumeInFlight = false; latchIncomplete() }
            return
        }
        pauseInFlight = true
        do {
            let date = try await recording.pause()
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
        } catch { pauseInFlight = false; latchIncomplete() }
    }
    private func sendPrepared() {
        guard let value = journal, let id = value.summaryID, let seq = value.prepareSequence, let end = value.preparedEnd else { return }
        var m = WatchWireMessage(.endPrepared, summaryID: id); m.sequence = seq; m.workoutEnd = end; transmit(m)
    }
    func recordingState(paused: Bool) {
        guard var value = journal, value.phase == .recording else { return }
        value.paused = paused
        display = paused ? "Recording paused on Apple Watch." : "Recording on Apple Watch"
        _ = persist(value)
    }
    func disconnected() {
        guard let phase = journal?.phase, [.creating, .unbound, .starting, .recording].contains(phase) else { return }
        if journal?.confirmed != true { latchIncomplete() }
        guard journal?.phase != .ambiguous else { return }
        display = phase == .recording ? "iPhone disconnected. Recording continues until you end it." : "iPhone disconnected. Recording start is unavailable or uncertain."
        changed?()
    }
    func failed() async { latchIncomplete(); await endWorkout() }
    func tick() async {
        if let deadline = startupDeadline, monotonic() >= deadline {
            startupDeadline = nil
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
        value.phase = .assembling
        guard persist(value) else { recording.end(); return }
        recording.end(); recordingAttached = false; startupDeadline = nil; endDeadline = nil
        do {
            try await recording.assemble(assembly)
            guard var current = journal, current.phase == .assembling else { return }
            current.phase = .finishing
            guard persist(current) else { return }
            let receipt = try await recording.finish()
            guard UUID(uuidString: receipt) != nil else { throw WatchStoreError.ambiguous }
            current.phase = .saved; current.savedWorkoutID = receipt
            guard persist(current) else { return }
            display = complete ? "Workout saved on Apple Watch." : "Workout saved with incomplete intervals."; changed?()
        } catch { if journal?.phase == .finishing { quarantine() } else { failBeforeFinish(error) } }
    }
    private func discard() {
        guard var value = journal, ![.discarded, .saved, .finishing, .ambiguous].contains(value.phase) else { return }
        // Persist intent first. Recovery of an interrupted discard remains ambiguous, never retries finish.
        value.phase = .assembling
        guard persist(value) else { recording.end(); return }
        recording.end(); recordingAttached = false
        do {
            try recording.discard(); value.phase = .discarded
            guard persist(value) else { return }
            display = "Workout not saved: no execution intervals were received or usable."; changed?()
        } catch { quarantine() }
    }
    private func failBeforeFinish(_ error: Error) {
        if case WatchStoreError.definite = error { discard() } else { quarantine(); recording.end() }
    }
    private func quarantine() {
        if var value = journal { value.phase = .ambiguous; _ = persist(value) }
        display = "Save result uncertain. No replacement workout will be created."; changed?()
    }
    private func latchIncomplete() { if var value = journal { value.incomplete = true; _ = persist(value) } }
    private func transmit(_ message: WatchWireMessage) {
        do { let data = try WatchWire.encode(message); if budget.accept(message, bytes: data.count, now: monotonic()) { send(data) } }
        catch { latchIncomplete() }
    }
}
