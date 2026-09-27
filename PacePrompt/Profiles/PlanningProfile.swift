import Foundation

// Historical planning evidence only. No connection, execution or provider capability.
struct PlanningProfileSnapshot: Codable, Equatable {
    struct Speed: Codable, Equatable {
        let minimumHundredthsKph: Int
        let maximumHundredthsKph: Int
        let incrementHundredthsKph: Int
    }
    struct Inclination: Codable, Equatable {
        let minimumTenthsPercent: Int
        let maximumTenthsPercent: Int
        let incrementTenthsPercent: Int
    }
    struct Provenance: Codable, Equatable {
        var kind = "ftmsRead"
        var interpretationVersion = 1
    }
    var snapshotVersion = 1
    let speed: Speed
    let inclination: Inclination
    let observedAt: String
    var provenance = Provenance()

    func validate() throws {
        guard snapshotVersion == 1, provenance.kind == "ftmsRead", provenance.interpretationVersion == 1 else {
            throw PlanningProfileFailure.unsupportedVersion
        }
        guard (0...65535).contains(speed.minimumHundredthsKph),
              (0...65535).contains(speed.maximumHundredthsKph),
              (1...65535).contains(speed.incrementHundredthsKph),
              speed.minimumHundredthsKph <= speed.maximumHundredthsKph,
              (-32768...32767).contains(inclination.minimumTenthsPercent),
              (-32768...32767).contains(inclination.maximumTenthsPercent),
              (1...65535).contains(inclination.incrementTenthsPercent),
              inclination.minimumTenthsPercent <= inclination.maximumTenthsPercent,
              Self.date(observedAt) != nil else { throw PlanningProfileFailure.corrupt }
    }
    func sameCapabilities(as other: Self) -> Bool { speed == other.speed && inclination == other.inclination }
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    static func date(_ text: String) -> Date? {
        guard text.hasSuffix("Z") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text), formatter.string(from: date) == text { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
    func ageWarning(at now: Date) -> String? {
        guard let date = Self.date(observedAt), now >= date else { return "Confirmation date cannot be verified" }
        return now.timeIntervalSince(date) >= 30 * 24 * 60 * 60
            ? "Saved profile is over 30 days old. Live compatibility is checked before execution." : nil
    }
}

struct PlanningProfile: Codable, Equatable, Identifiable {
    var id: String { profileID }
    let profileID: String
    let machineKey: String
    var name: String
    var equipmentType = "treadmill"
    var recordRevision: Int
    var snapshot: PlanningProfileSnapshot

    static func validName(_ name: String) -> Bool {
        name == name.trimmingCharacters(in: .whitespacesAndNewlines) && (1...80).contains(name.count)
            && name.utf8.count <= 512 && !name.unicodeScalars.contains { CharacterSet.controlCharacters.union(.newlines).contains($0) }
    }
    func validate() throws {
        guard UUID(uuidString: profileID)?.uuidString.lowercased() == profileID,
              machineKey.count == 64, machineKey.allSatisfy({ "0123456789abcdef".contains($0) }),
              Self.validName(name), equipmentType == "treadmill", recordRevision > 0 else {
            throw PlanningProfileFailure.corrupt
        }
        try snapshot.validate()
    }
}

struct PlanningProfileStore: Codable, Equatable {
    var formatVersion = 1
    var identityDerivationVersion = 1
    let installationSecret: [UInt8]
    var storeRevision: Int
    var lastSelectedProfileID: String?
    var records: [PlanningProfile]

    func validate() throws {
        guard formatVersion == 1, identityDerivationVersion == 1 else { throw PlanningProfileFailure.unsupportedVersion }
        guard installationSecret.count == 32, storeRevision >= 0, records.count <= 100,
              Set(records.map(\.profileID)).count == records.count,
              Set(records.map(\.machineKey)).count == records.count,
              lastSelectedProfileID == nil || records.contains(where: { $0.profileID == lastSelectedProfileID }) else {
            throw PlanningProfileFailure.corrupt
        }
        try records.forEach { try $0.validate() }
    }
}

enum PlanningProfileFailure: Error, Equatable {
    case protectedDataUnavailable, readFailure, corrupt, unsupportedVersion, interruptedWrite
    case writeFailure, partialWrite, conflict, invalidName, full, invalidEvidence
    var message: String {
        switch self {
        case .protectedDataUnavailable: "Saved treadmill profiles are unavailable while protected data is locked."
        case .readFailure: "Saved treadmill profiles could not be read. Try again."
        case .corrupt: "Saved treadmill profiles contain invalid data. Nothing has been replaced."
        case .unsupportedVersion: "Saved treadmill profiles use an unsupported version. Nothing has been migrated."
        case .interruptedWrite: "An interrupted profile write needs recovery. Nothing has been promoted."
        case .writeFailure: "The profile change could not be saved. Try again."
        case .partialWrite: "The profile write could not be verified. Reload before making another change."
        case .conflict: "This profile changed. Reload and review before trying again."
        case .invalidName: "Use a trimmed name of 1–80 characters without control characters."
        case .full: "Delete a saved profile to add another."
        case .invalidEvidence: "Complete current speed and inclination capability reads are required."
        }
    }
}

// Owned by the profile application layer; implementations must share the CAS contract.
@MainActor
protocol PlanningProfileRepository {
    func load() throws -> PlanningProfileStore?
    func commit(_ replacement: PlanningProfileStore, expectedRevision: Int?) throws
}

@MainActor
final class MemoryPlanningProfileRepository: PlanningProfileRepository {
    private var store: PlanningProfileStore?
    init(store: PlanningProfileStore? = nil) { self.store = store }
    func load() throws -> PlanningProfileStore? { try store?.validate(); return store }
    func commit(_ replacement: PlanningProfileStore, expectedRevision: Int?) throws {
        try PlanningProfileTransactions.validate(replacement, replacing: store, expectedRevision: expectedRevision)
        store = replacement
    }
}

enum PlanningProfileTransactions {
    static func validate(_ replacement: PlanningProfileStore, replacing old: PlanningProfileStore?, expectedRevision: Int?) throws {
        try replacement.validate()
        guard old?.storeRevision == expectedRevision, (expectedRevision ?? -1) < Int.max, replacement.storeRevision == (expectedRevision ?? -1) + 1,
              old == nil || old?.installationSecret == replacement.installationSecret else { throw PlanningProfileFailure.conflict }
        for record in replacement.records {
            if let previous = old?.records.first(where: { $0.id == record.id }) {
                guard record.machineKey == previous.machineKey, record.equipmentType == previous.equipmentType else {
                    throw PlanningProfileFailure.conflict
                }
                if record != previous {
                    guard previous.recordRevision < Int.max, record.recordRevision == previous.recordRevision + 1 else {
                        throw PlanningProfileFailure.conflict
                    }
                }
            } else {
                guard record.recordRevision == 1, old?.records.contains(where: { $0.machineKey == record.machineKey }) != true else {
                    throw PlanningProfileFailure.conflict
                }
            }
        }
    }
}
