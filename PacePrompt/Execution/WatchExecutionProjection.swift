import Foundation

// A one-way value projection. No mirror callback receives an execution or control capability.
enum WatchExecutionProjection {
    static func intervals(_ values: [WorkoutExecutedInterval]) -> [WatchInterval] {
        values.map { i in
            .init(segmentIndex: i.segmentIndex, intervalIndex: i.intervalIndex, startedAt: i.startedAt, endedAt: i.endedAt,
                  prescribed: .init(kind: i.prescribed.kind.rawValue, speedKilometresPerHour: i.prescribed.speedKilometresPerHour, inclinationPercent: i.prescribed.inclinationPercent),
                  effectiveSpeed: .init(kilometresPerHour: i.effectiveSpeed.kilometresPerHour, source: i.effectiveSpeed.source.rawValue),
                  effectiveInclination: .init(percent: i.effectiveInclination.percent, source: i.effectiveInclination.source.rawValue),
                  settledObservation: .init(observedAt: i.settledObservation.observedAt, speedKilometresPerHour: i.settledObservation.speedKilometresPerHour, inclinationPercent: i.settledObservation.inclinationPercent, provenance: i.settledObservation.provenance.rawValue),
                  endReason: i.endReason.rawValue, intervalDistance: i.intervalDistance)
        }
    }
    static func outcome(_ summary: WorkoutExecutionSummary?) -> String? {
        guard let summary else { return nil }
        switch summary.outcome {
        case .inProgress: return nil
        case .completed: return "completed"
        case .stoppedByUser: return "stoppedByUser"
        case .failed: return "failed"
        case .interrupted: return "interrupted"
        }
    }
    static func distance(_ summary: WorkoutExecutionSummary?) -> WatchDistance {
        guard let summary, case let .measuredWithProvenance(metres, provenance) = summary.distance,
              case let .recorded(start, end, _, _)? = summary.activityTimeline,
              metres >= 0, metres.isFinite, provenance.method == .fr30zCumulativeDistanceDelta,
              provenance.startCumulativeMetres >= 0, provenance.finalCumulativeMetres >= provenance.startCumulativeMetres,
              provenance.finalCumulativeMetres - provenance.startCumulativeMetres == metres,
              provenance.startObservedAt == start, provenance.finalObservedAt >= end else { return .unavailable }
        return .init(state: "accepted", metres: metres, provenance: "fr30zCumulativeDistanceDelta")
    }
}
