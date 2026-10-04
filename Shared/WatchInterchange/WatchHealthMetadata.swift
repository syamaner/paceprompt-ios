import Foundation

enum WatchHealthMetadata {
    static let namespace = "com.otherweather.PromptPace."
    static func workout(_ value: WatchAssembly, distanceDecision: WatchNativeDistanceDecision) -> [String: Any] {
        let n = namespace
        var result: [String: Any] = [n+"interchangeSchemaVersion": value.interchangeVersion,
            n+"summaryID": value.summaryID, n+"ownership": "watchPrimary", n+"interchangeStatus": value.complete ? "complete" : "incomplete",
            n+"manifestRevision": NSNumber(value: value.revision), n+"intervalCount": value.intervals.count,
            n+"distanceProvenance": distanceDecision.included ? "fr30zCumulativeDistanceDelta" : "unavailable"]
        guard value.interchangeVersion == 3 else { return result }
        result[n+"acceptedDistanceSchemaVersion"] = 1
        if value.distance.state == "accepted", let metres = value.distance.metres, metres.isFinite, metres >= 0,
           value.distance.provenance == "fr30zCumulativeDistanceDelta" {
            result[n+"acceptedDistanceState"] = "accepted"
            var canonical = metres
            result[n+"acceptedDistanceMetres"] = NSDecimalString(&canonical, Locale(identifier: "en_US_POSIX"))
            result[n+"acceptedDistanceProvenance"] = "fr30zCumulativeDistanceDelta"
        } else {
            result[n+"acceptedDistanceState"] = "unavailable"
            result[n+"acceptedDistanceReason"] = "notAccepted"
        }
        result[n+"nativeDistanceSampleState"] = distanceDecision.included ? "included" : "suppressed"
        if let reason = distanceDecision.reason { result[n+"nativeDistanceSampleReason"] = reason.rawValue }
        return result
    }
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
