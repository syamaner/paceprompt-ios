import Foundation
import XCTest
@testable import PacePrompt

@MainActor
final class PlansPresentationTests: XCTestCase {
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

    private func record(name: String) -> SavedPlanRecord {
        let plan = try! ManualWorkoutDraftParser.parse(validDraft(), locale: Locale(identifier: "en_GB")).get()
        return SavedPlanRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
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
    private(set) var createCallCount = 0
    private(set) var replaceCallCount = 0

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
}
