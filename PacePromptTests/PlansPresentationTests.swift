import Foundation
import XCTest
@testable import PacePrompt

@MainActor
final class PlansPresentationTests: XCTestCase {
    func testLibraryRowsContainOnlyCanonicalFactsWithExactDurationAndPluralisation() {
        let pluralRecord = record(name: "Synthetic progression")
        let plural = PlansPlanRowPresentation(record: pluralRecord)

        XCTAssertEqual(plural.name, "Synthetic progression")
        XCTAssertEqual(plural.activity, "Indoor running")
        XCTAssertEqual(plural.stepCount, "3 steps")
        XCTAssertEqual(plural.duration, "18:00")
        XCTAssertEqual(plural.accessibilityValue, "Indoor running, 3 steps, 18:00")

        let oneStepPlan = WorkoutPlan(
            schemaVersion: WorkoutPlanSchema.currentVersion,
            suggestedName: "Synthetic single step",
            activity: .indoorWalking,
            steps: [pluralRecord.plan.steps[0]]
        )
        let singularRecord = SavedPlanRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            createdAt: pluralRecord.createdAt,
            modifiedAt: pluralRecord.modifiedAt,
            plan: oneStepPlan
        )
        let singular = PlansPlanRowPresentation(record: singularRecord)

        XCTAssertEqual(singular.activity, "Indoor walking")
        XCTAssertEqual(singular.stepCount, "1 step")
        XCTAssertEqual(singular.duration, "6:00")
    }

    func testEmptyStateIsDistinctFromEveryCanonicalBlockedState() {
        let empty = PlansLibraryPresentation(
            status: .init(canonical: .empty, staging: .absent)
        )
        XCTAssertEqual(empty.content, .empty)

        let blockedStates: [SavedPlanCanonicalState] = [
            .protectedDataUnavailable,
            .readFailure,
            .corruptData,
            .partialWriteDetected,
            .unsupportedStoreVersion(4),
            .unsupportedPlanVersion(recordID: UUID(), version: 4),
        ]
        var titles: Set<String> = []
        for state in blockedStates {
            let presentation = PlansLibraryPresentation(
                status: .init(canonical: state, staging: .absent)
            )
            guard case let .blocked(card) = presentation.content else {
                return XCTFail("Blocked state was presented as \(presentation.content)")
            }
            titles.insert(card.title)
            XCTAssertFalse(presentation.canCreate)
            XCTAssertFalse(presentation.canImport)
            XCTAssertFalse(presentation.canExport)
            XCTAssertTrue(
                card.detail.localizedCaseInsensitiveContains("preserv")
                    || card.detail.contains("kept as-is")
                    || card.detail.contains("untouched")
            )
        }
        XCTAssertEqual(titles.count, blockedStates.count)
    }

    func testActionAvailabilityUsesCanonicalAndStagingCombinations() {
        let saved = record(name: "Synthetic readable")
        let empty = PlansLibraryPresentation(
            status: .init(canonical: .empty, staging: .absent)
        )
        XCTAssertTrue(empty.canCreate)
        XCTAssertTrue(empty.canImport)
        XCTAssertFalse(empty.canExport)

        let available = PlansLibraryPresentation(
            status: .init(canonical: .available(records: [saved]), staging: .absent)
        )
        XCTAssertTrue(available.canCreate)
        XCTAssertTrue(available.canImport)
        XCTAssertTrue(available.canExport)

        for staging in [SavedPlanStagingState.staleArtifactPresent, .presenceUnavailable] {
            let warning = PlansLibraryPresentation(
                status: .init(canonical: .available(records: [saved]), staging: staging)
            )
            XCTAssertFalse(warning.canCreate)
            XCTAssertFalse(warning.canImport)
            XCTAssertFalse(warning.canExport)
            XCTAssertNotNil(warning.stagingWarning)
            XCTAssertEqual(warning.content, .populated([PlansPlanRowPresentation(record: saved)]))
        }
    }

    func testUnsupportedStoreAndPlanVersionsRemainSpecificAndOfferNoRetry() {
        let store = PlansLibraryPresentation(
            status: .init(canonical: .unsupportedStoreVersion(7), staging: .absent)
        )
        let plan = PlansLibraryPresentation(
            status: .init(
                canonical: .unsupportedPlanVersion(recordID: UUID(), version: 9),
                staging: .absent
            )
        )

        guard case let .blocked(storeCard) = store.content,
              case let .blocked(planCard) = plan.content else {
            return XCTFail("Unsupported versions must remain blocked")
        }
        XCTAssertTrue(storeCard.detail.contains("schema v7"))
        XCTAssertTrue(planCard.detail.contains("schema v9"))
        XCTAssertNil(storeCard.retryTitle)
        XCTAssertNil(planCard.retryTitle)
        XCTAssertNotEqual(storeCard.title, planCard.title)
    }

    func testRetryIsOfferedOnlyForProtectedDataAndReadFailure() {
        let states: [(SavedPlanCanonicalState, String?)] = [
            (.protectedDataUnavailable, "Try again"),
            (.readFailure, "Retry read"),
            (.corruptData, nil),
            (.partialWriteDetected, nil),
            (.unsupportedStoreVersion(2), nil),
            (.unsupportedPlanVersion(recordID: UUID(), version: 2), nil),
        ]

        for (state, retryTitle) in states {
            let presentation = PlansLibraryPresentation(
                status: .init(canonical: state, staging: .absent)
            )
            guard case let .blocked(card) = presentation.content else {
                return XCTFail("Expected a blocked presentation")
            }
            XCTAssertEqual(card.retryTitle, retryTitle)
        }
    }

    func testDeletionConfirmationNamesPlanAndExactStepCount() {
        let confirmation = PlansDeletionPresentation(record: record(name: "Synthetic intervals"))

        XCTAssertEqual(confirmation.title, "Delete Synthetic intervals?")
        XCTAssertEqual(
            confirmation.message,
            "This permanently removes the plan and its 3 steps from this iPhone. It cannot be undone."
        )
    }

    func testEditorPresentationKeepsIdentityActivityOrderExactValuesAndProblemAssociation() {
        let draft = validDraft()
        let inputIssue = ManualWorkoutInputIssue(
            path: "steps[0].duration.value",
            message: "Enter step 1 duration as a whole number of seconds."
        )
        let validationIssue = WorkoutPlanValidationIssue(
            code: .targetOutOfRange,
            path: "steps[1].targetSpeed.value",
            message: "Synthetic exact out-of-range speed."
        )

        let presentation = ManualPlanEditorPresentation(
            draft: draft,
            editing: true,
            inputIssues: [inputIssue],
            validationIssues: [validationIssue]
        )

        XCTAssertEqual(presentation.title, "Edit plan")
        XCTAssertEqual(presentation.activity, "Indoor running")
        XCTAssertEqual(presentation.orderedStepCount, "Steps · 3 ordered")
        XCTAssertEqual(presentation.steps.map(\.id), draft.steps.map(\.id))
        XCTAssertEqual(presentation.steps.map(\.order), ["01", "02", "03"])
        XCTAssertEqual(presentation.steps.map(\.kindTitle), ["Warm-up", "Interval", "Cool-down"])
        XCTAssertEqual(presentation.steps[1].label, "Effort")
        XCTAssertEqual(presentation.steps[1].duration, "360")
        XCTAssertEqual(presentation.steps[1].speed, "10.5")
        XCTAssertEqual(presentation.steps[1].inclination, "1.0")
        XCTAssertEqual(presentation.steps[0].problemFields, [.duration])
        XCTAssertEqual(presentation.steps[1].problemFields, [.speed])
        XCTAssertEqual(presentation.issues.map(\.context), ["Step 01 · Duration", "Step 02 · Speed"])
        XCTAssertFalse(presentation.reviewActionEnabled)
        XCTAssertTrue(presentation.reviewFooter.contains("currently known capability snapshot"))
        XCTAssertTrue(presentation.reviewFooter.contains("does not save, contact or control"))
    }

    func testReviewPresentationUsesStableExactCanonicalFactsAndSeparateLabels() throws {
        let plan = try ManualWorkoutDraftParser.parse(
            validDraft(),
            locale: Locale(identifier: "en_GB")
        ).get()
        let validated = try WorkoutPlanValidator.validate(plan, against: knownCapabilities()).get()
        let preview = WorkoutPlanPreview(validatedPlan: validated)

        let create = ManualPlanReviewPresentation(
            preview: preview,
            editing: false,
            canConfirm: true,
            locale: Locale(identifier: "en_GB")
        )
        let edit = ManualPlanReviewPresentation(
            preview: preview,
            editing: true,
            canConfirm: false,
            locale: Locale(identifier: "en_GB")
        )

        XCTAssertEqual(create.name, "Synthetic progression")
        XCTAssertEqual(create.activity, "Indoor running")
        XCTAssertEqual(create.totalDuration, "18:00")
        XCTAssertEqual(create.estimatedDistance, "1.95 km")
        XCTAssertEqual(create.stepCount, "3")
        XCTAssertEqual(create.steps.map(\.order), ["01", "02", "03"])
        XCTAssertEqual(create.steps[1].title, "02 · Interval · Effort")
        XCTAssertEqual(create.steps[1].duration, "6:00")
        XCTAssertEqual(create.steps[1].exactDuration, "360 seconds")
        XCTAssertEqual(create.steps[1].speed, "10.5")
        XCTAssertEqual(create.steps[1].inclination, "1.0")
        XCTAssertEqual(create.confirmationTitle, "Confirm and save")
        XCTAssertTrue(create.confirmationEnabled)
        XCTAssertEqual(edit.confirmationTitle, "Confirm and update")
        XCTAssertFalse(edit.confirmationEnabled)
        XCTAssertTrue(create.confirmationFooter.contains("currently known capability snapshot"))
        XCTAssertFalse(create.confirmationFooter.localizedCaseInsensitiveContains(" at "))
    }

    func testCapabilityProblemPresentationsPreserveUnknownUnsupportedMalformedAndRangeCodes() {
        let issues: [WorkoutPlanValidationIssue] = [
            .init(code: .capabilityUnknown, path: "capabilities.speed", message: "Unknown"),
            .init(code: .targetUnsupported, path: "capabilities.speed", message: "Unsupported"),
            .init(code: .invalidCapabilityRange, path: "capabilities.speed", message: "Malformed"),
            .init(code: .targetOutOfRange, path: "steps[1].targetSpeed.value", message: "Out of range"),
        ]

        let presentation = ManualPlanEditorPresentation(
            draft: validDraft(),
            editing: false,
            inputIssues: [],
            validationIssues: issues
        )

        XCTAssertEqual(
            presentation.issues.map(\.kind),
            [
                .validation(.capabilityUnknown),
                .validation(.targetUnsupported),
                .validation(.invalidCapabilityRange),
                .validation(.targetOutOfRange),
            ]
        )
        XCTAssertEqual(
            presentation.issues.map(\.context),
            ["Capability snapshot", "Capability snapshot", "Capability snapshot", "Step 02 · Speed"]
        )
    }

    func testBackToEditPreservesTheExactDraftAndDoesNotMutateStorage() {
        let repository = FakeSavedPlanRepository()
        let model = PlansViewModel(repository: repository)
        model.beginCreate()
        let expected = validDraft()
        model.draft = expected
        model.validateForPreview(against: knownCapabilities(), locale: Locale(identifier: "en_GB"))
        XCTAssertNotNil(model.preview)

        model.returnToEditing()

        XCTAssertEqual(model.draft, expected)
        XCTAssertNil(model.preview)
        XCTAssertTrue(repository.records.isEmpty)
        XCTAssertEqual(repository.createCallCount, 0)
    }

    func testLocalisedManualEntryBuildsExplicitDomainUnitsAndExactPreviewTotals() throws {
        let draft = validDraft(decimalSeparator: ",")

        let plan = try ManualWorkoutDraftParser.parse(
            draft,
            locale: Locale(identifier: "de_DE")
        ).get()
        let validated = try WorkoutPlanValidator.validate(plan, against: knownCapabilities()).get()
        let preview = WorkoutPlanPreview(validatedPlan: validated)

        XCTAssertEqual(plan.activity, .indoorRunning)
        XCTAssertEqual(plan.steps.map(\.duration.unit), [.seconds, .seconds, .seconds])
        XCTAssertEqual(plan.steps.map(\.targetSpeed.unit), [.kilometresPerHour, .kilometresPerHour, .kilometresPerHour])
        XCTAssertEqual(plan.steps.map(\.targetInclination.unit), [.percent, .percent, .percent])
        XCTAssertEqual(plan.steps[1].targetSpeed.value, decimal("10.5"))
        XCTAssertEqual(preview.totalDurationSeconds, decimal("1080"))
        XCTAssertEqual(preview.estimatedDistanceKilometres, decimal("1.95"))
        XCTAssertEqual(PlanValueFormatter.localizedText(decimal("10.5"), locale: Locale(identifier: "de_DE")), "10,5")
    }

    func testMalformedManualNumbersAreActionableAndNeverReachPreviewOrRepository() {
        let repository = FakeSavedPlanRepository()
        let model = PlansViewModel(repository: repository)
        model.beginCreate()
        model.draft = validDraft()
        model.draft?.steps[0].durationSeconds = "1.5"
        model.draft?.steps[1].speedKilometresPerHour = "fast"

        model.validateForPreview(against: knownCapabilities(), locale: Locale(identifier: "en_GB"))

        XCTAssertNil(model.preview)
        XCTAssertEqual(
            model.inputIssues.map(\.path),
            ["steps[0].duration.value", "steps[1].targetSpeed.value"]
        )
        XCTAssertTrue(model.validationIssues.isEmpty)
        XCTAssertEqual(repository.createCallCount, 0)
    }

    func testGroupingOrWrongLocaleSeparatorIsRejectedRatherThanSilentlyReinterpreted() {
        var draft = validDraft(decimalSeparator: ",")
        draft.steps[0].speedKilometresPerHour = "5.0"

        let result = ManualWorkoutDraftParser.parse(
            draft,
            locale: Locale(identifier: "de_DE")
        )

        guard case let .failure(failure) = result else {
            return XCTFail("A grouping or wrong-locale separator must not be stripped")
        }
        XCTAssertEqual(failure.issues.map(\.path), ["steps[0].targetSpeed.value"])
    }

    func testAddingAfterCoolDownInsertsRecoveryBeforeTheFinalStep() {
        let repository = FakeSavedPlanRepository()
        let model = PlansViewModel(repository: repository)
        model.beginCreate()
        model.addStep()
        model.addStep()
        model.addStep()
        model.addStep()

        XCTAssertEqual(model.draft?.steps.map(\.kind), [.warmUp, .interval, .recovery, .coolDown])
    }

    func testValidCreateRequiresPreviewThenSeparateConfirmation() throws {
        let repository = FakeSavedPlanRepository()
        let model = PlansViewModel(repository: repository)
        model.beginCreate()
        model.draft = validDraft()

        model.validateForPreview(against: knownCapabilities(), locale: Locale(identifier: "en_GB"))

        XCTAssertNotNil(model.preview)
        XCTAssertEqual(repository.createCallCount, 0)
        XCTAssertEqual(repository.records.count, 0)

        model.confirmSave()

        XCTAssertEqual(repository.createCallCount, 1)
        XCTAssertEqual(repository.records.map(\.plan.suggestedName), ["Synthetic progression"])
        XCTAssertNil(model.draft)
        XCTAssertEqual(model.records, repository.records)
    }

    func testCancellationFromPreviewNeverSaves() {
        let repository = FakeSavedPlanRepository()
        let model = PlansViewModel(repository: repository)
        model.beginCreate()
        model.draft = validDraft()
        model.validateForPreview(against: knownCapabilities(), locale: Locale(identifier: "en_GB"))
        XCTAssertNotNil(model.preview)

        model.cancelEditor()

        XCTAssertEqual(repository.createCallCount, 0)
        XCTAssertTrue(repository.records.isEmpty)
        XCTAssertNil(model.draft)
        XCTAssertNil(model.preview)
    }

    func testCapabilityUnknownBlocksPreviewWithoutBecomingUnsupported() {
        assertBlocked(
            capabilities: .init(speed: .unknown, inclination: knownCapabilities().inclination),
            expectedCodes: [.capabilityUnknown]
        )
    }

    func testUnsupportedTargetBlocksPreviewWithoutBecomingUnknown() {
        assertBlocked(
            capabilities: .init(speed: knownCapabilities().speed, inclination: .unsupported),
            expectedCodes: [.targetUnsupported]
        )
    }

    func testMalformedCapabilityRangeBlocksPreviewAsInvalidRange() {
        let invalid = WorkoutSpeedRange(
            minimum: speed("12"),
            maximum: speed("4"),
            increment: speed("0.1")
        )
        assertBlocked(
            capabilities: .init(speed: .supported(invalid), inclination: knownCapabilities().inclination),
            expectedCodes: [.invalidCapabilityRange]
        )
    }

    func testInvalidPlanValuesAreReportedWithoutChangingEnteredTargets() {
        let repository = FakeSavedPlanRepository()
        let model = PlansViewModel(repository: repository)
        model.beginCreate()
        model.draft = validDraft()
        model.draft?.steps[1].speedKilometresPerHour = "20.1"
        model.draft?.steps[1].inclinationPercent = "1.2"

        model.validateForPreview(against: knownCapabilities(), locale: Locale(identifier: "en_GB"))

        XCTAssertNil(model.preview)
        XCTAssertEqual(model.validationIssues.map(\.code), [.targetOutOfRange, .targetNotIncrementAligned])
        XCTAssertEqual(model.draft?.steps[1].speedKilometresPerHour, "20.1")
        XCTAssertEqual(model.draft?.steps[1].inclinationPercent, "1.2")
        XCTAssertEqual(repository.createCallCount, 0)
    }

    func testSaveFailureLeavesPreviewVisibleAndStoredDataUnchanged() {
        let repository = FakeSavedPlanRepository()
        repository.createFailure = .writeFailed(.atomicReplacement)
        let model = PlansViewModel(repository: repository)
        model.beginCreate()
        model.draft = validDraft()
        model.validateForPreview(against: knownCapabilities(), locale: Locale(identifier: "en_GB"))

        model.confirmSave()

        XCTAssertNotNil(model.preview)
        XCTAssertTrue(model.saveError?.contains("atomic replacement") == true)
        XCTAssertTrue(repository.records.isEmpty)
    }

    func testEditUsesSamePreviewAndConfirmationAndPreservesIdentity() throws {
        let original = record(name: "Synthetic original")
        let repository = FakeSavedPlanRepository(records: [original])
        let model = PlansViewModel(repository: repository)
        model.beginEdit(original)
        model.draft?.suggestedName = "Synthetic revised"

        model.validateForPreview(against: knownCapabilities(), locale: Locale(identifier: "en_GB"))

        XCTAssertNotNil(model.preview)
        XCTAssertEqual(repository.replaceCallCount, 0)
        model.confirmSave()

        let replacement = try XCTUnwrap(repository.records.first)
        XCTAssertEqual(replacement.id, original.id)
        XCTAssertEqual(replacement.createdAt, original.createdAt)
        XCTAssertEqual(replacement.plan.suggestedName, "Synthetic revised")
        XCTAssertEqual(repository.replaceCallCount, 1)
    }

    func testEditFailureLeavesOriginalRecordAndPreviewUnchanged() {
        let original = record(name: "Synthetic original")
        let repository = FakeSavedPlanRepository(records: [original])
        repository.replaceFailure = .recordNotFound(original.id)
        let model = PlansViewModel(repository: repository)
        model.beginEdit(original)
        model.draft?.suggestedName = "Synthetic revised"
        model.validateForPreview(against: knownCapabilities(), locale: Locale(identifier: "en_GB"))

        model.confirmSave()

        XCTAssertEqual(repository.records, [original])
        XCTAssertNotNil(model.preview)
        XCTAssertTrue(model.saveError?.contains("no longer available") == true)
    }

    func testRepositoryFailureStatesRemainDistinctAndDisableMutation() {
        let states: [SavedPlanCanonicalState] = [
            .protectedDataUnavailable,
            .readFailure,
            .corruptData,
            .partialWriteDetected,
            .unsupportedStoreVersion(2),
            .unsupportedPlanVersion(recordID: UUID(), version: 2),
        ]

        for state in states {
            let repository = FakeSavedPlanRepository(canonical: state)
            let model = PlansViewModel(repository: repository)
            XCTAssertEqual(model.repositoryStatus.canonical, state)
            XCTAssertFalse(model.canMutate)
            model.beginCreate()
            XCTAssertNil(model.draft)
        }
    }

    func testStaleStagingKeepsCanonicalListReadableButDisablesMutation() {
        let original = record(name: "Synthetic readable")
        let repository = FakeSavedPlanRepository(
            records: [original],
            staging: .staleArtifactPresent
        )
        let model = PlansViewModel(repository: repository)

        XCTAssertEqual(model.records, [original])
        XCTAssertFalse(model.canMutate)
    }

    func testSavedPlanDeletionRequiresConfirmationAndCancellationDoesNotMutate() {
        let original = record(name: "Synthetic original")
        let repository = FakeSavedPlanRepository(records: [original])
        let model = PlansViewModel(repository: repository)

        model.requestDeletion(of: original)

        XCTAssertEqual(model.pendingDeletion, original)
        XCTAssertEqual(repository.deleteCallIDs, [])

        model.cancelDeletion()

        XCTAssertNil(model.pendingDeletion)
        XCTAssertEqual(repository.deleteCallIDs, [])
        XCTAssertEqual(repository.records, [original])
        XCTAssertEqual(model.records, [original])
    }

    func testConfirmedDeletionUsesBoundIdentityAfterListReordering() {
        let first = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            name: "Synthetic first"
        )
        let second = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            name: "Synthetic second"
        )
        let repository = FakeSavedPlanRepository(records: [first, second])
        let model = PlansViewModel(repository: repository)
        model.requestDeletion(of: first)
        repository.records = [second, first]
        model.reload()

        model.confirmDeletion()

        XCTAssertEqual(repository.deleteCallIDs, [first.id])
        XCTAssertEqual(repository.records, [second])
        XCTAssertEqual(model.records, [second])
        XCTAssertNil(model.pendingDeletion)
        XCTAssertNil(model.deletionError)
    }

    func testDeletionFailurePreservesDisplayedRecordsAndReportsNoConfirmation() {
        let original = record(name: "Synthetic original")
        let repository = FakeSavedPlanRepository(records: [original])
        repository.deleteFailure = .writeFailed(.atomicReplacement)
        let model = PlansViewModel(repository: repository)
        model.requestDeletion(of: original)

        model.confirmDeletion()

        XCTAssertEqual(repository.deleteCallIDs, [original.id])
        XCTAssertEqual(repository.records, [original])
        XCTAssertEqual(model.records, [original])
        XCTAssertEqual(
            model.libraryPresentation.content,
            .populated([PlansPlanRowPresentation(record: original)])
        )
        XCTAssertTrue(model.deletionError?.contains("Deletion was not confirmed") == true)
        XCTAssertTrue(model.deletionError?.contains("atomic replacement") == true)
    }

    func testBlockedStorageCannotOpenOrConfirmDeletion() {
        let original = record(name: "Synthetic readable")
        let repository = FakeSavedPlanRepository(
            records: [original],
            staging: .staleArtifactPresent
        )
        let model = PlansViewModel(repository: repository)

        model.requestDeletion(of: original)
        model.confirmDeletion()

        XCTAssertNil(model.pendingDeletion)
        XCTAssertEqual(repository.deleteCallIDs, [])
        XCTAssertEqual(repository.records, [original])
    }

    private func assertBlocked(
        capabilities: WorkoutPlanCapabilities,
        expectedCodes: [WorkoutPlanValidationIssue.Code]
    ) {
        let repository = FakeSavedPlanRepository()
        let model = PlansViewModel(repository: repository)
        model.beginCreate()
        model.draft = validDraft()

        model.validateForPreview(against: capabilities, locale: Locale(identifier: "en_GB"))

        XCTAssertNil(model.preview)
        XCTAssertEqual(model.validationIssues.map(\.code), expectedCodes)
        XCTAssertEqual(repository.createCallCount, 0)
    }

    private func validDraft(decimalSeparator: Character = ".") -> ManualWorkoutDraft {
        func value(_ text: String) -> String {
            text.replacingOccurrences(of: ".", with: String(decimalSeparator))
        }
        return ManualWorkoutDraft(
            suggestedName: "Synthetic progression",
            activity: .indoorRunning,
            steps: [
                .init(kind: .warmUp, label: "Prepare", durationSeconds: "360", speedKilometresPerHour: value("5.0"), inclinationPercent: value("0.0")),
                .init(kind: .interval, label: "Effort", durationSeconds: "360", speedKilometresPerHour: value("10.5"), inclinationPercent: value("1.0")),
                .init(kind: .coolDown, label: "Settle", durationSeconds: "360", speedKilometresPerHour: value("4.0"), inclinationPercent: value("0.0")),
            ]
        )
    }

    private func knownCapabilities() -> WorkoutPlanCapabilities {
        WorkoutPlanCapabilities(
            speed: .supported(
                WorkoutSpeedRange(
                    minimum: speed("0.5"),
                    maximum: speed("20"),
                    increment: speed("0.1")
                )
            ),
            inclination: .supported(
                WorkoutInclinationRange(
                    minimum: inclination("-3"),
                    maximum: inclination("15"),
                    increment: inclination("0.5")
                )
            )
        )
    }

    private func record(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
        name: String
    ) -> SavedPlanRecord {
        let plan = try! ManualWorkoutDraftParser.parse(validDraft(), locale: Locale(identifier: "en_GB")).get()
        return SavedPlanRecord(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            plan: WorkoutPlan(
                schemaVersion: plan.schemaVersion,
                suggestedName: name,
                activity: plan.activity,
                steps: plan.steps
            )
        )
    }

    private func speed(_ value: String) -> WorkoutSpeed {
        .init(value: decimal(value), unit: .kilometresPerHour)
    }

    private func inclination(_ value: String) -> WorkoutInclination {
        .init(value: decimal(value), unit: .percent)
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}

private final class FakeSavedPlanRepository: SavedPlanRepositoryProtocol {
    var records: [SavedPlanRecord]
    var canonicalOverride: SavedPlanCanonicalState?
    var staging: SavedPlanStagingState
    var createFailure: SavedPlanMutationFailure?
    var replaceFailure: SavedPlanMutationFailure?
    var deleteFailure: SavedPlanMutationFailure?
    private(set) var createCallCount = 0
    private(set) var replaceCallCount = 0
    private(set) var deleteCallIDs: [UUID] = []

    init(
        records: [SavedPlanRecord] = [],
        canonical: SavedPlanCanonicalState? = nil,
        staging: SavedPlanStagingState = .absent
    ) {
        self.records = records
        canonicalOverride = canonical
        self.staging = staging
    }

    func list() -> SavedPlanRepositoryStatus {
        .init(
            canonical: canonicalOverride ?? (records.isEmpty ? .empty : .available(records: records)),
            staging: staging
        )
    }

    func create(_ validatedPlan: WorkoutPlanValidator.ValidatedPlan) throws -> SavedPlanRecord {
        createCallCount += 1
        if let createFailure { throw createFailure }
        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
        let record = SavedPlanRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            createdAt: timestamp,
            modifiedAt: timestamp,
            plan: validatedPlan.plan
        )
        records.append(record)
        return record
    }

    func replace(
        id: UUID,
        with validatedPlan: WorkoutPlanValidator.ValidatedPlan
    ) throws -> SavedPlanRecord {
        replaceCallCount += 1
        if let replaceFailure { throw replaceFailure }
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw SavedPlanMutationFailure.recordNotFound(id)
        }
        let original = records[index]
        let replacement = SavedPlanRecord(
            id: original.id,
            createdAt: original.createdAt,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_200),
            plan: validatedPlan.plan
        )
        records[index] = replacement
        return replacement
    }

    func delete(id: UUID) throws {
        deleteCallIDs.append(id)
        if let deleteFailure { throw deleteFailure }
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw SavedPlanMutationFailure.recordNotFound(id)
        }
        records.remove(at: index)
    }
}
