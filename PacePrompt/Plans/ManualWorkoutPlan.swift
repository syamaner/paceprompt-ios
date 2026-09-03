import Foundation

struct ManualWorkoutDraft: Equatable {
    var suggestedName: String
    var activity: WorkoutActivity
    var steps: [ManualWorkoutStepDraft]

    static let empty = ManualWorkoutDraft(
        suggestedName: "",
        activity: .indoorWalking,
        steps: []
    )

    init(
        suggestedName: String,
        activity: WorkoutActivity,
        steps: [ManualWorkoutStepDraft]
    ) {
        self.suggestedName = suggestedName
        self.activity = activity
        self.steps = steps
    }

    init(plan: WorkoutPlan) {
        suggestedName = plan.suggestedName
        activity = plan.activity
        steps = plan.steps.map(ManualWorkoutStepDraft.init)
    }
}

struct ManualWorkoutStepDraft: Identifiable, Equatable {
    let id: UUID
    var kind: WorkoutStepKind
    var label: String
    var durationSeconds: String
    var speedKilometresPerHour: String
    var inclinationPercent: String

    init(
        id: UUID = UUID(),
        kind: WorkoutStepKind,
        label: String = "",
        durationSeconds: String = "",
        speedKilometresPerHour: String = "",
        inclinationPercent: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.durationSeconds = durationSeconds
        self.speedKilometresPerHour = speedKilometresPerHour
        self.inclinationPercent = inclinationPercent
    }

    init(step: WorkoutStep) {
        self.init(
            kind: step.kind,
            label: step.label,
            durationSeconds: String(step.duration.value),
            speedKilometresPerHour: PlanValueFormatter.domainText(step.targetSpeed.value),
            inclinationPercent: PlanValueFormatter.domainText(step.targetInclination.value)
        )
    }
}

struct ManualWorkoutInputIssue: Equatable {
    let path: String
    let message: String
}

struct ManualWorkoutInputFailure: Error, Equatable {
    let issues: [ManualWorkoutInputIssue]
}

enum ManualWorkoutDraftParser {
    static func parse(
        _ draft: ManualWorkoutDraft,
        locale: Locale = .autoupdatingCurrent
    ) -> Result<WorkoutPlan, ManualWorkoutInputFailure> {
        var parsedSteps: [WorkoutStep] = []
        var issues: [ManualWorkoutInputIssue] = []

        for (index, step) in draft.steps.enumerated() {
            let duration = parseInteger(
                step.durationSeconds,
                locale: locale,
                path: "steps[\(index)].duration.value",
                message: "Enter step \(index + 1) duration as a whole number of seconds.",
                issues: &issues
            )
            let speed = parseDecimal(
                step.speedKilometresPerHour,
                locale: locale,
                path: "steps[\(index)].targetSpeed.value",
                message: "Enter step \(index + 1) speed as a number in km/h.",
                issues: &issues
            )
            let inclination = parseDecimal(
                step.inclinationPercent,
                locale: locale,
                path: "steps[\(index)].targetInclination.value",
                message: "Enter step \(index + 1) inclination as a percentage.",
                issues: &issues
            )

            if let duration, let speed, let inclination {
                parsedSteps.append(
                    WorkoutStep(
                        kind: step.kind,
                        label: step.label,
                        duration: .init(value: duration, unit: .seconds),
                        targetSpeed: .init(value: speed, unit: .kilometresPerHour),
                        targetInclination: .init(value: inclination, unit: .percent)
                    )
                )
            }
        }

        guard issues.isEmpty else {
            return .failure(ManualWorkoutInputFailure(issues: issues))
        }

        return .success(
            WorkoutPlan(
                schemaVersion: WorkoutPlanSchema.currentVersion,
                suggestedName: draft.suggestedName,
                activity: draft.activity,
                steps: parsedSteps
            )
        )
    }

    private static func parseInteger(
        _ value: String,
        locale: Locale,
        path: String,
        message: String,
        issues: inout [ManualWorkoutInputIssue]
    ) -> Int? {
        guard let normalized = normalizedNumber(value, locale: locale, allowsDecimal: false),
              let result = Int(normalized) else {
            issues.append(.init(path: path, message: message))
            return nil
        }
        return result
    }

    private static func parseDecimal(
        _ value: String,
        locale: Locale,
        path: String,
        message: String,
        issues: inout [ManualWorkoutInputIssue]
    ) -> Decimal? {
        guard let normalized = normalizedNumber(value, locale: locale, allowsDecimal: true),
              let result = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            issues.append(.init(path: path, message: message))
            return nil
        }
        return result
    }

    private static func normalizedNumber(
        _ value: String,
        locale: Locale,
        allowsDecimal: Bool
    ) -> String? {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return nil }

        if let groupingSeparator = locale.groupingSeparator,
           !groupingSeparator.isEmpty,
           groupingSeparator != locale.decimalSeparator,
           result.contains(groupingSeparator) {
            return nil
        }
        if let decimalSeparator = locale.decimalSeparator,
           decimalSeparator != ".",
           !decimalSeparator.isEmpty {
            result = result.replacingOccurrences(of: decimalSeparator, with: ".")
        }

        var digitCount = 0
        var decimalCount = 0
        for (index, character) in result.enumerated() {
            if character.isNumber {
                digitCount += 1
            } else if (character == "+" || character == "-") && index == 0 {
                continue
            } else if character == "." && allowsDecimal {
                decimalCount += 1
            } else {
                return nil
            }
        }
        guard digitCount > 0, decimalCount <= 1 else { return nil }
        return result
    }
}

struct WorkoutPlanPreview: Equatable {
    let validatedPlan: WorkoutPlanValidator.ValidatedPlan
    let totalDurationSeconds: Decimal
    let estimatedDistanceKilometres: Decimal

    var plan: WorkoutPlan { validatedPlan.plan }

    init(validatedPlan: WorkoutPlanValidator.ValidatedPlan) {
        self.validatedPlan = validatedPlan
        totalDurationSeconds = validatedPlan.plan.steps.reduce(Decimal.zero) {
            $0 + Decimal($1.duration.value)
        }
        estimatedDistanceKilometres = validatedPlan.plan.steps.reduce(Decimal.zero) {
            $0 + ($1.targetSpeed.value * Decimal($1.duration.value) / Decimal(3_600))
        }
    }
}

enum PlanValueFormatter {
    static func domainText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func localizedText(_ value: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        let text = domainText(value)
        guard let separator = locale.decimalSeparator, separator != "." else { return text }
        return text.replacingOccurrences(of: ".", with: separator)
    }

    static func estimatedDistanceText(
        _ value: Decimal,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? domainText(value)
    }
}
