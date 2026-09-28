import XCTest
@testable import PacePrompt

@MainActor final class WatchInterchangeTests: XCTestCase {
    private let id = "11400000-0000-4000-8000-000000000001"
    private let start = Date(timeIntervalSince1970: 1_780_000_000)
    private var clock: TestClock!
    private var store: TestJournal!
    private var recording: TestRecording!
    private var sut: WatchWorkoutLifecycle!
    private var sent: [WatchWireMessage] = []

    override func setUp() async throws {
        clock = TestClock(); store = TestJournal(); recording = TestRecording(start: start)
        sut = WatchWorkoutLifecycle(store: store, recording: recording, now: { [unowned self] in self.start.addingTimeInterval(self.clock.time) },
            monotonic: { [unowned self] in self.clock.time }, send: { [unowned self] in if let m = try? WatchWire.decode($0) { self.sent.append(m) } })
    }
    private func message(_ kind: WatchWireMessage.Kind) -> WatchWireMessage { .init(kind, summaryID: id) }
    private func interval(_ index: Int = 0) -> WatchInterval {
        let a = start.addingTimeInterval(Double(index * 30 + 1))
        return .init(segmentIndex: 0, intervalIndex: index, startedAt: a, endedAt: a.addingTimeInterval(20),
            prescribed: .init(kind: "interval", speedKilometresPerHour: 4.2, inclinationPercent: 1),
            effectiveSpeed: .init(kilometresPerHour: 4.3, source: "manualOverride"), effectiveInclination: .init(percent: 1, source: "planned"),
            settledObservation: .init(observedAt: a, speedKilometresPerHour: 4.3, inclinationPercent: 1, provenance: "fr30zTreadmillDataCurrentEpoch"), endReason: "planTransition")
    }
    private func manifest(_ revision: Int64, final: Bool = false, intervals: [WatchInterval]? = nil) -> WatchWireMessage {
        var m = message(.manifest); m.revision = revision; m.workoutActivity = "indoorWalking"; m.workoutStart = start
        m.intervals = intervals ?? [interval()]; m.final = final; m.workoutEnd = final ? recording.pauseDate : nil
        m.localOutcome = final ? "completed" : nil; m.distance = .unavailable; return m
    }
    private func receive(_ m: WatchWireMessage) async throws { await sut.receive(try WatchWire.encode(m)) }
    private func bound() async throws {
        await sut.launch(activity: "indoorWalking")
        var m = message(.bind); m.workoutActivity = "indoorWalking"; try await receive(m)
        XCTAssertEqual(sut.journal?.phase, .recording)
    }
    private func prepared() async throws { var m = message(.prepareEnd); m.sequence = 1; try await receive(m) }
    private func complete(_ m: WatchWireMessage? = nil) async throws {
        try await prepared(); try await receive(m ?? manifest(1, final: true))
        var confirmation = message(.finalize); confirmation.revision = m?.revision ?? 1; try await receive(confirmation)
    }
    func testBindingPersistsBeforeCollectionAndDuplicateIsIdempotent() async throws {
        try await bound(); var bind = message(.bind); bind.workoutActivity = "indoorWalking"
        try await receive(bind); await sut.launch(activity: "indoorWalking")
        XCTAssertEqual(recording.creates, 1); XCTAssertEqual(recording.begins, 1)
        XCTAssertEqual(store.saved.map(\.phase).prefix(3), [.creating, .unbound, .starting])
        XCTAssertEqual(sent.filter { $0.kind == .bound }.count, 2)
    }
    func testReserveAndBoundJournalFailuresNeverBegin() async throws {
        store.failPhase = .creating; await sut.launch(activity: "indoorWalking")
        XCTAssertEqual(recording.creates, 0); XCTAssertEqual(recording.begins, 0)
    }
    func testBindingPersistenceFailureDoesNotBegin() async throws {
        await sut.launch(activity: "indoorWalking"); store.failPhase = .starting
        var bind = message(.bind); bind.workoutActivity = "indoorWalking"; try await receive(bind)
        XCTAssertEqual(recording.begins, 0); XCTAssertEqual(sut.journal?.phase, .ambiguous)
    }
    func testDuplicateBindingDuringPendingStartCannotBeginTwice() async throws {
        await sut.launch(activity: "indoorWalking"); recording.holdBegin = true
        var bind = message(.bind); bind.workoutActivity = "indoorWalking"
        let data = try WatchWire.encode(bind); let task = Task { await sut.receive(data) }
        await Task.yield(); await sut.receive(data)
        XCTAssertEqual(recording.begins, 1)
        recording.startWaiter?.resume(returning: start); recording.startWaiter = nil
        await task.value; XCTAssertEqual(recording.begins, 1)
    }
    func testAnotherSummaryIsRejectedWithoutAnotherPrimary() async throws {
        try await bound(); var bind = WatchWireMessage(.bind, summaryID: UUID().uuidString.lowercased()); bind.workoutActivity = "indoorWalking"
        try await receive(bind); XCTAssertEqual(recording.creates, 1); XCTAssertTrue(sut.journal!.incomplete)
    }
    func testUnboundStartupTimeoutDiscards() async {
        await sut.launch(activity: "indoorWalking"); clock.time = 30; await sut.tick(); await sut.tick()
        XCTAssertEqual(recording.discards, 1); XCTAssertEqual(recording.finishes, 0)
    }
    func testStartedButUnconfirmedBindingLeavesPhoneSuppression() async throws {
        let port = TestPhonePort(); var reservations = [UUID]()
        let phone = PhoneWatchLifecycle(port: port, reserve: { reservations.append($0) }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); clock.time = 30; phone.tick()
        XCTAssertEqual(phone.phase, .unavailable); XCTAssertEqual(reservations.count, 1); XCTAssertEqual(phone.summaryID, id)
    }
    func testPhoneReservationFailureDoesNotLaunch() async {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in throw WatchStoreError.definite }, makeID: UUID.init, monotonic: { 0 })
        await phone.start(activity: "indoorWalking"); XCTAssertEqual(port.launches, 0); XCTAssertNil(phone.summaryID)
    }
    func testCumulativeDuplicateDelayedAndSkippedRevisions() async throws {
        try await bound(); try await receive(manifest(1)); try await receive(manifest(1))
        try await receive(manifest(4, intervals: [interval(), interval(1)])); try await receive(manifest(1))
        XCTAssertEqual(sut.journal?.manifest?.revision, 4); XCTAssertEqual(sut.journal?.manifest?.intervals?.count, 2)
        XCTAssertEqual(recording.assemblies.count, 0); XCTAssertEqual(sent.last?.revision, 4); XCTAssertFalse(sut.journal!.incomplete)
    }
    func testConflictingDuplicateLatchesIncompleteAndRetainsPrefix() async throws {
        try await bound(); try await receive(manifest(1)); try await receive(manifest(1, intervals: []))
        XCTAssertEqual(sut.journal?.manifest?.intervals, [interval()]); XCTAssertTrue(sut.journal!.incomplete)
        try await complete(manifest(2, final: true)); XCTAssertFalse(recording.assemblies[0].complete)
    }
    func testPrefixTruncationIsAtomic() async throws {
        try await bound(); try await receive(manifest(1)); try await receive(manifest(3, intervals: []))
        XCTAssertEqual(sut.journal?.manifest?.revision, 1); XCTAssertTrue(sut.journal!.incomplete)
    }
    func testPersistFailureDoesNotAcknowledgeRevision() async throws {
        try await bound(); store.failNext = true; try await receive(manifest(1))
        XCTAssertFalse(sent.contains { $0.kind == .ack }); XCTAssertEqual(sut.journal?.phase, .ambiguous)
    }
    func testMalformedUnknownDuplicateKeysAndOversizedMessages() async throws {
        for data in [Data("{}".utf8), Data("{\"kind\":\"ack\",\"kind\":\"bind\"}".utf8), Data(repeating: 32, count: 32_769)] {
            XCTAssertThrowsError(try WatchWire.decode(data))
        }
        try await bound(); await sut.receive(Data("{}".utf8)); XCTAssertTrue(sut.journal!.incomplete)
    }
    func testWireRejectsBooleanRevisionUnknownFieldsAndInvalidNumbers() throws {
        let good = String(data: try WatchWire.encode(manifest(1)), encoding: .utf8)!
        for text in [good.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":true"),
                     good.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":1.0"),
                     good.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
                     good.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":9223372036854775808"),
                     good.replacingOccurrences(of: "\"revision\":1", with: "\"rawHeartRate\":[80],\"revision\":1"),
                     good.replacingOccurrences(of: "4.3", with: "1e999"),
                     good.replacingOccurrences(of: ".000Z", with: "Z")] {
            XCTAssertThrowsError(try WatchWire.decode(Data(text.utf8)), text)
        }
    }
    func testOutOfBoundsAndOverlapRejectedWithoutChangingPrefix() async throws {
        try await bound(); try await receive(manifest(1))
        var m = manifest(2, intervals: [interval(), interval()]); m.workoutStart = start.addingTimeInterval(10)
        XCTAssertThrowsError(try WatchWire.encode(m))
        var wrongClock = manifest(2); wrongClock.workoutStart = start.addingTimeInterval(-1)
        try await receive(wrongClock); XCTAssertEqual(sut.journal?.manifest?.revision, 1)
    }
    func testCompleteRequiresFinalAckConfirmationAndFinishesOnce() async throws {
        try await bound(); try await complete(); await sut.endWorkout()
        XCTAssertEqual(recording.finishes, 1); XCTAssertEqual(recording.assemblies.count, 1); XCTAssertTrue(recording.assemblies[0].complete)
        XCTAssertEqual(recording.order.suffix(3), ["end", "assemble", "finish"]); XCTAssertEqual(sut.journal?.phase, .saved)
        XCTAssertEqual(sent.last?.kind, .ack) // No save-result message exists after end.
    }
    func testLostFinalizeTimeoutSavesIncompleteAndOmitsDistance() async throws {
        try await bound(); try await prepared()
        var m = manifest(1, final: true); m.distance = .init(state: "accepted", metres: 100, provenance: "fr30zCumulativeDistanceDelta")
        try await receive(m); clock.time = 5; await sut.tick()
        XCTAssertFalse(recording.assemblies[0].complete); XCTAssertEqual(recording.assemblies[0].distance, .unavailable)
    }
    func testEmptyFinalDiscardsWithoutFinish() async throws {
        try await bound(); try await complete(manifest(1, final: true, intervals: []))
        XCTAssertEqual(recording.discards, 1); XCTAssertEqual(recording.finishes, 0); XCTAssertEqual(sut.journal?.phase, .discarded)
        XCTAssertTrue(sut.display.contains("no execution intervals"))
    }
    func testWatchEndBeforeAnyManifestDiscards() async throws {
        try await bound(); await sut.endWorkout(); await sut.endWorkout()
        XCTAssertEqual(recording.discards, 1); XCTAssertEqual(recording.finishes, 0)
    }
    func testWhollyUnusableBoundsDiscardsRatherThanClamping() async throws {
        try await bound(); try await receive(manifest(1)); clock.time = 0.5; await sut.endWorkout()
        XCTAssertEqual(recording.discards, 1); XCTAssertEqual(recording.finishes, 0)
    }
    func testPartiallyUsablePrefixSavesOnlyPrefixIncomplete() async throws {
        try await bound(); try await receive(manifest(1, intervals: [interval(), interval(1)])); clock.time = 25; await sut.endWorkout()
        XCTAssertEqual(recording.assemblies[0].intervals, [interval()]); XCTAssertFalse(recording.assemblies[0].complete)
    }
    func testAlreadyPausedPreparationUsesCurrentInstantAndRejectsResume() async throws {
        try await bound(); sut.recordingState(paused: true); clock.time = 60; try await prepared()
        XCTAssertEqual(sut.journal?.preparedEnd, start.addingTimeInterval(60)); XCTAssertEqual(recording.pauses, 0)
        var resume = message(.recordingState); resume.sequence = 2; resume.state = "running"; resume.observedAt = start.addingTimeInterval(61)
        try await receive(resume); XCTAssertEqual(recording.resumes, 0)
        try await prepared(); XCTAssertEqual(sent.last?.workoutEnd, start.addingTimeInterval(60))
    }
    func testMissingPauseCallbackExpiresWithoutWaitingAndLateCallbackCannotUpgrade() async throws {
        try await bound(); try await receive(manifest(1)); recording.holdPause = true
        var m = message(.prepareEnd); m.sequence = 1; let data = try WatchWire.encode(m)
        let pending = Task { await sut.receive(data) }; await Task.yield()
        clock.time = 60; await sut.tick()
        recording.pauseWaiter?.resume(returning: recording.pauseDate); recording.pauseWaiter = nil; await pending.value
        XCTAssertEqual(recording.finishes, 1); XCTAssertFalse(recording.assemblies[0].complete)
    }
    func testRecordingRequestsAreOneWayAndStaleSequencesIgnored() async throws {
        try await bound(); var m = message(.recordingState); m.sequence = 2; m.state = "paused"; m.observedAt = start
        try await receive(m); try await receive(m); m.sequence = 1; m.state = "running"; try await receive(m)
        XCTAssertEqual(recording.pauses, 1); XCTAssertEqual(recording.resumes, 0)
    }
    func testDefiniteAssemblyFailureDiscardsAndAmbiguousDoesNotRetry() async throws {
        try await bound(); recording.assemblyFailure = .definite; try await complete()
        XCTAssertEqual(recording.discards, 1); XCTAssertEqual(recording.finishes, 0)
    }
    func testAmbiguousActivityMutationQuarantines() async throws {
        try await bound(); recording.assemblyFailure = .ambiguous; try await complete(); await sut.endWorkout()
        XCTAssertEqual(sut.journal?.phase, .ambiguous); XCTAssertEqual(recording.discards, 0); XCTAssertEqual(recording.finishes, 0)
    }
    func testFinishNilErrorAndReceiptPersistenceFailureCannotRetry() async throws {
        try await bound(); recording.finishFailure = true; try await complete(); await sut.endWorkout()
        XCTAssertEqual(recording.finishes, 1); XCTAssertEqual(sut.journal?.phase, .ambiguous)
    }
    func testReceiptPersistenceFailureCannotRetry() async throws {
        try await bound(); store.failPhase = .saved; try await complete(); await sut.endWorkout()
        XCTAssertEqual(recording.finishes, 1); XCTAssertEqual(sut.journal?.phase, .ambiguous)
    }
    func testFinishIntentPersistenceFailureNeverFinishes() async throws {
        try await bound(); store.failPhase = .finishing; try await complete()
        XCTAssertEqual(recording.finishes, 0); XCTAssertEqual(sut.journal?.phase, .ambiguous)
    }
    func testUnknownDiscardShowsAmbiguousNotNotSaved() async throws {
        try await bound(); recording.discardFailure = true; await sut.endWorkout()
        XCTAssertEqual(sut.journal?.phase, .ambiguous); XCTAssertFalse(sut.display.contains("Workout not saved"))
    }
    func testRecoveredEmptyPrefixDiscardsExistingPrimary() async throws {
        var j = WatchWorkoutJournal(activity: "indoorWalking"); j.phase = .recording; j.summaryID = id; j.startedAt = start; j.sourceExclusionEstablished = true
        store.value = j; await sut.recover(); await sut.endWorkout()
        XCTAssertEqual(recording.recovers, 1); XCTAssertEqual(recording.creates, 0); XCTAssertEqual(recording.discards, 1); XCTAssertEqual(recording.finishes, 0)
    }
    func testUncertainStartupAndFinishRecoveryNeverCreateReplacement() async throws {
        for phase: WatchWorkoutJournal.Phase in [.creating, .starting, .assembling, .finishing, .ambiguous] {
            let local = TestJournal(); var j = WatchWorkoutJournal(activity: "indoorWalking"); j.phase = phase; local.value = j
            let engine = WatchWorkoutLifecycle(store: local, recording: recording, now: Date.init, monotonic: { 0 }, send: { _ in })
            await engine.recover(); await engine.launch(activity: "indoorWalking")
            XCTAssertEqual(engine.journal?.phase, .ambiguous)
        }
        XCTAssertEqual(recording.creates, 0); XCTAssertEqual(recording.finishes, 0)
    }
    func testRecoveryWithUnknownDistanceSourceIsQuarantined() async throws {
        var j = WatchWorkoutJournal(activity: "indoorWalking"); j.phase = .recording; j.summaryID = id; j.startedAt = start; j.sourceExclusionEstablished = true
        store.value = j; recording.recoverySource = false; await sut.recover()
        XCTAssertEqual(sut.journal?.phase, .ambiguous); XCTAssertEqual(recording.creates, 0)
    }
    func testTerminalBudgetSurvivesMaximumNonfinalAndControlPressure() {
        var budget = WatchSendBudget(); var m = manifest(1)
        XCTAssertTrue(budget.accept(m, bytes: 24_576, now: 0)); XCTAssertFalse(budget.accept(m, bytes: 1, now: 1))
        let control = message(.prepareEnd)
        for _ in 0..<16 { XCTAssertTrue(budget.accept(control, bytes: 512, now: 0)) }
        XCTAssertFalse(budget.accept(control, bytes: 1, now: 0)); m.final = true
        XCTAssertTrue(budget.accept(m, bytes: 32_768, now: 0)); XCTAssertFalse(budget.accept(m, bytes: 1, now: 0))
    }
    func testPhoneConfirmationNeverClaimsSaveReceipt() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); phone.mirrorConnected()
        var bound = message(.bound); bound.workoutStart = start; phone.receive(try WatchWire.encode(bound))
        phone.update(intervals: [interval()], outcome: "completed")
        var prepared = message(.endPrepared); prepared.sequence = 1; prepared.workoutEnd = recording.pauseDate; phone.receive(try WatchWire.encode(prepared))
        let final = port.messages.last!; XCTAssertEqual(final.kind, .manifest)
        var ack = message(.ack); ack.revision = final.revision; phone.receive(try WatchWire.encode(ack))
        XCTAssertEqual(phone.phase, .confirmed); XCTAssertEqual(port.messages.last?.kind, .finalize)
        XCTAssertEqual(phone.status, "Watch-owned; save result unavailable on iPhone")
    }
    func testPhonePrimaryEndedStopsSendingAndLateDisconnectPreservesResult() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
        phone.primaryEnded(); let count = port.messages.count; let status = phone.status
        phone.disconnect(); phone.tick(); phone.update(intervals: [interval()], outcome: "completed")
        XCTAssertEqual(phone.phase, .unavailable); XCTAssertEqual(port.messages.count, count)
        XCTAssertEqual(phone.status, status); XCTAssertTrue(status.contains("recording ended"))
    }
    func testNormalPhoneCompletionSurvivesEndAndDisconnectCallbacks() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
        phone.update(intervals: [interval()], outcome: "completed")
        var e = message(.endPrepared); e.sequence = 1; e.workoutEnd = recording.pauseDate; phone.receive(try WatchWire.encode(e))
        var ack = message(.ack); ack.revision = port.messages.last!.revision; phone.receive(try WatchWire.encode(ack))
        phone.primaryEnded(); phone.disconnect()
        XCTAssertEqual(phone.phase, .confirmed); XCTAssertEqual(phone.status, "Watch-owned; save result unavailable on iPhone")
    }
    func testDisconnectAfterWatchSavedOrDiscardedDoesNotOverwriteTerminalState() async throws {
        try await bound(); try await complete(); let saved = sut.display; sut.disconnected()
        XCTAssertEqual(sut.display, saved); XCTAssertEqual(sut.journal?.phase, .saved); XCTAssertFalse(sut.journal!.incomplete)
        await sut.launch(activity: "indoorWalking")
        var bind = message(.bind); bind.workoutActivity = "indoorWalking"; try await receive(bind)
        await sut.endWorkout(); let discarded = sut.display; sut.disconnected()
        XCTAssertEqual(sut.display, discarded); XCTAssertEqual(sut.journal?.phase, .discarded)
    }
    func testHeldPauseThenNewResumeReconcilesNewestState() async throws {
        try await bound(); recording.holdPause = true
        var pause = message(.recordingState); pause.sequence = 1; pause.state = "paused"; pause.observedAt = start
        let data = try WatchWire.encode(pause); let task = Task { await sut.receive(data) }; await Task.yield()
        var resume = message(.recordingState); resume.sequence = 2; resume.state = "running"; resume.observedAt = start
        try await receive(resume); XCTAssertEqual(recording.resumes, 0)
        recording.pauseWaiter?.resume(returning: recording.pauseDate); recording.pauseWaiter = nil; await task.value
        XCTAssertEqual(recording.resumes, 1)
    }
    func testHeldResumeThenNewPauseReconcilesNewestState() async throws {
        try await bound(); sut.recordingState(paused: true); recording.holdResume = true
        var resume = message(.recordingState); resume.sequence = 1; resume.state = "running"; resume.observedAt = start
        let data = try WatchWire.encode(resume); let task = Task { await sut.receive(data) }; await Task.yield()
        var pause = message(.recordingState); pause.sequence = 2; pause.state = "paused"; pause.observedAt = start
        try await receive(pause); XCTAssertEqual(recording.pauses, 0)
        recording.resumeWaiter?.resume(); recording.resumeWaiter = nil; await task.value
        XCTAssertEqual(recording.pauses, 1); XCTAssertEqual(sut.journal?.paused, true)
    }
    func testEndPreparationWaitsForPendingResumeThenPauses() async throws {
        try await bound(); sut.recordingState(paused: true); recording.holdResume = true
        var resume = message(.recordingState); resume.sequence = 1; resume.state = "running"; resume.observedAt = start
        let data = try WatchWire.encode(resume); let task = Task { await sut.receive(data) }; await Task.yield()
        var end = message(.prepareEnd); end.sequence = 2; try await receive(end)
        XCTAssertNil(sut.journal?.preparedEnd)
        recording.resumeWaiter?.resume(); recording.resumeWaiter = nil; await task.value
        XCTAssertEqual(recording.pauses, 1); XCTAssertEqual(sent.last?.kind, .endPrepared)
        XCTAssertEqual(sut.journal?.preparedEnd, recording.pauseDate)
    }
    func testEndPreparationCoalescesPendingPause() async throws {
        try await bound(); recording.holdPause = true
        var pause = message(.recordingState); pause.sequence = 1; pause.state = "paused"; pause.observedAt = start
        let data = try WatchWire.encode(pause); let task = Task { await sut.receive(data) }; await Task.yield()
        var end = message(.prepareEnd); end.sequence = 2; try await receive(end)
        recording.pauseWaiter?.resume(returning: recording.pauseDate); recording.pauseWaiter = nil; await task.value
        XCTAssertEqual(recording.pauses, 1); XCTAssertEqual(sent.last?.kind, .endPrepared)
        XCTAssertEqual(sut.journal?.preparedEnd, recording.pauseDate)
    }
    func testLateFinalizeRejectedWithoutTimerTick() async throws {
        try await bound(); try await prepared(); try await receive(manifest(1, final: true))
        clock.time = 5.01; var m = message(.finalize); m.revision = 1; try await receive(m)
        XCTAssertEqual(recording.finishes, 1); XCTAssertFalse(recording.assemblies[0].complete)
    }
    func testMalformedReplyAfterFinalManifestCannotConfirmCompleteness() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking")
        var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
        phone.update(intervals: [interval()], outcome: "completed")
        var e = message(.endPrepared); e.sequence = 1; e.workoutEnd = recording.pauseDate; phone.receive(try WatchWire.encode(e))
        var ack = message(.ack); ack.revision = port.messages.last!.revision
        phone.receive(Data("{}".utf8)); phone.receive(try WatchWire.encode(ack))
        XCTAssertTrue(phone.integrityFailed); XCTAssertFalse(port.messages.contains { $0.kind == .finalize })
        clock.time = 5.01; phone.tick(); XCTAssertEqual(phone.phase, .unavailable)
    }
    func testPhoneLateAckCannotConfirmWithoutTimerTick() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
        phone.update(intervals: [interval()], outcome: "completed")
        var e = message(.endPrepared); e.sequence = 1; e.workoutEnd = recording.pauseDate; phone.receive(try WatchWire.encode(e))
        var a = message(.ack); a.revision = port.messages.last!.revision; clock.time = 5.01; phone.receive(try WatchWire.encode(a))
        XCTAssertEqual(phone.phase, .unavailable); XCTAssertFalse(port.messages.contains { $0.kind == .finalize })
    }
    func testLaunchBeforeRecoveryReattachesExistingPrimary() async throws {
        var j = WatchWorkoutJournal(activity: "indoorWalking"); j.phase = .recording; j.summaryID = id; j.startedAt = start; j.sourceExclusionEstablished = true
        store.value = j; await sut.launch(activity: "indoorWalking"); await sut.recover()
        XCTAssertEqual(recording.recovers, 1); XCTAssertEqual(recording.creates, 0); XCTAssertTrue(sut.canEnd)
        await sut.endWorkout(); XCTAssertEqual(recording.discards, 1)
    }
    func testOldCallbackIdentityIsRejectedForEveryEventKind() {
        let old = NSObject(), current = NSObject()
        for _ in ["running", "paused", "ended", "failed", "data", "disconnected", "builder"] {
            XCTAssertFalse(WatchCallbackIdentity.accepts(old, current: current))
            XCTAssertTrue(WatchCallbackIdentity.accepts(current, current: current))
            XCTAssertFalse(WatchCallbackIdentity.accepts(old, current: nil))
        }
    }
    func testAdapterDelayedAuthorizationCannotCreateAfterCancellation() async throws {
        let backend = TestSessionOperations(); backend.holdAuthorization = true
        let adapter = WatchRecordingAdapter(operations: backend)
        let task = Task { try? await adapter.prepare(activity: "indoorWalking") }; await Task.yield()
        adapter.end(); backend.authorizationWaiter?.resume(returning: true); backend.authorizationWaiter = nil; await task.value
        XCTAssertFalse(backend.calls.contains("create")); XCTAssertFalse(backend.calls.contains("mirror"))
    }
    func testAdapterDelayedMirroringCannotBeginAfterCancellation() async throws {
        let backend = TestSessionOperations(); backend.holdMirror = true
        let adapter = WatchRecordingAdapter(operations: backend)
        let task = Task { try? await adapter.prepare(activity: "indoorWalking") }; await Task.yield()
        adapter.end(); backend.mirrorWaiter?.resume(); backend.mirrorWaiter = nil; await task.value
        do { _ = try await adapter.begin(); XCTFail("cancelled start") } catch { }
        XCTAssertEqual(backend.calls.filter { $0 == "create" }.count, 1); XCTAssertFalse(backend.calls.contains("start"))
    }
    func testRealAdapterOperationOrderAndNilFinishNeverRetries() async throws {
        let backend = TestSessionOperations(); let adapter = WatchRecordingAdapter(operations: backend)
        try await adapter.prepare(activity: "indoorWalking"); _ = try await adapter.begin()
        XCTAssertEqual(backend.calls, ["reset", "authorize", "recover", "create", "configure", "prepare", "mirror", "start", "collect"])
        adapter.end()
        let value = WatchAssembly(summaryID: id, activity: "indoorWalking", start: start, end: start.addingTimeInterval(60), intervals: [interval()], revision: 1, complete: true, distance: .unavailable)
        try await adapter.assemble(value); backend.nilFinish = true
        do { _ = try await adapter.finish(); XCTFail("nil receipt") } catch { }
        do { _ = try await adapter.finish(); XCTFail("repeated finish") } catch { }
        XCTAssertEqual(backend.calls.filter { $0 == "finish" }.count, 1)
    }
    func testRealAdapterDenialAndUnknownSourceCannotBegin() async throws {
        for denied in [true, false] {
            let backend = TestSessionOperations(); backend.authorized = !denied; backend.configuredSourceExcludesDistance = false
            let adapter = WatchRecordingAdapter(operations: backend)
            do { try await adapter.prepare(activity: "indoorWalking"); XCTFail("denied/unknown source") } catch { }
            XCTAssertFalse(backend.calls.contains("start")); XCTAssertFalse(backend.calls.contains("mirror"))
        }
    }
    func testAssemblySourceExclusionActivityMappingAndDistancePermission() async throws {
        let value = WatchAssembly(summaryID: id, activity: "indoorWalking", start: start, end: start.addingTimeInterval(60), intervals: [interval()], revision: 4, complete: true,
            distance: .init(state: "accepted", metres: 100, provenance: "fr30zCumulativeDistanceDelta"))
        for permission in [false, true] {
            let backend = TestSessionOperations(); backend.collectionStarted = true; backend.ended = true; backend.distanceAuthorized = permission
            try await WatchBuilderAssemblyWriter(builder: backend).assemble(value)
            XCTAssertEqual(backend.calls.contains("distance"), permission); XCTAssertEqual(backend.metadataDistance, permission)
            XCTAssertEqual(backend.activities.count, 1)
        }
        for failure in ["source", "distance", "extra", "mutated"] {
            let backend = TestSessionOperations(); backend.collectionStarted = true; backend.ended = true
            if failure == "source" { backend.sourceExcludesDistance = false }
            if failure == "distance" { backend.hasDistance = true }
            if failure == "extra" { backend.activities = [.init(start: start, end: nil, activity: "indoorWalking", indoor: true)] }
            if failure == "mutated" { backend.addExtraActivity = true }
            do { try await WatchBuilderAssemblyWriter(builder: backend).assemble(value); XCTFail(failure) } catch { }
            XCTAssertFalse(backend.calls.contains("distance")); XCTAssertFalse(backend.calls.contains("metadata"))
        }
    }
    func testProtectedReservationIsPermanentAndMissingNewOwnershipIsInvalid() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ownership = WatchOwnershipStore(directory: { directory }); let uuid = UUID()
        XCTAssertTrue(ownership.phoneSaveAllowed(uuid))
        try ownership.reserve(uuid)
        XCTAssertThrowsError(try ownership.reserve(uuid))
        XCTAssertFalse(ownership.phoneSaveAllowed(uuid))
        let broken = WatchOwnershipStore(directory: { throw WatchStoreError.ambiguous }); XCTAssertFalse(broken.phoneSaveAllowed(uuid))
    }
    func testRealWireAndMetadataMapperMatchSharedGoldenFixtures() throws {
        for name in ["complete", "incomplete"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name + ".synthetic", withExtension: "json"))
            let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let manifests = try XCTUnwrap(fixture["manifests"] as? [[String: Any]])
            let expected = try XCTUnwrap(fixture["expected"] as? [String: Any])
            let workout = try XCTUnwrap(expected["workout"] as? [String: Any])
            let activities = try XCTUnwrap(workout["activities"] as? [[String: Any]])
            let final = try WatchWire.decode(JSONSerialization.data(withJSONObject: manifests.last!))
            XCTAssertEqual(try WatchWire.decode(WatchWire.encode(final)), final)
            for (interval, activity) in zip(final.intervals!, activities) {
                let actual = WatchHealthMetadata.interval(interval, summaryID: final.summaryID)
                var golden = try XCTUnwrap(activity["metadata"] as? [String: Any])
                golden[WatchHealthMetadata.namespace + "observedAt"] = try WatchWire.date(golden[WatchHealthMetadata.namespace + "observedAt"] as! String)
                XCTAssertTrue(NSDictionary(dictionary: actual).isEqual(to: golden))
                XCTAssertEqual(actual.count, 16)
                XCTAssertTrue(actual[WatchHealthMetadata.namespace + "effectiveTargetSpeedKilometresPerHour"] is NSDecimalNumber)
            }
        }
    }
    func testLegacyPayloadUnchangedAndWatchOwnershipSuppressed() {
        let legacy = HistoryUITestFixtures.syntheticSummary()
        guard case .eligible = WorkoutHealthPayloadFactory.make(summary: legacy, syncVersion: 1) else { return XCTFail("legacy payload") }
        let owned = WorkoutExecutionSummary(id: legacy.id, schemaVersion: 3, sourcePlanID: legacy.sourcePlanID, planSnapshot: legacy.planSnapshot,
            attemptedAt: legacy.attemptedAt, lastUpdatedAt: legacy.lastUpdatedAt, outcome: legacy.outcome, activeDuration: legacy.activeDuration,
            distance: legacy.distance, progress: legacy.progress, physicalStopConfirmation: legacy.physicalStopConfirmation,
            activityTimeline: legacy.activityTimeline, healthExport: .notRequested, ownership: .watchPrimary)
        XCTAssertEqual(WorkoutHealthPayloadFactory.make(summary: owned, syncVersion: 1), .ineligible)
        XCTAssertNil(HistoryHealthExportPresenter.make(summary: owned, isSaving: false)?.actionTitle)
        XCTAssertEqual(owned.replacingHealthExport(with: .notRequested).ownership, .watchPrimary)
    }
}

@MainActor private final class TestClock { var time: TimeInterval = 0 }
@MainActor private final class TestJournal: WatchJournalStore {
    var value: WatchWorkoutJournal?; var saved: [WatchWorkoutJournal] = []; var failNext = false; var failPhase: WatchWorkoutJournal.Phase?
    func load() throws -> WatchWorkoutJournal? { value }
    func save(_ journal: WatchWorkoutJournal) throws {
        if failNext || journal.phase == failPhase { failNext = false; throw WatchStoreError.ambiguous }
        value = journal; saved.append(journal)
    }
}
@MainActor private final class TestRecording: WatchRecordingPort {
    let start: Date; var pauseDate: Date
    var creates = 0, begins = 0, pauses = 0, resumes = 0, discards = 0, finishes = 0, recovers = 0
    var order: [String] = []; var assemblies: [WatchAssembly] = []
    var assemblyFailure: WatchStoreError?; var finishFailure = false; var discardFailure = false; var recoverySource = true
    var holdBegin = false, holdPause = false, holdResume = false
    var startWaiter: CheckedContinuation<Date, Error>?, pauseWaiter: CheckedContinuation<Date, Error>?, resumeWaiter: CheckedContinuation<Void, Error>?
    init(start: Date) { self.start = start; pauseDate = start.addingTimeInterval(60) }
    func prepare(activity: String) async throws { creates += 1 }
    func recover(activity: String) async throws -> (start: Date, sourceExclusion: Bool) { recovers += 1; return (start, recoverySource) }
    func begin() async throws -> Date { begins += 1; if holdBegin { return try await withCheckedThrowingContinuation { startWaiter = $0 } }; return start }
    func pause() async throws -> Date { pauses += 1; if holdPause { return try await withCheckedThrowingContinuation { pauseWaiter = $0 } }; return pauseDate }
    func resume() async throws { resumes += 1; if holdResume { try await withCheckedThrowingContinuation { resumeWaiter = $0 } } }
    func end() { order.append("end") }
    func discard() throws { discards += 1; if discardFailure { throw WatchStoreError.ambiguous } }
    func assemble(_ value: WatchAssembly) async throws { order.append("assemble"); assemblies.append(value); if let assemblyFailure { throw assemblyFailure } }
    func finish() async throws -> String { order.append("finish"); finishes += 1; if finishFailure { throw WatchStoreError.ambiguous }; return "11400000-0000-4000-8000-000000000099" }
}
@MainActor private final class TestPhonePort: PhoneWatchPort {
    var launches = 0; var messages: [WatchWireMessage] = []
    func launch(activity: String) async throws { launches += 1 }
    func send(_ data: Data) { if let m = try? WatchWire.decode(data) { messages.append(m) } }
}

@MainActor private final class TestSessionOperations: WatchSessionOperations {
    var calls: [String] = []
    var collectionStarted = false, ended = false, sourceExcludesDistance = true, hasDistance = false, distanceAuthorized = true
    var activities: [WatchBuilderActivity] = []
    var authorized = true, configuredSourceExcludesDistance = true, addExtraActivity = false, nilFinish = false
    var holdAuthorization = false, holdMirror = false
    var authorizationWaiter: CheckedContinuation<Bool, Error>?, mirrorWaiter: CheckedContinuation<Void, Error>?
    var metadataDistance: Bool?
    func resetForNewAttempt() throws { calls.append("reset") }
    func authorize() async throws -> Bool { calls.append("authorize"); if holdAuthorization { return try await withCheckedThrowingContinuation { authorizationWaiter = $0 } }; return authorized }
    func recoverPrimary() async throws -> WatchRecoveredRecording? { calls.append("recover"); return nil }
    func createPrimary(activity: String) throws { calls.append("create") }
    func configureCollection() throws { calls.append("configure"); sourceExcludesDistance = configuredSourceExcludesDistance }
    func preparePrimary() { calls.append("prepare") }
    func mirrorPrimary() async throws { calls.append("mirror"); if holdMirror { try await withCheckedThrowingContinuation { mirrorWaiter = $0 } } }
    func startPrimary() async throws -> Date { calls.append("start"); return Date(timeIntervalSince1970: 1_780_000_000) }
    func beginCollection(at: Date) async throws { calls.append("collect"); collectionStarted = true }
    func pausePrimary() async throws -> Date { calls.append("pause"); return Date() }
    func resumePrimary() async throws { calls.append("resume") }
    func endPrimary() { calls.append("end"); ended = true }
    func discardBuilder() throws { calls.append("discard") }
    func finishBuilder() async throws -> String? { calls.append("finish"); return nilFinish ? nil : UUID().uuidString }
    func endCollection(at: Date) async throws { calls.append("endCollection") }
    func addActivity(_ interval: WatchInterval, summaryID: String, activity: String) async throws {
        calls.append("activity"); let item = WatchBuilderActivity(start: interval.startedAt, end: interval.endedAt, activity: activity, indoor: true)
        activities.append(item); if addExtraActivity { activities.append(item) }
    }
    func addDistance(metres: Decimal, summaryID: String, start: Date, end: Date) async throws { calls.append("distance") }
    func addMetadata(_ value: WatchAssembly, distanceIncluded: Bool) async throws { calls.append("metadata"); metadataDistance = distanceIncluded }
}
