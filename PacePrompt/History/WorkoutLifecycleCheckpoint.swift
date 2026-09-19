import Foundation

enum WorkoutLifecycleCheckpointPhase: String, Codable, Equatable {
  case acquiringControl
  case waitingForPhysicalStart
  case applyingTargets
  case running
  case checkingTreadmill
  case paused
  case restoringTargets
  case awaitingPhysicalStop
  case readyToEnd
  case ending
}

enum WorkoutLifecycleTargetIntent: Codable, Equatable {
  case requestControl
  case setTargetSpeed(Decimal)
  case setTargetInclination(Decimal)

  private enum Kind: String, Codable {
    case requestControl
    case setTargetSpeed
    case setTargetInclination
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .requestControl:
      self = .requestControl
    case .setTargetSpeed:
      self = .setTargetSpeed(try container.decode(Decimal.self, forKey: .value))
    case .setTargetInclination:
      self = .setTargetInclination(try container.decode(Decimal.self, forKey: .value))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .requestControl:
      try container.encode(Kind.requestControl, forKey: .kind)
    case .setTargetSpeed(let value):
      try container.encode(Kind.setTargetSpeed, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .setTargetInclination(let value):
      try container.encode(Kind.setTargetInclination, forKey: .kind)
      try container.encode(value, forKey: .value)
    }
  }
}

struct WorkoutLifecycleCheckpoint: Codable, Equatable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let historySummaryID: UUID
  let sourcePlanID: UUID?
  let recordedAt: Date
  let peripheralIdentity: String
  let equipmentIdentity: String
  let connectionEpoch: UInt64
  let executionProfileIdentity: String
  let phase: WorkoutLifecycleCheckpointPhase
  let currentStepIndex: Int
  let completedStepCount: Int
  let evidenceBackedActiveSeconds: TimeInterval
  let speedOverrideKilometresPerHour: Decimal?
  let inclinationOverridePercent: Decimal?
  let effectiveTargetSpeedKilometresPerHour: Decimal
  let effectiveTargetInclinationPercent: Decimal
  let lastConfirmedTargetSpeedKilometresPerHour: Decimal?
  let lastConfirmedTargetInclinationPercent: Decimal?
  let pendingProcedureID: UInt64?
  let pendingTargetIntent: WorkoutLifecycleTargetIntent?
}

protocol WorkoutLifecycleCheckpointRepositoryProtocol {
  func load() throws -> WorkoutLifecycleCheckpoint?
  func save(_ checkpoint: WorkoutLifecycleCheckpoint) throws
  func remove() throws
}

final class WorkoutLifecycleCheckpointRepository: WorkoutLifecycleCheckpointRepositoryProtocol {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func load() throws -> WorkoutLifecycleCheckpoint? {
    let url = try checkpointURL()
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let checkpoint = try JSONDecoder().decode(
      WorkoutLifecycleCheckpoint.self,
      from: Data(contentsOf: url)
    )
    guard checkpoint.schemaVersion == WorkoutLifecycleCheckpoint.currentSchemaVersion else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return checkpoint
  }

  func save(_ checkpoint: WorkoutLifecycleCheckpoint) throws {
    let url = try checkpointURL()
    let directory = url.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var mutableDirectory = directory
    try mutableDirectory.setResourceValues(resourceValues)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(checkpoint)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
  }

  func remove() throws {
    let url = try checkpointURL()
    guard fileManager.fileExists(atPath: url.path) else { return }
    try fileManager.removeItem(at: url)
  }

  private func checkpointURL() throws -> URL {
    try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    .appendingPathComponent("PacePromptLifecycle", isDirectory: true)
    .appendingPathComponent("active-workout-checkpoint.json")
  }
}
