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
    func testRecoveryDoesNotAcknowledgeBeforeVerificationOrOverwriteConcurrentState() async throws {
        try await bound(); try await receive(manifest(1))
        recording.holdRecovery = true
        var replies: [WatchWireMessage] = []
        let recovered = WatchWorkoutLifecycle(store: store, recording: recording, now: { self.start },
            monotonic: { self.clock.time }, send: { if let m = try? WatchWire.decode($0) { replies.append(m) } })
        let task = Task { await recovered.recover() }
        while recording.recoveryWaiter == nil { await Task.yield() }
        var bind = message(.bind); bind.workoutActivity = "indoorWalking"
        await recovered.receive(try WatchWire.encode(bind))
        await recovered.receive(try WatchWire.encode(manifest(2, intervals: [interval(), interval(1)])))
        await recovered.foreground()
        XCTAssertTrue(replies.isEmpty, "Recovery has not verified the primary; no bound or ACK may escape")
        XCTAssertEqual(recovered.journal?.manifest?.revision, 1)
        recovered.disconnected()
        recovered.recordingState(paused: true)
        recording.recoveryWaiter?.resume(returning: (start, true)); recording.recoveryWaiter = nil
        await task.value
        XCTAssertTrue(recovered.journal?.incomplete == true, "Recovery must preserve a connection gap observed while suspended")
        XCTAssertTrue(recovered.journal?.paused == true)
        await recovered.receive(try WatchWire.encode(bind))
        await recovered.receive(try WatchWire.encode(manifest(2, intervals: [interval(), interval(1)])))
        XCTAssertEqual(replies.filter { $0.kind == .bound }.count, 1)
        XCTAssertEqual(replies.filter { $0.kind == .ack }.last?.revision, 2)
        XCTAssertEqual(store.value?.manifest?.intervals?.count, 2)
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
        XCTAssertEqual(phone.status, "Watch recording end sent. Check the save result on Apple Watch.")
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
        XCTAssertEqual(phone.phase, .confirmed); XCTAssertEqual(phone.status, "Watch recording end sent. Check the save result on Apple Watch.")
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
    func testNextAttemptAfterDiscardWaitsForVerifiedNativeEnd() async throws {
        let ops = TestSessionOperations(); let adapter = WatchRecordingAdapter(operations: ops)
        try await adapter.prepare(activity: "indoorWalking"); _ = try await adapter.begin()
        adapter.end(); try adapter.discard(); ops.holdStop = true
        let before = ops.calls
        var completed = false
        let next = Task { defer { completed = true }; try await adapter.prepare(activity: "indoorWalking") }
        while ops.stopWaiter == nil && !completed { await Task.yield() }
        XCTAssertEqual(ops.calls, before + ["verifiedStop"])
        ops.stopWaiter?.resume(); ops.stopWaiter = nil
        try await next.value
        XCTAssertEqual(ops.calls.filter { $0 == "create" }.count, 2)
        XCTAssertEqual(ops.calls.suffix(8), ["verifiedStop", "reset", "authorize", "recover", "create", "configure", "prepare", "mirror"])
    }
    func testCancelledNextAttemptCannotResetAfterLateDiscardStopProof() async throws {
        let ops = TestSessionOperations(); let adapter = WatchRecordingAdapter(operations: ops)
        try await adapter.prepare(activity: "indoorWalking"); adapter.end(); try adapter.discard(); ops.holdStop = true
        var completed = false
        let next = Task { defer { completed = true }; try await adapter.prepare(activity: "indoorWalking") }
        while ops.stopWaiter == nil && !completed { await Task.yield() }
        adapter.end(); let cancelled = ops.calls
        ops.stopWaiter?.resume(); ops.stopWaiter = nil
        do { try await next.value; XCTFail("Cancelled preparation must fail") } catch {}
        XCTAssertEqual(ops.calls, cancelled)
        XCTAssertEqual(ops.calls.filter { $0 == "create" }.count, 1)
    }

    func testFailedDiscardStopProofCannotResetOrCreateNextPrimary() async throws {
        let ops = TestSessionOperations(); let adapter = WatchRecordingAdapter(operations: ops)
        try await adapter.prepare(activity: "indoorWalking"); adapter.end(); try adapter.discard(); ops.holdStop = true
        var completed = false
        let next = Task { defer { completed = true }; try await adapter.prepare(activity: "indoorWalking") }
        while ops.stopWaiter == nil && !completed { await Task.yield() }
        let pending = ops.calls
        ops.stopWaiter?.resume(throwing: WatchStoreError.ambiguous); ops.stopWaiter = nil
        do { try await next.value; XCTFail("Unverified stop must fail preparation") } catch {}
        XCTAssertEqual(ops.calls, pending)
        XCTAssertEqual(ops.calls.filter { $0 == "reset" }.count, 1)
        XCTAssertEqual(ops.calls.filter { $0 == "create" }.count, 1)
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
    func testLateNativeFailureCannotCancelStopOrOverwriteVerifiedResult() async throws {
        try await bound(); recording.holdStop = true
        let task = Task { await sut.forceStop() }; await Task.yield()
        let ends = recording.order.filter { $0 == "end" }.count
        let stopping = sut.display
        await sut.failed(); sut.recordingState(paused: false); sut.disconnected()
        XCTAssertEqual(sut.display, stopping); XCTAssertTrue(sut.stopping)
        XCTAssertEqual(recording.order.filter { $0 == "end" }.count, ends)
        recording.stopWaiter?.resume(); recording.stopWaiter = nil; await task.value
        let stopped = sut.display
        await sut.failed(); await sut.foreground()
        XCTAssertEqual(sut.display, stopped); XCTAssertTrue(sut.canPrepareNext); XCTAssertFalse(sut.canStop)
    }
    func testNativeFailureDoesNotReenterSavingOrOverwriteReceipt() async throws {
        try await bound(); try await receive(manifest(1)); clock.time = 60; recording.holdAssembly = true
        let task = Task { await sut.endWorkout() }; await Task.yield()
        let ends = recording.order.filter { $0 == "end" }.count
        await sut.failed()
        XCTAssertEqual(recording.order.filter { $0 == "end" }.count, ends)
        XCTAssertEqual(sut.journal?.phase, .assembling)
        recording.assemblyWaiter?.resume(); recording.assemblyWaiter = nil; await task.value
        let receipt = sut.journal; let status = sut.display
        await sut.failed(); sut.recordingState(paused: false); sut.disconnected()
        XCTAssertEqual(sut.journal, receipt); XCTAssertEqual(sut.display, status)
        XCTAssertFalse(sut.canEnd); XCTAssertFalse(sut.canStop); XCTAssertEqual(recording.finishes, 1)
    }
    func testEndPreparationShowsStableEndingStateAndHidesDuplicateEnd() async throws {
        try await bound(); try await prepared(); sut.recordingState(paused: true)
        XCTAssertEqual(sut.display, "Ending workout…"); XCTAssertFalse(sut.canEnd)
        XCTAssertTrue(sut.canStop)
        try await receive(manifest(1, final: true)); var m = message(.finalize); m.revision = 1
        try await receive(m)
        XCTAssertEqual(sut.journal?.phase, .saved); XCTAssertFalse(sut.canStop)
    }
    func testAssemblyWaitsForNativeEndAndCancellationFencesLateProof() async throws {
        let backend = TestSessionOperations(); let adapter = WatchRecordingAdapter(operations: backend)
        try await adapter.prepare(activity: "indoorWalking"); _ = try await adapter.begin(); adapter.end()
        backend.holdStop = true
        let value = WatchAssembly(summaryID: id, activity: "indoorWalking", start: start, end: start.addingTimeInterval(60), intervals: [interval()], revision: 1, complete: true, distance: .unavailable)
        let task = Task { try await adapter.assemble(value) }; await Task.yield()
        XCTAssertFalse(backend.calls.contains("endCollection"))
        // A second explicit stop fences the old save before its native proof arrives.
        backend.holdStop = false; try await adapter.stopAndVerify()
        backend.stopWaiter?.resume(); backend.stopWaiter = nil
        do { try await task.value; XCTFail("old save continued") } catch {}
        XCTAssertFalse(backend.calls.contains("endCollection")); XCTAssertFalse(backend.calls.contains("finish"))
    }
    func testAssemblyContinuesOnlyAfterVerifiedNativeEnd() async throws {
        let backend = TestSessionOperations(); let adapter = WatchRecordingAdapter(operations: backend)
        try await adapter.prepare(activity: "indoorWalking"); _ = try await adapter.begin(); adapter.end()
        backend.holdStop = true
        let value = WatchAssembly(summaryID: id, activity: "indoorWalking", start: start, end: start.addingTimeInterval(60), intervals: [interval()], revision: 1, complete: true, distance: .unavailable)
        let task = Task { try await adapter.assemble(value) }; await Task.yield()
        XCTAssertFalse(backend.calls.contains("endCollection"))
        backend.stopWaiter?.resume(); backend.stopWaiter = nil; try await task.value
        XCTAssertTrue(backend.calls.contains("endCollection")); _ = try await adapter.finish()
        XCTAssertEqual(backend.calls.filter { $0 == "finish" }.count, 1)
    }
    func testStopVerifierUsesAttachedPrimaryWithoutRecoveryProbe() async throws {
        let proof = WatchStopVerifier(); let current = NSObject(); var requested: AnyObject?
        let task = Task {
            try await proof.verify(current: current, probe: { XCTFail("attached session must not be recovered"); throw WatchStoreError.ambiguous },
                                   isEnded: { _ in false }, end: { requested = $0 })
        }
        await Task.yield(); XCTAssertTrue(requested === current)
        proof.observedEnded(current); try await task.value
    }
    func testPairedLifecycleCompletesWithoutWatchTapWhenOneTerminalLegIsLost() async throws {
        for lostKind in [WatchWireMessage.Kind.prepareEnd, .endPrepared, .manifest, .ack, .finalize] {
            try await setUp(); try await bound(); sent.removeAll(); clock.time = 60
            let port = TestPhonePort()
            let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
            await phone.start(activity: "indoorWalking")
            var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
            phone.update(intervals: [interval()], outcome: "stoppedByUser")
            var phoneIndex = 0, watchIndex = 0; var dropped = false
            for step in 0...8 {
                clock.time = 60 + Double(step) * 0.5; phone.tick(); await sut.tick()
                for _ in 0..<3 {
                    while phoneIndex < port.messages.count {
                        let m = port.messages[phoneIndex]; phoneIndex += 1
                        if !dropped && m.kind == lostKind { dropped = true; continue }
                        try await receive(m)
                    }
                    while watchIndex < sent.count {
                        let m = sent[watchIndex]; watchIndex += 1
                        if !dropped && m.kind == lostKind { dropped = true; continue }
                        phone.receive(try WatchWire.encode(m))
                    }
                }
            }
            XCTAssertTrue(dropped, "Lost leg: \(lostKind)")
            XCTAssertEqual(phone.phase, .confirmed); XCTAssertEqual(sut.journal?.phase, .saved)
            XCTAssertEqual(recording.finishes, 1); XCTAssertEqual(recording.assemblies.first?.complete, true)
            XCTAssertFalse(sut.canEnd); XCTAssertFalse(sut.canStop)
        }
    }
    func testPhoneRetriesLostEndMessagesWithoutExtendingDeadline() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
        phone.update(intervals: [interval()], outcome: "completed")
        let end = port.messages.last!; XCTAssertTrue(phone.isEnding)
        clock.time = 1; phone.tick(); XCTAssertEqual(port.messages.last, end)
        var e = message(.endPrepared); e.sequence = end.sequence; e.workoutEnd = recording.pauseDate
        phone.receive(try WatchWire.encode(e)); let final = port.messages.last!
        XCTAssertEqual(final.kind, .manifest)
        clock.time = 2; phone.tick(); XCTAssertEqual(port.messages.last, final)
        var ack = message(.ack); ack.revision = final.revision; phone.receive(try WatchWire.encode(ack))
        let confirmation = port.messages.last!; XCTAssertEqual(confirmation.kind, .finalize)
        clock.time = 3; phone.tick(); XCTAssertEqual(port.messages.last, confirmation)
        let count = port.messages.count; clock.time = 5; phone.tick(); phone.foreground()
        XCTAssertEqual(port.messages.count, count); XCTAssertEqual(phone.phase, .confirmed)
    }
    func testMalformedInputAfterLostFinalizeSuppressesFurtherConfirmationRetries() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
        phone.update(intervals: [interval()], outcome: "completed")
        var e = message(.endPrepared); e.sequence = 1; e.workoutEnd = recording.pauseDate; phone.receive(try WatchWire.encode(e))
        var ack = message(.ack); ack.revision = port.messages.last!.revision; phone.receive(try WatchWire.encode(ack))
        XCTAssertEqual(port.messages.last?.kind, .finalize)
        phone.receive(Data("malformed".utf8)); XCTAssertTrue(phone.integrityFailed)
        let count = port.messages.count; clock.time = 1; phone.tick(); phone.foreground()
        XCTAssertEqual(port.messages.count, count)
        XCTAssertEqual(phone.phase, .confirmed) // Earlier send remains uncertain, never retracted or replaced.
    }
    func testLostPrepareEndRetriesStopAtOriginalDeadline() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
        phone.update(intervals: [interval()], outcome: "stoppedByUser")
        for t in 1...4 { clock.time = Double(t); phone.tick() }
        XCTAssertEqual(port.messages.filter { $0.kind == .prepareEnd }.count, 5)
        clock.time = 5; phone.tick(); XCTAssertEqual(phone.phase, .unavailable)
        let count = port.messages.count; clock.time = 10; phone.tick(); XCTAssertEqual(port.messages.count, count)
    }
    func testForceStopPreservesUncertainAttemptAndRequiresExplicitRetirement() async throws {
        try await bound(); try await receive(manifest(1)); await sut.forceStop()
        XCTAssertEqual(recording.finishes, 0); XCTAssertEqual(recording.discards, 0)
        XCTAssertEqual(sut.journal?.phase, .ambiguous); XCTAssertTrue(sut.canPrepareNext)
        await sut.launch(activity: "indoorWalking"); XCTAssertEqual(recording.creates, 1)
        sut.prepareNextWorkout()
        XCTAssertEqual(store.archives.first?.summaryID, id); XCTAssertEqual(store.archives.first?.phase, .ambiguous)
        XCTAssertEqual(sut.journal?.phase, .retired); XCTAssertFalse(sut.canStop)
        await sut.launch(activity: "indoorWalking"); XCTAssertEqual(recording.creates, 2)
        XCTAssertNil(sut.journal?.summaryID); XCTAssertEqual(sut.journal?.phase, .unbound)
        var oldBind = message(.bind); oldBind.workoutActivity = "indoorWalking"; try await receive(oldBind)
        XCTAssertNil(sut.journal?.summaryID); XCTAssertEqual(recording.begins, 1)
        var fresh = WatchWireMessage(.bind, summaryID: "11400000-0000-4000-8000-000000000002"); fresh.workoutActivity = "indoorWalking"
        try await receive(fresh); XCTAssertEqual(recording.begins, 2)
    }
    func testFailedArchiveOrRetirementWriteDoesNotPermitNewAttempt() async throws {
        try await bound(); await sut.forceStop(); store.failArchive = true
        sut.prepareNextWorkout(); await sut.launch(activity: "indoorWalking")
        XCTAssertEqual(recording.creates, 1); XCTAssertEqual(sut.journal?.phase, .ambiguous)
        store.failArchive = false; store.failPhase = .retired
        sut.prepareNextWorkout(); XCTAssertEqual(sut.journal?.phase, .ambiguous)
        store.failPhase = nil; sut.prepareNextWorkout(); XCTAssertEqual(sut.journal?.phase, .retired)
    }
    func testHungStopDoubleTapAndForegroundTimeoutNeverClaimStopped() async throws {
        try await bound(); recording.holdStop = true
        let task = Task { await sut.forceStop() }; await Task.yield()
        await sut.forceStop(); XCTAssertEqual(recording.order.filter { $0 == "verifiedStop" }.count, 1)
        XCTAssertFalse(sut.canPrepareNext); clock.time = 16; await sut.foreground()
        XCTAssertFalse(sut.stopVerified); XCTAssertTrue(sut.canStop)
        recording.stopWaiter?.resume(); recording.stopWaiter = nil; await task.value
        XCTAssertFalse(sut.stopVerified); XCTAssertEqual(sut.journal?.phase, .ambiguous)
    }
    func testLatePreparationAfterStopAndNewAttemptCannotChangeNewJournal() async throws {
        recording.holdPrepare = true
        let old = Task { await sut.launch(activity: "indoorWalking") }; await Task.yield()
        await sut.forceStop(); sut.prepareNextWorkout(); recording.holdPrepare = false
        await sut.launch(activity: "indoorWalking"); let current = sut.journal; let calls = recording.order
        recording.prepareWaiter?.resume(throwing: WatchStoreError.definite); recording.prepareWaiter = nil; await old.value
        XCTAssertEqual(sut.journal, current); XCTAssertEqual(recording.order, calls); XCTAssertEqual(recording.discards, 0)
    }
    func testLateStartAfterStopAndNewAttemptCannotBindOldIdentity() async throws {
        await sut.launch(activity: "indoorWalking"); recording.holdBegin = true
        var b = message(.bind); b.workoutActivity = "indoorWalking"; let bytes = try WatchWire.encode(b)
        let old = Task { await sut.receive(bytes) }; await Task.yield()
        await sut.forceStop(); sut.prepareNextWorkout(); await sut.launch(activity: "indoorWalking")
        let current = sut.journal; recording.startWaiter?.resume(returning: start); recording.startWaiter = nil; await old.value
        XCTAssertEqual(sut.journal, current); XCTAssertFalse(sent.contains { $0.kind == .bound })
    }
    func testLateRecoveryErrorAfterStopCannotQuarantineNewAttempt() async throws {
        try await bound(); recording.holdRecovery = true
        let recovered = WatchWorkoutLifecycle(store: store, recording: recording, now: { self.start }, monotonic: { self.clock.time }, send: { _ in })
        let old = Task { await recovered.recover() }; await Task.yield()
        await recovered.forceStop(); recovered.prepareNextWorkout(); await recovered.launch(activity: "indoorWalking")
        let current = recovered.journal
        recording.recoveryWaiter?.resume(throwing: WatchStoreError.ambiguous); recording.recoveryWaiter = nil; await old.value
        XCTAssertEqual(recovered.journal, current)
    }
    func testLateAssemblyAfterStopCannotFinishOrOverwriteNewAttempt() async throws {
        try await bound(); try await receive(manifest(1)); clock.time = 60; recording.holdAssembly = true
        let old = Task { await sut.endWorkout() }; await Task.yield()
        XCTAssertTrue(sut.canStop); XCTAssertFalse(sut.canEnd)
        await sut.forceStop(); sut.prepareNextWorkout(); await sut.launch(activity: "indoorWalking")
        let current = sut.journal; recording.assemblyWaiter?.resume(); recording.assemblyWaiter = nil; await old.value
        XCTAssertEqual(sut.journal, current); XCTAssertEqual(recording.finishes, 0)
    }
    func testLateFinishAfterDeadlineAndRetirementDoesNotClaimNewSave() async throws {
        try await bound(); try await receive(manifest(1)); clock.time = 60; recording.holdFinish = true
        let old = Task { await sut.endWorkout() }; await Task.yield()
        XCTAssertEqual(sut.journal?.phase, .finishing); clock.time = 76; await sut.tick()
        XCTAssertEqual(sut.journal?.phase, .ambiguous); XCTAssertTrue(sut.canStop)
        await sut.forceStop(); sut.prepareNextWorkout(); await sut.launch(activity: "indoorWalking")
        let current = sut.journal
        recording.finishWaiter?.resume(returning: UUID().uuidString); recording.finishWaiter = nil; await old.value
        XCTAssertEqual(sut.journal, current); XCTAssertEqual(recording.finishes, 1)
        XCTAssertEqual(store.archives.first?.summaryID, id)
    }
    func testNativeAdapterAssemblyFenceStopsAfterEachSuspension() async throws {
        for stopAtActivity in [false, true] {
            let ops = TestSessionOperations(); let adapter = WatchRecordingAdapter(operations: ops)
            try await adapter.prepare(activity: "indoorWalking"); _ = try await adapter.begin(); adapter.end()
            ops.holdEndCollection = !stopAtActivity; ops.holdActivity = stopAtActivity
            let assembly = WatchAssembly(summaryID: id, activity: "indoorWalking", start: start, end: start.addingTimeInterval(60), intervals: [interval()], revision: 1, complete: false, distance: .unavailable)
            let old = Task { try await adapter.assemble(assembly) }; await Task.yield()
            try await adapter.stopAndVerify(); try adapter.releaseStopped()
            ops.activities = []; let before = ops.calls.count
            ops.builderWaiter?.resume(); ops.builderWaiter = nil
            do { try await old.value; XCTFail("stale assembly accepted") } catch {}
            XCTAssertEqual(ops.calls.count, before)
            XCTAssertFalse(ops.calls.contains("metadata")); XCTAssertFalse(ops.calls.contains("finish"))
        }
    }
    func testForegroundAndOSReconnectDoNotStartExecutionAgain() async throws {
        let port = TestPhonePort(); var starts = 0; var reserves = 0
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in reserves += 1 }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        phone.bound = { _ in starts += 1 }; await phone.start(activity: "indoorWalking")
        var b = message(.bound); b.workoutStart = start; let bytes = try WatchWire.encode(b); phone.receive(bytes)
        phone.disconnect(); XCTAssertEqual(phone.phase, .reconnecting)
        XCTAssertTrue(phone.acceptsMirror(activity: "indoorWalking", indoor: true, start: start))
        XCTAssertFalse(phone.acceptsMirror(activity: "indoorWalking", indoor: true, start: start.addingTimeInterval(1)))
        XCTAssertFalse(phone.acceptsMirror(activity: "indoorRunning", indoor: true, start: start))
        phone.update(intervals: [interval()], outcome: nil); phone.mirrorConnected(); phone.receive(bytes); phone.foreground()
        XCTAssertEqual(phone.phase, .bound); XCTAssertEqual(starts, 1); XCTAssertEqual(reserves, 1); XCTAssertEqual(port.launches, 1)
        XCTAssertEqual(port.messages.last(where: { $0.kind == .manifest })?.intervals, [interval()])
    }
    func testLostManifestAckRetriesSameRevisionAndStopsWhenAcknowledged() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
        phone.update(intervals: [interval()], outcome: nil); let first = port.messages.last!
        clock.time = 5; phone.foreground()
        XCTAssertEqual(port.messages.filter { $0.kind == .manifest }, [first, first])
        var ack = message(.ack); ack.revision = first.revision; phone.receive(try WatchWire.encode(ack))
        clock.time = 10; phone.tick(); XCTAssertEqual(port.messages.filter { $0.kind == .manifest }.count, 2)
    }
    func testReconnectDeadlineAndIntegrityFailureCannotBeClearedByForeground() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); var b = message(.bound); b.workoutStart = start; let bytes = try WatchWire.encode(b); phone.receive(bytes)
        phone.receive(Data("bad".utf8)); phone.disconnect(); clock.time = 10; phone.disconnect()
        clock.time = 30; phone.foreground(); phone.receive(bytes)
        XCTAssertEqual(phone.phase, .unavailable); XCTAssertTrue(phone.integrityFailed)
        XCTAssertFalse(phone.acceptsReplacementMirror); XCTAssertEqual(port.launches, 1)
    }
    func testDisconnectDuringEndPreparationNeverReopensFinalDeadline() async throws {
        let port = TestPhonePort()
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        await phone.start(activity: "indoorWalking"); var b = message(.bound); b.workoutStart = start; phone.receive(try WatchWire.encode(b))
        phone.update(intervals: [interval()], outcome: "completed"); phone.disconnect(); phone.foreground(); phone.receive(try WatchWire.encode(b))
        XCTAssertEqual(phone.phase, .unavailable); XCTAssertFalse(port.messages.contains { $0.kind == .finalize })
    }
    func testProtectedJournalLegacyMigrationAndIdempotentArchive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = ProtectedWatchJournal(directory: { root })
        var legacy = WatchWorkoutJournal(activity: "indoorWalking"); legacy.formatVersion = 1; legacy.phase = .ambiguous; legacy.summaryID = id
        try WatchProtectedFile(url: root.appendingPathComponent("watch-journal-v1.json")).write(JSONEncoder().encode(legacy))
        XCTAssertEqual(try disk.load(), legacy); try disk.archive(legacy); try disk.archive(legacy)
        var retired = legacy; retired.formatVersion = 2; retired.phase = .retired; try disk.save(retired)
        XCTAssertEqual(try disk.load(), retired)
        XCTAssertTrue(try disk.containsRetiredIdentity(id))
        let archive = root.appendingPathComponent("retired-attempts-v1").appendingPathComponent(id + ".json")
        XCTAssertEqual(try JSONDecoder().decode(WatchWorkoutJournal.self, from: Data(contentsOf: archive)), legacy)
        XCTAssertEqual(try archive.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        var conflict = legacy; conflict.incomplete = true; XCTAssertThrowsError(try disk.archive(conflict))
        try Data("partial".utf8).write(to: root.appendingPathComponent("watch-journal-v2.json.staging"))
        XCTAssertThrowsError(try disk.load())
    }

    func testFinishDeadlineIsCheckedBeforeAcceptingCallbackWithoutTick() async throws {
        try await bound(); try await receive(manifest(1)); clock.time = 60; recording.holdFinish = true
        let task = Task { await sut.endWorkout() }; await Task.yield()
        clock.time = 76
        recording.finishWaiter?.resume(returning: UUID().uuidString); recording.finishWaiter = nil; await task.value
        XCTAssertEqual(sut.journal?.phase, .ambiguous); XCTAssertNil(sut.journal?.savedWorkoutID)
        XCTAssertTrue(sut.canStop); XCTAssertEqual(recording.finishes, 1)
    }
    func testStopDeadlineIsCheckedBeforeAcceptingCallbackWithoutTick() async throws {
        try await bound(); recording.holdStop = true
        let task = Task { await sut.forceStop() }; await Task.yield(); clock.time = 16
        recording.stopWaiter?.resume(); recording.stopWaiter = nil; await task.value
        XCTAssertFalse(sut.canPrepareNext); XCTAssertFalse(sut.stopVerified); XCTAssertTrue(sut.canStop)
    }
    func testRecoveryDeadlineIsCheckedBeforeAcceptingCallbackWithoutTick() async throws {
        try await bound(); recording.holdRecovery = true
        let recovered = WatchWorkoutLifecycle(store: store, recording: recording, now: { self.start }, monotonic: { self.clock.time }, send: { _ in })
        let task = Task { await recovered.recover() }; await Task.yield(); clock.time = 16
        recording.recoveryWaiter?.resume(returning: (start, true)); recording.recoveryWaiter = nil; await task.value
        XCTAssertEqual(recovered.journal?.phase, .ambiguous); XCTAssertTrue(recovered.canStop); XCTAssertFalse(recovered.canEnd)
    }
    func testStopProbeAndReleaseFailureCannotRetireOrStartAnotherAttempt() async throws {
        try await bound(); recording.stopFailure = true; await sut.forceStop()
        XCTAssertFalse(sut.canPrepareNext); sut.prepareNextWorkout(); XCTAssertTrue(store.archives.isEmpty)
        await sut.launch(activity: "indoorWalking"); XCTAssertEqual(recording.creates, 1)
        recording.stopFailure = false; await sut.forceStop(); recording.releaseFailure = true
        sut.prepareNextWorkout(); XCTAssertEqual(store.value?.phase, .ambiguous)
        XCTAssertEqual(sut.journal?.phase, .ambiguous)
        recording.releaseFailure = false; sut.prepareNextWorkout(); XCTAssertEqual(store.value?.phase, .retired)
    }
    func testStopVerifierRequiresExactEndedObject() async throws {
        let proof = WatchStopVerifier(); let current = NSObject(); let stale = NSObject()
        var ended: AnyObject?; var completed = false
        let task = Task {
            try await proof.verify(probe: { current }, isEnded: { _ in false }, end: { ended = $0 })
            completed = true
        }
        await Task.yield(); XCTAssertTrue(ended === current)
        proof.observedEnded(stale); await Task.yield(); XCTAssertFalse(completed)
        proof.observedEnded(current); try await task.value; XCTAssertTrue(completed)
    }
    func testStopVerifierNilEndedAndProbeError() async throws {
        let proof = WatchStopVerifier(); let current = NSObject(); var endCalls = 0
        try await proof.verify(probe: { nil }, isEnded: { _ in false }, end: { _ in endCalls += 1 })
        try await proof.verify(probe: { current }, isEnded: { _ in true }, end: { _ in endCalls += 1 })
        XCTAssertEqual(endCalls, 0)
        do {
            try await proof.verify(probe: { throw WatchStoreError.ambiguous }, isEnded: { _ in false }, end: { _ in endCalls += 1 })
            XCTFail("probe error accepted")
        } catch {}
        XCTAssertEqual(endCalls, 0)
    }
    func testStopVerifierCancelledProbeNeverEndsItsLateResult() async throws {
        let proof = WatchStopVerifier(); var waiter: CheckedContinuation<AnyObject?, Error>?; var endCalls = 0
        let old = Task { try await proof.verify(probe: { try await withCheckedThrowingContinuation { waiter = $0 } }, isEnded: { _ in false }, end: { _ in endCalls += 1 }) }
        await Task.yield(); proof.cancel()
        try await proof.verify(probe: { nil }, isEnded: { _ in false }, end: { _ in endCalls += 1 })
        waiter?.resume(returning: NSObject()); waiter = nil
        do { try await old.value; XCTFail("late probe accepted") } catch {}
        XCTAssertEqual(endCalls, 0)
    }
    func testStopVerifierCancelledWaitRejectsLateEndedCallback() async throws {
        let proof = WatchStopVerifier(); let oldSession = NSObject(); let newSession = NSObject(); var finished = false
        let old = Task { try await proof.verify(probe: { oldSession }, isEnded: { _ in false }, end: { _ in }) }
        await Task.yield(); proof.cancel()
        do { try await old.value; XCTFail("cancelled stop accepted") } catch {}
        let next = Task { try await proof.verify(probe: { newSession }, isEnded: { _ in false }, end: { _ in }); finished = true }
        await Task.yield(); proof.observedEnded(oldSession); await Task.yield(); XCTAssertFalse(finished)
        proof.observedEnded(newSession); try await next.value; XCTAssertTrue(finished)
    }
    func testRepeatedAdapterReleaseAfterStorageFailureIsIdempotent() async throws {
        let ops = TestSessionOperations(); let adapter = WatchRecordingAdapter(operations: ops)
        try await adapter.prepare(activity: "indoorWalking"); adapter.end(); try await adapter.stopAndVerify()
        try adapter.releaseStopped(); let count = ops.calls.count; try adapter.releaseStopped()
        XCTAssertEqual(ops.calls.count, count)
        try await adapter.prepare(activity: "indoorWalking"); XCTAssertEqual(ops.calls.filter { $0 == "create" }.count, 2)
    }
    func testColdPhoneAndWrongIdentityNeverAcceptMirrorOrBeginExecution() async throws {
        let port = TestPhonePort(); var starts = 0
        let phone = PhoneWatchLifecycle(port: port, reserve: { _ in }, makeID: { UUID(uuidString: self.id)! }, monotonic: { self.clock.time })
        phone.bound = { _ in starts += 1 }
        XCTAssertFalse(phone.acceptsMirror(activity: "indoorWalking", indoor: true, start: start))
        phone.foreground(); phone.mirrorConnected(); XCTAssertTrue(port.messages.isEmpty)
        await phone.start(activity: "indoorWalking")
        var b = WatchWireMessage(.bound, summaryID: "11400000-0000-4000-8000-000000000002"); b.workoutStart = start
        phone.receive(try WatchWire.encode(b)); XCTAssertEqual(starts, 0); XCTAssertTrue(phone.integrityFailed)
    }

    func testLatePauseFailureCannotMarkNewBoundAttemptIncomplete() async throws {
        try await bound(); recording.holdPause = true
        var pause = message(.recordingState); pause.sequence = 1; pause.state = "paused"; pause.observedAt = start
        let data = try WatchWire.encode(pause); let old = Task { await sut.receive(data) }; await Task.yield()
        await sut.forceStop(); sut.prepareNextWorkout(); await sut.launch(activity: "indoorWalking")
        var fresh = WatchWireMessage(.bind, summaryID: "11400000-0000-4000-8000-000000000002"); fresh.workoutActivity = "indoorWalking"
        try await receive(fresh); let current = sut.journal; XCTAssertFalse(current!.incomplete)
        recording.pauseWaiter?.resume(throwing: WatchStoreError.ambiguous); recording.pauseWaiter = nil; await old.value
        XCTAssertEqual(sut.journal, current); XCTAssertEqual(sut.journal?.phase, .recording)
    }
    func testArchiveLimitNeverEvictsAnUncertainIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = ProtectedWatchJournal(directory: { root })
        for index in 0..<64 {
            var journal = WatchWorkoutJournal(activity: "indoorWalking", attemptID: String(format: "11400000-0000-4000-8000-%012d", index))
            journal.phase = .ambiguous; try disk.archive(journal)
        }
        var extra = WatchWorkoutJournal(activity: "indoorWalking", attemptID: "11400000-0000-4000-8000-999999999999"); extra.phase = .ambiguous
        XCTAssertThrowsError(try disk.archive(extra))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("retired-attempts-v1").path).count, 64)
    }

}

@MainActor private final class TestClock { var time: TimeInterval = 0 }
@MainActor private final class TestJournal: WatchJournalStore {
    var value: WatchWorkoutJournal?; var saved: [WatchWorkoutJournal] = []; var failNext = false; var failPhase: WatchWorkoutJournal.Phase?
    var archives: [WatchWorkoutJournal] = []; var failArchive = false
    func containsRetiredIdentity(_ summaryID: String) throws -> Bool { archives.contains { $0.summaryID == summaryID } }
    func archive(_ journal: WatchWorkoutJournal) throws { if failArchive { throw WatchStoreError.ambiguous }; archives.append(journal) }
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
    var stopFailure = false, releaseFailure = false
    var holdPrepare = false, holdRecovery = false, holdAssembly = false, holdFinish = false, holdStop = false
    var prepareWaiter: CheckedContinuation<Void, Error>?, assemblyWaiter: CheckedContinuation<Void, Error>?, stopWaiter: CheckedContinuation<Void, Error>?
    var recoveryWaiter: CheckedContinuation<(start: Date, sourceExclusion: Bool), Error>?, finishWaiter: CheckedContinuation<String, Error>?
    var holdBegin = false, holdPause = false, holdResume = false
    var startWaiter: CheckedContinuation<Date, Error>?, pauseWaiter: CheckedContinuation<Date, Error>?, resumeWaiter: CheckedContinuation<Void, Error>?
    init(start: Date) { self.start = start; pauseDate = start.addingTimeInterval(60) }
    func stopAndVerify() async throws { order.append("verifiedStop"); if stopFailure { throw WatchStoreError.ambiguous }; if holdStop { try await withCheckedThrowingContinuation { stopWaiter = $0 } } }
    func releaseStopped() throws { order.append("release"); if releaseFailure { throw WatchStoreError.ambiguous } }
    func prepare(activity: String) async throws { creates += 1; if holdPrepare { try await withCheckedThrowingContinuation { prepareWaiter = $0 } } }
    func recover(activity: String) async throws -> (start: Date, sourceExclusion: Bool) { recovers += 1; if holdRecovery { return try await withCheckedThrowingContinuation { recoveryWaiter = $0 } }; return (start, recoverySource) }
    func begin() async throws -> Date { begins += 1; if holdBegin { return try await withCheckedThrowingContinuation { startWaiter = $0 } }; return start }
    func pause() async throws -> Date { pauses += 1; if holdPause { return try await withCheckedThrowingContinuation { pauseWaiter = $0 } }; return pauseDate }
    func resume() async throws { resumes += 1; if holdResume { try await withCheckedThrowingContinuation { resumeWaiter = $0 } } }
    func end() { order.append("end") }
    func discard() throws { discards += 1; if discardFailure { throw WatchStoreError.ambiguous } }
    func assemble(_ value: WatchAssembly) async throws { order.append("assemble"); assemblies.append(value); if holdAssembly { try await withCheckedThrowingContinuation { assemblyWaiter = $0 } }; if let assemblyFailure { throw assemblyFailure } }
    func finish() async throws -> String { order.append("finish"); finishes += 1; if holdFinish { return try await withCheckedThrowingContinuation { finishWaiter = $0 } }; if finishFailure { throw WatchStoreError.ambiguous }; return "11400000-0000-4000-8000-000000000099" }
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
    var holdAuthorization = false, holdMirror = false, holdStop = false
    var stopWaiter: CheckedContinuation<Void, Error>?
    var authorizationWaiter: CheckedContinuation<Bool, Error>?, mirrorWaiter: CheckedContinuation<Void, Error>?
    var holdEndCollection = false, holdActivity = false
    var builderWaiter: CheckedContinuation<Void, Error>?
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
    func stopPrimaryAndVerify() async throws { calls.append("verifiedStop"); if holdStop { try await withCheckedThrowingContinuation { stopWaiter = $0 } }; ended = true }
    func discardBuilder() throws { calls.append("discard") }
    func finishBuilder() async throws -> String? { calls.append("finish"); return nilFinish ? nil : UUID().uuidString }
    func endCollection(at: Date) async throws { calls.append("endCollection"); if holdEndCollection { try await withCheckedThrowingContinuation { builderWaiter = $0 } } }
    func addActivity(_ interval: WatchInterval, summaryID: String, activity: String) async throws {
        calls.append("activity"); if holdActivity { try await withCheckedThrowingContinuation { builderWaiter = $0 } }; let item = WatchBuilderActivity(start: interval.startedAt, end: interval.endedAt, activity: activity, indoor: true)
        activities.append(item); if addExtraActivity { activities.append(item) }
    }
    func addDistance(metres: Decimal, summaryID: String, start: Date, end: Date) async throws { calls.append("distance") }
    func addMetadata(_ value: WatchAssembly, distanceIncluded: Bool) async throws { calls.append("metadata"); metadataDistance = distanceIncluded }
}
