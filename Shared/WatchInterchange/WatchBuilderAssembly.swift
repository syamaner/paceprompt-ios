import Foundation

struct WatchBuilderActivity: Equatable {
    let start: Date
    let end: Date?
    let activity: String
    let indoor: Bool
}

// Consumer-owned seam for deterministic testing of the real assembly policy.
// All SDK objects stay inside the implementation of this port.
@MainActor protocol WatchBuilderOperations: AnyObject {
    var collectionStarted: Bool { get }
    var activityStopped: Bool { get }
    var sourceExcludesDistance: Bool { get }
    var hasDistance: Bool { get }
    var distanceAuthorized: Bool { get }
    var activities: [WatchBuilderActivity] { get }
    func endCollection(at: Date) async throws
    func addActivity(_ interval: WatchInterval, summaryID: String, activity: String) async throws
    func addDistance(metres: Decimal, summaryID: String, start: Date, end: Date) async throws
    func distanceSampleEvidence() -> WatchDistanceSampleEvidence
    func addMetadata(_ value: WatchAssembly, distanceDecision: WatchNativeDistanceDecision) async throws
}

@MainActor struct WatchBuilderAssemblyWriter {
    let builder: any WatchBuilderOperations
    var stage: (WatchSaveStage) -> Void = { _ in }
    var validate: () throws -> Void = {}
    func assemble(_ value: WatchAssembly) async throws {
        try validate()
        stage(.assemblyValidation)
        guard [1, 2, 3].contains(value.interchangeVersion),
              builder.collectionStarted, builder.activityStopped, !value.intervals.isEmpty,
              value.end > value.start, builder.activities.isEmpty, !builder.hasDistance,
              builder.sourceExcludesDistance else { throw WatchStoreError.definite }
        guard value.intervals.allSatisfy({ interval in
            interval.startedAt >= value.start && interval.endedAt <= value.end
                && (value.interchangeVersion == 1) == (interval.intervalDistance == nil)
                && (interval.intervalDistance.map { $0.isValid(start: interval.startedAt, end: interval.endedAt) } ?? true)
        }) else { throw WatchStoreError.definite }
        // SDK callback failures may leave partial mutation; never retry them in another builder.
        stage(.activities)
        for interval in value.intervals {
            do { try await builder.addActivity(interval, summaryID: value.summaryID, activity: value.activity) }
            catch { throw WatchStoreError.ambiguous }
            try validate()
        }
        let expected = value.intervals.map { WatchBuilderActivity(start: $0.startedAt, end: $0.endedAt, activity: value.activity, indoor: true) }
        guard builder.activities == expected, !builder.hasDistance, builder.sourceExcludesDistance else { throw WatchStoreError.definite }
        // HealthKit requires an active builder when adding workout activities.
        // Keep collection open through exact interval assembly, then close it.
        stage(.endCollection)
        do { try await builder.endCollection(at: value.end) } catch { throw WatchStoreError.ambiguous }
        try validate()
        guard builder.activities == expected, !builder.hasDistance, builder.sourceExcludesDistance else { throw WatchStoreError.definite }
        stage(.distance)
        var decision = WatchNativeDistanceDecision.suppressed(.notAccepted)
        if value.interchangeVersion == 3 {
            decision = WatchDistanceSamplePolicy.decision(distance: value.distance, authorized: builder.distanceAuthorized,
                                                         start: value.start, end: value.end, evidence: builder.distanceSampleEvidence())
        } else if value.distance.state == "accepted", let metres = value.distance.metres, metres.isFinite, metres > 0,
                  value.distance.provenance == "fr30zCumulativeDistanceDelta", builder.distanceAuthorized {
            decision = .included
        }
        if decision == .included, let metres = value.distance.metres {
            do { try await builder.addDistance(metres: metres, summaryID: value.summaryID, start: value.start, end: value.end) }
            catch { throw WatchStoreError.ambiguous }
            try validate()
        }
        stage(.metadata)
        // Metadata failure is documented as non-mutating by HKWorkoutBuilder.
        do { try await builder.addMetadata(value, distanceDecision: decision) } catch { throw WatchStoreError.definite }
        try validate()
    }
}


// Native timing enters as plain values; sample safety is a closed, deterministic policy.
struct WatchDistanceSampleEvidence: Equatable {
    struct Event: Equatable {
        enum Kind: Equatable { case pause, resume, annotation, unsupported }
        let kind: Kind
        let start: Date
        let end: Date
    }
    let collectionStart: Date?
    let collectionEnd: Date?
    let events: [Event]
}

enum WatchNativeDistanceDecision: Equatable {
    enum Reason: String { case pauseOverlap, uncertainTemporalCoverage, zeroAggregate, notAccepted, writeNotAuthorized }
    case included
    case suppressed(Reason)
    var included: Bool { self == .included }
    var reason: Reason? { if case let .suppressed(reason) = self { return reason }; return nil }
}

enum WatchDistanceSamplePolicy {
    static func decision(distance: WatchDistance, authorized: Bool, start: Date, end: Date,
                         evidence: WatchDistanceSampleEvidence) -> WatchNativeDistanceDecision {
        guard distance.state == "accepted", let metres = distance.metres, metres.isFinite, metres >= 0,
              distance.provenance == "fr30zCumulativeDistanceDelta" else { return .suppressed(.notAccepted) }
        if metres == 0 { return .suppressed(.zeroAggregate) }
        guard authorized else { return .suppressed(.writeNotAuthorized) }
        guard let collectionStart = evidence.collectionStart, let collectionEnd = evidence.collectionEnd,
              [start, end, collectionStart, collectionEnd].allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
              collectionStart < collectionEnd, start > collectionStart, end <= collectionEnd, start < end else {
            return .suppressed(.uncertainTemporalCoverage)
        }
        var previous = collectionStart
        var pause: Date?
        var overlap = false
        for (index, event) in evidence.events.enumerated() {
            let finalRoundedPause = index == evidence.events.count - 1 && event.kind == .pause
                && event.start == event.end && event.start > collectionEnd
                && event.start.timeIntervalSinceReferenceDate.isFinite
                && WatchWire.timestamp(event.start) == collectionEnd
            guard event.start.timeIntervalSinceReferenceDate.isFinite, event.end.timeIntervalSinceReferenceDate.isFinite,
                  event.start >= previous, event.start >= collectionStart, event.end >= event.start,
                  (event.end <= collectionEnd || finalRoundedPause) else { return .suppressed(.uncertainTemporalCoverage) }
            previous = event.start
            switch event.kind {
            case .unsupported: return .suppressed(.uncertainTemporalCoverage)
            case .annotation: continue
            case .pause:
                guard event.start == event.end, pause == nil else { return .suppressed(.uncertainTemporalCoverage) }
                pause = event.start
            case .resume:
                guard event.start == event.end, let pausedAt = pause, event.start > pausedAt else { return .suppressed(.uncertainTemporalCoverage) }
                if max(start, pausedAt) < min(end, event.start) { overlap = true }
                pause = nil
            }
        }
        if let pause, max(start, pause) < end { overlap = true }
        return overlap ? .suppressed(.pauseOverlap) : .included
    }
}
