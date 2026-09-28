import Foundation

// Closed v1 interchange vocabulary; no platform or treadmill capability crosses this boundary.
struct WatchInterval: Codable, Equatable {
    struct Prescribed: Codable, Equatable { let kind: String; let speedKilometresPerHour: Decimal; let inclinationPercent: Decimal }
    struct Speed: Codable, Equatable { let kilometresPerHour: Decimal; let source: String }
    struct Inclination: Codable, Equatable { let percent: Decimal; let source: String }
    struct Observation: Codable, Equatable { let observedAt: Date; let speedKilometresPerHour: Decimal; let inclinationPercent: Decimal; let provenance: String }
    let segmentIndex: Int
    let intervalIndex: Int
    let startedAt: Date
    let endedAt: Date
    let prescribed: Prescribed
    let effectiveSpeed: Speed
    let effectiveInclination: Inclination
    let settledObservation: Observation
    let endReason: String
}

struct WatchDistance: Codable, Equatable {
    let state: String
    var metres: Decimal? = nil
    var provenance: String? = nil
    static let unavailable = Self(state: "unavailable")
}

struct WatchWireMessage: Codable, Equatable {
    enum Kind: String, Codable { case bind, bound, manifest, ack, prepareEnd, endPrepared, finalize, recordingState }
    let schemaVersion: Int
    let summaryID: String
    let kind: Kind
    var workoutActivity: String? = nil
    var workoutStart: Date? = nil
    var revision: Int64? = nil
    var intervals: [WatchInterval]? = nil
    var final: Bool? = nil
    var workoutEnd: Date? = nil
    var localOutcome: String? = nil
    var distance: WatchDistance? = nil
    var sequence: Int64? = nil
    var state: String? = nil
    var observedAt: Date? = nil

    init(_ kind: Kind, summaryID: String) { self.schemaVersion = 1; self.summaryID = summaryID; self.kind = kind }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, summaryID, kind, workoutActivity, workoutStart, revision, intervals, final, workoutEnd, localOutcome, distance, sequence, state, observedAt
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(summaryID, forKey: .summaryID); try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(workoutActivity, forKey: .workoutActivity); try c.encodeIfPresent(workoutStart, forKey: .workoutStart)
        try c.encodeIfPresent(revision, forKey: .revision); try c.encodeIfPresent(intervals, forKey: .intervals); try c.encodeIfPresent(final, forKey: .final)
        if kind == .manifest {
            try c.encode(workoutEnd, forKey: .workoutEnd); try c.encode(localOutcome, forKey: .localOutcome)
        } else { try c.encodeIfPresent(workoutEnd, forKey: .workoutEnd) }
        try c.encodeIfPresent(distance, forKey: .distance); try c.encodeIfPresent(sequence, forKey: .sequence)
        try c.encodeIfPresent(state, forKey: .state); try c.encodeIfPresent(observedAt, forKey: .observedAt)
    }
}

enum WatchWireError: Error { case invalid, oversized }

enum WatchWire {
    static func formatter() -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"; f.isLenient = false
        return f
    }
    static func date(_ value: String) throws -> Date {
        let f = formatter()
        guard value.utf8.count == 24, let d = f.date(from: value), f.string(from: d) == value else { throw WatchWireError.invalid }
        return d
    }
    static func timestamp(_ date: Date) -> Date { formatter().date(from: formatter().string(from: date))! }
    static func encode(_ m: WatchWireMessage) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer(); try c.encode(formatter().string(from: date))
        }
        let data = try encoder.encode(m)
        _ = try decode(data)
        return data
    }
    static func decode(_ data: Data) throws -> WatchWireMessage {
        guard data.count <= 32_768 else { throw WatchWireError.oversized }
        let root = try StrictImportJSON.parse(data)
        guard let kindText = root["kind"]?.string, let kind = WatchWireMessage.Kind(rawValue: kindText) else { throw WatchWireError.invalid }
        let fields: Set<String>
        switch kind {
        case .bind: fields = ["workoutActivity"]
        case .bound: fields = ["workoutStart"]
        case .manifest: fields = ["revision", "workoutActivity", "workoutStart", "intervals", "final", "workoutEnd", "localOutcome", "distance"]
        case .ack, .finalize: fields = ["revision"]
        case .prepareEnd: fields = ["sequence"]
        case .endPrepared: fields = ["sequence", "workoutEnd"]
        case .recordingState: fields = ["sequence", "state", "observedAt"]
        }
        _ = try root.fields(required: fields.union(["schemaVersion", "summaryID", "kind"]))
        guard try integer(root["schemaVersion"], minimum: 1) == 1,
              let id = root["summaryID"]?.string, let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id else { throw WatchWireError.invalid }
        if let r = root["revision"] { _ = try integer(r, minimum: kind == .ack ? 0 : 1) }
        if let s = root["sequence"] { _ = try integer(s, minimum: 1) }
        if let activity = root["workoutActivity"] { try member(activity, ["indoorWalking", "indoorRunning"]) }
        for key in ["workoutStart", "observedAt"] where root[key] != nil { _ = try dateValue(root[key]) }
        if kind == .endPrepared { _ = try dateValue(root["workoutEnd"]) }
        if kind == .recordingState { try member(root["state"], ["paused", "running"]) }
        if kind == .manifest { try validateManifest(root) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in try date(decoder.singleValueContainer().decode(String.self)) }
        return try decoder.decode(WatchWireMessage.self, from: data)
    }
    private static func integer(_ value: ImportJSON?, minimum: Int64 = 0) throws -> Int64 {
        guard case let .number(token)? = value, token.range(of: #"^(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil,
              let number = Int64(token), number >= minimum else { throw WatchWireError.invalid }
        return number
    }
    private static func member(_ v: ImportJSON?, _ values: Set<String>) throws {
        guard let text = v?.string, values.contains(text) else { throw WatchWireError.invalid }
    }
    private static func dateValue(_ v: ImportJSON?) throws -> Date {
        guard let text = v?.string else { throw WatchWireError.invalid }; return try date(text)
    }
    private static func validateManifest(_ root: ImportJSON) throws {
        guard case let .bool(final)? = root["final"], let intervals = root["intervals"]?.array, intervals.count <= 64 else { throw WatchWireError.invalid }
        let start = try dateValue(root["workoutStart"])
        var end: Date?
        if final {
            end = try dateValue(root["workoutEnd"])
            guard end! > start else { throw WatchWireError.invalid }
            try member(root["localOutcome"], ["completed", "stoppedByUser", "failed", "interrupted"])
        } else if root["workoutEnd"] != .null || root["localOutcome"] != .null { throw WatchWireError.invalid }
        var previousEnd = start, previousSegment: Int64 = -1, previousIndex: Int64 = -1
        for i in intervals {
            _ = try i.fields(required: ["segmentIndex", "intervalIndex", "startedAt", "endedAt", "prescribed", "effectiveSpeed", "effectiveInclination", "settledObservation", "endReason"])
            let segment = try integer(i["segmentIndex"]), index = try integer(i["intervalIndex"])
            guard segment >= previousSegment,
                  segment > previousSegment ? index == 0 : (previousIndex < Int64.max && index == previousIndex + 1) else { throw WatchWireError.invalid }
            let a = try dateValue(i["startedAt"]), b = try dateValue(i["endedAt"])
            guard a >= previousEnd, b > a, end.map({ b <= $0 }) ?? true else { throw WatchWireError.invalid }
            guard let p = i["prescribed"], let s = i["effectiveSpeed"], let g = i["effectiveInclination"], let o = i["settledObservation"] else { throw WatchWireError.invalid }
            _ = try p.fields(required: ["kind", "speedKilometresPerHour", "inclinationPercent"])
            _ = try s.fields(required: ["kilometresPerHour", "source"]); _ = try g.fields(required: ["percent", "source"])
            _ = try o.fields(required: ["observedAt", "speedKilometresPerHour", "inclinationPercent", "provenance"])
            try member(p["kind"], ["warmUp", "interval", "recovery", "coolDown"])
            try member(s["source"], ["planned", "manualOverride"]); try member(g["source"], ["planned", "manualOverride"])
            try member(o["provenance"], ["fr30zTreadmillDataCurrentEpoch"])
            guard try dateValue(o["observedAt"]) == a else { throw WatchWireError.invalid }
            for (object, key) in [(p,"speedKilometresPerHour"),(p,"inclinationPercent"),(s,"kilometresPerHour"),(g,"percent"),(o,"speedKilometresPerHour"),(o,"inclinationPercent")] {
                guard let value = object[key] else { throw WatchWireError.invalid }; _ = try value.decimal()
            }
            try member(i["endReason"], ["planTransition", "targetChanged", "paused", "completed", "endedByUser", "interrupted", "failed"])
            previousEnd = b; previousSegment = segment; previousIndex = index
        }
        guard let d = root["distance"] else { throw WatchWireError.invalid }
        if d["state"] == .string("unavailable") { _ = try d.fields(required: ["state"]) }
        else {
            _ = try d.fields(required: ["state", "metres", "provenance"])
            guard final, d["state"] == .string("accepted"), d["provenance"] == .string("fr30zCumulativeDistanceDelta"),
                  let metres = d["metres"], try metres.decimal() > 0 else { throw WatchWireError.invalid }
        }
    }
}

struct WatchSendBudget {
    private var sends: [(time: TimeInterval, bytes: Int, kind: Int)] = []
    private var lastNonfinal: TimeInterval?
    mutating func accept(_ message: WatchWireMessage, bytes: Int, now: TimeInterval) -> Bool {
        guard now.isFinite, bytes > 0, bytes <= 32_768, sends.last.map({ now >= $0.time }) ?? true else { return false }
        sends.removeAll { now - $0.time >= 10 }
        let kind = message.kind == .manifest ? (message.final == true ? 1 : 0) : 2
        let same = sends.filter { $0.kind == kind }
        let limit = [24_576, 32_768, 8_192][kind]
        guard sends.reduce(0, { $0 + $1.bytes }) + bytes <= 65_536,
              same.reduce(0, { $0 + $1.bytes }) + bytes <= limit else { return false }
        if kind == 0, let lastNonfinal, now - lastNonfinal < 5 { return false }
        if kind == 2, bytes > 512 || same.count >= 16 { return false }
        sends.append((now, bytes, kind)); if kind == 0 { lastNonfinal = now }; return true
    }
}
