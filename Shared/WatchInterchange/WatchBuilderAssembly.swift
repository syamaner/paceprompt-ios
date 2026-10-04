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
    func addMetadata(_ value: WatchAssembly, distanceIncluded: Bool) async throws
}

@MainActor struct WatchBuilderAssemblyWriter {
    let builder: any WatchBuilderOperations
    var stage: (WatchSaveStage) -> Void = { _ in }
    var validate: () throws -> Void = {}
    func assemble(_ value: WatchAssembly) async throws {
        try validate()
        stage(.assemblyValidation)
        guard builder.collectionStarted, builder.activityStopped, !value.intervals.isEmpty,
              value.end > value.start, builder.activities.isEmpty, !builder.hasDistance,
              builder.sourceExcludesDistance else { throw WatchStoreError.definite }
        // SDK callback failures may leave partial mutation; never retry them in another builder.
        stage(.activities)
        for interval in value.intervals {
            guard interval.startedAt >= value.start, interval.endedAt <= value.end,
                  interval.intervalDistance.map({ $0.isValid(start: interval.startedAt, end: interval.endedAt) }) ?? true else { throw WatchStoreError.definite }
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
        var included = false
        if value.distance.state == "accepted", let metres = value.distance.metres, metres.isFinite, metres > 0,
           value.distance.provenance == "fr30zCumulativeDistanceDelta", builder.distanceAuthorized {
            do { try await builder.addDistance(metres: metres, summaryID: value.summaryID, start: value.start, end: value.end) }
            catch { throw WatchStoreError.ambiguous }
            try validate()
            included = true
        }
        stage(.metadata)
        // Metadata failure is documented as non-mutating by HKWorkoutBuilder.
        do { try await builder.addMetadata(value, distanceIncluded: included) } catch { throw WatchStoreError.definite }
        try validate()
    }
}
