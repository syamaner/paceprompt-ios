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
}
