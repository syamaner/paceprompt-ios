import Foundation

enum WatchHealthMetadata {
    static let namespace = "com.otherweather.PromptPace."
    static func interval(_ i: WatchInterval, summaryID: String) -> [String: Any] {
        let n = namespace
        var result: [String: Any] = [n+"timelineSchemaVersion": 1, n+"summaryID": summaryID, n+"segmentIndex": i.segmentIndex, n+"intervalIndex": i.intervalIndex,
                n+"prescribedSegmentKind": i.prescribed.kind, n+"prescribedSpeedKilometresPerHour": NSDecimalNumber(decimal: i.prescribed.speedKilometresPerHour),
                n+"prescribedInclinationPercent": NSDecimalNumber(decimal: i.prescribed.inclinationPercent),
                n+"effectiveTargetSpeedKilometresPerHour": NSDecimalNumber(decimal: i.effectiveSpeed.kilometresPerHour),
                n+"effectiveTargetInclinationPercent": NSDecimalNumber(decimal: i.effectiveInclination.percent),
                n+"speedTargetSource": i.effectiveSpeed.source, n+"inclinationTargetSource": i.effectiveInclination.source,
                n+"observedSpeedKilometresPerHour": NSDecimalNumber(decimal: i.settledObservation.speedKilometresPerHour),
                n+"observedInclinationPercent": NSDecimalNumber(decimal: i.settledObservation.inclinationPercent),
                n+"observedAt": i.settledObservation.observedAt, n+"observationProvenance": i.settledObservation.provenance, n+"intervalEndReason": i.endReason]
        if let d = i.intervalDistance {
            result[n+"intervalDistanceSchemaVersion"] = d.schemaVersion
            result[n+"intervalDistanceState"] = d.state
            if let reason = d.reason { result[n+"intervalDistanceReason"] = reason }
            if let value = d.metres { result[n+"intervalDistanceMetres"] = NSDecimalNumber(decimal: value) }
            if let value = d.startCumulativeMetres { result[n+"intervalDistanceStartCumulativeMetres"] = NSDecimalNumber(decimal: value) }
            if let value = d.endCumulativeMetres { result[n+"intervalDistanceEndCumulativeMetres"] = NSDecimalNumber(decimal: value) }
            if let value = d.startObservedAt { result[n+"intervalDistanceStartObservedAt"] = value }
            if let value = d.endObservedAt { result[n+"intervalDistanceEndObservedAt"] = value }
            if let value = d.provenance { result[n+"intervalDistanceProvenance"] = value }
        }
        return result
    }
}
