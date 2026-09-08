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
