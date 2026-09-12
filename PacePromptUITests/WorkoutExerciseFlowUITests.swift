import UIKit
import XCTest

final class WorkoutExerciseFlowUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  override func tearDownWithError() throws {
    app?.terminate()
    XCUIDevice.shared.orientation = .portrait
  }

  func testPortraitSnapshotsCoverEveryRequiredState() {
    let scenarios = [
      ("waiting", "Press Start on the treadmill"),
      ("applying", "Applying targets"),
      ("running", "Running"),
      ("override", "Manual override"),
      ("checking", "Checking treadmill"),
      ("paused", "Workout paused — press Start on the treadmill to resume"),
      ("restoring", "Restoring targets"),
      ("ending", "Ending workout"),
      ("failed", "Workout failed"),
      ("interrupted", "Workout interrupted"),
    ]

    for (scenario, title) in scenarios {
      launch(scenario: scenario, orientation: .portrait)
      XCTAssertTrue(app.staticTexts[title].exists, scenario)
      XCTAssertTrue(element("exercise.countdown").exists, scenario)
      XCTAssertTrue(element("exercise.speed.evidence").exists, scenario)
      XCTAssertTrue(element("exercise.inclination.evidence").exists, scenario)
      attachScreenshot(named: "portrait-\(scenario)")
    }
  }

  func testLandscapeSnapshotsCoverEveryRequiredState() {
    let scenarios = [
      "waiting", "applying", "running", "override", "checking",
      "paused", "restoring", "ending", "failed", "interrupted",
    ]

    for scenario in scenarios {
      launch(scenario: scenario, orientation: .landscapeLeft)
      XCTAssertTrue(element("exercise.progress-region").exists, scenario)
      XCTAssertTrue(element("exercise.speed").exists, scenario)
      XCTAssertTrue(element("exercise.inclination").exists, scenario)
      XCTAssertGreaterThan(
        element("exercise.speed").frame.minX, element("exercise.progress-region").frame.minX)
      attachScreenshot(named: "landscape-\(scenario)")
    }
  }

  func testControlsAreLargeTypedAndContainNoBeltStartStopPauseOrResume() {
    launch(scenario: "running", orientation: .portrait)

    for identifier in [
      "exercise.speed.minus", "exercise.speed.plus",
      "exercise.inclination.minus", "exercise.inclination.plus",
    ] {
      let control = app.buttons[identifier]
      XCTAssertTrue(control.isHittable, identifier)
      XCTAssertGreaterThanOrEqual(control.frame.width, 56, identifier)
      XCTAssertGreaterThanOrEqual(control.frame.height, 56, identifier)
    }
    XCTAssertFalse(app.buttons["Start"].exists)
    XCTAssertFalse(app.buttons["Stop"].exists)
    XCTAssertFalse(app.buttons["Pause"].exists)
    XCTAssertFalse(app.buttons["Resume"].exists)
    XCTAssertTrue(element("exercise.console-authority").exists)
  }

  func testOverrideCanReturnToPlanWithoutLeavingExerciseMode() {
    launch(scenario: "running", orientation: .portrait)

    app.buttons["exercise.speed.plus"].tap()
    XCTAssertTrue(element("exercise.override-state").waitForExistence(timeout: 2))
    let returnToPlan = app.buttons["exercise.return-to-plan"]
    XCTAssertTrue(returnToPlan.isHittable)
    XCTAssertGreaterThanOrEqual(returnToPlan.frame.height, 56)
    returnToPlan.tap()

    XCTAssertFalse(element("exercise.override-state").exists)
    XCTAssertTrue(element("exercise.screen").exists)
    XCTAssertFalse(app.tabBars.firstMatch.exists)
  }

  func testFullPlanAffordanceShowsEverySyntheticSegment() {
    launch(scenario: "running", orientation: .portrait)

    app.buttons["exercise.plan.open"].tap()
    XCTAssertTrue(element("exercise.plan.sheet").waitForExistence(timeout: 2))
    XCTAssertTrue(element("exercise.plan.step.0").exists)
    XCTAssertTrue(element("exercise.plan.step.1").exists)
    XCTAssertTrue(element("exercise.plan.step.2").exists)
    XCTAssertTrue(app.staticTexts["Current"].exists)
  }

  func testPausedEndConfirmationStatesNoFTMSStopAndEndsLocally() {
    launch(scenario: "paused", orientation: .portrait)

    app.swipeUp()
    app.swipeUp()
    let end = app.buttons["exercise.end"]
    scrollTo(end)
    XCTAssertTrue(end.isHittable)
    XCTAssertGreaterThanOrEqual(end.frame.height, 56)
    end.tap()
    let confirmEnd = app.buttons["End and save local attempt"]
    XCTAssertTrue(confirmEnd.waitForExistence(timeout: 2))
    XCTAssertTrue(
      app.staticTexts[
        "This sends no FTMS Stop. The treadmill remains under physical-console control."
      ].exists
    )
    app.swipeUp()
    scrollTo(confirmEnd)
    confirmEnd.tap()
    app.swipeDown()
    app.swipeDown()
    XCTAssertTrue(app.staticTexts["Ending workout"].waitForExistence(timeout: 2))
  }

  func testCheckingUsesSeparatelyConfirmedOperatorFallback() {
    launch(scenario: "checking", orientation: .portrait)

    XCTAssertTrue(element("exercise.stationary-fallback").exists)
    XCTAssertFalse(app.buttons["exercise.end"].exists)
    app.swipeUp()
    app.swipeUp()
    let stationaryConfirmation = app.buttons["exercise.confirm-stationary"]
    scrollTo(stationaryConfirmation)
    stationaryConfirmation.tap()
    let confirmStationary = app.buttons["Confirm treadmill is stationary"]
    XCTAssertTrue(confirmStationary.waitForExistence(timeout: 2))
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(
          format: "label == %@",
          "Confirm only after directly observing that the treadmill is stationary. Silence, stale telemetry and disconnection are not stationary evidence."
        )
      ).firstMatch.exists
    )
    app.swipeUp()
    scrollTo(confirmStationary)
    confirmStationary.tap()
    app.swipeDown()
    app.swipeDown()
    XCTAssertTrue(
      app.staticTexts["Workout paused — press Start on the treadmill to resume"].waitForExistence(
        timeout: 2))
    app.swipeUp()
    app.swipeUp()
    XCTAssertTrue(app.buttons["exercise.end"].exists)
  }

  func testAccessibilityDynamicTypePreservesVoiceOverOrderAndLargeControls() {
    launch(
      scenario: "running",
      orientation: .portrait,
      extraArguments: [
        "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
      ]
    )

    let status = element("exercise.status")
    let progress = element("exercise.progress-region")
    XCTAssertLessThan(status.frame.minY, progress.frame.minY)

    let speedIncrease = app.buttons["exercise.speed.plus"]
    scrollTo(speedIncrease)
    XCTAssertTrue(speedIncrease.isHittable)
    XCTAssertGreaterThanOrEqual(speedIncrease.frame.height, 56)
    XCTAssertTrue(speedIncrease.label.contains("Increase by 0.1 km/h"))
    XCTAssertTrue(element("exercise.speed.evidence").label.contains("Confirmed by treadmill"))
  }

  func testReducedMotionKeepsStaticColourIndependentStatus() {
    launch(
      scenario: "checking",
      orientation: .portrait,
      extraEnvironment: ["PACEPROMPT_EXERCISE_REDUCE_MOTION": "1"]
    )

    XCTAssertEqual(element("exercise.motion").value as? String, "Static guidance")
    XCTAssertTrue(app.staticTexts["Checking treadmill"].exists)
    XCTAssertTrue(element("exercise.speed.evidence").label.contains("Stale treadmill report"))
    XCTAssertTrue(element("exercise.inclination.evidence").label.contains("Stale treadmill report"))
  }

  private func launch(
    scenario: String,
    orientation: UIDeviceOrientation,
    extraArguments: [String] = [],
    extraEnvironment: [String: String] = [:]
  ) {
    app?.terminate()
    XCUIDevice.shared.orientation = orientation
    app = XCUIApplication()
    app.launchArguments = ["--paceprompt-exercise-ui-testing"] + extraArguments
    app.launchEnvironment = ["PACEPROMPT_EXERCISE_SCENARIO": scenario]
      .merging(extraEnvironment) { _, replacement in replacement }
    app.launch()
    XCTAssertTrue(element("exercise.screen").waitForExistence(timeout: 3), scenario)
  }

  private func attachScreenshot(named name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func scrollTo(_ element: XCUIElement) {
    var attempts = 0
    while !element.isHittable && attempts < 8 {
      app.swipeUp()
      attempts += 1
    }
  }
}
