import Foundation

// Authoring-only historical evidence. Never an execution-valid token.
enum HistoricalPlanningSelection: Equatable {
    case none
    case unavailable(String)
    case profile(PlanningProfile)
}
struct HistoricalPlanCompatibility: Equatable {
    struct Mismatch: Equatable, Identifiable {
        let stepIndex: Int
        let target: String
        let value: Decimal
        let minimum: Decimal
        let maximum: Decimal
        let increment: Decimal
        let outOfRange: Bool
        var id: String { "steps[\(stepIndex)].\(target)" }
    }
    let plan: WorkoutPlan
    let selection: HistoricalPlanningSelection
    let mismatches: [Mismatch]
    let ageWarning: String?
    var isMismatch: Bool { !mismatches.isEmpty }
    var profile: PlanningProfile? { if case .profile(let profile) = selection { return profile }; return nil }
    var title: String {
        if isMismatch { return mismatches.contains(where: \.outOfRange) ? "Outside saved profile range" : "Outside saved profile increment" }
        return profile == nil ? "Treadmill compatibility not yet checked" : "Validated against saved profile"
    }
}
enum HistoricalPlanCompatibilityPolicy {
    static func compare(_ token: CanonicalWorkoutAuthoringValidator.ValidatedPlan,
                        selection: HistoricalPlanningSelection, at now: Date) -> HistoricalPlanCompatibility {
        guard case .profile(let profile) = selection else {
            return .init(plan: token.plan, selection: selection, mismatches: [], ageWarning: nil)
        }
        do { try profile.validate() } catch {
            return .init(plan: token.plan, selection: .unavailable("Saved profile is invalid or incomplete. Compatibility has not been checked."), mismatches: [], ageWarning: nil)
        }
        var mismatches: [HistoricalPlanCompatibility.Mismatch] = []
        for (index, step) in token.plan.steps.enumerated() {
            let speed = profile.snapshot.speed
            let incline = profile.snapshot.inclination
            for (target, value, minimum, maximum, increment) in [
                ("speed", step.targetSpeed.value, Decimal(speed.minimumHundredthsKph) / 100, Decimal(speed.maximumHundredthsKph) / 100, Decimal(speed.incrementHundredthsKph) / 100),
                ("inclination", step.targetInclination.value, Decimal(incline.minimumTenthsPercent) / 10, Decimal(incline.maximumTenthsPercent) / 10, Decimal(incline.incrementTenthsPercent) / 10)
            ] {
                let outside = value < minimum || value > maximum
                // Bound before arithmetic: huge canonical values cannot overflow comparison math.
                if outside || !aligned(value, minimum: minimum, increment: increment) {
                    mismatches.append(.init(stepIndex: index, target: target, value: value, minimum: minimum,
                                            maximum: maximum, increment: increment, outOfRange: outside))
                }
            }
        }
        return .init(plan: token.plan, selection: selection, mismatches: mismatches, ageWarning: profile.snapshot.ageWarning(at: now))
    }
    private static func aligned(_ value: Decimal, minimum: Decimal, increment: Decimal) -> Bool {
        // Only an exactly represented integral quotient can match the minimum-origin grid.
        var source = value
        var origin = minimum
        var delta = Decimal()
        guard NSDecimalSubtract(&delta, &source, &origin, .plain) == .noError else { return false }
        var divisor = increment
        var quotient = Decimal()
        guard NSDecimalDivide(&quotient, &delta, &divisor, .plain) == .noError else { return false }
        var integral = Decimal()
        NSDecimalRound(&integral, &quotient, 0, .plain)
        return quotient == integral
    }
}
