import Foundation

// Keeps number lexemes until checked decimal mapping; Foundation's generic JSON
// decoder can round numbers and silently collapse duplicate object keys.
indirect enum ImportJSON: Equatable {
    case object([String: ImportJSON]), array([ImportJSON]), string(String)
    case number(String), bool(Bool), null

    var object: [String: ImportJSON]? { if case let .object(v) = self { return v }; return nil }
    var array: [ImportJSON]? { if case let .array(v) = self { return v }; return nil }
    var string: String? { if case let .string(v) = self { return v }; return nil }
    subscript(_ key: String) -> ImportJSON? { object?[key] }

    func fields(required: Set<String>, optional: Set<String> = []) throws -> [String: ImportJSON] {
        guard let o = object, required.isSubset(of: Set(o.keys)),
              Set(o.keys).isSubset(of: required.union(optional)) else { throw ImportFailure.structure }
        return o
    }
    func decimal() throws -> Decimal {
        guard case let .number(token) = self else { throw ImportFailure.structure }
        return try ExactImportDecimal.parse(token)
    }
    func integer() throws -> Int {
        let value = try decimal()
        guard let n = Int(NSDecimalNumber(decimal: value).stringValue), Decimal(n) == value else {
            throw ImportFailure.mapping
        }
        return n
    }
}

enum ImportFailure: String, Error {
    case structure, identity, mapping, transport, timeout, cancelled, missingCredential
    case authentication, credits, restrictedRoute, rateLimited, unavailable, resources
    case redirect, responseContentType
    case identityResponseURL, identityModelMissing, identityModelAlias
    case identityModelRevisionWithoutProvider, identityModelNonString, identityModelMismatch
    case identityProviderMissing, identityProviderMismatch
    case identityServiceTier, identityMessageModel
}

enum ExactImportDecimal {
    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var a = lhs, b = rhs, result = Decimal()
        guard NSDecimalMultiply(&result, &a, &b, .plain) == .noError, !result.isNaN else {
            throw ImportFailure.mapping
        }
        return result
    }

    static func parse(_ token: String) throws -> Decimal {
        guard token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#,
                          options: .regularExpression) != nil else { throw ImportFailure.mapping }
        let parts = token.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw ImportFailure.mapping }
        let exponent = parts.count == 2 ? Int(parts[1]) : 0
        guard let exponent, (-1000...1000).contains(exponent) else { throw ImportFailure.mapping }
        let negative = parts[0].hasPrefix("-")
        let mantissa = parts[0].replacingOccurrences(of: "-", with: "")
        let fraction = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        var digits = mantissa.replacingOccurrences(of: ".", with: "")
        var power = exponent - (fraction.count == 2 ? fraction[1].count : 0)
        while digits.first == "0" { digits.removeFirst() }
        if digits.isEmpty { return .zero }
        while digits.last == "0" { digits.removeLast(); power += 1 }
        var value = Decimal.zero
        for character in digits {
            guard let digit = character.wholeNumberValue else { throw ImportFailure.mapping }
            value = try multiply(value, 10)
            var a = value, b = Decimal(digit), result = Decimal()
            guard NSDecimalAdd(&result, &a, &b, .plain) == .noError else { throw ImportFailure.mapping }
            value = result
        }
        guard let p = Int16(exactly: power) else { throw ImportFailure.mapping }
        var result = Decimal()
        guard NSDecimalMultiplyByPowerOf10(&result, &value, p, .plain) == .noError,
              !result.isNaN else { throw ImportFailure.mapping }
        return negative ? -result : result
    }
}

struct StrictImportJSON {
    private let bytes: [UInt8]
    private var index = 0

    static func parse(_ data: Data) throws -> ImportJSON {
        guard String(data: data, encoding: .utf8) != nil else { throw ImportFailure.structure }
        var parser = StrictImportJSON(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw ImportFailure.structure }
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
    private mutating func value(depth: Int) throws -> ImportJSON {
        whitespace()
        guard depth < 32, index < bytes.count else { throw ImportFailure.structure }
        switch bytes[index] {
        case 123:
            index += 1
            var object: [String: ImportJSON] = [:]
            if consume(125) { return .object(object) }
            repeat {
                whitespace()
                let key = try string()
                guard object[key] == nil, consume(58) else { throw ImportFailure.structure }
                object[key] = try value(depth: depth + 1)
                if consume(125) { return .object(object) }
            } while consume(44)
            throw ImportFailure.structure
        case 91:
            index += 1
            var array: [ImportJSON] = []
            if consume(93) { return .array(array) }
            repeat {
                array.append(try value(depth: depth + 1))
                if consume(93) { return .array(array) }
            } while consume(44)
            throw ImportFailure.structure
        case 34: return .string(try string())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            guard token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#,
                              options: .regularExpression) != nil else { throw ImportFailure.structure }
            return .number(token)
        }
    }
    private mutating func literal(_ literal: String) throws {
        let expected = Array(literal.utf8)
        guard index + expected.count <= bytes.count,
              Array(bytes[index..<(index + expected.count)]) == expected else { throw ImportFailure.structure }
        index += expected.count
    }
    private mutating func string() throws -> String {
        guard index < bytes.count, bytes[index] == 34 else { throw ImportFailure.structure }
        let start = index
        index += 1
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 && !escaped {
                let data = Data(bytes[start..<index])
                guard let decoded = try? JSONDecoder().decode(String.self, from: data) else {
                    throw ImportFailure.structure
                }
                return decoded
            }
            if byte == 92 && !escaped { escaped = true } else { escaped = false }
        }
        throw ImportFailure.structure
    }
}
