import XCTest

final class HealthExportFlowUITests: XCTestCase {
  func testDeliberateSaveShowsTruthfulPreviewThenSavedState() {
    let app = XCUIApplication()
    app.launchArguments = ["--paceprompt-health-export-ui-testing"]
    app.launch()

    app.tabBars.buttons["History"].tap()
    let save = app.buttons["history.health.save"]
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
}
