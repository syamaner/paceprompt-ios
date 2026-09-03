import Foundation
import CoreFoundation

enum GeneratorOutputParser {
    static func parse(_ data: Data) -> NormalizedObservedResult {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .invalidGeneratorOutput([.init(code: "malformedJSON", path: "$")])
        }
        guard let root = object as? [String: Any] else {
            return .invalidGeneratorOutput([.init(code: "expectedObject", path: "$")])
        }
        let errors = validateOutcome(root)
        guard errors.isEmpty else { return .invalidGeneratorOutput(errors) }
        do {
            return .valid(try JSONDecoder().decode(NormalizedGeneratorOutcome.self, from: data))
        } catch {
            return .invalidGeneratorOutput([.init(code: "decodingFailure", path: "$")])
        }
    }

    private static func validateOutcome(_ value: [String: Any]) -> [GeneratorStructureError] {
        guard let type = value["type"] as? String else {
            return [.init(code: "missingOrInvalidType", path: "type")]
        }
        if type == "proposal" {
            var errors = exactKeys(value, expected: ["type", "proposal"], path: "$")
            guard let proposal = value["proposal"] as? [String: Any] else {
                errors.append(.init(code: "missingOrInvalidObject", path: "proposal"))
                return errors
            }
            errors.append(contentsOf: validateProposal(proposal))
            return errors
        }
        let reasonTypes = [
            "clarificationRequired", "unsupportedRequest", "refusal",
            "providerUnavailable", "providerFailure"
        ]
        guard reasonTypes.contains(type) else {
            return [.init(code: "unsupportedOutcome", path: "type")]
        }
        var errors = exactKeys(
            value,
            expected: ["type", "reasonCategory", "affectedPaths"],
            path: "$"
        )
        if !isNonemptyString(value["reasonCategory"]) {
            errors.append(.init(code: "missingOrEmptyString", path: "reasonCategory"))
        }
        guard let paths = value["affectedPaths"] as? [Any],
              paths.allSatisfy({ isNonemptyString($0) }) else {
            errors.append(.init(code: "invalidStringArray", path: "affectedPaths"))
            return errors
        }
        let strings = paths.compactMap { $0 as? String }
        if Set(strings).count != strings.count {
            errors.append(.init(code: "duplicateArrayItem", path: "affectedPaths"))
        }
        return errors
    }

    private static func validateProposal(_ value: [String: Any]) -> [GeneratorStructureError] {
        var errors = exactKeys(
            value,
            expected: ["contractVersion", "suggestedName", "activity", "steps"],
            path: "proposal"
        )
        if value["contractVersion"] as? String != WorkoutImportEvaluationContract.proposalContractVersion {
            errors.append(.init(code: "unsupportedContractVersion", path: "proposal.contractVersion"))
        }
        if !isNonemptyString(value["suggestedName"]) {
            errors.append(.init(code: "missingOrEmptyString", path: "proposal.suggestedName"))
        }
        guard let activity = value["activity"] as? String,
              ["indoorWalking", "indoorRunning"].contains(activity) else {
            errors.append(.init(code: "unsupportedActivity", path: "proposal.activity"))
            return errors
        }
        guard let steps = value["steps"] as? [Any], !steps.isEmpty else {
            errors.append(.init(code: "missingOrEmptyArray", path: "proposal.steps"))
            return errors
        }
        for (index, item) in steps.enumerated() {
            guard let step = item as? [String: Any] else {
                errors.append(.init(code: "expectedObject", path: "proposal.steps[\(index)]"))
                continue
            }
            errors.append(contentsOf: validateStep(step, index: index))
        }
        return errors
    }

    private static func validateStep(_ value: [String: Any], index: Int) -> [GeneratorStructureError] {
        let base = "proposal.steps[\(index)]"
        var errors = exactKeys(
            value,
            expected: ["kind", "label", "duration", "targetSpeed", "targetInclination"],
            path: base
        )
        guard let kind = value["kind"] as? String,
              ["warmUp", "interval", "recovery", "coolDown"].contains(kind) else {
            errors.append(.init(code: "unsupportedStepKind", path: "\(base).kind"))
            return errors
        }
        if !isNonemptyString(value["label"]) {
            errors.append(.init(code: "missingOrEmptyString", path: "\(base).label"))
        }
        errors.append(contentsOf: validateQuantity(
            value["duration"],
            path: "\(base).duration",
            units: ["seconds", "minutes"],
            requiresPositiveValue: true
        ))
        errors.append(contentsOf: validateQuantity(
            value["targetSpeed"],
            path: "\(base).targetSpeed",
            units: ["kilometresPerHour", "milesPerHour"],
            requiresPositiveValue: false
        ))
        errors.append(contentsOf: validateQuantity(
            value["targetInclination"],
            path: "\(base).targetInclination",
            units: ["percent"],
            requiresPositiveValue: false
        ))
        return errors
    }

    private static func validateQuantity(
        _ value: Any?,
        path: String,
        units: Set<String>,
        requiresPositiveValue: Bool
    ) -> [GeneratorStructureError] {
        guard let quantity = value as? [String: Any] else {
            return [.init(code: "expectedObject", path: path)]
        }
        var errors = exactKeys(quantity, expected: ["value", "unit"], path: path)
        if let number = decimal(quantity["value"]) {
            if requiresPositiveValue && number <= 0 {
                errors.append(.init(code: "valueNotPositive", path: "\(path).value"))
            }
        } else {
            errors.append(.init(code: "invalidNumber", path: "\(path).value"))
        }
        guard let unit = quantity["unit"] as? String, units.contains(unit) else {
            errors.append(.init(code: "unsupportedUnit", path: "\(path).unit"))
            return errors
        }
        return errors
    }

    private static func exactKeys(
        _ value: [String: Any],
        expected: Set<String>,
        path: String
    ) -> [GeneratorStructureError] {
        var errors: [GeneratorStructureError] = []
        for key in expected.subtracting(value.keys) {
            errors.append(.init(code: "missingProperty", path: path == "$" ? key : "\(path).\(key)"))
        }
        for key in Set(value.keys).subtracting(expected) {
            errors.append(.init(code: "additionalProperty", path: path == "$" ? key : "\(path).\(key)"))
        }
        return errors.sorted { ($0.path, $0.code) < ($1.path, $1.code) }
    }

    private static func isNonemptyString(_ value: Any?) -> Bool {
        guard let string = value as? String else { return false }
        return !string.isEmpty
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
    }
}
