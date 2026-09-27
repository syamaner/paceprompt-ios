import XCTest

final class PlanningProfileFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func tearDown() { app?.terminate(); app = nil; super.tearDown() }
    private func launch(_ scenario: String, large: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--paceprompt-home-ui-testing", "--paceprompt-profile-ui-testing"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIAccessibilityReduceMotionEnabled", "YES"] }
        app.launchEnvironment = ["PACEPROMPT_HOME_SCENARIO": "idle", "PACEPROMPT_PROFILE_SCENARIO": scenario]
        app.launch()
        app.buttons["home.setup"].tap()
    }
    private func manage() {
        let link = app.buttons["profiles.manage"]
        if !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 3)); link.tap()
        XCTAssertTrue(app.navigationBars["Saved treadmills"].waitForExistence(timeout: 3))
    }
    func testEmptyCollectionAndNeutralNoSelection() {
        launch("empty"); manage()
        XCTAssertTrue(app.staticTexts["No saved treadmill profiles"].exists)
        XCTAssertTrue(app.staticTexts["No treadmill selected"].exists)
    }
    func testDetailRenameCancelSaveAndConfirmedSelectedDeletion() {
        launch("populated"); manage()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profiles.record.")).firstMatch
        XCTAssertTrue(row.exists); row.tap()
        app.buttons["profiles.rename"].tap()
        let field = app.textFields["profiles.name"]
        XCTAssertTrue(field.exists)
        app.buttons["Cancel rename"].tap()
        XCTAssertFalse(field.exists)
        app.buttons["profiles.rename"].tap()
        field.tap()
        field.typeText(" edited")
        app.buttons["profiles.rename.save"].tap()
        XCTAssertFalse(field.exists)
        app.swipeUp()
        app.buttons["profiles.delete"].tap()
        XCTAssertTrue(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Plans and history are unaffected")).firstMatch.exists)
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["profiles.delete"].exists)
        app.buttons["profiles.delete"].tap()
        app.alerts.buttons["Delete profile"].tap()
        XCTAssertTrue(app.navigationBars["Saved treadmills"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No treadmill selected"].exists)
    }
    func testCreatedProfileUsesPersistedSelection() {
        launch("created")
        XCTAssertTrue(app.staticTexts["Treadmill profile saved"].waitForExistence(timeout: 3))
        app.buttons["Use for planning"].tap()
        manage()
        XCTAssertTrue(app.staticTexts["profiles.selection"].exists)
        XCTAssertEqual(app.staticTexts["profiles.selection"].label, "Treadmill 1")
    }
    func testChangedReviewKeepAndUpdate() {
        launch("changed")
        XCTAssertTrue(app.staticTexts["Treadmill capabilities changed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Speed changed")).firstMatch.exists)
        if !app.buttons["Keep saved profile"].exists || !app.buttons["Keep saved profile"].isHittable { app.swipeUp() }
        app.buttons["Keep saved profile"].tap()
        manage()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profiles.record.")).firstMatch.label.contains("18.00"))
        app.terminate()
        launch("changed")
        if !app.buttons["Update profile"].isHittable { app.swipeUp() }
        app.buttons["Update profile"].tap()
        manage()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profiles.record.")).firstMatch.label.contains("20.00"))
    }
    func testLargeTextReducedMotionKeepsLongNameOperable() {
        launch("populated", large: true); manage()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profiles.record.")).firstMatch
        for _ in 0..<5 where !row.exists || !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.exists)
        row.tap()
        XCTAssertTrue(app.buttons["profiles.rename"].exists)
    }
    private func launchAuthoring(_ scenario: String, large: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--paceprompt-home-ui-testing", "--paceprompt-profile-ui-testing", "--paceprompt-ui-testing", "--paceprompt-import-ui-testing"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIAccessibilityReduceMotionEnabled", "YES"] }
        app.launchEnvironment = ["PACEPROMPT_HOME_SCENARIO": "idle", "PACEPROMPT_PROFILE_SCENARIO": scenario, "PACEPROMPT_UI_DRAFT": "valid", "PACEPROMPT_UI_CAPABILITIES": "unknown"]
        app.launch(); app.tabBars.buttons["Plans"].tap()
    }
    private var activeSelector: XCUIElement {
        let query = app.buttons.matching(identifier: "planning.selector")
        return query.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? query.firstMatch
    }
    private func tapAuthoring(_ element: XCUIElement) {
        for _ in 0..<24 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable); element.tap()
    }
    func testSharedSelectorDoneCancelAndManualDraftRetention() {
        launchAuthoring("populated")
        let selector = activeSelector
        XCTAssertTrue(selector.label.contains("Synthetic treadmill"))
        selector.tap(); app.buttons["planning.picker.none"].tap()
        app.navigationBars["Treadmill profile"].buttons["Cancel"].tap()
        XCTAssertTrue(selector.label.contains("Synthetic treadmill"))
        app.buttons["plans.new"].tap()
        let name = app.textFields["plan.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        let original = name.value as? String
        activeSelector.tap(); app.buttons["planning.picker.none"].tap(); app.buttons["planning.picker.done"].tap()
        XCTAssertEqual(name.value as? String, original)
        XCTAssertTrue(activeSelector.label.contains("No treadmill selected"))
        tapAuthoring(app.buttons["plan.review"])
        XCTAssertTrue(app.staticTexts["Synthetic progression"].waitForExistence(timeout: 3))
        tapAuthoring(app.buttons["plan.confirm-save"])
        XCTAssertTrue(app.buttons["plans.record.00000000-0000-0000-0000-000000000011"].waitForExistence(timeout: 3))
    }
    func testUnavailableSelectorSupportsExplicitNoneAndAIInputRetention() {
        launchAuthoring("unavailable")
        XCTAssertTrue(activeSelector.label.contains("Saved profiles unavailable"))
        activeSelector.tap(); app.buttons["planning.picker.none"].tap(); app.buttons["planning.picker.done"].tap()
        XCTAssertTrue(activeSelector.label.contains("No treadmill selected"))
        app.buttons["plans.import"].tap()
        let text = app.textViews["import.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 3)); text.tap(); text.typeText("Synthetic fixed workout")
        app.swipeDown()
        tapAuthoring(activeSelector)
        app.navigationBars["Treadmill profile"].buttons["Cancel"].tap()
        XCTAssertEqual(text.value as? String, "Synthetic fixed workout")
        tapAuthoring(app.buttons["import.disclosure"])
        let disclosedText = app.staticTexts["Synthetic fixed workout"]
        for _ in 0..<12 { if disclosedText.exists { break }; app.swipeUp() }
        XCTAssertTrue(disclosedText.exists)
        tapAuthoring(app.buttons["import.consent"])
        XCTAssertTrue(app.staticTexts["Complete plan"].waitForExistence(timeout: 3))
    }
    func testLargeTextPickerKeepsHistoricalRowsNeutralAndEmptyRecoveryTruthful() {
        launchAuthoring("empty", large: true)
        tapAuthoring(activeSelector)
        XCTAssertTrue(app.buttons["planning.picker.none"].waitForExistence(timeout: 3))
        tapAuthoring(app.buttons["Manage saved profiles"])
        XCTAssertTrue(app.navigationBars["Saved treadmills"].waitForExistence(timeout: 3))
        let empty = app.staticTexts["No saved treadmill profiles"]
        for _ in 0..<12 { if empty.exists { break }; app.swipeUp() }
        XCTAssertTrue(empty.exists)
        XCTAssertFalse(app.buttons["Set up treadmill"].exists)
        let recovery = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Close the picker, then open Home")).firstMatch
        for _ in 0..<12 { if recovery.exists { break }; app.swipeUp() }
        XCTAssertTrue(recovery.exists)
    }

}
