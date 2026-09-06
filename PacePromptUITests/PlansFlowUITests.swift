import XCTest

final class PlansFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
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
        XCTAssertTrue(app.staticTexts["Synthetic imported plan"].waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.staticTexts["Complete plan"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["1. Warm-up: Prepare"].exists)
        XCTAssertTrue(findByScrolling(app.staticTexts["Duration, 1260 seconds"]))
        XCTAssertTrue(findByScrolling(app.staticTexts["Estimated distance, 2.2 km"]))
        XCTAssertTrue(findByScrolling(app.staticTexts["4. Cool-down: Settle"]))

        tapWhenVisible(app.buttons["plan.confirm-save"])

        XCTAssertTrue(app.staticTexts["Synthetic progression revised"].waitForExistence(timeout: 2))
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

    func testCancellationFromPreviewLeavesStorageEmpty() {
        launch(capabilities: "known", draft: "valid")
        openCreate()
        reviewPlan()

        app.buttons["plan.cancel"].tap()

        XCTAssertTrue(app.staticTexts["No saved plans"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Synthetic progression"].exists)
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
        XCTAssertTrue(app.staticTexts["Synthetic progression"].waitForExistence(timeout: 2))
    }

    func testRepositoryFailuresAreNotShownAsEmptyAndDisableMutation() {
        assertRepositoryBlocked(repository: "protected", title: "Plans are locked")
        assertRepositoryBlocked(repository: "corrupt", title: "Saved plans are corrupt")
        assertRepositoryBlocked(repository: "unsupported", title: "Saved-plan version is unsupported")
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

    private func assertRepositoryBlocked(repository: String, title: String) {
        app?.terminate()
        launch(capabilities: "known", draft: "valid", repository: repository)

        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["No saved plans"].exists)
        XCTAssertFalse(app.buttons["plans.new"].isEnabled)
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
            XCTAssertTrue(app.staticTexts["Complete plan"].waitForExistence(timeout: 2))
        }
    }

    private func tapWhenVisible(_ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        element.tap()
    }

    private func findByScrolling(_ element: XCUIElement) -> Bool {
        for _ in 0..<8 {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 2)
    }
}
