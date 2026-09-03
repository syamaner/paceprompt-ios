import Foundation
import FoundationModels

enum EvaluationLaunchReadiness: Equatable {
    case ready(provider: String, details: [String])
    case notReady(reasons: [String])

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        let commonKeys = [
            "PACEPROMPT_EVALUATION_PROVIDER",
            "PACEPROMPT_MODEL_ID",
            "PACEPROMPT_RUN_CONFIGURATION_ID",
            "PACEPROMPT_REPETITION_COUNT",
            "PACEPROMPT_APP_COMMIT",
            "PACEPROMPT_DEVICE_LOCALE"
        ]
        var missing = commonKeys.filter { environment[$0]?.isEmpty != false }
        guard let provider = environment["PACEPROMPT_EVALUATION_PROVIDER"] else {
            return .notReady(reasons: missing.map { "Missing \($0)" })
        }
        if let repetitions = environment["PACEPROMPT_REPETITION_COUNT"],
           (Int(repetitions) ?? 0) < 1 {
            missing.append("PACEPROMPT_REPETITION_COUNT must be a positive integer")
        }
        if let commit = environment["PACEPROMPT_APP_COMMIT"],
           commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) == nil {
            missing.append("PACEPROMPT_APP_COMMIT must be an exact lowercase Git SHA")
        }

        switch provider {
        case "apple":
            if environment["PACEPROMPT_INFERENCE_PARAMETERS_JSON"]?.isEmpty != false {
                missing.append("Missing PACEPROMPT_INFERENCE_PARAMETERS_JSON")
            } else if !isJSONObject(environment["PACEPROMPT_INFERENCE_PARAMETERS_JSON"], allowsEmpty: true) {
                missing.append("PACEPROMPT_INFERENCE_PARAMETERS_JSON must be a JSON object")
            }
            guard missing.isEmpty else { return .notReady(reasons: missing) }
            let model = SystemLanguageModel.default
            let locale = Locale(identifier: environment["PACEPROMPT_DEVICE_LOCALE"]!)
            var details = ["Runtime: available", "Locale: \(model.supportsLocale(locale) ? "available" : "unavailable")"]
            switch model.availability {
            case .available: details.append("Model: available")
            case let .unavailable(reason): details.append("Model: unavailable (\(availabilityText(reason)))")
            }
            return model.isAvailable && model.supportsLocale(locale)
                ? .ready(provider: "Apple Foundation Models", details: details)
                : .notReady(reasons: details.filter { $0.contains("unavailable") })
        case "openrouter":
            let remoteKeys = [
                "PACEPROMPT_OPENROUTER_PROVIDER_ROUTING_JSON",
                "PACEPROMPT_OPENROUTER_TIMEOUT_SECONDS",
                "PACEPROMPT_INFERENCE_PARAMETERS_JSON",
                OpenRouterCredential.environmentKey
            ]
            missing.append(contentsOf: remoteKeys.filter { environment[$0]?.isEmpty != false })
            if let routing = environment["PACEPROMPT_OPENROUTER_PROVIDER_ROUTING_JSON"],
               !isJSONObject(routing, allowsEmpty: false) {
                missing.append("PACEPROMPT_OPENROUTER_PROVIDER_ROUTING_JSON must be a non-empty JSON object")
            }
            if let inference = environment["PACEPROMPT_INFERENCE_PARAMETERS_JSON"],
               !isJSONObject(inference, allowsEmpty: true) {
                missing.append("PACEPROMPT_INFERENCE_PARAMETERS_JSON must be a JSON object")
            }
            if let timeout = environment["PACEPROMPT_OPENROUTER_TIMEOUT_SECONDS"],
               !(Double(timeout)?.isFinite == true && (Double(timeout) ?? 0) > 0) {
                missing.append("PACEPROMPT_OPENROUTER_TIMEOUT_SECONDS must be positive and bounded")
            }
            guard missing.isEmpty else { return .notReady(reasons: missing) }
            return .ready(
                provider: "OpenRouter",
                details: [
                    "Runtime: available",
                    "Model and routing: explicitly configured",
                    "Credential: present and redacted",
                    "Network: not probed"
                ]
            )
        default:
            return .notReady(reasons: ["PACEPROMPT_EVALUATION_PROVIDER is unsupported"])
        }
    }

    private static func availabilityText(
        _ reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible: return "device not eligible"
        case .appleIntelligenceNotEnabled: return "Apple Intelligence not enabled"
        case .modelNotReady: return "model not ready"
        @unknown default: return "unknown reason"
        }
    }

    private static func isJSONObject(_ text: String?, allowsEmpty: Bool) -> Bool {
        guard let text,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return false }
        return allowsEmpty || !dictionary.isEmpty
    }
}
