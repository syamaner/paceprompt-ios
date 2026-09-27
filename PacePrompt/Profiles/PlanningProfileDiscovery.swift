import CryptoKit
import Foundation
import Security

struct LocalPlanningProfileIdentity: PlanningProfileIdentity {
    func newSecret() throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw PlanningProfileFailure.writeFailure
        }
        return bytes
    }
    func newProfileID() -> String { UUID().uuidString.lowercased() }
    func machineKey(peer: String, secret: [UInt8]) throws -> String {
        guard let uuid = UUID(uuidString: peer), uuid.uuidString.lowercased() == peer.lowercased(), secret.count == 32 else {
            throw PlanningProfileFailure.invalidEvidence
        }
        let message = Data(("paceprompt.planning-profile.v1:" + uuid.uuidString.lowercased()).utf8)
        return HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret))
            .map { String(format: "%02x", $0) }.joined()
    }
}

// Passive adapter, using only reads already delivered by explicit setup. No FTMS client ownership or commands.
@MainActor
final class PlanningProfileDiscovery {
    private let profiles: PlanningProfilesViewModel
    private let now: () -> Date
    private var peer: String?
    private var connected = false
    private var flags: FTMSFeatureFlags?
    private var speed: FTMSSpeedRange?
    private var inclination: FTMSInclinationRange?
    private var completed = false
    init(profiles: PlanningProfilesViewModel, now: @escaping () -> Date = Date.init) {
        self.profiles = profiles
        self.now = now
    }
    func receive(_ event: FTMSClientEvent, peerIdentifier: UUID?) {
        switch event {
        case let .connection(state):
            switch state {
            case .connecting:
                reset()
            case .discovering, .connected:
                guard let id = peerIdentifier?.uuidString.lowercased() else { reset(); return }
                if peer != id {
                    reset()
                    peer = id
                    profiles.beginDiscovery(peer: id)
                }
                connected = state.isProfileConnected
                project()
            default: reset()
            }
        case let .value(uuid, data, source):
            guard peer != nil, peerIdentifier?.uuidString.lowercased() == peer, source == .initialRead,
                  [FTMSUUID.fitnessMachineFeature, FTMSUUID.supportedSpeedRange, FTMSUUID.supportedInclinationRange].contains(uuid) else { return }
            do {
                if completed {
                    let unchanged: Bool
                    switch uuid {
                    case FTMSUUID.fitnessMachineFeature: unchanged = flags == (try FTMSParser.fitnessMachineFeature(data))
                    case FTMSUUID.supportedSpeedRange: unchanged = speed == (try FTMSParser.supportedSpeedRange(data))
                    default: unchanged = inclination == (try FTMSParser.supportedInclinationRange(data))
                    }
                    if !unchanged { profiles.invalidateDiscovery(status: "Capability evidence changed during review — reconnect explicitly for a new read.") }
                    return
                }
                switch uuid {
                case FTMSUUID.fitnessMachineFeature: flags = try FTMSParser.fitnessMachineFeature(data)
                case FTMSUUID.supportedSpeedRange: speed = try FTMSParser.supportedSpeedRange(data)
                default: inclination = try FTMSParser.supportedInclinationRange(data)
                }
                project()
            } catch { profiles.invalidateDiscovery(status: "Invalid capability read — no saved profile change."); completed = true }
        case let .valueError(uuid, _, _):
            guard peerIdentifier?.uuidString.lowercased() == peer else { return }
            if [FTMSUUID.fitnessMachineFeature, FTMSUUID.supportedSpeedRange, FTMSUUID.supportedInclinationRange].contains(uuid) {
                profiles.invalidateDiscovery(status: "Capability read unavailable — no saved profile change.")
                completed = true
            }
        default: break
        }
    }
    private func reset() {
        peer = nil; connected = false; flags = nil; speed = nil; inclination = nil; completed = false
        profiles.invalidateDiscovery()
    }
    private func project() {
        guard connected, !completed, let peer, let flags else { return }
        guard flags.supportsSpeedTargetSetting, flags.supportsInclinationTargetSetting else {
            profiles.invalidateDiscovery(status: "Target capability unsupported — no usable v1 profile.")
            completed = true
            return
        }
        guard let speed, let inclination else { return }
        do {
            let snapshot = PlanningProfileSnapshot(
                speed: .init(minimumHundredthsKph: try units(speed.minimumKilometresPerHour, scale: 100),
                             maximumHundredthsKph: try units(speed.maximumKilometresPerHour, scale: 100),
                             incrementHundredthsKph: try units(speed.minimumIncrementKilometresPerHour, scale: 100)),
                inclination: .init(minimumTenthsPercent: try units(inclination.minimumPercent, scale: 10),
                                  maximumTenthsPercent: try units(inclination.maximumPercent, scale: 10),
                                  incrementTenthsPercent: try units(inclination.minimumIncrementPercent, scale: 10)),
                observedAt: PlanningProfileSnapshot.timestamp(now()))
            try snapshot.validate()
            completed = true
            profiles.observe(snapshot, peer: peer)
        } catch { profiles.invalidateDiscovery(status: "Invalid capability bounds or increment — no saved profile change."); completed = true }
    }
    private func units(_ value: Double, scale: Double) throws -> Int {
        let scaled = value * scale
        // Parser values are integer FTMS units; allow only binary floating representation noise.
        guard scaled.isFinite, abs(scaled - scaled.rounded()) < 0.00000001, abs(scaled) <= 65535 else {
            throw PlanningProfileFailure.invalidEvidence
        }
        return Int(scaled.rounded())
    }
}

private extension TreadmillConnectionState {
    var isProfileConnected: Bool { if case .connected = self { return true }; return false }
}
