import Foundation

// Private strict JSON reader: preserves duplicate keys and rejects unknown fields before decoding.
indirect enum PlanningProfileJSON {
    case object([String: PlanningProfileJSON]), array([PlanningProfileJSON]), string(String)
    case number(String), bool(Bool), null
    func fields(_ names: Set<String>) throws -> [String: Self] {
        guard case let .object(fields) = self, Set(fields.keys) == names else { throw PlanningProfileFailure.corrupt }
        return fields
    }
    var object: [String: Self]? { if case let .object(values) = self { return values }; return nil }
    func requireV1(_ field: String) throws {
        guard case let .number(token)? = object?[field], let version = Int(token) else { throw PlanningProfileFailure.corrupt }
        guard version == 1 else { throw PlanningProfileFailure.unsupportedVersion }
    }
    var array: [Self]? { if case let .array(values) = self { return values }; return nil }
}
struct PlanningProfileJSONParser {
    private let bytes: [UInt8]
    private var index = 0

    static func parse(_ data: Data) throws -> PlanningProfileJSON {
        guard String(data: data, encoding: .utf8) != nil else { throw PlanningProfileFailure.corrupt }
        var parser = PlanningProfileJSONParser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw PlanningProfileFailure.corrupt }
        return value
    }

    private mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    private mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
    private mutating func value(depth: Int) throws -> PlanningProfileJSON {
        whitespace()
        guard depth < 32, index < bytes.count else { throw PlanningProfileFailure.corrupt }
        switch bytes[index] {
        case 123:
            index += 1
            var object: [String: PlanningProfileJSON] = [:]
            if consume(125) { return .object(object) }
            repeat {
                whitespace()
                let key = try string()
                guard object[key] == nil, consume(58) else { throw PlanningProfileFailure.corrupt }
                object[key] = try value(depth: depth + 1)
                if consume(125) { return .object(object) }
            } while consume(44)
            throw PlanningProfileFailure.corrupt
        case 91:
            index += 1
            var array: [PlanningProfileJSON] = []
            if consume(93) { return .array(array) }
            repeat {
                array.append(try value(depth: depth + 1))
                if consume(93) { return .array(array) }
            } while consume(44)
            throw PlanningProfileFailure.corrupt
        case 34: return .string(try string())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            guard token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#,
                              options: .regularExpression) != nil else { throw PlanningProfileFailure.corrupt }
            return .number(token)
        }
    }
    private mutating func literal(_ literal: String) throws {
        let expected = Array(literal.utf8)
        guard index + expected.count <= bytes.count,
              Array(bytes[index..<(index + expected.count)]) == expected else { throw PlanningProfileFailure.corrupt }
        index += expected.count
    }
    private mutating func string() throws -> String {
        guard index < bytes.count, bytes[index] == 34 else { throw PlanningProfileFailure.corrupt }
        let start = index
        index += 1
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 && !escaped {
                let data = Data(bytes[start..<index])
                guard let decoded = try? JSONDecoder().decode(String.self, from: data) else {
                    throw PlanningProfileFailure.corrupt
                }
                return decoded
            }
            if byte == 92 && !escaped { escaped = true } else { escaped = false }
        }
        throw PlanningProfileFailure.corrupt
    }
}

struct PlanningProfileCodec {
    static let maximumBytes = 256 * 1024
    func encode(_ store: PlanningProfileStore) throws -> Data {
        try store.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encode nil selection explicitly, rather than synthesised optional omission.
        let data = try encoder.encode(store)
        var fields = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        fields["lastSelectedProfileID"] = store.lastSelectedProfileID ?? NSNull() as Any
        let result = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        _ = try decode(result)
        return result
    }
    func decode(_ data: Data) throws -> PlanningProfileStore {
        guard data.count <= Self.maximumBytes else { throw PlanningProfileFailure.corrupt }
        let root = try PlanningProfileJSONParser.parse(data)
        try root.requireV1("formatVersion")
        try root.requireV1("identityDerivationVersion")
        let envelope = try root.fields(["formatVersion", "identityDerivationVersion", "installationSecret", "storeRevision", "lastSelectedProfileID", "records"])
        guard let records = envelope["records"]?.array else { throw PlanningProfileFailure.corrupt }
        for record in records {
            let fields = try record.fields(["profileID", "machineKey", "name", "equipmentType", "recordRevision", "snapshot"])
            try fields["snapshot"]!.requireV1("snapshotVersion")
            let snapshot = try fields["snapshot"]!.fields(["snapshotVersion", "speed", "inclination", "observedAt", "provenance"])
            _ = try snapshot["speed"]!.fields(["minimumHundredthsKph", "maximumHundredthsKph", "incrementHundredthsKph"])
            _ = try snapshot["inclination"]!.fields(["minimumTenthsPercent", "maximumTenthsPercent", "incrementTenthsPercent"])
            _ = try snapshot["provenance"]!.fields(["kind", "interpretationVersion"])
        }
        let result: PlanningProfileStore
        do { result = try JSONDecoder().decode(PlanningProfileStore.self, from: data) }
        catch { throw PlanningProfileFailure.corrupt }
        try result.validate()
        return result
    }
}
