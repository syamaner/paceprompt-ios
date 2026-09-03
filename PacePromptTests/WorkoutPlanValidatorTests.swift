import Foundation
import XCTest
@testable import PacePrompt

final class WorkoutPlanValidatorTests: XCTestCase {
    func testSchemaDecodesExplicitUnitsAndPreservesStepOrder() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "suggestedName": "Synthetic intervals",
          "activity": "indoorRunning",
          "steps": [
            {
              "kind": "warmUp",
              "label": "Warm up",
              "duration": { "value": 300, "unit": "seconds" },
              "targetSpeed": { "value": 5.5, "unit": "kilometresPerHour" },
              "targetInclination": { "value": 0.0, "unit": "percent" }
            },
            {
              "kind": "interval",
              "label": "Run",
              "duration": { "value": 180, "unit": "seconds" },
              "targetSpeed": { "value": 10.0, "unit": "kilometresPerHour" },
              "targetInclination": { "value": 1.0, "unit": "percent" }
            },
            {
              "kind": "coolDown",
              "label": "Cool down",
              "duration": { "value": 300, "unit": "seconds" },
              "targetSpeed": { "value": 4.5, "unit": "kilometresPerHour" },
              "targetInclination": { "value": 0.0, "unit": "percent" }
            }
          ]
        }
        """#

        let plan = try JSONDecoder().decode(WorkoutPlan.self, from: Data(json.utf8))

        XCTAssertEqual(plan.schemaVersion, WorkoutPlanSchema.currentVersion)
        XCTAssertEqual(plan.activity, .indoorRunning)
        XCTAssertEqual(plan.steps.map(\.kind), [.warmUp, .interval, .coolDown])
        XCTAssertEqual(plan.steps[0].duration.unit, .seconds)
        XCTAssertEqual(plan.steps[1].targetSpeed.unit, .kilometresPerHour)
        XCTAssertEqual(plan.steps[2].targetInclination.unit, .percent)
    }

    func testSchemaRejectsUnsupportedUnitsBeforeValidation() {
        let json = #"""
        {
          "schemaVersion": 1,
          "suggestedName": "Synthetic plan",
          "activity": "indoorWalking",
          "steps": [
            {
              "kind": "warmUp",
              "label": "Warm up",
              "duration": { "value": 300, "unit": "minutes" },
              "targetSpeed": { "value": 5.0, "unit": "kilometresPerHour" },
              "targetInclination": { "value": 0.0, "unit": "percent" }
            }
          ]
        }
        """#

        XCTAssertThrowsError(try JSONDecoder().decode(WorkoutPlan.self, from: Data(json.utf8)))
    }

    func testKnownBoundaryValuesProduceValidatedPlan() throws {
        let plan = validPlan(
            steps: [
                step(.warmUp, label: "Warm up", speed: "0.5", inclination: "-3"),
                step(.interval, label: "Run", speed: "20", inclination: "15"),
                step(.recovery, label: "Recover", speed: "5.5", inclination: "0"),
                step(.coolDown, label: "Cool down", speed: "0.5", inclination: "-3"),
            ]
        )

        let validated = try WorkoutPlanValidator.validate(plan, against: knownCapabilities()).get()

        XCTAssertEqual(validated.plan, plan)
    }

    func testMalformedPlanReturnsEveryActionableStructuralError() {
        let plan = WorkoutPlan(
            schemaVersion: 99,
            suggestedName: "  \n",
            activity: .indoorRunning,
            steps: [
                step(.recovery, label: "", duration: 0),
                step(.warmUp, label: "Late warm-up"),
                step(.coolDown, label: "Early cool-down"),
                step(.recovery, label: "Not a cool-down"),
            ]
        )

        let issues = failure(for: plan, capabilities: knownCapabilities()).issues

        XCTAssertEqual(
            issues.map(\.code),
            [
                .unsupportedSchemaVersion,
                .missingSuggestedName,
                .invalidStepOrder,
                .invalidStepOrder,
                .missingInterval,
                .invalidStepOrder,
                .invalidStepOrder,
                .missingStepLabel,
                .invalidDuration,
            ]
        )
        XCTAssertEqual(issues.first?.path, "schemaVersion")
        XCTAssertEqual(issues.last?.path, "steps[0].duration.value")
        XCTAssertTrue(issues.allSatisfy { !$0.message.isEmpty })
    }

    func testEmptyPlanHasOneStepsErrorWithoutIndexingIt() {
        let plan = validPlan(steps: [])

        let issues = failure(for: plan, capabilities: knownCapabilities()).issues

        XCTAssertEqual(issues.map(\.code), [.missingSteps])
        XCTAssertEqual(issues.map(\.path), ["steps"])
    }

    func testUnknownCapabilityIsNotReportedAsUnsupportedOrInvalid() {
        let capabilities = WorkoutPlanCapabilities(
            speed: .unknown,
            inclination: knownCapabilities().inclination
        )

        let issues = failure(for: validPlan(), capabilities: capabilities).issues

        XCTAssertEqual(issues.map(\.code), [.capabilityUnknown])
        XCTAssertEqual(issues.map(\.path), ["capabilities.speed"])
    }

    func testUnsupportedCapabilityIsNotReportedAsUnknownOrInvalid() {
        let capabilities = WorkoutPlanCapabilities(
            speed: knownCapabilities().speed,
            inclination: .unsupported
        )

        let issues = failure(for: validPlan(), capabilities: capabilities).issues

        XCTAssertEqual(issues.map(\.code), [.targetUnsupported])
        XCTAssertEqual(issues.map(\.path), ["capabilities.inclination"])
    }

    func testInvalidKnownCapabilityRangeIsDistinctFromUnknown() {
        let invalidRange = WorkoutSpeedRange(
            minimum: speed("10"),
            maximum: speed("5"),
            increment: speed("0.1")
        )
        let capabilities = WorkoutPlanCapabilities(
            speed: .supported(invalidRange),
            inclination: knownCapabilities().inclination
        )

        let issues = failure(for: validPlan(), capabilities: capabilities).issues

        XCTAssertEqual(issues.map(\.code), [.invalidCapabilityRange])
        XCTAssertEqual(issues.map(\.path), ["capabilities.speed"])
    }

    func testTargetsOutsideRangeOrOffIncrementAreRejectedWithoutClamping() {
        let plan = validPlan(
            steps: [
                step(.warmUp, label: "Warm up"),
                step(.interval, label: "Run", speed: "20.1", inclination: "1.2"),
                step(.coolDown, label: "Cool down"),
            ]
        )

        let issues = failure(for: plan, capabilities: knownCapabilities()).issues

        XCTAssertEqual(issues.map(\.code), [.targetOutOfRange, .targetNotIncrementAligned])
        XCTAssertEqual(
            issues.map(\.path),
            ["steps[1].targetSpeed.value", "steps[1].targetInclination.value"]
        )
        XCTAssertTrue(issues[0].message.contains("20.1 km/h"))
        XCTAssertTrue(issues[1].message.contains("0.5 % increments"))
        XCTAssertEqual(plan.steps[1].targetSpeed.value, decimal("20.1"))
        XCTAssertEqual(plan.steps[1].targetInclination.value, decimal("1.2"))
    }

    func testNonFiniteTargetIsRejectedBeforeRangeArithmetic() {
        let plan = validPlan(
            steps: [
                step(.warmUp, label: "Warm up"),
                WorkoutStep(
                    kind: .interval,
                    label: "Run",
                    duration: .init(value: 60, unit: .seconds),
                    targetSpeed: .init(value: .nan, unit: .kilometresPerHour),
                    targetInclination: inclination("0")
                ),
                step(.coolDown, label: "Cool down"),
            ]
        )

        let issues = failure(for: plan, capabilities: knownCapabilities()).issues

        XCTAssertEqual(issues.map(\.code), [.nonFiniteTarget])
        XCTAssertEqual(issues.map(\.path), ["steps[1].targetSpeed.value"])
    }

    private func failure(
        for plan: WorkoutPlan,
        capabilities: WorkoutPlanCapabilities
    ) -> WorkoutPlanValidationFailure {
        switch WorkoutPlanValidator.validate(plan, against: capabilities) {
        case .success:
            XCTFail("Expected validation to fail")
            return WorkoutPlanValidationFailure(issues: [])
        case let .failure(failure):
            return failure
        }
    }

    private func validPlan(steps: [WorkoutStep]? = nil) -> WorkoutPlan {
        WorkoutPlan(
            schemaVersion: WorkoutPlanSchema.currentVersion,
            suggestedName: "Synthetic intervals",
            activity: .indoorRunning,
            steps: steps ?? [
                step(.warmUp, label: "Warm up"),
                step(.interval, label: "Run"),
                step(.recovery, label: "Recover"),
                step(.coolDown, label: "Cool down"),
            ]
        )
    }

    private func step(
        _ kind: WorkoutStepKind,
        label: String,
        duration: Int = 60,
        speed speedValue: String = "5.5",
        inclination inclinationValue: String = "0"
    ) -> WorkoutStep {
        WorkoutStep(
            kind: kind,
            label: label,
            duration: .init(value: duration, unit: .seconds),
            targetSpeed: speed(speedValue),
            targetInclination: inclination(inclinationValue)
        )
    }

    private func knownCapabilities() -> WorkoutPlanCapabilities {
        WorkoutPlanCapabilities(
            speed: .supported(
                WorkoutSpeedRange(
                    minimum: speed("0.5"),
                    maximum: speed("20"),
                    increment: speed("0.1")
                )
            ),
            inclination: .supported(
                WorkoutInclinationRange(
                    minimum: inclination("-3"),
                    maximum: inclination("15"),
                    increment: inclination("0.5")
                )
            )
        )
    }

    private func speed(_ value: String) -> WorkoutSpeed {
        WorkoutSpeed(value: decimal(value), unit: .kilometresPerHour)
    }

    private func inclination(_ value: String) -> WorkoutInclination {
        WorkoutInclination(value: decimal(value), unit: .percent)
    }

    private func decimal(_ value: String) -> Decimal {
        guard let value = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            XCTFail("Invalid test decimal: \(value)")
            return .nan
        }
        return value
    }
}
