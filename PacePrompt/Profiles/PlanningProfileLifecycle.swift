import Combine
import Foundation

protocol PlanningProfileIdentity {
    func newSecret() throws -> [UInt8]
    func machineKey(peer: String, secret: [UInt8]) throws -> String
    func newProfileID() -> String
}

@MainActor
final class PlanningProfilesViewModel: ObservableObject {
    struct Review: Equatable {
        let profile: PlanningProfile
        let snapshot: PlanningProfileSnapshot
        let generation: Int
    }
    @Published private(set) var store: PlanningProfileStore?
    @Published private(set) var failure: PlanningProfileFailure?
    @Published private(set) var review: Review?
    @Published private(set) var createdProfileID: String?
    @Published private(set) var currentProfileID: String?
    @Published private(set) var discoveryStatus = "Connect explicitly to read complete treadmill capabilities."
    private let repository: any PlanningProfileRepository
    private let identity: any PlanningProfileIdentity
    private let now: () -> Date
    private var generation = 0
    private var consumed = false
    private var activePeer: String?

    init(repository: any PlanningProfileRepository, identity: any PlanningProfileIdentity, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.identity = identity
        self.now = now
        reload()
    }
    var records: [PlanningProfile] { store?.records ?? [] }
    var selectedName: String {
        if store == nil && failure != nil { return "Saved profiles unavailable" }
        return records.first { $0.id == store?.lastSelectedProfileID }?.name ?? "No treadmill selected"
    }
    func warning(_ snapshot: PlanningProfileSnapshot) -> String? { snapshot.ageWarning(at: now()) }
    func reload() {
        do { store = try repository.load(); failure = nil }
        catch { store = nil; failure = (error as? PlanningProfileFailure) ?? .readFailure }
    }
    func protectedDataLost() {
        store = nil
        failure = .protectedDataUnavailable
        invalidateDiscovery()
    }
    func beginDiscovery(peer: String) {
        generation += 1
        consumed = false
        activePeer = peer
        review = nil
        createdProfileID = nil
        currentProfileID = nil
        discoveryStatus = "Capability read incomplete — no saved profile change."
    }
    func invalidateDiscovery(status: String = "Disconnected — saved profiles remain historical.") {
        activePeer = nil
        review = nil
        currentProfileID = nil
        discoveryStatus = status
    }
    func observe(_ snapshot: PlanningProfileSnapshot, peer: String) {
        guard activePeer == peer, !consumed else { return }
        do {
            try snapshot.validate()
            guard failure == nil else { return }
            let old = try repository.load()
            let secret = try old?.installationSecret ?? identity.newSecret()
            let key = try identity.machineKey(peer: peer, secret: secret)
            var replacement = old ?? PlanningProfileStore(installationSecret: secret, storeRevision: -1,
                                                           lastSelectedProfileID: nil, records: [])
            if let index = replacement.records.firstIndex(where: { $0.machineKey == key }) {
                let record = replacement.records[index]
                currentProfileID = record.id
                if !record.snapshot.sameCapabilities(as: snapshot) {
                    store = old
                    review = Review(profile: record, snapshot: snapshot, generation: generation)
                    consumed = true
                    discoveryStatus = "Capabilities changed — review before updating the saved profile."
                    return
                }
                guard record.recordRevision < Int.max else { throw PlanningProfileFailure.conflict }
                replacement.records[index].snapshot = snapshot
                replacement.records[index].recordRevision += 1
            } else {
                guard replacement.records.count < 100 else { throw PlanningProfileFailure.full }
                var number = 1
                while replacement.records.contains(where: { $0.name == "Treadmill \(number)" }) { number += 1 }
                let record = PlanningProfile(profileID: identity.newProfileID(), machineKey: key,
                                             name: "Treadmill \(number)", recordRevision: 1, snapshot: snapshot)
                replacement.records.append(record)
            }
            guard replacement.storeRevision < Int.max else { throw PlanningProfileFailure.conflict }
            replacement.storeRevision += 1
            try repository.commit(replacement, expectedRevision: old?.storeRevision)
            store = replacement
            consumed = true
            currentProfileID = replacement.records.first { $0.machineKey == key }?.id
            createdProfileID = old?.records.contains(where: { $0.machineKey == key }) == true ? nil : currentProfileID
            discoveryStatus = createdProfileID == nil ? "Saved profile confirmed by complete read." : "Treadmill profile saved."
        } catch { handle(error) }
    }
    func keepSaved() { review = nil }
    func dismissCreated() { createdProfileID = nil }
    func updateReviewed() {
        guard let review, activePeer != nil, review.generation == generation else { return }
        let success = mutate { replacement in
            guard let index = replacement.records.firstIndex(where: { $0.id == review.profile.id }),
                  replacement.records[index].recordRevision == review.profile.recordRevision,
                  replacement.records[index].machineKey == review.profile.machineKey else { throw PlanningProfileFailure.conflict }
            guard replacement.records[index].recordRevision < Int.max else { throw PlanningProfileFailure.conflict }
            replacement.records[index].snapshot = review.snapshot
            replacement.records[index].recordRevision += 1
        }
        if success || failure == .conflict { self.review = nil }
    }
    @discardableResult
    func rename(_ record: PlanningProfile, to text: String) -> Bool {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlanningProfile.validName(name) else { failure = .invalidName; return false }
        return mutate { replacement in
            guard let index = replacement.records.firstIndex(where: { $0.id == record.id }),
                  replacement.records[index].recordRevision == record.recordRevision,
                  replacement.records[index].recordRevision < Int.max else { throw PlanningProfileFailure.conflict }
            replacement.records[index].name = name
            replacement.records[index].recordRevision += 1
        }
    }
    @discardableResult
    func delete(_ record: PlanningProfile) -> Bool {
        let success = mutate { replacement in
            guard replacement.records.contains(where: { $0.id == record.id && $0.recordRevision == record.recordRevision }) else {
                throw PlanningProfileFailure.conflict
            }
            replacement.records.removeAll { $0.id == record.id }
            if replacement.lastSelectedProfileID == record.id { replacement.lastSelectedProfileID = nil }
        }
        if success {
            if currentProfileID == record.id { consumed = true; currentProfileID = nil }
            if review?.profile.id == record.id { consumed = true; review = nil }
            if createdProfileID == record.id { createdProfileID = nil }
        }
        return success
    }
    @discardableResult
    func selectCreated(_ id: String) -> Bool {
        mutate { replacement in
            guard replacement.records.contains(where: { $0.id == id }) else { throw PlanningProfileFailure.conflict }
            replacement.lastSelectedProfileID = id
        }
    }
    private func mutate(_ operation: (inout PlanningProfileStore) throws -> Void) -> Bool {
        do {
            guard var replacement = try repository.load() else { throw PlanningProfileFailure.conflict }
            let expected = replacement.storeRevision
            try operation(&replacement)
            guard expected < Int.max else { throw PlanningProfileFailure.conflict }
            replacement.storeRevision += 1
            try repository.commit(replacement, expectedRevision: expected)
            store = replacement
            failure = nil
            return true
        } catch { handle(error); return false }
    }
    private func handle(_ error: Error) {
        let failure = (error as? PlanningProfileFailure) ?? .writeFailure
        // Disk can have changed after a partial replacement. Always re-read rather than asserting the old state.
        reload()
        self.failure = failure
    }
}
