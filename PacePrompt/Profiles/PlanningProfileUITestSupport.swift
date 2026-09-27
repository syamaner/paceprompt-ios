#if DEBUG
import Foundation

@MainActor
enum PlanningProfileUITestSupport {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--paceprompt-profile-ui-testing")
    static func model() -> PlanningProfilesViewModel {
        if ProcessInfo.processInfo.environment["PACEPROMPT_PROFILE_SCENARIO"] == "unavailable" {
            return PlanningProfilesViewModel(repository: UnavailableProfileUITestRepository(), identity: LocalPlanningProfileIdentity())
        }
        let repository = MemoryPlanningProfileRepository()
        let model = PlanningProfilesViewModel(repository: repository, identity: LocalPlanningProfileIdentity())
        let scenario = ProcessInfo.processInfo.environment["PACEPROMPT_PROFILE_SCENARIO"] ?? "populated"
        if scenario != "empty" {
            let peer = "00000000-0000-0000-0000-000000000141"
            let snapshot = PlanningProfileSnapshot(
                speed: .init(minimumHundredthsKph: 50, maximumHundredthsKph: 1800, incrementHundredthsKph: 10),
                inclination: .init(minimumTenthsPercent: 0, maximumTenthsPercent: 150, incrementTenthsPercent: 5),
                observedAt: PlanningProfileSnapshot.timestamp(Date(timeIntervalSince1970: 1_700_000_000)))
            model.beginDiscovery(peer: peer)
            model.observe(snapshot, peer: peer)
            if scenario != "created" {
                if let record = model.records.first {
                    _ = model.selectCreated(record.id)
                    _ = model.rename(record, to: "Synthetic treadmill with a long accessible name")
                }
                model.dismissCreated()
                model.invalidateDiscovery()
                if scenario == "changed" {
                    model.beginDiscovery(peer: peer)
                    model.observe(.init(speed: .init(minimumHundredthsKph: 50, maximumHundredthsKph: 2000, incrementHundredthsKph: 20),
                                        inclination: snapshot.inclination, observedAt: snapshot.observedAt), peer: peer)
                }
            }
        }
        return model
    }
}
@MainActor
private final class UnavailableProfileUITestRepository: PlanningProfileRepository {
    func load() throws -> PlanningProfileStore? { throw PlanningProfileFailure.readFailure }
    func commit(_ replacement: PlanningProfileStore, expectedRevision: Int?) throws { throw PlanningProfileFailure.writeFailure }
}
#endif
