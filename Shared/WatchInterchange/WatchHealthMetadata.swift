import Foundation

enum WatchHealthMetadata {
    static let namespace = "com.otherweather.PromptPace."
    static func interval(_ i: WatchInterval, summaryID: String) -> [String: Any] {
        let n = namespace
        return [n+"timelineSchemaVersion": 1, n+"summaryID": summaryID, n+"segmentIndex": i.segmentIndex, n+"intervalIndex": i.intervalIndex,
                n+"prescribedSegmentKind": i.prescribed.kind, n+"prescribedSpeedKilometresPerHour": NSDecimalNumber(decimal: i.prescribed.speedKilometresPerHour),
                n+"prescribedInclinationPercent": NSDecimalNumber(decimal: i.prescribed.inclinationPercent),
                n+"effectiveTargetSpeedKilometresPerHour": NSDecimalNumber(decimal: i.effectiveSpeed.kilometresPerHour),
                n+"effectiveTargetInclinationPercent": NSDecimalNumber(decimal: i.effectiveInclination.percent),
                n+"speedTargetSource": i.effectiveSpeed.source, n+"inclinationTargetSource": i.effectiveInclination.source,
                n+"observedSpeedKilometresPerHour": NSDecimalNumber(decimal: i.settledObservation.speedKilometresPerHour),
                n+"observedInclinationPercent": NSDecimalNumber(decimal: i.settledObservation.inclinationPercent),
                n+"observedAt": i.settledObservation.observedAt, n+"observationProvenance": i.settledObservation.provenance, n+"intervalEndReason": i.endReason]
    }
}
