import Foundation

struct HistoryHealthExportPresentation: Equatable {
  let title: String
  let outcome: String
  let activity: String
  let timing: String
  let duration: String
  let distance: String
  let intervalCount: String
  let status: String
  let actionTitle: String?
  let confirmationTitle: String
  let confirmationMessage: String
}

enum HistoryHealthExportPresenter {
  static func make(
    summary: WorkoutExecutionSummary,
    isSaving: Bool
  ) -> HistoryHealthExportPresentation? {
    let candidateVersion = nextVersion(summary.healthExport)
    guard case let .eligible(payload) = WorkoutHealthPayloadFactory.make(
      summary: summary,
      syncVersion: candidateVersion
    ) else { return nil }

    let distance = payload.distanceMetres.map {
      "\(NSDecimalNumber(decimal: $0).stringValue) m"
    } ?? "Not included"
    let activity = summary.planSnapshot.activity == .indoorWalking
      ? "Indoor walking" : "Indoor running"
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    let timing = "\(formatter.string(from: payload.startedAt)) – \(formatter.string(from: payload.endedAt))"
    let state = summary.healthExport ?? .notRequested
    return .init(
      title: summary.planSnapshot.suggestedName,
      outcome: outcome(summary.outcome),
      activity: activity,
      timing: timing,
      duration: duration(payload.activeDurationSeconds),
      distance: distance,
      intervalCount: "\(payload.intervals.count)",
      status: status(state, isSaving: isSaving),
      actionTitle: action(state, isSaving: isSaving),
      confirmationTitle: "Save to Apple Health?",
      confirmationMessage: "\(activity), \(timing), \(duration(payload.activeDurationSeconds)), distance: \(distance), \(payload.intervals.count) interval metadata record\(payload.intervals.count == 1 ? "" : "s"). Each interval contains prescribed, effective-target and separately observed speed and inclination."
    )
  }

  private static func nextVersion(_ state: WorkoutHealthExportState?) -> Int {
    switch state {
    case let .pending(_, version)?, let .failedAmbiguous(_, version)?: version + 1
    case let .failedRetryable(_, version)?: version + 1
    case let .saved(_, version, _, _, _)?: version
    case .notRequested?, .denied?, .unavailable?, nil: 1
    }
  }

  private static func outcome(_ outcome: WorkoutExecutionOutcome) -> String {
    switch outcome {
    case .completed: "Completed"
    case .stoppedByUser: "Stopped by you"
    case .inProgress: "In progress"
    case .interrupted: "Interrupted"
    case .failed: "Failed"
    }
  }

  private static func duration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainder = seconds % 60
    return minutes > 0 ? "\(minutes)m \(remainder)s" : "\(remainder)s"
  }

  private static func status(
    _ state: WorkoutHealthExportState,
    isSaving: Bool
  ) -> String {
    if isSaving { return "Saving to Apple Health…" }
    return switch state {
    case .notRequested: "Not saved to Apple Health"
    case .pending: "Save result is uncertain"
    case let .saved(_, _, _, _, included):
      included ? "Saved to Apple Health with distance" : "Saved to Apple Health without distance"
    case let .denied(type):
      type == .workout ? "Apple Health workout permission denied" : "Apple Health distance permission denied"
    case .unavailable: "Apple Health is unavailable"
    case .failedRetryable: "Apple Health save failed; you can retry"
    case .failedAmbiguous: "Apple Health may have saved this workout; retry will replace it"
    }
  }

  private static func action(
    _ state: WorkoutHealthExportState,
    isSaving: Bool
  ) -> String? {
    guard !isSaving else { return nil }
    return switch state {
    case .saved: nil
    case .notRequested, .denied, .unavailable: "Save to Apple Health"
    case .pending, .failedRetryable, .failedAmbiguous: "Retry Apple Health Save"
    }
  }
}

@MainActor
final class HistoryHealthExportViewModel: ObservableObject {
  @Published private(set) var summary: WorkoutExecutionSummary?
  @Published private(set) var isSaving = false
  private let history: any WorkoutHistoryRepositoryProtocol
  private let coordinator: WorkoutHealthExportCoordinator

  init(
    history: any WorkoutHistoryRepositoryProtocol,
    healthStore: any WorkoutHealthStoreProtocol
  ) {
    self.history = history
    coordinator = WorkoutHealthExportCoordinator(history: history, healthStore: healthStore)
    refresh()
  }

  var presentation: HistoryHealthExportPresentation? {
    summary.flatMap { HistoryHealthExportPresenter.make(summary: $0, isSaving: isSaving) }
  }

  func save() async {
    guard let summary else { return }
    isSaving = true
    _ = await coordinator.save(summary)
    refresh()
    isSaving = false
  }

  private func refresh() {
    guard case let .available(summaries) = history.list().canonical else {
      summary = nil
      return
    }
    summary = summaries
      .filter { HistoryHealthExportPresenter.make(summary: $0, isSaving: false) != nil }
      .max(by: { $0.lastUpdatedAt < $1.lastUpdatedAt })
  }
}

#if DEBUG
@MainActor
enum HistoryHealthExportUITestConfiguration {
  static func makeViewModelIfRequested() -> HistoryHealthExportViewModel? {
    guard ProcessInfo.processInfo.arguments.contains("--paceprompt-health-export-ui-testing") else {
      return nil
    }
    let summary = syntheticSummary()
    let history = UITestHistory(summary: summary)
    return .init(history: history, healthStore: UITestHealthStore())
  }

  private static func syntheticSummary() -> WorkoutExecutionSummary {
    let start = Date(timeIntervalSince1970: 1_780_000_000)
    let end = start.addingTimeInterval(90)
    let plan = WorkoutPlan(
      schemaVersion: 1,
      suggestedName: "Synthetic steady walk",
      activity: .indoorWalking,
      steps: [
        .init(
          kind: .interval,
          label: "Steady",
          duration: .init(value: 90, unit: .seconds),
          targetSpeed: .init(value: 4.2, unit: .kilometresPerHour),
          targetInclination: .init(value: 1, unit: .percent)
        )
      ]
    )
    let interval = WorkoutExecutedInterval(
      segmentIndex: 0,
      intervalIndex: 0,
      startedAt: start,
      endedAt: end,
      prescribed: .init(kind: .interval, speedKilometresPerHour: 4.2, inclinationPercent: 1),
      effectiveSpeed: .init(kilometresPerHour: 4.2, source: .planned),
      effectiveInclination: .init(percent: 1, source: .planned),
      settledObservation: .init(
        observedAt: start,
        speedKilometresPerHour: 4.2,
        inclinationPercent: 1,
        provenance: .fr30zTreadmillDataCurrentEpoch
      ),
      endReason: .completed
    )
    return .init(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000064")!,
      schemaVersion: 2,
      sourcePlanID: nil,
      planSnapshot: plan,
      attemptedAt: start,
      lastUpdatedAt: end,
      outcome: .completed,
      activeDuration: .measured(seconds: 90),
      distance: .measuredWithProvenance(
        metres: 105,
        provenance: .init(
          method: .fr30zCumulativeDistanceDelta,
          startCumulativeMetres: 20,
          startObservedAt: start,
          finalCumulativeMetres: 125,
          finalObservedAt: end
        )
      ),
      progress: .init(completedStepCount: 1, currentStepIndex: nil, activeSecondsInCurrentStep: 0),
      physicalStopConfirmation: .humanConfirmed(at: end),
      activityTimeline: .recorded(
        startedAt: start,
        endedAt: end,
        timingProvenance: .executionClock,
        executedIntervals: [interval]
      ),
      healthExport: .notRequested
    )
  }
}

private final class UITestHistory: WorkoutHistoryRepositoryProtocol {
  private var summary: WorkoutExecutionSummary
  init(summary: WorkoutExecutionSummary) { self.summary = summary }
  func list() -> WorkoutHistoryRepositoryStatus {
    .init(canonical: .available(summaries: [summary]), staging: .absent)
  }
  func record(_ summary: WorkoutExecutionSummary) { self.summary = summary }
}

private final class UITestHealthStore: WorkoutHealthStoreProtocol {
  var isHealthDataAvailable: Bool { true }
  func requestWriteAuthorization() async throws {}
  func authorizationStatus(for type: WorkoutHealthWriteType) -> WorkoutHealthAuthorizationStatus {
    .authorized
  }
  func save(_ payload: WorkoutHealthExportPayload) async throws -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000000164")!
  }
}
#endif
