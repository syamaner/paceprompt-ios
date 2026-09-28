import Foundation

@MainActor protocol PhoneWatchPort: AnyObject {
    func launch(activity: String) async throws
    func send(_ data: Data)
}

@MainActor final class PhoneWatchLifecycle {
    enum Phase: Equatable { case idle, binding, bound, reconnecting, preparingEnd, awaitingAck, confirmed, unavailable }
    private let port: any PhoneWatchPort
    private let reserve: (UUID) throws -> Void
    private let makeID: () -> UUID
    private let monotonic: () -> TimeInterval
    private var budget = WatchSendBudget()
    private var deadline: TimeInterval?
    private var lastBind: TimeInterval?
    private var manifestRevision: Int64 = 0
    private var sequence: Int64 = 0
    private var latestIntervals: [WatchInterval] = []
    private var lastSentIntervals: [WatchInterval]?
    private var pendingManifest: WatchWireMessage?
    private var acknowledgedRevision: Int64 = 0
    private var lastManifestSend: TimeInterval?
    private var finalManifest: WatchWireMessage?
    private var terminalOutcome: String?
    private var terminalDistance = WatchDistance.unavailable
    private var lastRecordingRequest: String?
    private(set) var phase: Phase = .idle
    private(set) var summaryID: String?
    private(set) var activity: String?
    private(set) var workoutStart: Date?
    private(set) var integrityFailed = false
    private(set) var status = "Apple Watch is optional."
    var bound: ((UUID) -> Void)?
    var changed: (() -> Void)?

    init(port: any PhoneWatchPort, reserve: @escaping (UUID) throws -> Void,
         makeID: @escaping () -> UUID, monotonic: @escaping () -> TimeInterval) {
        self.port = port; self.reserve = reserve; self.makeID = makeID; self.monotonic = monotonic
    }
    func start(activity: String) async {
        guard phase == .idle else { return }
        let id = makeID()
        do { try reserve(id) } catch { fail("Watch ownership could not be reserved. Nothing was launched."); return }
        summaryID = id.uuidString.lowercased(); self.activity = activity
        phase = .binding; deadline = monotonic() + 30
        status = "Connecting to Apple Watch… iPhone Health saving is disabled for this attempt."; changed?()
        do { try await port.launch(activity: activity) } catch { fail("Watch unavailable. End this attempt before starting another.") }
    }
    var acceptsReplacementMirror: Bool { [.binding, .bound, .reconnecting].contains(phase) }
    func acceptsMirror(activity: String, indoor: Bool, start: Date?) -> Bool {
        guard acceptsReplacementMirror, indoor, activity == self.activity else { return false }
        return phase == .binding || start.map { WatchWire.timestamp($0) == workoutStart } == true
    }
    func mirrorConnected() {
        guard acceptsReplacementMirror else { return }
        if phase == .bound { disconnect() }
        sendBind()
    }
    func foreground() {
        tick()
        if [.binding, .bound, .reconnecting].contains(phase) { sendBind() }
    }
    private func sendBind() {
        guard let id = summaryID else { return }
        var m = WatchWireMessage(.bind, summaryID: id); m.workoutActivity = activity
        if transmit(m) { lastBind = monotonic() }
    }
    func receive(_ data: Data) {
        if let deadline, monotonic() >= deadline { fail("Watch interchange timed out. Save result unavailable on iPhone."); return }
        guard let id = summaryID else { return }
        guard let m = try? WatchWire.decode(data), m.summaryID == id else { integrityFailed = true; return }
        switch m.kind {
        case .bound:
            if phase == .binding, let start = m.workoutStart, let uuid = UUID(uuidString: id) {
                workoutStart = start; phase = .bound; deadline = nil
                status = "Watch-owned; save result unavailable on iPhone"; changed?(); bound?(uuid)
            } else if [.bound, .reconnecting].contains(phase), m.workoutStart == workoutStart {
                let reconnecting = phase == .reconnecting
                phase = .bound; deadline = nil; lastRecordingRequest = nil
                if reconnecting { status = "Watch reconnected; previous connection gaps remain incomplete."; changed?() }
                sendNonfinal()
                if let outcome = terminalOutcome { update(intervals: latestIntervals, outcome: outcome, distance: terminalDistance) }
            } else if m.workoutStart != workoutStart { integrityFailed = true }
        case .endPrepared:
            guard phase == .preparingEnd, m.sequence == sequence, let end = m.workoutEnd else { return }
            guard let manifest = manifest(final: true, end: end) else { return }
            finalManifest = manifest; phase = .awaitingAck
            if !transmit(manifest) { integrityFailed = true }
        case .ack:
            if phase == .bound, let pendingManifest, m.revision == pendingManifest.revision {
                acknowledgedRevision = m.revision!; return
            }
            guard !integrityFailed, phase == .awaitingAck, let finalManifest, m.revision == finalManifest.revision else { return }
            var confirmation = WatchWireMessage(.finalize, summaryID: id); confirmation.revision = m.revision
            if transmit(confirmation) { phase = .confirmed; deadline = nil; changed?() }
        case .bind, .manifest, .prepareEnd, .finalize, .recordingState: integrityFailed = true
        }
    }
    func update(intervals: [WatchInterval], outcome: String?, distance: WatchDistance = .unavailable) {
        guard [.bound, .reconnecting].contains(phase) else { return }
        guard intervals.starts(with: latestIntervals) else { integrityFailed = true; return }
        latestIntervals = intervals
        if phase == .reconnecting {
            if let outcome { terminalOutcome = outcome; terminalDistance = distance }
            return
        }
        if let outcome {
            terminalOutcome = outcome; terminalDistance = distance
            guard sequence < Int64.max, let id = summaryID else { fail("Watch interchange is incomplete."); return }
            sequence += 1; phase = .preparingEnd; deadline = monotonic() + 5
            var m = WatchWireMessage(.prepareEnd, summaryID: id); m.sequence = sequence
            if !transmit(m) { integrityFailed = true }
        } else { sendNonfinal() }
    }
    func requestRecording(_ state: String, observedAt: Date) {
        guard phase == .bound, lastRecordingRequest != state, sequence < Int64.max, let id = summaryID else { return }
        sequence += 1
        var m = WatchWireMessage(.recordingState, summaryID: id); m.sequence = sequence; m.state = state; m.observedAt = observedAt
        if transmit(m) { lastRecordingRequest = state }
    }
    func cancel() {
        if phase == .bound { update(intervals: latestIntervals, outcome: "interrupted") }
        else if phase == .binding || phase == .reconnecting { fail("Watch start is uncertain. End any recording on Apple Watch.") }
    }
    func primaryEnded() {
        guard phase != .confirmed, phase != .unavailable else { return }
        fail("Watch recording ended; save result unavailable on iPhone. iPhone Health saving remains disabled.")
    }
    func disconnect() {
        guard phase != .confirmed, phase != .unavailable else { return }
        if phase == .bound {
            phase = .reconnecting; deadline = monotonic() + 30
            status = "Watch connection interrupted. Waiting for the same recording; iPhone Health saving remains disabled."
            changed?()
        } else if phase != .reconnecting && phase != .binding {
            fail("Watch disconnected. End recording on Watch. iPhone Health saving remains disabled.")
        }
    }
    func tick() {
        if let deadline, monotonic() >= deadline { fail("Watch interchange timed out. Save result unavailable on iPhone."); return }
        if [.binding, .reconnecting].contains(phase), lastBind.map({ monotonic() - $0 >= 5 }) ?? false { sendBind() }
        if phase == .bound { sendNonfinal() }
    }
    private func sendNonfinal() {
        guard phase == .bound, !integrityFailed else { return }
        if latestIntervals != lastSentIntervals {
            guard let message = manifest(final: false, end: nil) else { return }
            pendingManifest = message; lastSentIntervals = latestIntervals
        }
        guard let message = pendingManifest, acknowledgedRevision < message.revision!,
              lastManifestSend.map({ monotonic() - $0 >= 5 }) ?? true else { return }
        if transmit(message) { lastManifestSend = monotonic() }
    }
    private func manifest(final: Bool, end: Date?) -> WatchWireMessage? {
        guard !integrityFailed, let id = summaryID, let start = workoutStart, manifestRevision < Int64.max else { return nil }
        if latestIntervals.count > 64 { integrityFailed = true; return nil }
        manifestRevision += 1
        var m = WatchWireMessage(.manifest, summaryID: id)
        m.revision = manifestRevision; m.workoutActivity = activity; m.workoutStart = start
        m.intervals = latestIntervals; m.final = final; m.workoutEnd = end
        m.localOutcome = final ? terminalOutcome : nil; m.distance = final ? terminalDistance : .unavailable
        return m
    }
    private func transmit(_ m: WatchWireMessage) -> Bool {
        do {
            let data = try WatchWire.encode(m)
            guard budget.accept(m, bytes: data.count, now: monotonic()) else { return false }
            port.send(data); return true
        } catch { integrityFailed = true; return false }
    }
    private func fail(_ text: String) { phase = .unavailable; deadline = nil; status = text; changed?() }
}
