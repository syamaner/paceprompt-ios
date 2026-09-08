import Foundation

enum PlansStatusTone: Equatable {
    case neutral
    case warning
    case failure
}

struct PlansStatusPresentation: Equatable {
    let title: String
    let detail: String
    let symbol: String
    let tone: PlansStatusTone
    let retryTitle: String?
}

struct PlansPlanRowPresentation: Equatable, Identifiable {
    let id: UUID
    let name: String
    let activity: String
    let activitySymbol: String
    let stepCount: String
    let duration: String

    init(record: SavedPlanRecord) {
        id = record.id
        name = record.plan.suggestedName
        switch record.plan.activity {
        case .indoorWalking:
            activity = "Indoor walking"
            activitySymbol = "figure.walk"
        case .indoorRunning:
            activity = "Indoor running"
            activitySymbol = "figure.run"
        }
        let count = record.plan.steps.count
        stepCount = "\(count) \(count == 1 ? "step" : "steps")"
        duration = Self.durationText(for: record.plan.steps)
    }

    var accessibilityValue: String {
        "\(activity), \(stepCount), \(duration)"
    }

    private static func durationText(for steps: [WorkoutStep]) -> String {
        let total = steps.reduce(Decimal.zero) { partial, step in
            partial + Decimal(step.duration.value)
        }
        let totalSeconds = NSDecimalNumber(decimal: total).int64Value
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PlansDeletionPresentation: Equatable {
    let title: String
    let message: String

    init(record: SavedPlanRecord) {
        let count = record.plan.steps.count
        title = "Delete \(record.plan.suggestedName)?"
        message = "This permanently removes the plan and its \(count) \(count == 1 ? "step" : "steps") from this iPhone. It cannot be undone."
    }
}

enum ManualPlanProblemKind: Equatable {
    case input
    case validation(WorkoutPlanValidationIssue.Code)
}

enum ManualPlanStepField: String, Hashable {
    case kind
    case label
    case duration
    case speed
    case inclination

    var displayName: String {
        switch self {
        case .kind: "type"
        case .label: "label"
        case .duration: "duration"
        case .speed: "speed"
        case .inclination: "inclination"
        }
    }
}

struct ManualPlanIssuePresentation: Equatable {
    let kind: ManualPlanProblemKind
    let path: String
    let context: String
    let message: String
    let stepIndex: Int?
    let field: ManualPlanStepField?

    init(input issue: ManualWorkoutInputIssue) {
        self.init(kind: .input, path: issue.path, message: issue.message)
    }

    init(validation issue: WorkoutPlanValidationIssue) {
        self.init(kind: .validation(issue.code), path: issue.path, message: issue.message)
    }

    private init(kind: ManualPlanProblemKind, path: String, message: String) {
        self.kind = kind
        self.path = path
        self.message = message

        let location = Self.location(for: path)
        stepIndex = location.stepIndex
        field = location.field
        context = Self.context(for: path, stepIndex: location.stepIndex, field: location.field)
    }

    private static func location(for path: String) -> (stepIndex: Int?, field: ManualPlanStepField?) {
        guard path.hasPrefix("steps["),
              let closingBracket = path.firstIndex(of: "]"),
              let index = Int(path[path.index(path.startIndex, offsetBy: 6)..<closingBracket]) else {
            return (nil, nil)
        }

        let field: ManualPlanStepField?
        if path.hasSuffix(".kind") {
            field = .kind
        } else if path.hasSuffix(".label") {
            field = .label
        } else if path.hasSuffix(".duration.value") {
            field = .duration
        } else if path.hasSuffix(".targetSpeed.value") {
            field = .speed
        } else if path.hasSuffix(".targetInclination.value") {
            field = .inclination
        } else {
            field = nil
        }
        return (index, field)
    }

    private static func context(
        for path: String,
        stepIndex: Int?,
        field: ManualPlanStepField?
    ) -> String {
        if let stepIndex {
            let order = String(format: "%02d", stepIndex + 1)
            if let field {
                return "Step \(order) · \(field.displayName.capitalized)"
            }
            return "Step \(order)"
        }
        if path == "suggestedName" { return "Plan name" }
        if path == "steps" { return "Ordered steps" }
        if path.hasPrefix("capabilities.") { return "Capability snapshot" }
        if path == "schemaVersion" { return "Plan format" }
        return "Plan"
    }
}

struct ManualPlanEditorStepPresentation: Equatable, Identifiable {
    let id: UUID
    let index: Int
    let order: String
    let kind: WorkoutStepKind
    let kindTitle: String
    let label: String
    let duration: String
    let speed: String
    let inclination: String
    let problemFields: [ManualPlanStepField]
    let hasProblem: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool

    var problemSummary: String? {
        guard !problemFields.isEmpty else { return hasProblem ? "Step needs attention" : nil }
        return "Needs attention: \(problemFields.map(\.displayName).joined(separator: ", "))"
    }

    var accessibilityValue: String {
        "\(kindTitle), \(label), \(duration) seconds, \(speed) kilometres per hour, \(inclination) percent"
    }
}

struct ManualPlanEditorPresentation: Equatable {
    let title: String
    let activity: String
    let orderedStepCount: String
    let steps: [ManualPlanEditorStepPresentation]
    let issues: [ManualPlanIssuePresentation]
    let planNameHasProblem: Bool
    let reviewActionEnabled: Bool
    let reviewFooter: String

    init(
        draft: ManualWorkoutDraft,
        editing: Bool,
        inputIssues: [ManualWorkoutInputIssue],
        validationIssues: [WorkoutPlanValidationIssue]
    ) {
        title = editing ? "Edit plan" : "New plan"
        activity = draft.activity.displayName
        orderedStepCount = "Steps · \(draft.steps.count) ordered"
        let mappedIssues = inputIssues.map(ManualPlanIssuePresentation.init(input:))
            + validationIssues.map(ManualPlanIssuePresentation.init(validation:))
        issues = mappedIssues
        planNameHasProblem = mappedIssues.contains { $0.path == "suggestedName" }
        reviewActionEnabled = mappedIssues.isEmpty
        reviewFooter = "Review validates the whole plan against the currently known capability snapshot. It does not save, contact or control the treadmill."

        steps = draft.steps.enumerated().map { index, step in
            let stepIssues = mappedIssues.filter { $0.stepIndex == index }
            let problemFields = Array(Set(stepIssues.compactMap(\.field))).sorted {
                Self.fieldOrder($0) < Self.fieldOrder($1)
            }
            return ManualPlanEditorStepPresentation(
                id: step.id,
                index: index,
                order: String(format: "%02d", index + 1),
                kind: step.kind,
                kindTitle: step.kind.displayName,
                label: step.label,
                duration: step.durationSeconds,
                speed: step.speedKilometresPerHour,
                inclination: step.inclinationPercent,
                problemFields: problemFields,
                hasProblem: !stepIssues.isEmpty,
                canMoveUp: index > 0,
                canMoveDown: index < draft.steps.count - 1
            )
        }
    }

    private static func fieldOrder(_ field: ManualPlanStepField) -> Int {
        switch field {
        case .kind: 0
        case .label: 1
        case .duration: 2
        case .speed: 3
        case .inclination: 4
        }
    }
}

struct ManualPlanReviewStepPresentation: Equatable, Identifiable {
    let id: Int
    let order: String
    let kind: WorkoutStepKind
    let kindTitle: String
    let label: String
    let duration: String
    let exactDuration: String
    let speed: String
    let inclination: String

    var title: String {
        label.isEmpty ? "\(order) · \(kindTitle)" : "\(order) · \(kindTitle) · \(label)"
    }

    var targets: String {
        "\(speed) km/h · \(inclination) %"
    }

    var accessibilityValue: String {
        "\(kindTitle), \(label), \(exactDuration), \(speed) kilometres per hour, \(inclination) percent"
    }
}

struct ManualPlanReviewPresentation: Equatable {
    let name: String
    let activity: String
    let activitySymbol: String
    let totalDuration: String
    let estimatedDistance: String
    let stepCount: String
    let steps: [ManualPlanReviewStepPresentation]
    let confirmationTitle: String
    let confirmationEnabled: Bool
    let confirmationFooter: String

    init(
        preview: WorkoutPlanPreview,
        editing: Bool,
        canConfirm: Bool,
        locale: Locale = .autoupdatingCurrent
    ) {
        name = preview.plan.suggestedName
        activity = preview.plan.activity.displayName
        activitySymbol = preview.plan.activity == .indoorWalking ? "figure.walk" : "figure.run"
        totalDuration = manualPlanDurationText(
            seconds: NSDecimalNumber(decimal: preview.totalDurationSeconds).int64Value
        )
        estimatedDistance = "\(PlanValueFormatter.estimatedDistanceText(preview.estimatedDistanceKilometres, locale: locale)) km"
        stepCount = preview.plan.steps.count.formatted(.number.locale(locale))
        confirmationTitle = editing ? "Confirm and update" : "Confirm and save"
        confirmationEnabled = canConfirm
        confirmationFooter = "Validated against the currently known capability snapshot. Review and confirmation do not contact or control the treadmill. Only confirmation writes to local storage."
        steps = preview.plan.steps.enumerated().map { index, step in
            ManualPlanReviewStepPresentation(
                id: index,
                order: String(format: "%02d", index + 1),
                kind: step.kind,
                kindTitle: step.kind.displayName,
                label: step.label,
                duration: manualPlanDurationText(seconds: Int64(step.duration.value)),
                exactDuration: "\(step.duration.value) seconds",
                speed: manualPlanTargetText(step.targetSpeed.value, locale: locale),
                inclination: manualPlanTargetText(step.targetInclination.value, locale: locale)
            )
        }
    }

}

private func manualPlanDurationText(seconds: Int64) -> String {
    let hours = seconds / 3_600
    let minutes = seconds % 3_600 / 60
    let remainingSeconds = seconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%d:%02d", minutes, remainingSeconds)
}

private func manualPlanTargetText(_ value: Decimal, locale: Locale) -> String {
    let text = PlanValueFormatter.localizedText(value, locale: locale)
    let separator = locale.decimalSeparator ?? "."
    return text.contains(separator) ? text : "\(text)\(separator)0"
}

enum PlansLibraryContent: Equatable {
    case empty
    case populated([PlansPlanRowPresentation])
    case blocked(PlansStatusPresentation)
}

struct PlansLibraryPresentation: Equatable {
    let content: PlansLibraryContent
    let stagingWarning: PlansStatusPresentation?
    let canCreate: Bool
    let canImport: Bool
    let canExport: Bool

    init(status: SavedPlanRepositoryStatus) {
        let mutationAllowed = status.staging == .absent && status.canonical.allowsMutation
        canCreate = mutationAllowed
        canImport = mutationAllowed
        canExport = mutationAllowed && status.canonical.hasRecords
        stagingWarning = Self.warning(for: status.staging)

        switch status.canonical {
        case .empty:
            content = .empty
        case let .available(records):
            content = .populated(records.map(PlansPlanRowPresentation.init))
        case .protectedDataUnavailable:
            content = .blocked(
                Self.statusCard(
                    title: "Plans are locked",
                    detail: "Protected data is unavailable until this iPhone is unlocked. Your saved plans are untouched.",
                    symbol: "lock.shield",
                    tone: .neutral,
                    retryTitle: "Try again"
                )
            )
        case .readFailure:
            content = .blocked(
                Self.statusCard(
                    title: "Could not read plans",
                    detail: "The plan store could not be opened. Nothing was written or deleted, and your saved data was preserved.",
                    symbol: "exclamationmark.triangle.fill",
                    tone: .failure,
                    retryTitle: "Retry read"
                )
            )
        case .corruptData:
            content = .blocked(
                Self.statusCard(
                    title: "Saved plans are corrupt",
                    detail: "The stored records could not be decoded safely. They were preserved unchanged; editing and export are disabled.",
                    symbol: "exclamationmark.triangle.fill",
                    tone: .failure,
                    retryTitle: nil
                )
            )
        case .partialWriteDetected:
            content = .blocked(
                Self.statusCard(
                    title: "Last save finished partially",
                    detail: "A partial write was detected. Existing plans were preserved; editing and export are disabled.",
                    symbol: "exclamationmark.triangle.fill",
                    tone: .warning,
                    retryTitle: nil
                )
            )
        case let .unsupportedStoreVersion(version):
            content = .blocked(
                Self.statusCard(
                    title: "Saved by a newer version",
                    detail: "This plan store uses schema v\(version); this build reads v\(SavedPlanStoreSchema.currentVersion). The data is kept as-is and cannot be shown safely.",
                    symbol: "exclamationmark.circle.fill",
                    tone: .neutral,
                    retryTitle: nil
                )
            )
        case let .unsupportedPlanVersion(_, version):
            content = .blocked(
                Self.statusCard(
                    title: "A plan uses a newer version",
                    detail: "A saved plan uses schema v\(version); this build reads v\(WorkoutPlanSchema.currentVersion). The store is kept as-is and cannot be shown safely.",
                    symbol: "exclamationmark.circle.fill",
                    tone: .neutral,
                    retryTitle: nil
                )
            )
        }
    }

    private static func warning(for staging: SavedPlanStagingState) -> PlansStatusPresentation? {
        switch staging {
        case .absent:
            nil
        case .staleArtifactPresent:
            statusCard(
                title: "A previous save needs attention",
                detail: "A stale staging file was detected. Readable plans remain visible and preserved, but all changes are disabled.",
                symbol: "exclamationmark.triangle.fill",
                tone: .warning,
                retryTitle: nil
            )
        case .presenceUnavailable:
            statusCard(
                title: "Save status is unavailable",
                detail: "PacePrompt could not check for a staging file. Saved data was preserved, and all changes are disabled.",
                symbol: "exclamationmark.triangle.fill",
                tone: .warning,
                retryTitle: nil
            )
        }
    }

    private static func statusCard(
        title: String,
        detail: String,
        symbol: String,
        tone: PlansStatusTone,
        retryTitle: String?
    ) -> PlansStatusPresentation {
        .init(title: title, detail: detail, symbol: symbol, tone: tone, retryTitle: retryTitle)
    }
}

private extension SavedPlanCanonicalState {
    var allowsMutation: Bool {
        switch self {
        case .empty, .available:
            true
        case .protectedDataUnavailable,
             .readFailure,
             .corruptData,
             .partialWriteDetected,
             .unsupportedStoreVersion,
             .unsupportedPlanVersion:
            false
        }
    }

    var hasRecords: Bool {
        guard case let .available(records) = self else { return false }
        return !records.isEmpty
    }
}

extension WorkoutActivity {
    static var allCases: [WorkoutActivity] { [.indoorWalking, .indoorRunning] }

    var displayName: String {
        switch self {
        case .indoorWalking: "Indoor walking"
        case .indoorRunning: "Indoor running"
        }
    }
}

extension WorkoutStepKind {
    static var allCases: [WorkoutStepKind] { [.warmUp, .interval, .recovery, .coolDown] }

    var displayName: String {
        switch self {
        case .warmUp: "Warm-up"
        case .interval: "Interval"
        case .recovery: "Recovery"
        case .coolDown: "Cool-down"
        }
    }
}
