import CryptoKit
import Foundation

struct ImportRequestSnapshot: Equatable {
    let text: String
    let capabilities: WorkoutPlanCapabilities

    var capabilityStates: String {
        func state<T>(_ value: WorkoutTargetCapability<T>) -> String {
            switch value { case .unknown: "unknown"; case .unsupported: "unsupported"; case .supported: "supported" }
        }
        return "{\"inclination\":{\"state\":\"\(state(capabilities.inclination))\"},\"speed\":{\"state\":\"\(state(capabilities.speed))\"}}"
    }
    var userMessage: String { "Locale: en-GB\nCapabilities: \(capabilityStates)\nWorkout request:\n\(text)" }
}

struct ImportResources {
    let system: String
    let examples: [[String: String]]
    let schema: [String: Any]

    init(bundle: Bundle = .main) throws {
        func read(_ name: String, hash: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "ImportResources"),
                  let data = try? Data(contentsOf: url),
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else { throw ImportFailure.resources }
            return data
        }
        let prompt = try read("system.md", hash: "d58800efc4b0e01994a1a5be1a1d644ce52dbb6bb7c12655745dc78b6e355fd3")
        let examples = try read("examples.json", hash: "0313c531454bae3545ec97118be33232f53b0b62613a2339d8a96dbe21a680fd")
        let schema = try read("transport.json", hash: "d4901b2dc3b1a57654ed5d6f7e96bdce30687062913036f86e616fb2f5a9bba0")
        guard let text = String(data: prompt, encoding: .utf8),
              let messages = try JSONSerialization.jsonObject(with: examples) as? [[String: String]], messages.count == 22,
              let object = try JSONSerialization.jsonObject(with: schema) as? [String: Any] else { throw ImportFailure.resources }
        system = text
        self.examples = messages
        self.schema = object
    }
    func request(for snapshot: ImportRequestSnapshot) throws -> URLRequest {
        let messages = [["role": "system", "content": system]] + examples + [["role": "user", "content": snapshot.userMessage]]
        let body: [String: Any] = [
            "model": WorkoutImportContract.model, "messages": messages,
            "provider": ["order": ["openai"], "only": ["openai"], "allow_fallbacks": false,
                         "require_parameters": true, "data_collection": "deny"],
            "response_format": ["type": "json_schema", "json_schema": [
                "name": "paceprompt_workout_import_transport_v2_3", "strict": true, "schema": schema]],
            "max_tokens": 8192, "stream": false, "reasoning": ["enabled": false, "effort": "none"]]
        var request = URLRequest(url: WorkoutImportContract.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        return request
    }
}
