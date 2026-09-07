import Foundation

enum WorkoutExecutionSummarySchema {
    static let currentVersion = 1
}

struct WorkoutExecutionReasonCode: RawRepresentable, Codable, Equatable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum WorkoutExecutionOutcome: Equatable, Codable {
    case inProgress
    case completed
    case stoppedByUser(reason: WorkoutExecutionReasonCode)
    case interrupted(reason: WorkoutExecutionReasonCode)
    case failed(reason: WorkoutExecutionReasonCode)

    private enum State: String, Codable {
        case inProgress
        case completed
        case stoppedByUser
        case interrupted
        case failed
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case reasonCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(State.self, forKey: .state)
        switch state {
        case .inProgress:
            self = .inProgress
        case .completed:
            self = .completed
        case .stoppedByUser:
            self = .stoppedByUser(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        case .interrupted:
            self = .interrupted(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        case .failed:
            self = .failed(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inProgress:
            try container.encode(State.inProgress, forKey: .state)
        case .completed:
            try container.encode(State.completed, forKey: .state)
        case let .stoppedByUser(reason):
            try container.encode(State.stoppedByUser, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        case let .interrupted(reason):
            try container.encode(State.interrupted, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        case let .failed(reason):
            try container.encode(State.failed, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        }
    }
}

enum WorkoutActiveDuration: Equatable, Codable {
    case measured(seconds: Int)
    case unavailable(reason: WorkoutExecutionReasonCode)

    private enum State: String, Codable { case measured, unavailable }
    private enum CodingKeys: String, CodingKey { case state, seconds, reasonCode }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .measured:
            self = .measured(seconds: try container.decode(Int.self, forKey: .seconds))
        case .unavailable:
            self = .unavailable(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .measured(seconds):
            try container.encode(State.measured, forKey: .state)
            try container.encode(seconds, forKey: .seconds)
        case let .unavailable(reason):
            try container.encode(State.unavailable, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        }
    }
}

enum WorkoutDistance: Equatable, Codable {
    case measured(metres: Decimal)
    case unavailable(reason: WorkoutExecutionReasonCode)

    private enum State: String, Codable { case measured, unavailable }
    private enum CodingKeys: String, CodingKey { case state, metres, reasonCode }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .measured:
            self = .measured(metres: try container.decode(Decimal.self, forKey: .metres))
        case .unavailable:
            self = .unavailable(reason: try container.decode(WorkoutExecutionReasonCode.self, forKey: .reasonCode))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .measured(metres):
            try container.encode(State.measured, forKey: .state)
            try container.encode(metres, forKey: .metres)
        case let .unavailable(reason):
            try container.encode(State.unavailable, forKey: .state)
            try container.encode(reason, forKey: .reasonCode)
        }
    }
}

struct WorkoutExecutionProgress: Codable, Equatable {
    let completedStepCount: Int
    let currentStepIndex: Int?
    let activeSecondsInCurrentStep: Int
}

enum WorkoutPhysicalStopConfirmation: Equatable, Codable {
    case notRequired
    case humanConfirmed(at: Date)
    case unconfirmed

    private enum State: String, Codable { case notRequired, humanConfirmed, unconfirmed }
    private enum CodingKeys: String, CodingKey { case state, confirmedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .notRequired:
            self = .notRequired
        case .humanConfirmed:
            self = .humanConfirmed(at: try container.decode(Date.self, forKey: .confirmedAt))
        case .unconfirmed:
            self = .unconfirmed
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notRequired:
            try container.encode(State.notRequired, forKey: .state)
        case let .humanConfirmed(at):
            try container.encode(State.humanConfirmed, forKey: .state)
            try container.encode(at, forKey: .confirmedAt)
        case .unconfirmed:
            try container.encode(State.unconfirmed, forKey: .state)
        }
    }
}

struct WorkoutExecutionSummary: Codable, Equatable {
    let id: UUID
    let schemaVersion: Int
    let sourcePlanID: UUID?
    let planSnapshot: WorkoutPlan
    let attemptedAt: Date
    let lastUpdatedAt: Date
    let outcome: WorkoutExecutionOutcome
    let activeDuration: WorkoutActiveDuration
    let distance: WorkoutDistance
    let progress: WorkoutExecutionProgress
    let physicalStopConfirmation: WorkoutPhysicalStopConfirmation
}
