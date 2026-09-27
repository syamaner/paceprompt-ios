import Foundation
import XCTest
@testable import PacePrompt

@MainActor
final class PlanningProfileTests: XCTestCase {
    private let peer = "00000000-0000-0000-0000-000000000141"
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(maximum: Int = 1800, increment: Int = 10, date: Date? = nil) -> PlanningProfileSnapshot {
        .init(speed: .init(minimumHundredthsKph: 50, maximumHundredthsKph: maximum, incrementHundredthsKph: increment),
              inclination: .init(minimumTenthsPercent: -10, maximumTenthsPercent: 150, incrementTenthsPercent: 5),
              observedAt: PlanningProfileSnapshot.timestamp(date ?? instant))
    }
    private func store() -> PlanningProfileStore {
        .init(installationSecret: Array(repeating: 42, count: 32), storeRevision: 0, lastSelectedProfileID: nil,
              records: [.init(profileID: "00000000-0000-0000-0000-000000000001", machineKey: String(repeating: "a", count: 64),
                              name: "Treadmill 1", recordRevision: 1, snapshot: snapshot())])
    }
    private func model(_ repository: any PlanningProfileRepository) -> PlanningProfilesViewModel {
        PlanningProfilesViewModel(repository: repository, identity: TestIdentity(), now: { self.instant })
    }
    func testRepositoryContractForMemoryAndFile() throws {
        try contract(MemoryPlanningProfileRepository())
        let files = ProfileTestFiles()
        try contract(FilePlanningProfileRepository(directory: URL(fileURLWithPath: "/synthetic/PlanningProfiles"), files: files,
                                                  protectedDataAvailable: { true }))
    }
    private func contract(_ repository: any PlanningProfileRepository) throws {
        XCTAssertNil(try repository.load())
        var first = store()
        try repository.commit(first, expectedRevision: nil)
        XCTAssertEqual(try repository.load(), first)
        XCTAssertThrowsError(try repository.commit(first, expectedRevision: nil))
        var invalidMutation = first
        invalidMutation.storeRevision += 1
        invalidMutation.records[0].recordRevision += 1
        invalidMutation.records[0] = PlanningProfile(profileID: invalidMutation.records[0].id,
            machineKey: String(repeating: "b", count: 64), name: first.records[0].name,
            recordRevision: 2, snapshot: first.records[0].snapshot)
        XCTAssertThrowsError(try repository.commit(invalidMutation, expectedRevision: 0))
        invalidMutation = first; invalidMutation.storeRevision += 1; invalidMutation.records[0].name = "unversioned change"
        XCTAssertThrowsError(try repository.commit(invalidMutation, expectedRevision: 0))
        invalidMutation = first; invalidMutation.storeRevision += 1; invalidMutation.records[0].name = ""
        XCTAssertThrowsError(try repository.commit(invalidMutation, expectedRevision: 0))
        XCTAssertEqual(try repository.load(), first)
        first.records[0].name = "Renamed"
        first.records[0].recordRevision += 1
        first.lastSelectedProfileID = first.records[0].id
        first.storeRevision += 1
        try repository.commit(first, expectedRevision: 0)
        XCTAssertEqual(try repository.load(), first)
        var stale = first
        stale.storeRevision += 1
        XCTAssertThrowsError(try repository.commit(stale, expectedRevision: 0))
        first.records.removeAll()
        first.lastSelectedProfileID = nil
        first.storeRevision += 1
        try repository.commit(first, expectedRevision: 1)
        XCTAssertEqual(try repository.load()?.records, [])
        XCTAssertNil(try repository.load()?.lastSelectedProfileID)
    }
    func testOpaqueIdentityIsInstallationScopedAndCanonical() throws {
        let identity = LocalPlanningProfileIdentity()
        let secret = Array(repeating: UInt8(1), count: 32)
        let key = try identity.machineKey(peer: peer, secret: secret)
        XCTAssertEqual(key.count, 64)
        XCTAssertEqual(key, try identity.machineKey(peer: peer.uppercased(), secret: secret))
        XCTAssertNotEqual(key, try identity.machineKey(peer: peer, secret: Array(repeating: 2, count: 32)))
        XCTAssertNotEqual(key, try identity.machineKey(peer: "00000000-0000-0000-0000-000000000142", secret: secret))
        XCTAssertThrowsError(try identity.machineKey(peer: "not a UUID", secret: secret))
        XCTAssertThrowsError(try identity.machineKey(peer: peer, secret: []))
        XCTAssertEqual(try identity.newSecret().count, 32)
    }
    func testDiscoveryDeduplicatesRefreshesAndRequiresChangeReview() throws {
        let repository = MemoryPlanningProfileRepository()
        let model = model(repository)
        model.beginDiscovery(peer: peer)
        model.observe(snapshot(), peer: peer)
        let original = try XCTUnwrap(model.records.first)
        XCTAssertEqual(model.createdProfileID, original.id)
        XCTAssertNil(model.store?.lastSelectedProfileID)
        model.observe(snapshot(), peer: peer)
        XCTAssertEqual(model.records, [original])
        model.dismissCreated()
        model.beginDiscovery(peer: peer)
        model.observe(snapshot(date: instant.addingTimeInterval(100)), peer: peer)
        let refreshed = try XCTUnwrap(model.records.first)
        XCTAssertEqual(refreshed.id, original.id)
        XCTAssertEqual(refreshed.recordRevision, 2)
        XCTAssertNotEqual(refreshed.snapshot.observedAt, original.snapshot.observedAt)
        model.beginDiscovery(peer: peer)
        let changed = snapshot(increment: 20, date: instant.addingTimeInterval(200))
        model.observe(changed, peer: peer)
        XCTAssertEqual(model.records, [refreshed])
        XCTAssertNotNil(model.review)
        model.keepSaved()
        XCTAssertEqual(model.records, [refreshed])
        model.beginDiscovery(peer: peer)
        model.observe(changed, peer: peer)
        model.updateReviewed()
        XCTAssertEqual(model.records[0].snapshot, changed)
        XCTAssertEqual(model.records[0].id, original.id)
        XCTAssertEqual(model.records[0].name, original.name)
    }
    func testRenameRaceAndDisconnectInvalidateReviewWithoutOverwrite() throws {
        let model = model(MemoryPlanningProfileRepository())
        model.beginDiscovery(peer: peer); model.observe(snapshot(), peer: peer)
        let first = try XCTUnwrap(model.records.first)
        model.beginDiscovery(peer: peer); model.observe(snapshot(maximum: 2000), peer: peer)
        XCTAssertTrue(model.rename(first, to: "Private synthetic name"))
        model.updateReviewed()
        XCTAssertEqual(model.failure, .conflict)
        XCTAssertEqual(model.records[0].name, "Private synthetic name")
        XCTAssertEqual(model.records[0].snapshot, first.snapshot)
        model.beginDiscovery(peer: peer); model.observe(snapshot(maximum: 2000), peer: peer)
        model.invalidateDiscovery(); model.updateReviewed()
        XCTAssertEqual(model.records[0].snapshot, first.snapshot)
    }
    func testDeletionClearsSelectionConsumesGenerationAndAllowsLaterExplicitDiscovery() throws {
        let model = model(MemoryPlanningProfileRepository())
        model.beginDiscovery(peer: peer); model.observe(snapshot(), peer: peer)
        let first = try XCTUnwrap(model.records.first)
        XCTAssertTrue(model.selectCreated(first.id))
        XCTAssertTrue(model.delete(first))
        XCTAssertEqual(model.selectedName, "No treadmill selected")
        model.observe(snapshot(), peer: peer)
        XCTAssertTrue(model.records.isEmpty)
        model.beginDiscovery(peer: peer); model.observe(snapshot(), peer: peer)
        XCTAssertEqual(model.records.count, 1)
        XCTAssertNotEqual(model.records[0].id, first.id)
    }
    func testRenameValidationAndDuplicateDisplayNames() throws {
        let model = model(MemoryPlanningProfileRepository())
        model.beginDiscovery(peer: peer); model.observe(snapshot(), peer: peer)
        let first = try XCTUnwrap(model.records.first)
        for invalid in ["", "\n", "a\nb", "a\u{2028}b", "a\u{2029}b", String(repeating: "a", count: 81), "bad\u{0}"] {
            XCTAssertFalse(model.rename(first, to: invalid))
            XCTAssertEqual(model.records[0], first)
        }
        XCTAssertTrue(model.rename(first, to: "  Synthetic  "))
        XCTAssertEqual(model.records[0].name, "Synthetic")
        XCTAssertEqual(model.records[0].snapshot, first.snapshot)
        model.reload()
        model.beginDiscovery(peer: "00000000-0000-0000-0000-000000000142"); model.observe(snapshot(), peer: "00000000-0000-0000-0000-000000000142")
        XCTAssertTrue(model.rename(model.records[1], to: "Synthetic"))
        XCTAssertEqual(model.records.map(\.name), ["Synthetic", "Synthetic"])
    }
    func testSnapshotBoundsZeroWidthAndAge() throws {
        XCTAssertNoThrow(try snapshot(maximum: 50).validate())
        XCTAssertThrowsError(try snapshot(maximum: 49).validate())
        XCTAssertThrowsError(try snapshot(increment: 0).validate())
        XCTAssertThrowsError(try snapshot(maximum: 65536).validate())
        XCTAssertNil(snapshot().ageWarning(at: instant.addingTimeInterval(30 * 86400 - 0.001)))
        XCTAssertNotNil(snapshot().ageWarning(at: instant.addingTimeInterval(30 * 86400)))
        XCTAssertEqual(snapshot().ageWarning(at: instant.addingTimeInterval(-1)), "Confirmation date cannot be verified")
    }
    func testStrictCodecRejectsCorruptionUnknownFieldsVersionsDuplicatesAndLimits() throws {
        let codec = PlanningProfileCodec()
        let bytes = try codec.encode(store())
        XCTAssertEqual(try codec.decode(bytes), store())
        XCTAssertThrowsError(try codec.decode(Data(#"{"formatVersion":2,"futureFields":true}"#.utf8))) {
            XCTAssertEqual($0 as? PlanningProfileFailure, .unsupportedVersion)
        }
        let futureSnapshot = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"snapshotVersion\":1", with: "\"snapshotVersion\":2,\"futureField\":true")
        XCTAssertThrowsError(try codec.decode(Data(futureSnapshot.utf8))) {
            XCTAssertEqual($0 as? PlanningProfileFailure, .unsupportedVersion)
        }
        let text = String(decoding: bytes, as: UTF8.self)
        for invalid in [text.replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":2"),
                        text.replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":1,\"formatVersion\":1"),
                        text.replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":1,\"unexpected\":0"),
                        text.replacingOccurrences(of: "\"snapshotVersion\":1", with: "\"snapshotVersion\":2"),
                        text.replacingOccurrences(of: "\"identityDerivationVersion\":1", with: "\"identityDerivationVersion\":2"),
                        text.replacingOccurrences(of: "\"lastSelectedProfileID\":null", with: "\"lastSelectedProfileID\":\"missing\""),
                        text.replacingOccurrences(of: "\"installationSecret\":[42", with: "\"installationSecret\":[] ,\"bad\":[42")] {
            XCTAssertThrowsError(try codec.decode(Data(invalid.utf8)))
        }
        XCTAssertThrowsError(try codec.decode(Data(repeating: 32, count: PlanningProfileCodec.maximumBytes + 1)))
        var duplicate = store(); duplicate.records.append(duplicate.records[0])
        XCTAssertThrowsError(try codec.encode(duplicate))
        var tooMany = store()
        tooMany.records = (0...100).map { number in
            var record = tooMany.records[0]
            record = PlanningProfile(profileID: UUID().uuidString.lowercased(), machineKey: String(format: "%064x", number),
                                     name: record.name, recordRevision: 1, snapshot: record.snapshot)
            return record
        }
        XCTAssertThrowsError(try codec.encode(tooMany))
    }
    func testFaultInjectionPreservesCanonicalOrReportsPostReplaceAmbiguity() throws {
        for point in ["prepare", "directoryProtection", "directoryBackup", "directoryVerify", "stage", "stagingProtection", "stagingBackup", "stagingVerify", "sync", "replace", "postVerify"] {
            let files = ProfileTestFiles()
            let repository = FilePlanningProfileRepository(directory: URL(fileURLWithPath: "/synthetic/PlanningProfiles"),
                                                           files: files, protectedDataAvailable: { true })
            let first = store()
            try repository.commit(first, expectedRevision: nil)
            var next = first; next.storeRevision += 1; next.records[0].name = "Changed"; next.records[0].recordRevision += 1
            files.failure = point
            XCTAssertThrowsError(try repository.commit(next, expectedRevision: 0)) { error in
                XCTAssertEqual(error as? PlanningProfileFailure, ["replace", "postVerify"].contains(point) ? .partialWrite : .writeFailure)
            }
            files.failure = nil
            XCTAssertEqual(try repository.load(), point == "postVerify" ? next : first)
        }
    }
    func testLockedOrphanAndCorruptStoresNeverBecomeEmpty() throws {
        let files = ProfileTestFiles()
        let directory = URL(fileURLWithPath: "/synthetic/PlanningProfiles")
        let locked = FilePlanningProfileRepository(directory: directory, files: files, protectedDataAvailable: { false })
        XCTAssertThrowsError(try locked.load()) { XCTAssertEqual($0 as? PlanningProfileFailure, .protectedDataUnavailable) }
        XCTAssertThrowsError(try locked.commit(store(), expectedRevision: nil))
        XCTAssertTrue(files.bytes.isEmpty)
        files.failure = "exists"
        let inaccessible = FilePlanningProfileRepository(directory: directory, files: files, protectedDataAvailable: { true })
        XCTAssertThrowsError(try inaccessible.load()) { XCTAssertEqual($0 as? PlanningProfileFailure, .readFailure) }
        XCTAssertThrowsError(try inaccessible.commit(store(), expectedRevision: nil))
        XCTAssertTrue(files.bytes.isEmpty)
        files.failure = nil
        let repository = FilePlanningProfileRepository(directory: directory, files: files, protectedDataAvailable: { true })
        files.bytes[directory.appendingPathComponent("profiles-v1.staging").path] = Data("orphan".utf8)
        XCTAssertThrowsError(try repository.load()) { XCTAssertEqual($0 as? PlanningProfileFailure, .interruptedWrite) }
        XCTAssertThrowsError(try repository.commit(store(), expectedRevision: nil))
        XCTAssertEqual(files.bytes.count, 1)
        files.bytes[directory.appendingPathComponent("profiles-v1.json").path] = Data("broken".utf8)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(files.bytes.count, 2)
    }
    func testFoundationStorageThroughTrustedAliasRejectsOwnedSymlinks() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let actual = root.appendingPathComponent("actual", isDirectory: true)
        try files.createDirectory(at: actual, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("trusted-alias")
        try files.createSymbolicLink(at: alias, withDestinationURL: actual)
        let directory = alias.appendingPathComponent("PlanningProfiles", isDirectory: true)
        let repository = FilePlanningProfileRepository(directory: directory, protectedDataAvailable: { true })
        XCTAssertNil(try repository.load())
        let foundation = FoundationPlanningProfileFileSystem()
        let canonicalDirectory = actual.appendingPathComponent("PlanningProfiles", isDirectory: true)
        let original = canonicalDirectory.appendingPathComponent("profiles-v1.json")
        #if targetEnvironment(simulator)
        // Simulator Foundation does not report a protection class. Never bypass it to persist private data.
        XCTAssertThrowsError(try repository.commit(store(), expectedRevision: nil)) { error in
            XCTAssertEqual(error as? PlanningProfileFailure, .readFailure)
        }
        XCTAssertFalse(files.fileExists(atPath: original.path))
        let attributes = try files.attributesOfItem(atPath: canonicalDirectory.path)
        XCTAssertNil(attributes[.protectionKey])
        XCTAssertEqual(try canonicalDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        #else
        try repository.commit(store(), expectedRevision: nil)
        XCTAssertEqual(try repository.load(), store())
        var replacement = store(); replacement.storeRevision += 1
        try repository.commit(replacement, expectedRevision: 0)
        XCTAssertEqual(try repository.load(), replacement)
        XCTAssertNoThrow(try foundation.verify(canonicalDirectory))
        XCTAssertNoThrow(try foundation.verify(original))
        try files.removeItem(at: original)
        #endif
        let target = root.appendingPathComponent("untouched.json")
        let synthetic = Data("synthetic non-private sentinel".utf8)
        try synthetic.write(to: target)
        try files.createSymbolicLink(at: original, withDestinationURL: target)
        XCTAssertThrowsError(try foundation.rejectSymlinks(original))
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.commit(store(), expectedRevision: nil))
        XCTAssertEqual(try Data(contentsOf: target), synthetic)
        try files.removeItem(at: original)
        try files.createSymbolicLink(at: original, withDestinationURL: root.appendingPathComponent("missing-target"))
        XCTAssertThrowsError(try foundation.rejectSymlinks(original))
        XCTAssertThrowsError(try repository.load())
        try files.removeItem(at: canonicalDirectory)
        try files.createSymbolicLink(at: canonicalDirectory, withDestinationURL: target)
        XCTAssertThrowsError(try foundation.rejectSymlinks(canonicalDirectory))
        XCTAssertThrowsError(try repository.load())
    }

    func testFullCollectionAndFailedDeletionRetainSelection() throws {
        var full = store()
        full.records = (1...100).map { n in
            PlanningProfile(profileID: UUID().uuidString.lowercased(), machineKey: String(format: "%064x", n),
                            name: "Treadmill \(n)", recordRevision: 1, snapshot: snapshot())
        }
        let repository = MemoryPlanningProfileRepository(store: full)
        let model = model(repository)
        model.beginDiscovery(peer: peer); model.observe(snapshot(), peer: peer)
        XCTAssertEqual(model.failure, .full)
        XCTAssertEqual(model.records, full.records)
        let files = ProfileTestFiles()
        let fileRepository = FilePlanningProfileRepository(directory: URL(fileURLWithPath: "/synthetic/PlanningProfiles"),
                                                            files: files, protectedDataAvailable: { true })
        var selected = store(); selected.lastSelectedProfileID = selected.records[0].id
        try fileRepository.commit(selected, expectedRevision: nil)
        let fileModel = self.model(fileRepository)
        files.failure = "stage"
        XCTAssertFalse(fileModel.delete(selected.records[0]))
        XCTAssertEqual(fileModel.store, selected)
        XCTAssertEqual(fileModel.selectedName, selected.records[0].name)
    }
    func testLateOldPeerCannotCompleteNewPeerEvidence() {
        let model = model(MemoryPlanningProfileRepository())
        let collector = PlanningProfileDiscovery(profiles: model)
        let old = UUID(uuidString: peer)!
        let new = UUID(uuidString: "00000000-0000-0000-0000-000000000142")!
        collector.receive(.connection(.connected(name: "old")), peerIdentifier: old)
        collector.receive(.connection(.connecting(name: "new")), peerIdentifier: new)
        collector.receive(.connection(.connected(name: "new")), peerIdentifier: new)
        for (uuid, data) in [(FTMSUUID.fitnessMachineFeature, [UInt8](arrayLiteral: 0,0,0,0,3,0,0,0)),
                            (FTMSUUID.supportedSpeedRange, [50,0,8,7,10,0]),
                            (FTMSUUID.supportedInclinationRange, [0,0,150,0,5,0])] {
            collector.receive(.value(uuid: uuid, data: Data(data), source: .initialRead), peerIdentifier: old)
        }
        XCTAssertTrue(model.records.isEmpty)
        collector.receive(.value(uuid: FTMSUUID.supportedInclinationRange, data: Data([0,0,150,0,5,0]), source: .initialRead), peerIdentifier: new)
        XCTAssertTrue(model.records.isEmpty)
    }
    func testProfilesDoNotEnterProviderRequestOrLiveCapability() throws {
        let treadmill = TreadmillSetupViewModel(client: ProfileNoOperationClient())
        let model = model(MemoryPlanningProfileRepository())
        treadmill.attachPlanningProfiles(model)
        let resources = try ImportResources()
        let context = ImportRequestSnapshot(text: "Synthetic fixed workout", capabilities: treadmill.workoutPlanCapabilities)
        let before = try resources.request(for: context).httpBody
        model.beginDiscovery(peer: peer); model.observe(snapshot(), peer: peer)
        let record = try XCTUnwrap(model.records.first)
        XCTAssertTrue(model.rename(record, to: "Private Synthetic Profile 141"))
        XCTAssertTrue(model.selectCreated(record.id))
        XCTAssertEqual(treadmill.workoutPlanCapabilities, context.capabilities)
        XCTAssertEqual(try resources.request(for: .init(text: context.text, capabilities: treadmill.workoutPlanCapabilities)).httpBody, before)
        XCTAssertFalse(String(decoding: before!, as: UTF8.self).contains("Private Synthetic Profile 141"))
        model.beginDiscovery(peer: peer); model.observe(snapshot(maximum: 1900), peer: peer)
        model.updateReviewed()
        XCTAssertEqual(try resources.request(for: .init(text: context.text, capabilities: treadmill.workoutPlanCapabilities)).httpBody, before)
        XCTAssertTrue(model.commitAuthoringSelection(nil))
        XCTAssertEqual(try resources.request(for: .init(text: context.text, capabilities: treadmill.workoutPlanCapabilities)).httpBody, before)
        model.protectedDataLost()
        XCTAssertTrue(model.commitAuthoringSelection(nil))
        XCTAssertEqual(try resources.request(for: .init(text: context.text, capabilities: treadmill.workoutPlanCapabilities)).httpBody, before)
        model.reload()
        XCTAssertTrue(model.delete(model.records[0]))
        XCTAssertEqual(try resources.request(for: .init(text: context.text, capabilities: treadmill.workoutPlanCapabilities)).httpBody, before)
    }
    func testPassiveDiscoveryRejectsMixedEpochUnsupportedMalformedAndLateChanges() throws {
        let model = model(MemoryPlanningProfileRepository())
        let collector = PlanningProfileDiscovery(profiles: model, now: { self.instant })
        let id = UUID(uuidString: peer)!
        func send(_ uuid: String, _ bytes: [UInt8]) { collector.receive(.value(uuid: uuid, data: Data(bytes), source: .initialRead), peerIdentifier: id) }
        collector.receive(.connection(.connected(name: "synthetic")), peerIdentifier: id)
        send(FTMSUUID.fitnessMachineFeature, [0,0,0,0,3,0,0,0])
        send(FTMSUUID.supportedSpeedRange, [50,0,8,7,10,0])
        XCTAssertTrue(model.records.isEmpty)
        collector.receive(.connection(.disconnected(message: nil)), peerIdentifier: nil)
        collector.receive(.connection(.connected(name: "synthetic")), peerIdentifier: id)
        send(FTMSUUID.supportedInclinationRange, [0,0,150,0,5,0])
        XCTAssertTrue(model.records.isEmpty)
        send(FTMSUUID.fitnessMachineFeature, [0,0,0,0,1,0,0,0])
        send(FTMSUUID.supportedSpeedRange, [50,0,8,7,10,0])
        XCTAssertTrue(model.records.isEmpty)
        collector.receive(.connection(.connecting(name: "synthetic")), peerIdentifier: id)
        collector.receive(.connection(.connected(name: "synthetic")), peerIdentifier: id)
        send(FTMSUUID.fitnessMachineFeature, [0,0,0,0,3,0,0,0])
        send(FTMSUUID.supportedSpeedRange, [50,0,8,7,10,0])
        send(FTMSUUID.supportedInclinationRange, [0,0,150,0,5,0])
        XCTAssertEqual(model.records.count, 1)
        XCTAssertNotNil(model.currentProfileID)
        send(FTMSUUID.supportedSpeedRange, [50,0,8,7,20,0])
        XCTAssertNil(model.currentProfileID)
        XCTAssertEqual(model.records[0].snapshot.speed.incrementHundredthsKph, 10)
        collector.receive(.connection(.connecting(name: "synthetic")), peerIdentifier: id)
        collector.receive(.connection(.connected(name: "synthetic")), peerIdentifier: id)
        send(FTMSUUID.fitnessMachineFeature, [0])
        send(FTMSUUID.supportedSpeedRange, [50,0,8,7,10,0])
        send(FTMSUUID.supportedInclinationRange, [0,0,150,0,5,0])
        XCTAssertNil(model.review)
        XCTAssertEqual(model.records.count, 1)
    }
    func testAuthoringRejectsLossyTextAndKeepsOverflowEstimateUnavailable() throws {
        var draft = ManualWorkoutDraft(suggestedName: "Synthetic", activity: .indoorWalking, steps: [.warmUp, .interval, .coolDown].map {
            .init(kind: $0, label: "Synthetic", durationSeconds: "60", speedKilometresPerHour: "1.123456789012345678901234567890123456789012345", inclinationPercent: "0")
        })
        XCTAssertThrowsError(try ManualWorkoutDraftParser.parse(draft, locale: Locale(identifier: "en_GB")).get())
        XCTAssertNil(ManualWorkoutDraftParser.incrementText(draft.steps[0].speedKilometresPerHour, by: 1))
        for index in draft.steps.indices { draft.steps[index].speedKilometresPerHour = "0001.250000" }
        let exact = try ManualWorkoutDraftParser.parse(draft, locale: Locale(identifier: "en_GB")).get()
        XCTAssertEqual(exact.steps[0].targetSpeed.value, Decimal(string: "1.25"))
        let huge = WorkoutPlan(schemaVersion: 1, suggestedName: "Synthetic extreme", activity: .indoorWalking,
            steps: exact.steps.map { .init(kind: $0.kind, label: $0.label, duration: .init(value: Int.max, unit: .seconds), targetSpeed: .init(value: Decimal(string: String(repeating: "9", count: 38) + "e127")!, unit: .kilometresPerHour), targetInclination: $0.targetInclination) })
        let token = try CanonicalWorkoutAuthoringValidator.validate(huge).get()
        let preview = WorkoutPlanPreview(authoringPlan: token)
        XCTAssertNil(preview.estimatedDistanceKilometres)
        XCTAssertEqual(PlanValueFormatter.estimatedDistanceSummary(preview.estimatedDistanceKilometres), "Estimate unavailable")
        XCTAssertEqual(preview.plan, huge)
        XCTAssertEqual(ManualWorkoutDraftParser.incrementText("20.1", by: Decimal(string: "0.1")!, locale: Locale(identifier: "en_GB")), "20.2")
        XCTAssertEqual(ManualWorkoutDraftParser.incrementText("-1", by: Decimal(string: "-0.5")!, locale: Locale(identifier: "en_GB")), "-1.5")
    }
    func testAuthoringSelectionRestoresClearsDeletesAndRejectsStalePickerCandidate() throws {
        let repository = MemoryPlanningProfileRepository()
        let model = model(repository)
        XCTAssertTrue(model.commitAuthoringSelection(nil))
        model.beginDiscovery(peer: peer); model.observe(snapshot(), peer: peer)
        let record = try XCTUnwrap(model.records.first)
        XCTAssertTrue(model.commitAuthoringSelection(record.id))
        XCTAssertEqual(self.model(repository).selectedProfile?.id, record.id)
        XCTAssertTrue(model.commitAuthoringSelection(nil))
        XCTAssertNil(model.selectedProfile)
        XCTAssertTrue(model.commitAuthoringSelection(record.id))
        XCTAssertTrue(model.delete(model.records[0]))
        XCTAssertNil(model.selectedProfile)
        XCTAssertFalse(model.commitAuthoringSelection(record.id))
        XCTAssertNil(model.selectedProfile)
    }
    func testDeliberateNoProfileSurvivesProtectedStoreRecovery() throws {
        let repository = MemoryPlanningProfileRepository()
        let model = model(repository)
        model.beginDiscovery(peer: peer); model.observe(snapshot(), peer: peer)
        let id = try XCTUnwrap(model.records.first?.id)
        XCTAssertTrue(model.commitAuthoringSelection(id))
        model.protectedDataLost()
        XCTAssertTrue(model.commitAuthoringSelection(nil))
        model.reload()
        XCTAssertNil(model.selectedProfile)
        XCTAssertEqual(model.authoringSelectionName, "No treadmill selected")
        XCTAssertEqual(try repository.load()?.lastSelectedProfileID, id)
        XCTAssertTrue(model.commitAuthoringSelection(nil))
        XCTAssertNil(self.model(repository).selectedProfile)
    }
    func testUnavailableProfilesAllowDeliberateNoProfileWithoutWriting() throws {
        let files = ProfileTestFiles(); files.failure = "exists"
        let repository = FilePlanningProfileRepository(directory: URL(fileURLWithPath: "/synthetic/PlanningProfiles"), files: files, protectedDataAvailable: { true })
        let model = model(repository)
        XCTAssertEqual(model.authoringSelectionName, "Saved profiles unavailable")
        XCTAssertTrue(model.commitAuthoringSelection(nil))
        XCTAssertEqual(model.authoringSelectionName, "No treadmill selected")
        XCTAssertNotNil(model.failure); XCTAssertTrue(files.bytes.isEmpty)
        XCTAssertFalse(model.commitAuthoringSelection("00000000-0000-0000-0000-000000000001"))
    }
    func testCanonicalAuthoringDoesNotForgeLiveValidityOrClampTargets() throws {
        let kinds: [WorkoutStepKind] = [.warmUp, .interval, .coolDown]
        func plan(speed: Decimal, inclination: Decimal = -1) -> WorkoutPlan {
            .init(schemaVersion: 1, suggestedName: "Synthetic detached plan", activity: .indoorWalking,
                  steps: kinds.map { .init(kind: $0, label: "Synthetic", duration: .init(value: 60, unit: .seconds), targetSpeed: .init(value: speed, unit: .kilometresPerHour), targetInclination: .init(value: inclination, unit: .percent)) })
        }
        let exact = plan(speed: Decimal(string: "100.123456")!)
        let token = try CanonicalWorkoutAuthoringValidator.validate(exact).get()
        XCTAssertEqual(token.plan, exact)
        XCTAssertThrowsError(try WorkoutPlanValidator.validate(exact, against: .init(speed: .unknown, inclination: .unknown)).get())
        XCTAssertThrowsError(try CanonicalWorkoutAuthoringValidator.validate(plan(speed: -1)).get())
        XCTAssertThrowsError(try CanonicalWorkoutAuthoringValidator.validate(plan(speed: .nan)).get())
        XCTAssertThrowsError(try CanonicalWorkoutAuthoringValidator.validate(plan(speed: 1, inclination: .nan)).get())
        let plans = PlansViewModel()
        plans.beginCreate(); plans.draft = ManualWorkoutDraft(plan: exact)
        let draft = plans.draft
        plans.reviewForAuthoring(locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(plans.preview?.plan, exact); XCTAssertEqual(plans.draft, draft)
    }

    private func historicalPlan(speed: Decimal = 1, inclination: Decimal = 0) -> WorkoutPlan {
        .init(schemaVersion: 1, suggestedName: "Synthetic historical plan", activity: .indoorWalking,
              steps: [WorkoutStepKind.warmUp, .interval, .coolDown].map {
            .init(kind: $0, label: "Synthetic", duration: .init(value: 60, unit: .seconds),
                  targetSpeed: .init(value: speed, unit: .kilometresPerHour), targetInclination: .init(value: inclination, unit: .percent))
        })
    }
    private func comparison(_ plan: WorkoutPlan, profile: PlanningProfile? = nil, at date: Date? = nil) throws -> HistoricalPlanCompatibility {
        HistoricalPlanCompatibilityPolicy.compare(try CanonicalWorkoutAuthoringValidator.validate(plan).get(),
            selection: .profile(profile ?? store().records[0]), at: date ?? instant)
    }
    func testHistoricalComparisonAllStepsIndependentTargetsAndExactBoundaries() throws {
        for (speed, inclination, targets) in [(Decimal(19), Decimal(0), ["speed"]), (1, 16, ["inclination"]), (19, 16, ["speed", "inclination"])] {
            let plan = historicalPlan(speed: speed, inclination: inclination)
            let result = try comparison(plan)
            XCTAssertEqual(result.mismatches.count, targets.count * 3)
            XCTAssertEqual(Set(result.mismatches.map(\.stepIndex)), Set(0..<3))
            XCTAssertEqual(Set(result.mismatches.map(\.target)), Set(targets))
            XCTAssertEqual(result.plan, plan)
        }
        for (speed, incline) in [(Decimal(string: "0.5")!, Decimal(-1)), (18, 15)] {
            XCTAssertTrue(try comparison(historicalPlan(speed: speed, inclination: incline)).mismatches.isEmpty)
        }
        let misaligned = try comparison(historicalPlan(speed: Decimal(string: "0.55")!, inclination: Decimal(string: "0.1")!))
        XCTAssertEqual(misaligned.mismatches.count, 6)
        XCTAssertTrue(misaligned.mismatches.allSatisfy { !$0.outOfRange })
        XCTAssertTrue(try comparison(historicalPlan(speed: Decimal(string: "1e127")!)).isMismatch)
    }
    func testHistoricalMinimumOriginGridZeroWidthAgeAndUnavailableEvidence() throws {
        var record = store().records[0]
        record.snapshot = .init(speed: .init(minimumHundredthsKph: 55, maximumHundredthsKph: 155, incrementHundredthsKph: 10),
                                inclination: .init(minimumTenthsPercent: -5, maximumTenthsPercent: -5, incrementTenthsPercent: 5), observedAt: snapshot().observedAt)
        XCTAssertFalse(try comparison(historicalPlan(speed: Decimal(string: "0.65")!, inclination: Decimal(string: "-0.5")!), profile: record).isMismatch)
        XCTAssertTrue(try comparison(historicalPlan(speed: Decimal(string: "0.6")!, inclination: Decimal(string: "-0.4")!), profile: record).isMismatch)
        let plan = historicalPlan()
        for seconds in [30.0 * 86400 - 0.001, 30.0 * 86400, 30.0 * 86400 + 0.001] {
            let result = try comparison(plan, at: instant.addingTimeInterval(seconds))
            XCTAssertEqual(result.ageWarning != nil, seconds >= 30 * 86400)
            XCTAssertFalse(result.isMismatch)
        }
        XCTAssertEqual(try comparison(plan, at: instant.addingTimeInterval(-1)).ageWarning, "Confirmation date cannot be verified")
        let token = try CanonicalWorkoutAuthoringValidator.validate(plan).get()
        for selection in [HistoricalPlanningSelection.none, .unavailable("Locked")] {
            let result = HistoricalPlanCompatibilityPolicy.compare(token, selection: selection, at: instant)
            XCTAssertNil(result.profile); XCTAssertFalse(result.isMismatch)
            XCTAssertEqual(result.title, "Treadmill compatibility not yet checked")
        }
        record.snapshot.snapshotVersion = 99
        let invalid = try comparison(plan, profile: record)
        XCTAssertNil(invalid.profile)
        guard case .unavailable = invalid.selection else { return XCTFail("Invalid snapshot must never pass") }
    }
    func testAIHistoricalEditRecoveryRoundtripsExactTargetsInCommaLocale() throws {
        let plans = PlansViewModel(repository: HistoricalPlanTestRepository())
        let exact = historicalPlan(speed: Decimal(string: "8.04672")!, inclination: Decimal(string: "-0.5")!)
        try plans.reviewImportedForAuthoring(exact).get()
        plans.editHistoricalStep(1, locale: Locale(identifier: "de_DE"))
        XCTAssertFalse(plans.isEditorPresented, "AI edit stays inside its existing import sheet")
        let draft = try XCTUnwrap(plans.draft)
        XCTAssertEqual(draft.steps[0].speedKilometresPerHour, "8,04672")
        XCTAssertEqual(draft.steps[2].inclinationPercent, "-0,5")
        XCTAssertEqual(try ManualWorkoutDraftParser.parse(draft, locale: Locale(identifier: "de_DE")).get(), exact)
        plans.reviewForAuthoring(locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(plans.preview?.plan, exact)
    }
    func testHistoricalSaveRechecksEvidenceAndPlanAndAcknowledgementNeverPersists() throws {
        let repository = HistoricalPlanTestRepository()
        var selected = HistoricalPlanningSelection.profile(store().records[0])
        let plans = PlansViewModel(repository: repository, now: { self.instant })
        plans.configureHistoricalSelection { _ in selected }
        let exact = historicalPlan(speed: 19)
        plans.beginCreate(); plans.draft = ManualWorkoutDraft(plan: exact); plans.reviewForAuthoring()
        let acknowledgement = try XCTUnwrap(plans.historicalReview)
        plans.confirmSave(); XCTAssertTrue(repository.records.isEmpty)
        plans.confirmSave(acknowledging: acknowledgement)
        XCTAssertEqual(repository.records.map(\.plan), [exact])
        for change in 0..<4 {
            selected = .profile(store().records[0])
            plans.beginCreate(); plans.draft = ManualWorkoutDraft(plan: exact); plans.reviewForAuthoring()
            let old = try XCTUnwrap(plans.historicalReview)
            if change == 0 { selected = .none }
            if change == 1 { selected = .unavailable("Corrupt store") }
            if change == 2 { var record = store().records[0]; record.recordRevision += 1; record.name = "Renamed"; selected = .profile(record) }
            if change == 3 { plans.draft?.suggestedName = "Changed exact plan"; plans.reviewForAuthoring() }
            plans.confirmSave(acknowledging: old)
            XCTAssertEqual(repository.records.count, 1)
            XCTAssertNotNil(plans.preview); XCTAssertNotNil(plans.saveError)
            plans.confirmSave(acknowledging: plans.historicalReview)
            XCTAssertEqual(repository.records.count, 2)
            repository.records.removeLast()
        }
        plans.beginCreate(); plans.draft = ManualWorkoutDraft(plan: exact); plans.reviewForAuthoring()
        plans.editHistoricalStep(1)
        XCTAssertNil(plans.preview); XCTAssertEqual(plans.focusedStepIndex, 1)
        XCTAssertEqual(plans.draft?.steps[1].speedKilometresPerHour, "19")
    }

}

private struct TestIdentity: PlanningProfileIdentity {
    func newSecret() throws -> [UInt8] { Array(repeating: 42, count: 32) }
    func machineKey(peer: String, secret: [UInt8]) throws -> String { try LocalPlanningProfileIdentity().machineKey(peer: peer, secret: secret) }
    func newProfileID() -> String { UUID().uuidString.lowercased() }
}

private final class ProfileTestFiles: PlanningProfileFileSystem {
    var bytes: [String: Data] = [:]
    var directories: Set<String> = []
    var failure: String? { didSet { replaced = false } }
    private var replaced = false
    func exists(_ url: URL) throws -> Bool {
        if failure == "exists" { throw CocoaError(.fileReadNoPermission) }
        return bytes[url.path] != nil || directories.contains(url.path)
    }
    func rejectSymlinks(_ url: URL) throws {}
    func prepareDirectory(_ url: URL) throws {
        if ["prepare", "directoryProtection", "directoryBackup", "directoryVerify"].contains(failure ?? "") { throw CocoaError(.fileWriteUnknown) }
        directories.insert(url.path)
    }
    func verify(_ url: URL) throws { if failure == "postVerify" && replaced { throw CocoaError(.fileReadUnknown) } }
    func read(_ url: URL) throws -> Data { try verify(url); return bytes[url.path] ?? Data() }
    func stage(_ data: Data, at url: URL) throws {
        replaced = false
        if ["stage", "stagingProtection", "stagingBackup", "stagingVerify"].contains(failure ?? "") { throw CocoaError(.fileWriteUnknown) }
        bytes[url.path] = data
        if failure == "sync" { throw CocoaError(.fileWriteUnknown) }
    }
    func replace(_ canonical: URL, with staging: URL) throws {
        if failure == "replace" { throw CocoaError(.fileWriteUnknown) }
        bytes[canonical.path] = bytes.removeValue(forKey: staging.path)
        replaced = true
    }
    func remove(_ url: URL) throws { bytes.removeValue(forKey: url.path) }
}

@MainActor
private final class ProfileNoOperationClient: FTMSClientProtocol {
    weak var delegate: (any FTMSClientDelegate)?
    func startScan() { XCTFail("Profile lifecycle must not scan") }
    func stopScan() { XCTFail("Profile lifecycle must not scan") }
    func connect(to identifier: UUID) { XCTFail("Profile lifecycle must not connect") }
    func disconnect() { XCTFail("Profile lifecycle must not disconnect") }
}

@MainActor
private final class HistoricalPlanTestRepository: SavedPlanRepositoryProtocol {
    var records: [SavedPlanRecord] = []
    func list() -> SavedPlanRepositoryStatus { .init(canonical: records.isEmpty ? .empty : .available(records: records), staging: .absent) }
    func create(_ token: CanonicalWorkoutAuthoringValidator.ValidatedPlan) throws -> SavedPlanRecord {
        let record = SavedPlanRecord(id: UUID(), createdAt: Date(timeIntervalSince1970: 0), modifiedAt: Date(timeIntervalSince1970: 0), plan: token.plan)
        records.append(record); return record
    }
    func replace(id: UUID, with token: CanonicalWorkoutAuthoringValidator.ValidatedPlan) throws -> SavedPlanRecord { throw SavedPlanMutationFailure.recordNotFound(id) }
    func delete(id: UUID) throws { records.removeAll { $0.id == id } }
}
