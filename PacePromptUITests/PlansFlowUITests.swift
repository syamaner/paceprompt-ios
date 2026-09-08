import XCTest

final class PlansFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testPopulatedLibraryShowsCanonicalRowAndToolbarActions() {
        launch(capabilities: "known", draft: "valid", repository: "populated")

        XCTAssertTrue(app.navigationBars["Plans"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["plans.import"].isEnabled)
        XCTAssertTrue(app.buttons["plans.export"].isEnabled)
        XCTAssertTrue(app.buttons["plans.new"].isEnabled)

        let row = app.buttons["plans.record.00000000-0000-0000-0000-000000000010"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertEqual(row.label, "Synthetic progression")
        XCTAssertEqual(row.value as? String, "Indoor running, 4 steps, 21:00")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "km")).firstMatch.exists)
    }

    func testEmptyLibraryShowsDesignAlignedActionsAndDisabledExport() {
        launch(capabilities: "known", draft: "valid")

        XCTAssertTrue(app.staticTexts["No plans yet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "review every exact target")).firstMatch.exists)
        XCTAssertTrue(app.buttons["plans.create-empty"].isEnabled)
        XCTAssertTrue(app.buttons["plans.import-empty"].isEnabled)
        XCTAssertFalse(app.buttons["plans.export"].isEnabled)
    }

    func testEveryBlockedAndWarningRepositoryStateRemainsDistinct() {
        assertRepositoryBlocked(repository: "protected", title: "Plans are locked", retry: true)
        assertRepositoryBlocked(repository: "read-failure", title: "Could not read plans", retry: true)
        assertRepositoryBlocked(repository: "corrupt", title: "Saved plans are corrupt")
        assertRepositoryBlocked(repository: "partial-write", title: "Last save finished partially")
        assertRepositoryBlocked(repository: "unsupported-store", title: "Saved by a newer version")
        assertRepositoryBlocked(repository: "unsupported-plan", title: "A plan uses a newer version")

        for scenario in ["stale-staging", "staging-unavailable"] {
            app?.terminate()
            launch(capabilities: "known", draft: "valid", repository: scenario)
            XCTAssertTrue(app.otherElements["plans.staging-warning"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.buttons["plans.record.00000000-0000-0000-0000-000000000010"].exists)
            XCTAssertFalse(app.buttons["plans.new"].isEnabled)
            XCTAssertFalse(app.buttons["plans.import"].isEnabled)
            XCTAssertFalse(app.buttons["plans.export"].isEnabled)
            XCTAssertFalse(app.staticTexts["No plans yet"].exists)
        }
    }

    func testPopulatedRowStillOpensExistingEditor() {
        launch(capabilities: "known", draft: "valid", repository: "populated")
        app.buttons["plans.record.00000000-0000-0000-0000-000000000010"].tap()

        XCTAssertTrue(app.navigationBars["Edit plan"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields["plan.name"].value as? String, "Synthetic progression")
        XCTAssertTrue(app.buttons["plan.cancel"].exists)
        XCTAssertTrue(app.buttons["plan.reorder"].exists)
        XCTAssertEqual(app.textFields["plan.step.0.duration"].value as? String, "360 s")
    }

    func testNewPlanHierarchyActivityAndExactFieldEditing() {
        launch(capabilities: "known", draft: "valid")
        openCreate()

        XCTAssertTrue(app.navigationBars["New plan"].exists)
        XCTAssertTrue(app.buttons["plan.cancel"].exists)
        XCTAssertTrue(app.buttons["Indoor running"].isSelected)
        app.buttons["Indoor walking"].tap()
        XCTAssertTrue(app.buttons["Indoor walking"].isSelected)

        let speed = app.textFields["plan.step.0.speed"]
        XCTAssertTrue(findByScrolling(speed))
        XCTAssertEqual(speed.value as? String, "5.0 km/h")
        replaceText(in: speed, with: "5.5")
        XCTAssertEqual(speed.value as? String, "5.5 km/h")

        let inclination = app.textFields["plan.step.0.inclination"]
        XCTAssertEqual(inclination.value as? String, "0.0 %")
        XCTAssertTrue(element("plan.step.0.card").exists)
    }

    func testAddDeleteAndReorderControlsKeepOrderedCardsExplicit() {
        launch(capabilities: "known", draft: "valid")
        openCreate()

        app.buttons["plan.reorder"].tap()
        let moveDown = app.buttons["plan.step.1.move-down"]
        XCTAssertTrue(findByScrolling(moveDown))
        moveDown.tap()
        XCTAssertTrue(element("plan.step.1.card").waitForExistence(timeout: 2))
        XCTAssertTrue((element("plan.step.1.card").value as? String)?.contains("Recovery") == true)

        let delete = app.buttons["plan.step.1.delete"]
        XCTAssertTrue(delete.exists)
        delete.tap()
        XCTAssertTrue(app.staticTexts["Steps · 3 ordered"].waitForExistence(timeout: 2))

        tapWhenVisible(app.buttons["plan.add-step"])
        XCTAssertTrue(app.staticTexts["Steps · 4 ordered"].waitForExistence(timeout: 2))
        XCTAssertTrue(findByScrolling(app.textFields["plan.step.3.inclination"]))
    }

    func testLongPlanScrollsThroughEveryOrderedStepIntoExactReview() {
        launch(capabilities: "known", draft: "long")
        openCreate()

        XCTAssertTrue(app.staticTexts["Steps · 18 ordered"].exists)
        XCTAssertTrue(findByScrolling(element("plan.step.17.card"), attempts: 30))
        XCTAssertTrue(app.textFields["plan.step.17.duration"].exists)
        tapWhenVisible(app.buttons["plan.review"], attempts: 30)

        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 2))
        XCTAssertTrue(findByScrolling(element("plan.review.step.17"), attempts: 30))
        XCTAssertTrue((element("plan.review.step.17").value as? String)?.contains("300 seconds") == true)
    }

    func testImportDisclosureCancellationThenExactPreviewAndSeparateSave() {
        launch(capabilities: "known", draft: "valid")
        app.tabBars.buttons["Plans"].tap()
        app.buttons["plans.import"].tap()
        let editor = app.textViews["import.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap(); editor.typeText("Synthetic treadmill workout")
        tapWhenVisible(app.buttons["import.disclosure"])
        XCTAssertTrue(app.navigationBars["Remote-send disclosure"].waitForExistence(timeout: 3))
        app.navigationBars["Remote-send disclosure"].buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["plan.confirm-save"].exists)
        XCTAssertEqual(editor.value as? String, "")
        editor.tap(); editor.typeText("Synthetic treadmill workout")
        tapWhenVisible(app.buttons["import.disclosure"])
        tapWhenVisible(app.buttons["import.consent"])
        XCTAssertTrue(app.staticTexts["Complete plan"].waitForExistence(timeout: 3))
        XCTAssertTrue(findByScrolling(app.staticTexts["3. Cool-down: Synthetic coolDown"]))
        tapWhenVisible(app.buttons["plan.confirm-save"])
        XCTAssertTrue(app.buttons["plans.record.00000000-0000-0000-0000-000000000011"].waitForExistence(timeout: 3))
    }

    func testImportedProposalWithUnknownCapabilitiesCannotPreviewOrSave() {
        launch(capabilities: "unknown", draft: "valid")
        app.tabBars.buttons["Plans"].tap(); app.buttons["plans.import"].tap()
        let editor = app.textViews["import.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap(); editor.typeText("Synthetic treadmill workout")
        tapWhenVisible(app.buttons["import.disclosure"])
        tapWhenVisible(app.buttons["import.consent"])
        XCTAssertTrue(app.staticTexts["Local validation"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["plan.confirm-save"].exists)
        XCTAssertEqual(editor.value as? String, "")
    }

    func testValidManualPlanPreviewsExactlyAndSavesOnlyAfterConfirmation() {
        launch(capabilities: "known", draft: "valid")
        openCreate()

        let name = app.textFields["plan.name"]
        XCTAssertEqual(name.value as? String, "Synthetic progression")
        name.tap()
        name.typeText(" revised")
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
        XCTAssertEqual(name.value as? String, "Synthetic progression revised")
        reviewPlan()
        XCTAssertTrue(app.staticTexts["Synthetic progression revised"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["01 · Warm-up · Prepare"].exists)
        XCTAssertTrue(app.staticTexts["21:00"].exists)
        XCTAssertTrue(app.staticTexts["2.2 km"].exists)
        XCTAssertTrue(findByScrolling(element("plan.review.step.3")))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "currently known capability snapshot")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "capability read at")).firstMatch.exists)

        tapWhenVisible(app.buttons["plan.confirm-save"])

        XCTAssertTrue(app.buttons["plans.record.00000000-0000-0000-0000-000000000011"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["plan.confirm-save"].exists)
    }

    func testEveryValidationClassBlocksPreviewWithDistinctGuidance() {
        assertValidationBlocked(
            capabilities: "unknown",
            draft: "valid",
            message: "Speed capability is unknown. Read the treadmill's speed target feature and range before validating this plan."
        )
        assertValidationBlocked(
            capabilities: "unsupported",
            draft: "valid",
            message: "This treadmill reports speed target-setting as unsupported, so the plan cannot be executed."
        )
        assertValidationBlocked(
            capabilities: "malformed",
            draft: "valid",
            message: "The reported speed capability range is invalid. Re-read a finite minimum, maximum and positive increment in km/h."
        )
        assertValidationBlocked(
            capabilities: "known",
            draft: "invalid",
            message: "Step 2 speed is 20.1 km/h. Enter a value from 0.5 to 20 km/h."
        )
    }

    func testValidationGuidanceIsGroupedAssociatedAndBlocksPreviewUntilEdited() {
        launch(capabilities: "known", draft: "invalid")
        openCreate()
        reviewPlan(expectPreview: false)

        XCTAssertTrue(element("plan.validation-errors").waitForExistence(timeout: 2))
        XCTAssertTrue(findByScrolling(element("plan.validation.issue.0")))
        XCTAssertTrue(element("plan.validation.issue.0").label.contains("Step 02 · Speed"))
        XCTAssertTrue(findByScrolling(element("plan.validation.issue.1")))
        XCTAssertTrue(element("plan.validation.issue.1").label.contains("Step 02 · Inclination"))
        XCTAssertTrue(findByScrolling(app.staticTexts["Needs attention: speed, inclination"]))
        let review = app.buttons["plan.review"]
        XCTAssertTrue(findByScrolling(review))
        XCTAssertFalse(review.isEnabled)
        XCTAssertFalse(app.buttons["plan.confirm-save"].exists)
    }

    func testBackToEditPreservesDraftAndEditUsesSeparateUpdateConfirmation() {
        launch(capabilities: "known", draft: "valid", repository: "populated")
        app.buttons["plans.record.00000000-0000-0000-0000-000000000010"].tap()
        let name = app.textFields["plan.name"]
        name.tap()
        name.typeText(" revised")
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
        XCTAssertEqual(name.value as? String, "Synthetic progression revised")
        reviewPlan()

        XCTAssertTrue(app.buttons["plan.confirm-save"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons["plan.confirm-save"].label, "Confirm and update")
        app.buttons["plan.back-to-edit"].tap()

        XCTAssertTrue(app.navigationBars["Edit plan"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields["plan.name"].value as? String, "Synthetic progression revised")
        XCTAssertFalse(app.buttons["plan.confirm-save"].exists)
    }

    func testCancellationFromPreviewLeavesStorageEmpty() {
        launch(capabilities: "known", draft: "valid")
        openCreate()
        reviewPlan()

        app.buttons["plan.cancel"].tap()

        XCTAssertTrue(app.staticTexts["No plans yet"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", "Synthetic progression")).firstMatch.exists)
    }

    func testSaveFailureStaysInPreviewAndReportsPreservedStorage() {
        launch(capabilities: "known", draft: "valid", repository: "save-failure")
        openCreate()
        reviewPlan()

        tapWhenVisible(app.buttons["plan.confirm-save"])

        XCTAssertTrue(app.staticTexts["Save failed"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Existing plans were left unchanged")).firstMatch.exists)
        XCTAssertTrue(findByScrolling(app.buttons["plan.confirm-save"]))
    }

    func testEditFailureUsesPreviewAndLeavesOriginalRecordAvailable() {
        launch(capabilities: "known", draft: "valid", repository: "edit-failure")
        let row = app.buttons["plans.record.00000000-0000-0000-0000-000000000010"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.tap()
        reviewPlan()

        tapWhenVisible(app.buttons["plan.confirm-save"])

        XCTAssertTrue(app.staticTexts["Save failed"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "no longer available to edit")).firstMatch.exists)
        app.buttons["plan.cancel"].tap()
        XCTAssertTrue(app.buttons["plans.record.00000000-0000-0000-0000-000000000010"].waitForExistence(timeout: 2))
    }

    func testSavedPlanDeletionNamesRecordCancelsThenDeletesOnlyAfterConfirmation() {
        launch(capabilities: "known", draft: "valid", repository: "delete")
        let identifier = "00000000-0000-0000-0000-000000000010"
        let row = app.buttons["plans.record.\(identifier)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))

        row.swipeLeft()
        app.buttons["plans.delete.\(identifier)"].tap()
        XCTAssertTrue(app.staticTexts["Delete Synthetic progression?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["This permanently removes the plan and its 4 steps from this iPhone. It cannot be undone."].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 2))

        row.swipeLeft()
        app.buttons["plans.delete.\(identifier)"].tap()
        XCTAssertTrue(app.staticTexts["Delete Synthetic progression?"].waitForExistence(timeout: 2))
        app.buttons["Delete plan"].tap()

        XCTAssertTrue(app.staticTexts["No plans yet"].waitForExistence(timeout: 2))
        XCTAssertFalse(row.exists)
    }

    func testSavedPlanExportRequiresSelectionAndExactPreviewBeforeShare() {
        launch(capabilities: "known", draft: "valid", repository: "export")

        let exportButton = app.buttons["plans.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 2))
        exportButton.tap()

        let reviewButton = app.buttons["export.review"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 2))
        XCTAssertFalse(reviewButton.isEnabled)
        app.buttons["export.select.00000000-0000-0000-0000-000000000010"].tap()
        XCTAssertTrue(reviewButton.isEnabled)
        reviewButton.tap()

        XCTAssertTrue(app.staticTexts["Exact export"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "PacePrompt-saved-plans.json")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "savedPlans")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Records, 1")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["savedPlans[].plan.schemaVersion"].exists)
        XCTAssertTrue(
            findByScrolling(app.staticTexts["savedPlans[].plan.steps[].targetInclination.unit"])
        )
        XCTAssertTrue(app.buttons["export.share"].exists)

        app.buttons["export.cancel"].tap()
        XCTAssertTrue(app.buttons["plans.record.00000000-0000-0000-0000-000000000010"].waitForExistence(timeout: 2))
    }

    private func assertValidationBlocked(capabilities: String, draft: String, message: String) {
        app?.terminate()
        launch(capabilities: capabilities, draft: draft)
        openCreate()
        reviewPlan(expectPreview: false)

        let error = app.staticTexts[message]
        XCTAssertTrue(findByScrolling(error), "Missing validation message for \(capabilities)/\(draft)")
        XCTAssertFalse(app.buttons["plan.confirm-save"].exists)
    }

    private func assertRepositoryBlocked(repository: String, title: String, retry: Bool = false) {
        app?.terminate()
        launch(capabilities: "known", draft: "valid", repository: repository)

        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["No plans yet"].exists)
        XCTAssertFalse(app.buttons["plans.new"].isEnabled)
        XCTAssertFalse(app.buttons["plans.import"].isEnabled)
        XCTAssertFalse(app.buttons["plans.export"].isEnabled)
        XCTAssertEqual(app.buttons["plans.retry"].exists, retry)
    }

    private func launch(capabilities: String, draft: String, repository: String = "empty") {
        app = XCUIApplication()
        app.launchArguments = ["--paceprompt-ui-testing"]
        app.launchEnvironment = [
            "PACEPROMPT_UI_CAPABILITIES": capabilities,
            "PACEPROMPT_UI_DRAFT": draft,
            "PACEPROMPT_UI_REPOSITORY": repository,
        ]
        app.launch()
        app.tabBars.buttons["Plans"].tap()
    }

    private func openCreate() {
        let button = app.buttons["plans.create-empty"]
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        button.tap()
        XCTAssertTrue(app.textFields["plan.name"].waitForExistence(timeout: 2))
    }

    private func reviewPlan(expectPreview: Bool = true) {
        tapWhenVisible(app.buttons["plan.review"])
        if expectPreview {
            XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 2))
        }
    }

    private func tapWhenVisible(_ element: XCUIElement, attempts: Int = 8) {
        for _ in 0..<attempts where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        element.tap()
    }

    private func findByScrolling(_ element: XCUIElement, attempts: Int = 8) -> Bool {
        for _ in 0..<attempts {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 2)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        field.tap()
        field.press(forDuration: 1)
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 2))
        selectAll.tap()
        field.typeText(value)
    }
}
