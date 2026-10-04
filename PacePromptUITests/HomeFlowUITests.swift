import XCTest

final class HomeFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testIdleHomeKeepsAvailableBluetoothSeparateAndStartsNoScan() {
        launch(scenario: "idle")

        XCTAssertEqual(status("bluetooth").value as? String, "Available. Bluetooth is on and PacePrompt has permission to use it.")
        XCTAssertEqual(status("treadmill").value as? String, "Idle. Choose Set up treadmill to find and check your treadmill.")
        let setup = app.buttons["home.setup"]
        XCTAssertTrue(setup.exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.safety"].exists)

        setup.tap()
        XCTAssertTrue(app.navigationBars["Treadmill"].waitForExistence(timeout: 2))
    }

    func testInProgressHomeDoesNotPresentConnectionAsReady() {
        launch(scenario: "in-progress")

        let value = status("treadmill").value as? String
        XCTAssertTrue(value?.hasPrefix("Checking treadmill.") == true)
        XCTAssertTrue(value?.contains("still being checked") == true)
        XCTAssertFalse(value?.localizedCaseInsensitiveContains("ready") == true)
    }

    func testConnectedHomeShowsOnlySyntheticCurrentReadEvidence() {
        launch(scenario: "connected-evidence")

        let value = status("treadmill").value as? String
        XCTAssertTrue(value?.hasPrefix("Connected.") == true)
        XCTAssertTrue(value?.contains("supported speed") == true)
        XCTAssertTrue(value?.contains("0.8–16.0 km/h") == true)
        XCTAssertTrue(value?.contains("0.0–12.0%") == true)
    }

    func testUnauthorisedHomeRoutesToSettingsInsteadOfRetry() {
        launch(scenario: "unauthorised")

        XCTAssertTrue((status("bluetooth").value as? String)?.hasPrefix("Not authorised.") == true)
        XCTAssertTrue(app.buttons["home.bluetooth.action"].exists)
        XCTAssertEqual(app.buttons["home.bluetooth.action"].label, "Open iOS Settings")
        XCTAssertFalse(app.buttons["home.treadmill.action"].exists)
    }

    func testFailedHomeRetriesOnlyAfterExplicitTap() {
        launch(scenario: "failed")

        XCTAssertTrue((status("treadmill").value as? String)?.hasPrefix("Connection failed.") == true)
        let retry = app.buttons["home.treadmill.action"]
        XCTAssertEqual(retry.label, "Retry")
        retry.tap()

        XCTAssertTrue((status("treadmill").value as? String)?.hasPrefix("Scanning.") == true)
    }

    func testProductionScopeCopyMatchesAcceptedWorkoutAndHealthBoundaries() {
        launch(scenario: "idle")

        XCTAssertEqual(
            app.descendants(matching: .any)["home.safety"].value as? String,
            "PacePrompt adjusts speed and incline only during a reviewed workout. "
                + "It never starts, stops or pauses the treadmill. Use the physical console "
                + "and safety key."
        )

        app.buttons["Settings"].tap()
        let screenAwake = app.descendants(matching: .any)["settings.screen-awake"]
        XCTAssertTrue(screenAwake.waitForExistence(timeout: 2))
        XCTAssertTrue(screenAwake.label.contains("keeps the display awake"))
        app.swipeUp()
        let guidedAccess = app.descendants(matching: .any)["settings.guided-access"]
        XCTAssertTrue(guidedAccess.waitForExistence(timeout: 2))
        XCTAssertTrue(guidedAccess.label.contains("triple-click the side button"))
        let phone = app.staticTexts["settings.privacy.health.phone"]
        reveal(phone)
        XCTAssertTrue(phone.label.contains("The iPhone does not read Health data"))
        let watch = app.staticTexts["settings.privacy.health.watch"]
        reveal(watch)
        XCTAssertTrue(watch.label.contains("Watch separately reads available heart rate and active energy"))
        let empty = app.staticTexts["settings.privacy.health.empty"]
        reveal(empty)
        XCTAssertTrue(empty.label.contains("Workouts without usable step details are not saved"))
        app.swipeUp()
        XCTAssertEqual(
            app.descendants(matching: .any)["settings.current-slice"].value as? String,
            "Saved plans, workouts and Health export"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["settings.ftms-control"].value as? String,
            "Speed and incline during workouts"
        )
    }

    func testSetupKeepsLimitsAndReadingAvailabilityOutsideDiagnostics() throws {
        launch(scenario: "setup-diagnostics")
        app.buttons["home.setup"].tap()
        let speed = app.descendants(matching: .any)["setup.speed.limits"]
        reveal(speed)
        XCTAssertTrue(speed.label.contains("0.80–16.00 km/h"))
        XCTAssertFalse(app.staticTexts["Raw"].exists)
        XCTAssertFalse(app.buttons["Share reading capture"].exists)
        XCTAssertFalse(app.staticTexts["00000000-0000-0000-0000-000000000107"].exists)
        let readings = app.descendants(matching: .any)["setup.reading.2ACD"]
        reveal(readings)
        XCTAssertTrue(readings.label.contains("Ready to receive updates"))
        let failed = app.descendants(matching: .any)["setup.reading.2AD3"]
        reveal(failed)
        XCTAssertTrue(failed.label.contains("Could not receive updates"))
        let unsupported = app.descendants(matching: .any)["setup.reading.2ADA"]
        reveal(unsupported)
        XCTAssertTrue(unsupported.label.contains("Live updates not available"))
        let link = app.buttons["setup.troubleshooting"]
        reveal(link)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        capture("setup-reading-availability")
        link.tap()
        XCTAssertTrue(app.navigationBars["Troubleshooting"].waitForExistence(timeout: 2))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        capture("troubleshooting-capture")
        XCTAssertTrue(app.staticTexts["troubleshooting.privacy"].label.contains("device identifiers"))
        let share = app.buttons["Share reading capture"]
        reveal(share)
        XCTAssertFalse(app.buttons["Share issue #52 capture"].exists)
        app.buttons["Copy reading capture"].tap()
        XCTAssertTrue(app.buttons["Reading capture copied"].exists)
        app.navigationBars["Troubleshooting"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Treadmill"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Share reading capture"].exists)
    }

    func testUnreadableSetupLimitStaysActionableWithDetailsSecondary() {
        launch(scenario: "setup-malformed")
        app.buttons["home.setup"].tap()
        let speed = app.descendants(matching: .any)["setup.speed.limits"]
        reveal(speed)
        XCTAssertTrue(speed.label.contains("Could not read the limits. Reconnect to try again."))
        XCTAssertFalse(speed.label.contains("16.00"))
        XCTAssertFalse(app.staticTexts["Raw"].exists)
        let reason = "Supported Speed Range expected exactly 6 bytes, received 1."
        XCTAssertFalse(app.staticTexts[reason].exists)
        let link = app.buttons["setup.troubleshooting"]
        reveal(link)
        link.tap()
        XCTAssertEqual(app.staticTexts["troubleshooting.error"].label, reason)
    }

    func testReadOnlyStatusDoesNotClaimAllReadingsUnavailable() {
        launch(scenario: "setup-read-only")
        app.buttons["home.setup"].tap()
        let status = app.descendants(matching: .any)["setup.reading.2AD3"]
        reveal(status)
        XCTAssertTrue(status.label.contains("Live updates not available"))
        let link = app.buttons["setup.troubleshooting"]
        reveal(link)
        link.tap()
        let copy = app.buttons["Copy reading capture"]
        reveal(copy)
        copy.tap()
        XCTAssertTrue(app.buttons["Reading capture copied"].exists)
    }

    func testLargeTextTroubleshootingNavigationAndDisabledObservation() throws {
        launch(scenario: "idle", largeText: true)
        app.buttons["home.setup"].tap()
        let link = app.buttons["setup.troubleshooting"]
        reveal(link)
        XCTAssertGreaterThanOrEqual(link.frame.height, 44)
        link.tap()
        XCTAssertTrue(app.navigationBars["Troubleshooting"].waitForExistence(timeout: 2))
        let observation = app.buttons["troubleshooting.observation"]
        reveal(observation)
        XCTAssertFalse(observation.isEnabled)
        let copy = app.buttons["Copy reading capture"]
        reveal(copy)
        XCTAssertTrue(copy.isHittable)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        capture("troubleshooting-large-text")
        app.navigationBars["Troubleshooting"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Treadmill"].waitForExistence(timeout: 2))
    }

    func testPrivacyGroupsRetainDisclosuresAtLargeText() throws {
        launch(scenario: "idle", largeText: true)
        app.buttons["Settings"].tap()
        let policy = app.descendants(matching: .any)["settings.privacy.policy"]
        reveal(policy)
        XCTAssertTrue(policy.isHittable)
        XCTAssertEqual(policy.label, "Privacy Policy")
        let local = app.staticTexts["settings.privacy.local"]
        reveal(local)
        XCTAssertTrue(local.label.contains("Saved plans stay on this device"))
        XCTAssertTrue(local.label.contains("this device’s Keychain"))
        XCTAssertTrue(local.label.contains("No analytics are used"))
        let ai = app.staticTexts["settings.privacy.ai"]
        reveal(ai)
        XCTAssertTrue(ai.label.contains("OpenRouter and OpenAI"))
        XCTAssertTrue(ai.label.contains("your agreement for each request"))
        XCTAssertTrue(ai.label.contains("no zero-retention guarantee"))
        let phone = app.staticTexts["settings.privacy.health.phone"]
        reveal(phone)
        XCTAssertTrue(phone.label.contains("only after you choose Save to Apple Health"))
        let watch = app.staticTexts["settings.privacy.health.watch"]
        reveal(watch)
        XCTAssertTrue(watch.label.contains("execution intervals and available treadmill distance"))
        XCTAssertTrue(watch.label.contains("iPhone saving stays disabled for that attempt"))
        let empty = app.staticTexts["settings.privacy.health.empty"]
        reveal(empty)
        XCTAssertTrue(empty.label.contains("heart rate and calorie samples may still remain in Apple Health"))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        capture("privacy-large-text")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTFail("Expected reachable control: \(element)", file: file, line: line)
    }

    private func launch(scenario: String, largeText: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--paceprompt-home-ui-testing"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment = ["PACEPROMPT_HOME_SCENARIO": scenario]
        app.launch()
        XCTAssertTrue(status("bluetooth").waitForExistence(timeout: 3))
        XCTAssertTrue(status("treadmill").waitForExistence(timeout: 3))
    }

    private func status(_ kind: String) -> XCUIElement {
        app.descendants(matching: .any)["home.\(kind).status"]
    }
}
