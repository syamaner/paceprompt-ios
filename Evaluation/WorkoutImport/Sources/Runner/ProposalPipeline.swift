import Foundation

struct CanonicalMappingFailure: Error, Equatable, Sendable {
    let code: String
    let path: String
}

enum ProposalPipelineClassification: String, Equatable, Sendable {
    case notAttempted
    case mappedAndValidated
    case failedCanonicalMapping
    case invalidLocalPlan
    case localValidationBlocked
}

struct ProposalPipelineResult: Equatable, Sendable {
    let classification: ProposalPipelineClassification
    let mappingFailure: CanonicalMappingFailure?
    let validationIssues: [WorkoutPlanValidationIssue]

    static let notAttempted = ProposalPipelineResult(
        classification: .notAttempted,
        mappingFailure: nil,
        validationIssues: []
    )
}

enum WorkoutProposalCanonicalMapper {
    static func map(_ proposal: WorkoutProposalV1) -> Result<WorkoutPlan, CanonicalMappingFailure> {
        guard proposal.contractVersion == WorkoutImportEvaluationContract.proposalContractVersion else {
            return .failure(.init(code: "unsupportedContractVersion", path: "contractVersion"))
        }
        guard let activity = WorkoutActivity(rawValue: proposal.activity) else {
            return .failure(.init(code: "unsupportedActivity", path: "activity"))
        }
        var mappedSteps: [WorkoutStep] = []
        for (index, step) in proposal.steps.enumerated() {
            guard let kind = WorkoutStepKind(rawValue: step.kind) else {
                return .failure(.init(code: "unsupportedStepKind", path: "steps[\(index)].kind"))
            }
            var duration = step.duration.value
            switch step.duration.unit {
            case "seconds": break
            case "minutes": duration *= 60
            default:
                return .failure(.init(code: "unsupportedDurationUnit", path: "steps[\(index)].duration.unit"))
            }
            var roundedDuration = Decimal()
            var sourceDuration = duration
            NSDecimalRound(&roundedDuration, &sourceDuration, 0, .plain)
            guard roundedDuration == duration,
                  duration > 0,
                  duration <= Decimal(Int.max) else {
                return .failure(.init(
                    code: "nonIntegralCanonicalDuration",
                    path: "steps[\(index)].duration.value"
                ))
            }

            var speed = step.targetSpeed.value
            switch step.targetSpeed.unit {
            case "kilometresPerHour": break
            case "milesPerHour": speed *= Decimal(string: "1.609344")!
            default:
                return .failure(.init(code: "unsupportedSpeedUnit", path: "steps[\(index)].targetSpeed.unit"))
            }
            guard step.targetInclination.unit == "percent" else {
                return .failure(.init(
                    code: "unsupportedInclinationUnit",
                    path: "steps[\(index)].targetInclination.unit"
                ))
            }
            mappedSteps.append(
                WorkoutStep(
                    kind: kind,
                    label: step.label,
                    duration: .init(value: NSDecimalNumber(decimal: duration).intValue, unit: .seconds),
                    targetSpeed: .init(value: speed, unit: .kilometresPerHour),
                    targetInclination: .init(value: step.targetInclination.value, unit: .percent)
                )
            )
        }
        return .success(
            WorkoutPlan(
                schemaVersion: WorkoutPlanSchema.currentVersion,
                suggestedName: proposal.suggestedName,
                activity: activity,
                steps: mappedSteps
            )
        )
    }
}

enum WorkoutProposalLocalPipeline {
    static func process(
        _ outcome: NormalizedGeneratorOutcome,
        capabilities: WorkoutImportCapabilities
    ) -> ProposalPipelineResult {
        guard case let .proposal(proposal) = outcome else { return .notAttempted }
        let plan: WorkoutPlan
        switch WorkoutProposalCanonicalMapper.map(proposal) {
        case let .failure(error):
            return ProposalPipelineResult(
                classification: .failedCanonicalMapping,
                mappingFailure: error,
                validationIssues: []
            )
        case let .success(mapped):
            plan = mapped
        }
        switch WorkoutPlanValidator.validate(plan, against: canonicalCapabilities(capabilities)) {
        case .success:
            return ProposalPipelineResult(
                classification: .mappedAndValidated,
                mappingFailure: nil,
                validationIssues: []
            )
        case let .failure(failure):
            let blockingCodes: Set<WorkoutPlanValidationIssue.Code> = [
                .capabilityUnknown, .targetUnsupported, .invalidCapabilityRange
            ]
            let classification: ProposalPipelineClassification = failure.issues.contains {
                blockingCodes.contains($0.code)
            } ? .localValidationBlocked : .invalidLocalPlan
            return ProposalPipelineResult(
                classification: classification,
                mappingFailure: nil,
                validationIssues: failure.issues
            )
        }
    }

    private static func canonicalCapabilities(
        _ capabilities: WorkoutImportCapabilities
    ) -> WorkoutPlanCapabilities {
        WorkoutPlanCapabilities(
            speed: speedCapability(capabilities.speed),
            inclination: inclinationCapability(capabilities.inclination)
        )
    }

    private static func speedCapability(
        _ capability: WorkoutImportCapability
    ) -> WorkoutTargetCapability<WorkoutSpeedRange> {
        switch capability.state {
        case .unknown: return .unknown
        case .unsupported: return .unsupported
        case .supported:
            return .supported(
                WorkoutSpeedRange(
                    minimum: .init(value: capability.minimum ?? .nan, unit: .kilometresPerHour),
                    maximum: .init(value: capability.maximum ?? .nan, unit: .kilometresPerHour),
                    increment: .init(value: capability.increment ?? .nan, unit: .kilometresPerHour)
                )
            )
        }
    }

    private static func inclinationCapability(
        _ capability: WorkoutImportCapability
    ) -> WorkoutTargetCapability<WorkoutInclinationRange> {
        switch capability.state {
        case .unknown: return .unknown
        case .unsupported: return .unsupported
        case .supported:
            return .supported(
                WorkoutInclinationRange(
                    minimum: .init(value: capability.minimum ?? .nan, unit: .percent),
                    maximum: .init(value: capability.maximum ?? .nan, unit: .percent),
                    increment: .init(value: capability.increment ?? .nan, unit: .percent)
                )
            )
        }
    }
}
