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

  func testAcceptedActivityStatusInBothOrientations() {
    for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
      for (activity, title) in [("indoorWalking", "Walking"), ("indoorRunning", "Running")] {
        launch(
          scenario: "running", orientation: orientation,
          extraEnvironment: ["PACEPROMPT_EXERCISE_ACTIVITY": activity]
        )
        XCTAssertTrue(app.staticTexts[title].exists)
        let status = element("exercise.status")
        XCTAssertTrue(status.exists)
        XCTAssertEqual(
          status.value as? String,
          "\(title). The treadmill reports your current speed and incline settings."
        )
      }
    }
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
    var referenceRegionFrames: [String: CGRect]?

    for scenario in scenarios {
      launch(scenario: scenario, orientation: .landscapeLeft)
      XCTAssertTrue(element("exercise.progress-region").exists, scenario)
      XCTAssertTrue(element("exercise.speed").exists, scenario)
      XCTAssertTrue(element("exercise.inclination").exists, scenario)
      XCTAssertGreaterThan(
        element("exercise.speed").frame.minX, element("exercise.progress-region").frame.minX)
      let regionFrames = landscapeRegionFrames()
      if let referenceRegionFrames {
        for (identifier, frame) in regionFrames {
          XCTAssertEqual(frame, referenceRegionFrames[identifier], "\(scenario): \(identifier)")
        }
      } else {
        referenceRegionFrames = regionFrames
      }
      attachScreenshot(named: "landscape-\(scenario)")
    }
  }

  func testLandscapeRegionsContainTheirAccessibleActions() {
    for (scenario, region, identifier) in [
      ("running", "exercise.landscape.left", "exercise.plan.open"),
      ("paused", "exercise.landscape.actions", "exercise.end"),
      ("checking", "exercise.landscape.actions", "exercise.confirm-stationary"),
    ] {
      launch(scenario: scenario, orientation: .landscapeLeft)
      let action = app.otherElements[region].buttons[identifier]
      XCTAssertTrue(action.exists, identifier)
      XCTAssertTrue(action.isHittable, identifier)
    }
  }

  func testLandscapeRecoveryObservationCanBeCancelled() {
    launch(scenario: "interrupted", orientation: .landscapeLeft)
    app.buttons["exercise.confirm-stationary"].tap()
    XCTAssertTrue(app.buttons["Confirm treadmill is stationary"].waitForExistence(timeout: 2))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.staticTexts["Workout interrupted"].exists)
    XCTAssertFalse(app.buttons["exercise.end"].exists)
  }

  func testLandscapeFullPlanOpensUsingAccessibleButton() {
    launch(scenario: "running", orientation: .landscapeLeft)
    let fullPlan = app.buttons["exercise.plan.open"]
    XCTAssertTrue(fullPlan.isHittable)
    fullPlan.tap()
    XCTAssertTrue(element("exercise.plan.sheet").waitForExistence(timeout: 2))
    for index in 0..<3 {
      XCTAssertTrue(element("exercise.plan.step.\(index)").exists)
    }
  }

  func testLandscapeReferenceSizeUsesFixedTwoColumnGeometryWithoutScrolling() {
    launch(scenario: "running", orientation: .landscapeLeft)

    let screen = app.windows.firstMatch.frame
    XCTAssertEqual(screen.width, 874, accuracy: 1)
    XCTAssertEqual(screen.height, 402, accuracy: 1)
    attachScreenshot(named: "landscape-reference-geometry")
    assertFixedLandscapeGeometry()
  }

  func testLandscapeAlternateSizeKeepsImportantRegionsVisible() {
    launch(scenario: "running", orientation: .landscapeLeft)

    attachScreenshot(named: "landscape-alternate-geometry")
    assertFixedLandscapeGeometry()
    for identifier in [
      "exercise.countdown", "exercise.next", "exercise.speed", "exercise.inclination",
      "exercise.landscape.actions", "exercise.plan.open",
    ] {
      let item = element(identifier)
      XCTAssertTrue(item.exists, identifier)
      XCTAssertTrue(app.windows.firstMatch.frame.intersects(item.frame), identifier)
    }
  }

  func testLandscapeRegionsStayFixedAfterActiveOverride() {
    launch(scenario: "running", orientation: .landscapeLeft)

    let identifiers = [
      "exercise.landscape.left", "exercise.landscape.right",
      "exercise.landscape.axes", "exercise.landscape.actions",
      "exercise.speed", "exercise.inclination",
    ]
    let initialFrames = Dictionary(
      uniqueKeysWithValues: identifiers.map { ($0, element($0).frame) }
    )

    app.buttons["exercise.speed.plus"].tap()
    XCTAssertTrue(element("exercise.override-state").waitForExistence(timeout: 2))

    for identifier in identifiers {
      XCTAssertEqual(element(identifier).frame, initialFrames[identifier], identifier)
    }
  }

  func testLandscapeEndNeedsOneTapAndNoConfirmation() {
    launch(scenario: "paused", orientation: .landscapeLeft)
    let end = app.buttons["exercise.end"]
    XCTAssertTrue(end.isHittable); XCTAssertGreaterThanOrEqual(end.frame.height, 48)
    end.tap()
    XCTAssertTrue(app.staticTexts["Ending workout"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["End and save local attempt"].exists)
    XCTAssertFalse(app.buttons["exercise.end"].exists)
  }

  func testLandscapeStationaryAndEndNeedsOneExplicitTap() {
    launch(scenario: "checking", orientation: .landscapeLeft)
    let end = app.buttons["exercise.confirm-stationary"]
    XCTAssertTrue(end.isHittable); XCTAssertGreaterThanOrEqual(end.frame.height, 48)
    XCTAssertEqual(end.label, "Treadmill stopped — end workout")
    end.tap()
    XCTAssertTrue(app.staticTexts["Ending workout"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["Confirm treadmill is stationary"].exists)
    XCTAssertFalse(app.buttons["exercise.confirm-stationary"].exists)
  }

  func testLandscapeAccessibilityDynamicTypeRemainsFixedAndNonScrolling() {
    launch(
      scenario: "running",
      orientation: .landscapeLeft,
      extraArguments: [
        "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
      ]
    )

    XCTAssertEqual(app.scrollViews.count, 0)
    XCTAssertTrue(element("exercise.landscape").exists)
    XCTAssertTrue(element("exercise.countdown").exists)
    XCTAssertTrue(element("exercise.speed").exists)
    XCTAssertTrue(element("exercise.inclination").exists)
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

  func testPortraitEndNeedsOneTapAndNoConfirmation() {
    launch(scenario: "paused", orientation: .portrait)
    let end = app.buttons["exercise.end"]; scrollTo(end)
    XCTAssertTrue(end.isHittable); XCTAssertGreaterThanOrEqual(end.frame.height, 56)
    end.tap(); app.swipeDown(); app.swipeDown()
    XCTAssertTrue(app.staticTexts["Ending workout"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["End and save local attempt"].exists)
  }

  func testPortraitStationaryAndEndNeedsOneExplicitTap() {
    launch(scenario: "checking", orientation: .portrait)
    XCTAssertFalse(app.buttons["exercise.end"].exists)
    let end = app.buttons["exercise.confirm-stationary"]; scrollTo(end)
    XCTAssertEqual(end.label, "Treadmill stopped — end workout")
    end.tap(); app.swipeDown(); app.swipeDown()
    XCTAssertTrue(app.staticTexts["Ending workout"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["Confirm treadmill is stationary"].exists)
  }

  func testInterruptedWorkoutCanRecordStationaryObservationWithoutChangingOutcome() {
    launch(scenario: "interrupted", orientation: .portrait)

    XCTAssertTrue(app.staticTexts["Workout interrupted"].exists)
    XCTAssertFalse(app.buttons["exercise.end"].exists)
    app.swipeUp()
    app.swipeUp()
    let stationaryConfirmation = app.buttons["exercise.confirm-stationary"]
    scrollTo(stationaryConfirmation)
    XCTAssertTrue(stationaryConfirmation.isHittable)
    stationaryConfirmation.tap()

    let confirmStationary = app.buttons["Confirm treadmill is stationary"]
    XCTAssertTrue(confirmStationary.waitForExistence(timeout: 2))
    app.swipeUp()
    scrollTo(confirmStationary)
    confirmStationary.tap()

    XCTAssertTrue(app.staticTexts["Workout interrupted"].waitForExistence(timeout: 2))
    XCTAssertTrue(
      app.buttons["exercise.confirm-stationary"].waitForNonExistence(timeout: 2)
    )
    XCTAssertFalse(app.buttons["exercise.end"].exists)
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
    XCTAssertTrue(element("exercise.speed.evidence").label.contains("Waiting for an update"))
    XCTAssertTrue(element("exercise.inclination.evidence").label.contains("Waiting for an update"))
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
    // Launch may restore a cached portrait orientation after the device was
    // rotated. Request the test layout once the app is ready, then verify it.
    XCUIDevice.shared.orientation = orientation
    if orientation.isLandscape {
      XCTAssertTrue(element("exercise.landscape.left").waitForExistence(timeout: 5), scenario)
    }
  }

  private func attachScreenshot(named name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func assertFixedLandscapeGeometry() {
    let left = element("exercise.landscape.left")
    let right = element("exercise.landscape.right")
    let axes = element("exercise.landscape.axes")
    let actions = element("exercise.landscape.actions")
    let speed = element("exercise.speed")
    let inclination = element("exercise.inclination")

    for item in [left, right, axes, actions, speed, inclination] {
      XCTAssertTrue(item.exists, item.identifier)
    }
    XCTAssertEqual(app.scrollViews.count, 0)

    let columnRatio = left.frame.width / (left.frame.width + right.frame.width)
    XCTAssertEqual(columnRatio, 0.57, accuracy: 0.015)
    XCTAssertEqual(speed.frame.width, inclination.frame.width, accuracy: 1)
    XCTAssertEqual(speed.frame.minY, inclination.frame.minY, accuracy: 1)
    XCTAssertEqual(speed.frame.maxY, inclination.frame.maxY, accuracy: 1)
    XCTAssertGreaterThan(actions.frame.minY, axes.frame.maxY)

    let regionHeight = axes.frame.height + actions.frame.height
    XCTAssertEqual(axes.frame.height / regionHeight, 0.72, accuracy: 0.015)

    let countdown = element("exercise.countdown")
    let fullPlan = app.buttons["exercise.plan.open"]
    XCTAssertLessThan(countdown.frame.minY, fullPlan.frame.minY)
    XCTAssertTrue(fullPlan.isHittable)
    XCTAssertGreaterThanOrEqual(fullPlan.frame.height, 48)

    for identifier in [
      "exercise.speed.minus", "exercise.speed.plus",
      "exercise.inclination.minus", "exercise.inclination.plus",
    ] {
      let control = app.buttons[identifier]
      XCTAssertTrue(control.isHittable, identifier)
      XCTAssertGreaterThanOrEqual(control.frame.width, 48, identifier)
      XCTAssertGreaterThanOrEqual(control.frame.height, 48, identifier)
    }
  }

  private func landscapeRegionFrames() -> [String: CGRect] {
    let identifiers = [
      "exercise.landscape.left", "exercise.landscape.right",
      "exercise.landscape.axes", "exercise.landscape.actions",
      "exercise.speed", "exercise.inclination",
    ]
    return Dictionary(uniqueKeysWithValues: identifiers.map { ($0, element($0).frame) })
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
