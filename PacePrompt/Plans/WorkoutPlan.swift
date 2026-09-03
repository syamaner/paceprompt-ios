import Foundation

enum WorkoutPlanSchema {
    static let currentVersion = 1
}

struct WorkoutPlan: Codable, Equatable {
    let schemaVersion: Int
    let suggestedName: String
    let activity: WorkoutActivity
    let steps: [WorkoutStep]
}

enum WorkoutActivity: String, Codable, Equatable {
    case indoorWalking
    case indoorRunning
}

struct WorkoutStep: Codable, Equatable {
    let kind: WorkoutStepKind
    let label: String
    let duration: WorkoutDuration
    let targetSpeed: WorkoutSpeed
    let targetInclination: WorkoutInclination
}

enum WorkoutStepKind: String, Codable, Equatable {
    case warmUp
    case interval
    case recovery
    case coolDown
}

struct WorkoutDuration: Codable, Equatable {
    let value: Int
    let unit: WorkoutDurationUnit
}

enum WorkoutDurationUnit: String, Codable, Equatable {
    case seconds
}

struct WorkoutSpeed: Codable, Equatable {
    let value: Decimal
    let unit: WorkoutSpeedUnit
}

enum WorkoutSpeedUnit: String, Codable, Equatable {
    case kilometresPerHour
}

struct WorkoutInclination: Codable, Equatable {
    let value: Decimal
    let unit: WorkoutInclinationUnit
}

enum WorkoutInclinationUnit: String, Codable, Equatable {
    case percent
}

struct WorkoutPlanCapabilities: Equatable {
    let speed: WorkoutTargetCapability<WorkoutSpeedRange>
    let inclination: WorkoutTargetCapability<WorkoutInclinationRange>
}

enum WorkoutTargetCapability<Range: Equatable>: Equatable {
    case unknown
    case unsupported
    case supported(Range)
}

struct WorkoutSpeedRange: Equatable {
    let minimum: WorkoutSpeed
    let maximum: WorkoutSpeed
    let increment: WorkoutSpeed
}

struct WorkoutInclinationRange: Equatable {
    let minimum: WorkoutInclination
    let maximum: WorkoutInclination
    let increment: WorkoutInclination
}
