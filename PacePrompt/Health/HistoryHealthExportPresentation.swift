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
      status: status(state, isSaving: isSaving, formatter: formatter),
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
    isSaving: Bool,
    formatter: DateFormatter
  ) -> String {
    if isSaving { return "Saving to Apple Health…" }
    return switch state {
    case .notRequested: "Not saved to Apple Health"
    case .pending: "Save result is uncertain"
    case let .saved(savedAt, _, _, _, included):
      "Saved to Apple Health on \(formatter.string(from: savedAt)) "
        + (included ? "with distance" : "without distance")
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

#if DEBUG
enum HistoryUITestFixtures {
  static func syntheticSummary() -> WorkoutExecutionSummary {
    let start = Date(timeIntervalSince1970: 1_780_000_000)
    let firstEnd = start.addingTimeInterval(30)
    let secondEnd = firstEnd.addingTimeInterval(30)
    let end = secondEnd.addingTimeInterval(30)
    let plan = WorkoutPlan(
      schemaVersion: 1,
      suggestedName: "Synthetic steady walk",
      activity: .indoorWalking,
      steps: [
        .init(
          kind: .warmUp,
          label: "Warm up",
          duration: .init(value: 30, unit: .seconds),
          targetSpeed: .init(value: 3.5, unit: .kilometresPerHour),
          targetInclination: .init(value: 0, unit: .percent)
        ),
        .init(
          kind: .interval,
          label: "Steady",
          duration: .init(value: 30, unit: .seconds),
          targetSpeed: .init(value: 4.2, unit: .kilometresPerHour),
          targetInclination: .init(value: 1, unit: .percent)
        ),
        .init(
          kind: .coolDown,
          label: "Cool down",
          duration: .init(value: 30, unit: .seconds),
          targetSpeed: .init(value: 3.2, unit: .kilometresPerHour),
          targetInclination: .init(value: 0, unit: .percent)
        ),
      ]
    )
    func interval(
      _ segment: Int,
      _ intervalStart: Date,
      _ intervalEnd: Date,
      _ endReason: WorkoutExecutedIntervalEndReason
    ) -> WorkoutExecutedInterval {
      let step = plan.steps[segment]
      return .init(
        segmentIndex: segment,
        intervalIndex: 0,
        startedAt: intervalStart,
        endedAt: intervalEnd,
        prescribed: .init(
          kind: step.kind,
          speedKilometresPerHour: step.targetSpeed.value,
          inclinationPercent: step.targetInclination.value
        ),
        effectiveSpeed: .init(kilometresPerHour: step.targetSpeed.value, source: .planned),
        effectiveInclination: .init(percent: step.targetInclination.value, source: .planned),
        settledObservation: .init(
          observedAt: intervalStart,
          speedKilometresPerHour: step.targetSpeed.value,
          inclinationPercent: step.targetInclination.value,
          provenance: .fr30zTreadmillDataCurrentEpoch
        ),
        endReason: endReason
      )
    }
    let intervals = [
      interval(0, start, firstEnd, .planTransition),
      interval(1, firstEnd, secondEnd, .planTransition),
      interval(2, secondEnd, end, .completed),
    ]
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
      progress: .init(completedStepCount: 3, currentStepIndex: nil, activeSecondsInCurrentStep: 0),
      physicalStopConfirmation: .humanConfirmed(at: end),
      activityTimeline: .recorded(
        startedAt: start,
        endedAt: end,
        timingProvenance: .executionClock,
        executedIntervals: intervals
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

enum HistoryRepositoryTone: Equatable { case neutral, warning, failure }

struct HistoryRepositoryMessage: Equatable {
  let title: String
  let detail: String
  let symbol: String
  let tone: HistoryRepositoryTone
}

struct HistoryWorkoutRow: Equatable, Identifiable {
  let id: UUID
  let title: String
  let outcome: String
  let activity: String
  let date: String
  let duration: String
  let distance: String
  let health: String

  var accessibilityValue: String {
    "\(outcome), \(activity), \(date), duration \(duration), distance \(distance), \(health)"
  }
}

enum HistoryLibraryContent: Equatable {
  case loading
  case empty
  case populated([HistoryWorkoutRow])
  case blocked(HistoryRepositoryMessage)
}

struct HistoryLibraryPresentation: Equatable {
  let content: HistoryLibraryContent
  let warning: HistoryRepositoryMessage?

  static let loading = Self(content: .loading, warning: nil)

  private init(content: HistoryLibraryContent, warning: HistoryRepositoryMessage?) {
    self.content = content
    self.warning = warning
  }

  init(
    status: WorkoutHistoryRepositoryStatus,
    locale: Locale = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent
  ) {
    warning = Self.warning(status.staging)
    switch status.canonical {
    case .empty:
      content = .empty
    case let .available(summaries):
      let rows = summaries.sorted {
        $0.attemptedAt == $1.attemptedAt
          ? $0.id.uuidString < $1.id.uuidString
          : $0.attemptedAt > $1.attemptedAt
      }.map { HistoryWorkoutRow(summary: $0, locale: locale, timeZone: timeZone) }
      content = rows.isEmpty ? .empty : .populated(rows)
    case .protectedDataUnavailable:
      content = .blocked(Self.message(
        "History is locked",
        "Unlock this iPhone, then retry. Stored workouts were preserved and were not treated as empty.",
        "lock.fill",
        .neutral
      ))
    case .readFailure:
      content = .blocked(Self.message(
        "History could not be read",
        "PacePrompt could not read the protected history file. The file was preserved.",
        "exclamationmark.triangle.fill",
        .failure
      ))
    case .corruptData:
      content = .blocked(Self.message(
        "History data is unreadable",
        "The stored file could not be decoded safely. It was preserved without guessing or showing an empty library.",
        "exclamationmark.triangle.fill",
        .failure
      ))
    case .partialWriteDetected:
      content = .blocked(Self.message(
        "A partial history write was detected",
        "The incomplete data was preserved. PacePrompt will not promote, merge or guess its contents.",
        "exclamationmark.triangle.fill",
        .warning
      ))
    case let .unsupportedStoreVersion(version):
      content = .blocked(Self.message(
        "History was saved by a newer version",
        "This store uses format v\(version). It was preserved unchanged and cannot be shown safely.",
        "exclamationmark.circle.fill",
        .neutral
      ))
    case let .unsupportedSummaryVersion(_, version):
      content = .blocked(Self.message(
        "A workout uses a newer version",
        "One workout uses schema v\(version). The complete store was preserved unchanged.",
        "exclamationmark.circle.fill",
        .neutral
      ))
    case let .unsupportedPlanVersion(_, version):
      content = .blocked(Self.message(
        "A plan snapshot uses a newer version",
        "One workout plan uses schema v\(version). The complete store was preserved unchanged.",
        "exclamationmark.circle.fill",
        .neutral
      ))
    }
  }

  private static func message(
    _ title: String,
    _ detail: String,
    _ symbol: String,
    _ tone: HistoryRepositoryTone
  ) -> HistoryRepositoryMessage {
    .init(title: title, detail: detail, symbol: symbol, tone: tone)
  }

  private static func warning(_ staging: WorkoutHistoryStagingState) -> HistoryRepositoryMessage? {
    switch staging {
    case .absent:
      nil
    case .staleArtifactPresent:
      .init(
        title: "A previous history save needs attention",
        detail: "Readable workouts remain visible, but Apple Health save-state changes are disabled while the stale staging file is preserved.",
        symbol: "exclamationmark.triangle.fill",
        tone: .warning
      )
    case .presenceUnavailable:
      .init(
        title: "History save status is unavailable",
        detail: "PacePrompt could not check for a staging file. Workouts remain visible, but Apple Health save-state changes are disabled.",
        symbol: "exclamationmark.triangle.fill",
        tone: .warning
      )
    }
  }
}

struct HistoryPlanSegment: Equatable, Identifiable {
  let id: Int
  let title: String
  let duration: String
  let targets: String
}

struct HistoryExecutedIntervalDetail: Equatable, Identifiable {
  let id: String
  let title: String
  let timing: String
  let prescribed: String
  let effective: String
  let observed: String
  let ended: String
}

struct HistoryHealthCard: Equatable {
  let title: String
  let detail: String
  let symbol: String
  let actionTitle: String?
  let confirmationTitle: String?
  let confirmationMessage: String?
}

struct HistoryWorkoutDetail: Equatable {
  let id: UUID
  let title: String
  let outcome: String
  let activityAndDate: String
  let duration: String
  let distance: String
  let progress: String
  let prescribed: [HistoryPlanSegment]
  let executed: [HistoryExecutedIntervalDetail]
  let executionUnavailable: String?
  let health: HistoryHealthCard
}

enum HistoryWorkoutDetailPresenter {
  static func make(
    summary: WorkoutExecutionSummary,
    isSaving: Bool,
    healthMutationAllowed: Bool,
    locale: Locale = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> HistoryWorkoutDetail {
    let dateFormatter = historyDateFormatter(locale: locale, timeZone: timeZone)
    let timeFormatter = historyTimeFormatter(locale: locale, timeZone: timeZone)
    let executed: [HistoryExecutedIntervalDetail]
    let unavailable: String?
    if summary.schemaVersion == WorkoutExecutionSummarySchema.legacyVersion {
      executed = []
      unavailable = "Executed interval detail is unavailable in schema v1. PacePrompt does not reconstruct it from plan targets or summary timestamps."
    } else {
      switch summary.activityTimeline {
      case let .recorded(_, _, _, intervals):
        executed = intervals.map { interval in
          .init(
            id: "\(interval.segmentIndex)-\(interval.intervalIndex)",
            title: "Segment \(interval.segmentIndex + 1) · interval \(interval.intervalIndex + 1)",
            timing: "\(timeFormatter.string(from: interval.startedAt))–\(timeFormatter.string(from: interval.endedAt))",
            prescribed: "Prescribed · \(historyDecimal(interval.prescribed.speedKilometresPerHour, locale: locale)) km/h · \(historyDecimal(interval.prescribed.inclinationPercent, locale: locale))%",
            effective: "Effective · \(historyDecimal(interval.effectiveSpeed.kilometresPerHour, locale: locale)) km/h (\(source(interval.effectiveSpeed.source))) · \(historyDecimal(interval.effectiveInclination.percent, locale: locale))% (\(source(interval.effectiveInclination.source)))",
            observed: "Observed · \(historyDecimal(interval.settledObservation.speedKilometresPerHour, locale: locale)) km/h · \(historyDecimal(interval.settledObservation.inclinationPercent, locale: locale))% at \(timeFormatter.string(from: interval.settledObservation.observedAt))",
            ended: "Ended · \(endReason(interval.endReason))"
          )
        }
        unavailable = nil
      case let .unavailable(reason):
        executed = []
        unavailable = "Executed interval timing is unavailable (\(reason.rawValue)). No detail was inferred."
      case nil:
        executed = []
        unavailable = "Executed interval detail is unavailable. No detail was inferred."
      }
    }

    return .init(
      id: summary.id,
      title: summary.planSnapshot.suggestedName,
      outcome: outcome(summary),
      activityAndDate: "\(activity(summary.planSnapshot.activity)) · \(dateFormatter.string(from: summary.attemptedAt))",
      duration: duration(summary.activeDuration),
      distance: distance(summary.distance, locale: locale),
      progress: progress(summary),
      prescribed: summary.planSnapshot.steps.enumerated().map { index, step in
        .init(
          id: index,
          title: "\(index + 1). \(step.kind.historyName) · \(step.label)",
          duration: historyDuration(step.duration.value),
          targets: "\(historyDecimal(step.targetSpeed.value, locale: locale)) km/h · \(historyDecimal(step.targetInclination.value, locale: locale))%"
        )
      },
      executed: executed,
      executionUnavailable: unavailable,
      health: healthCard(
        summary: summary,
        isSaving: isSaving,
        mutationAllowed: healthMutationAllowed
      )
    )
  }

  static func outcome(_ summary: WorkoutExecutionSummary) -> String {
    if case .unconfirmed = summary.physicalStopConfirmation { return "Physically uncertain" }
    return switch summary.outcome {
    case .completed: "Completed"
    case .stoppedByUser: "Ended by you"
    case .inProgress: "Interrupted · completion unknown"
    case .interrupted: "Interrupted"
    case .failed: "Failed"
    }
  }

  static func activity(_ value: WorkoutActivity) -> String {
    value == .indoorWalking ? "Indoor walking" : "Indoor running"
  }

  static func duration(_ value: WorkoutActiveDuration) -> String {
    switch value {
    case let .measured(seconds): historyDuration(seconds)
    case .unavailable: "Unavailable"
    }
  }

  static func distance(_ value: WorkoutDistance, locale: Locale) -> String {
    switch value {
    case let .measured(metres), let .measuredWithProvenance(metres, _):
      if metres >= 1_000 {
        return "\(historyDecimal(metres / 1_000, locale: locale)) km"
      }
      return "\(historyDecimal(metres, locale: locale)) m"
    case .unavailable:
      return "Unavailable"
    }
  }

  private static func healthCard(
    summary: WorkoutExecutionSummary,
    isSaving: Bool,
    mutationAllowed: Bool
  ) -> HistoryHealthCard {
    guard let export = HistoryHealthExportPresenter.make(summary: summary, isSaving: isSaving) else {
      let detail: String
      if summary.schemaVersion == WorkoutExecutionSummarySchema.legacyVersion {
        detail = "Schema v1 stays local and is not reconstructed for Apple Health."
      } else if case .inProgress = summary.outcome {
        detail = "This persisted in-progress attempt is shown as interrupted; completion is unknown."
      } else if case .unconfirmed = summary.physicalStopConfirmation {
        detail = "The physical stop state is uncertain, so this workout remains local only."
      } else {
        detail = "This outcome or execution timeline is not eligible for Apple Health."
      }
      return .init(
        title: "Not eligible for Apple Health",
        detail: detail,
        symbol: "heart.slash",
        actionTitle: nil,
        confirmationTitle: nil,
        confirmationMessage: nil
      )
    }
    let status = mutationAllowed || export.actionTitle == nil
      ? export.status
      : "History storage needs attention before Apple Health saving."
    return .init(
      title: historyHealthTitle(summary.healthExport, isSaving: isSaving),
      detail: status,
      symbol: historyHealthSymbol(summary.healthExport, isSaving: isSaving),
      actionTitle: mutationAllowed ? export.actionTitle : nil,
      confirmationTitle: export.confirmationTitle,
      confirmationMessage: export.confirmationMessage
    )
  }

  private static func progress(_ summary: WorkoutExecutionSummary) -> String {
    let completed = summary.progress.completedStepCount
    let total = summary.planSnapshot.steps.count
    if let current = summary.progress.currentStepIndex {
      return "\(completed) of \(total) completed · step \(current + 1) active for \(historyDuration(summary.progress.activeSecondsInCurrentStep))"
    }
    return "\(completed) of \(total) prescribed segments completed"
  }

  private static func source(_ value: WorkoutTargetValueSource) -> String {
    value == .planned ? "planned" : "manual override"
  }

  private static func endReason(_ value: WorkoutExecutedIntervalEndReason) -> String {
    switch value {
    case .planTransition: "plan transition"
    case .targetChanged: "target changed"
    case .paused: "paused"
    case .completed: "completed"
    case .endedByUser: "ended by user"
    case .interrupted: "interrupted"
    case .failed: "failed"
    }
  }
}

@MainActor
final class HistoryLibraryViewModel: ObservableObject {
  @Published private(set) var repositoryStatus: WorkoutHistoryRepositoryStatus?
  @Published private(set) var savingSummaryID: UUID?

  private let history: any WorkoutHistoryRepositoryProtocol
  private let coordinator: WorkoutHealthExportCoordinator

  init(
    history: any WorkoutHistoryRepositoryProtocol,
    healthStore: any WorkoutHealthStoreProtocol
  ) {
    self.history = history
    coordinator = WorkoutHealthExportCoordinator(history: history, healthStore: healthStore)
  }

  var presentation: HistoryLibraryPresentation {
    repositoryStatus.map { HistoryLibraryPresentation(status: $0) } ?? .loading
  }

  func reload() { repositoryStatus = history.list() }

  func detail(for id: UUID) -> HistoryWorkoutDetail? {
    guard let summary = summary(for: id) else { return nil }
    return HistoryWorkoutDetailPresenter.make(
      summary: summary,
      isSaving: savingSummaryID == id,
      healthMutationAllowed: repositoryStatus?.staging == .absent
    )
  }

  func planSnapshot(for id: UUID) -> WorkoutPlan? { summary(for: id)?.planSnapshot }

  func save(summaryID: UUID) async {
    guard savingSummaryID == nil, repositoryStatus?.staging == .absent,
          let summary = summary(for: summaryID) else { return }
    savingSummaryID = summaryID
    _ = await coordinator.save(summary)
    reload()
    savingSummaryID = nil
  }

  private func summary(for id: UUID) -> WorkoutExecutionSummary? {
    guard case let .available(summaries)? = repositoryStatus?.canonical else { return nil }
    return summaries.first { $0.id == id }
  }
}

private extension HistoryWorkoutRow {
  init(summary: WorkoutExecutionSummary, locale: Locale, timeZone: TimeZone) {
    id = summary.id
    title = summary.planSnapshot.suggestedName
    outcome = HistoryWorkoutDetailPresenter.outcome(summary)
    activity = HistoryWorkoutDetailPresenter.activity(summary.planSnapshot.activity)
    date = historyDateFormatter(locale: locale, timeZone: timeZone).string(from: summary.attemptedAt)
    duration = HistoryWorkoutDetailPresenter.duration(summary.activeDuration)
    distance = HistoryWorkoutDetailPresenter.distance(summary.distance, locale: locale)
    health = historyHealthRowStatus(summary.healthExport, schemaVersion: summary.schemaVersion)
  }
}

private func historyHealthRowStatus(_ state: WorkoutHealthExportState?, schemaVersion: Int) -> String {
  guard schemaVersion == WorkoutExecutionSummarySchema.currentVersion, let state else {
    return "Apple Health unavailable"
  }
  return switch state {
  case .notRequested: "Not saved to Apple Health"
  case .pending: "Apple Health result uncertain"
  case let .saved(_, _, _, _, included):
    included ? "Saved to Apple Health with distance" : "Saved to Apple Health without distance"
  case .denied: "Apple Health permission denied"
  case .unavailable: "Apple Health unavailable"
  case .failedRetryable: "Apple Health save failed"
  case .failedAmbiguous: "Apple Health save may have completed"
  }
}

private func historyHealthTitle(_ state: WorkoutHealthExportState?, isSaving: Bool) -> String {
  if isSaving { return "Saving to Apple Health" }
  return switch state ?? .notRequested {
  case .notRequested: "Save to Apple Health"
  case .pending, .failedAmbiguous: "Apple Health result uncertain"
  case .saved: "Saved to Apple Health"
  case .denied: "Apple Health permission denied"
  case .unavailable: "Apple Health unavailable"
  case .failedRetryable: "Apple Health save failed"
  }
}

private func historyHealthSymbol(_ state: WorkoutHealthExportState?, isSaving: Bool) -> String {
  if isSaving { return "arrow.triangle.2.circlepath" }
  return switch state ?? .notRequested {
  case .notRequested: "heart"
  case .saved: "heart.fill"
  case .denied, .unavailable: "heart.slash"
  case .pending, .failedRetryable, .failedAmbiguous: "exclamationmark.triangle.fill"
  }
}

private func historyDateFormatter(
  locale: Locale = .autoupdatingCurrent,
  timeZone: TimeZone = .autoupdatingCurrent
) -> DateFormatter {
  let formatter = DateFormatter()
  formatter.locale = locale
  formatter.timeZone = timeZone
  formatter.dateStyle = .medium
  formatter.timeStyle = .short
  return formatter
}

private func historyTimeFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
  let formatter = DateFormatter()
  formatter.locale = locale
  formatter.timeZone = timeZone
  formatter.dateStyle = .none
  formatter.timeStyle = .short
  return formatter
}

private func historyDuration(_ seconds: Int) -> String {
  let hours = seconds / 3_600
  let minutes = seconds % 3_600 / 60
  let remainder = seconds % 60
  if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
  return String(format: "%d:%02d", minutes, remainder)
}

private func historyDecimal(_ value: Decimal, locale: Locale) -> String {
  let formatter = NumberFormatter()
  formatter.locale = locale
  formatter.numberStyle = .decimal
  formatter.maximumFractionDigits = 2
  return formatter.string(from: NSDecimalNumber(decimal: value))
    ?? NSDecimalNumber(decimal: value).stringValue
}

private extension WorkoutStepKind {
  var historyName: String {
    switch self {
    case .warmUp: "Warm-up"
    case .interval: "Interval"
    case .recovery: "Recovery"
    case .coolDown: "Cool-down"
    }
  }
}

#if DEBUG
@MainActor
enum HistoryLibraryUITestConfiguration {
  static func makeViewModelIfRequested() -> HistoryLibraryViewModel? {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--paceprompt-history-read-failure-ui-testing") {
      return .init(
        history: UITestStatusHistory(
          status: .init(canonical: .readFailure, staging: .absent)
        ),
        healthStore: UITestHealthStore()
      )
    }
    guard arguments.contains("--paceprompt-history-ui-testing")
            || arguments.contains("--paceprompt-health-export-ui-testing") else {
      return nil
    }
    return .init(
      history: UITestHistory(summary: HistoryUITestFixtures.syntheticSummary()),
      healthStore: UITestHealthStore()
    )
  }
}

private final class UITestStatusHistory: WorkoutHistoryRepositoryProtocol {
  let status: WorkoutHistoryRepositoryStatus

  init(status: WorkoutHistoryRepositoryStatus) { self.status = status }
  func list() -> WorkoutHistoryRepositoryStatus { status }
  func record(_ summary: WorkoutExecutionSummary) {}
}
#endif
