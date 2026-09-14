import XCTest

final class HealthExportFlowUITests: XCTestCase {
  private var app: XCUIApplication!

  override func tearDown() {
    app?.terminate()
    app = nil
    super.tearDown()
  }

  func testDeliberateSaveShowsTruthfulPreviewThenSavedState() {
    app = XCUIApplication()
    app.launchArguments = ["--paceprompt-health-export-ui-testing"]
    app.launch()

    app.tabBars.buttons["History"].tap()
    let record = app.descendants(matching: .any)[
      "history.record.00000000-0000-0000-0000-000000000064"
    ]
    XCTAssertTrue(record.waitForExistence(timeout: 3))
    record.tap()

    let save = app.buttons["history.health.save"]
    for _ in 0..<6 where !save.exists { app.swipeUp() }
    XCTAssertTrue(save.waitForExistence(timeout: 3))
    XCTAssertEqual(save.label, "Save to Apple Health")
    XCTAssertEqual(
      app.descendants(matching: .any)["history.health.status"].label,
      "Not saved to Apple Health"
    )

    save.tap()
    XCTAssertTrue(app.alerts["Save to Apple Health?"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.alerts["Save to Apple Health?"].staticTexts.element(boundBy: 1).label.contains(
      "prescribed, effective-target and separately observed speed and inclination"
    ))
    app.alerts["Save to Apple Health?"].buttons["Save"].tap()

    let status = app.descendants(matching: .any)["history.health.status"]
    let predicate = NSPredicate(
      format: "label BEGINSWITH %@ AND label ENDSWITH %@",
      "Saved to Apple Health on ",
      " with distance"
    )
    expectation(for: predicate, evaluatedWith: status)
    waitForExpectations(timeout: 3)
    XCTAssertFalse(app.buttons["history.health.save"].exists)
  }

  func testHistoryListDetailRepeatAndDeferredActions() {
    app = XCUIApplication()
    app.launchArguments = ["--paceprompt-history-ui-testing"]
    app.launch()

    app.tabBars.buttons["History"].tap()
    let record = app.descendants(matching: .any)[
      "history.record.00000000-0000-0000-0000-000000000064"
    ]
    XCTAssertTrue(record.waitForExistence(timeout: 3))
    XCTAssertTrue(record.value as? String != nil)
    record.tap()

    XCTAssertEqual(
      app.staticTexts.matching(identifier: "history.detail.outcome").firstMatch.label,
      "Completed"
    )

    let repeatButton = app.buttons["history.repeat"]
    XCTAssertTrue(repeatButton.waitForExistence(timeout: 3))
    XCTAssertTrue(repeatButton.isHittable)
    repeatButton.tap()
    XCTAssertTrue(app.navigationBars["Repeat Synthetic steady walk"].waitForExistence(timeout: 5))
    let reviewOnly = app.staticTexts[
      "Review only. This does not arm, connect to or operate a treadmill, and it does not create or save a new plan."
    ]
    for _ in 0..<4 where !reviewOnly.exists { app.swipeUp() }
    XCTAssertTrue(reviewOnly.exists)
    app.buttons["Done"].tap()
    XCTAssertTrue(repeatButton.waitForExistence(timeout: 3))

    app.swipeUp()
    XCTAssertTrue(app.descendants(matching: .any)["history.executed.0-0"].waitForExistence(timeout: 2))

    let export = app.buttons["history.export-json"]
    let delete = app.buttons["history.delete"]
    for _ in 0..<8 where !export.exists { app.swipeUp() }
    XCTAssertTrue(export.exists)
    XCTAssertFalse(export.isEnabled)
    XCTAssertTrue(delete.exists)
    XCTAssertFalse(delete.isEnabled)
  }

  func testHistoryReadFailureIsNotPresentedAsEmptyAndOffersRetry() {
    app = XCUIApplication()
    app.launchArguments = ["--paceprompt-history-read-failure-ui-testing"]
    app.launch()

    app.tabBars.buttons["History"].tap()
    XCTAssertTrue(app.staticTexts["History could not be read"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["history.retry"].isEnabled)
    XCTAssertFalse(app.descendants(matching: .any)["history.empty"].exists)
  }
}
