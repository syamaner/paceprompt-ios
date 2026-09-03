import Foundation

struct WorkoutPlanValidationIssue: Equatable {
    enum Code: String, Equatable {
        case unsupportedSchemaVersion
        case missingSuggestedName
        case missingSteps
        case invalidStepOrder
        case missingInterval
        case missingStepLabel
        case invalidDuration
        case capabilityUnknown
        case targetUnsupported
        case invalidCapabilityRange
        case nonFiniteTarget
        case targetOutOfRange
        case targetNotIncrementAligned
    }

    let code: Code
    let path: String
    let message: String
}

struct WorkoutPlanValidationFailure: Error, Equatable, LocalizedError {
    let issues: [WorkoutPlanValidationIssue]

    var errorDescription: String? {
        issues.map(\.message).joined(separator: "\n")
    }
}

enum WorkoutPlanValidator {
    struct ValidatedPlan: Equatable {
        let plan: WorkoutPlan

        fileprivate init(plan: WorkoutPlan) {
            self.plan = plan
        }
    }

    static func validate(
        _ plan: WorkoutPlan,
        against capabilities: WorkoutPlanCapabilities
    ) -> Result<ValidatedPlan, WorkoutPlanValidationFailure> {
        var issues: [WorkoutPlanValidationIssue] = []

        validateStructure(plan, issues: &issues)
        let speedRange = validateSpeedCapability(capabilities.speed, issues: &issues)
        let inclinationRange = validateInclinationCapability(capabilities.inclination, issues: &issues)

        for (index, step) in plan.steps.enumerated() {
            validateStep(step, at: index, issues: &issues)

            if let speedRange {
                validateTarget(
                    step.targetSpeed.value,
                    range: speedRange,
                    targetName: "speed",
                    unit: "km/h",
                    path: "steps[\(index)].targetSpeed.value",
                    stepNumber: index + 1,
                    issues: &issues
                )
            }
            if let inclinationRange {
                validateTarget(
                    step.targetInclination.value,
                    range: inclinationRange,
                    targetName: "inclination",
                    unit: "%",
                    path: "steps[\(index)].targetInclination.value",
                    stepNumber: index + 1,
                    issues: &issues
                )
            }
        }

        guard issues.isEmpty else {
            return .failure(WorkoutPlanValidationFailure(issues: issues))
        }
        return .success(ValidatedPlan(plan: plan))
    }

    private static func validateStructure(
        _ plan: WorkoutPlan,
        issues: inout [WorkoutPlanValidationIssue]
    ) {
        if plan.schemaVersion != WorkoutPlanSchema.currentVersion {
            issues.append(
                .init(
                    code: .unsupportedSchemaVersion,
                    path: "schemaVersion",
                    message: "Schema version \(plan.schemaVersion) is unsupported. Use version \(WorkoutPlanSchema.currentVersion)."
                )
            )
        }

        if plan.suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                .init(
                    code: .missingSuggestedName,
                    path: "suggestedName",
                    message: "Add a workout name."
                )
            )
        }

        guard !plan.steps.isEmpty else {
            issues.append(
                .init(
                    code: .missingSteps,
                    path: "steps",
                    message: "Add ordered warm-up, interval and cool-down steps."
                )
            )
            return
        }

        if plan.steps.first?.kind != .warmUp {
            issues.append(
                .init(
                    code: .invalidStepOrder,
                    path: "steps[0].kind",
                    message: "The first step must be a warm-up."
                )
            )
        }

        let finalIndex = plan.steps.index(before: plan.steps.endIndex)
        if plan.steps[finalIndex].kind != .coolDown {
            issues.append(
                .init(
                    code: .invalidStepOrder,
                    path: "steps[\(finalIndex)].kind",
                    message: "The final step must be a cool-down."
                )
            )
        }

        if !plan.steps.contains(where: { $0.kind == .interval }) {
            issues.append(
                .init(
                    code: .missingInterval,
                    path: "steps",
                    message: "Add at least one interval step between the warm-up and cool-down."
                )
            )
        }

        for (index, step) in plan.steps.enumerated() {
            if step.kind == .warmUp, index != plan.steps.startIndex {
                issues.append(
                    .init(
                        code: .invalidStepOrder,
                        path: "steps[\(index)].kind",
                        message: "Step \(index + 1) is a warm-up, but warm-up is only allowed as the first step."
                    )
                )
            }
            if step.kind == .coolDown, index != finalIndex {
                issues.append(
                    .init(
                        code: .invalidStepOrder,
                        path: "steps[\(index)].kind",
                        message: "Step \(index + 1) is a cool-down, but cool-down is only allowed as the final step."
                    )
                )
            }
        }
    }

    private static func validateStep(
        _ step: WorkoutStep,
        at index: Int,
        issues: inout [WorkoutPlanValidationIssue]
    ) {
        if step.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                .init(
                    code: .missingStepLabel,
                    path: "steps[\(index)].label",
                    message: "Add a label for step \(index + 1)."
                )
            )
        }

        if step.duration.value <= 0 {
            issues.append(
                .init(
                    code: .invalidDuration,
                    path: "steps[\(index)].duration.value",
                    message: "Step \(index + 1) duration must be greater than 0 seconds."
                )
            )
        }
    }

    private static func validateSpeedCapability(
        _ capability: WorkoutTargetCapability<WorkoutSpeedRange>,
        issues: inout [WorkoutPlanValidationIssue]
    ) -> DecimalRange? {
        switch capability {
        case .unknown:
            issues.append(
                .init(
                    code: .capabilityUnknown,
                    path: "capabilities.speed",
                    message: "Speed capability is unknown. Read the treadmill's speed target feature and range before validating this plan."
                )
            )
            return nil
        case .unsupported:
            issues.append(
                .init(
                    code: .targetUnsupported,
                    path: "capabilities.speed",
                    message: "This treadmill reports speed target-setting as unsupported, so the plan cannot be executed."
                )
            )
            return nil
        case let .supported(range):
            return validateRange(
                minimum: range.minimum.value,
                maximum: range.maximum.value,
                increment: range.increment.value,
                targetName: "speed",
                unit: "km/h",
                requiresNonnegativeMinimum: true,
                path: "capabilities.speed",
                issues: &issues
            )
        }
    }

    private static func validateInclinationCapability(
        _ capability: WorkoutTargetCapability<WorkoutInclinationRange>,
        issues: inout [WorkoutPlanValidationIssue]
    ) -> DecimalRange? {
        switch capability {
        case .unknown:
            issues.append(
                .init(
                    code: .capabilityUnknown,
                    path: "capabilities.inclination",
                    message: "Inclination capability is unknown. Read the treadmill's inclination target feature and range before validating this plan."
                )
            )
            return nil
        case .unsupported:
            issues.append(
                .init(
                    code: .targetUnsupported,
                    path: "capabilities.inclination",
                    message: "This treadmill reports inclination target-setting as unsupported, so the plan cannot be executed."
                )
            )
            return nil
        case let .supported(range):
            return validateRange(
                minimum: range.minimum.value,
                maximum: range.maximum.value,
                increment: range.increment.value,
                targetName: "inclination",
                unit: "%",
                requiresNonnegativeMinimum: false,
                path: "capabilities.inclination",
                issues: &issues
            )
        }
    }

    private static func validateRange(
        minimum: Decimal,
        maximum: Decimal,
        increment: Decimal,
        targetName: String,
        unit: String,
        requiresNonnegativeMinimum: Bool,
        path: String,
        issues: inout [WorkoutPlanValidationIssue]
    ) -> DecimalRange? {
        let isInvalid = minimum.isNaN
            || maximum.isNaN
            || increment.isNaN
            || minimum > maximum
            || increment <= 0
            || (requiresNonnegativeMinimum && minimum < 0)

        guard !isInvalid else {
            issues.append(
                .init(
                    code: .invalidCapabilityRange,
                    path: path,
                    message: "The reported \(targetName) capability range is invalid. Re-read a finite minimum, maximum and positive increment in \(unit)."
                )
            )
            return nil
        }

        return DecimalRange(minimum: minimum, maximum: maximum, increment: increment)
    }

    private static func validateTarget(
        _ value: Decimal,
        range: DecimalRange,
        targetName: String,
        unit: String,
        path: String,
        stepNumber: Int,
        issues: inout [WorkoutPlanValidationIssue]
    ) {
        guard !value.isNaN else {
            issues.append(
                .init(
                    code: .nonFiniteTarget,
                    path: path,
                    message: "Step \(stepNumber) \(targetName) must be a finite value in \(unit)."
                )
            )
            return
        }

        guard value >= range.minimum, value <= range.maximum else {
            issues.append(
                .init(
                    code: .targetOutOfRange,
                    path: path,
                    message: "Step \(stepNumber) \(targetName) is \(text(value)) \(unit). Enter a value from \(text(range.minimum)) to \(text(range.maximum)) \(unit)."
                )
            )
            return
        }

        guard isAligned(value, to: range.increment, from: range.minimum) else {
            issues.append(
                .init(
                    code: .targetNotIncrementAligned,
                    path: path,
                    message: "Step \(stepNumber) \(targetName) is \(text(value)) \(unit). Use \(text(range.increment)) \(unit) increments starting at \(text(range.minimum)) \(unit)."
                )
            )
            return
        }
    }

    private static func isAligned(_ value: Decimal, to increment: Decimal, from minimum: Decimal) -> Bool {
        var quotient = (value - minimum) / increment
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .plain)
        return quotient == rounded
    }

    private static func text(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private struct DecimalRange {
        let minimum: Decimal
        let maximum: Decimal
        let increment: Decimal
    }
}
