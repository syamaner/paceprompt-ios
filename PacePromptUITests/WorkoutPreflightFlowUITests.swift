import XCTest

final class WorkoutPreflightFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testReadyPreflightPresentsDesignHierarchyAndMovesToPhysicalStartWaiting() {
        launch(scenario: "ready-to-begin")

        XCTAssertTrue(element("preflight.plan").exists)
        XCTAssertTrue((element("preflight.plan").value as? String)?.contains("18:00") == true)
        XCTAssertTrue(statusValue().hasPrefix("Ready to begin."))
        XCTAssertTrue(element("preflight.ceilings").exists)
        XCTAssertTrue((element("preflight.ceilings").value as? String)?.contains("10.0 km/h") == true)
        XCTAssertTrue(element("preflight.health").exists)
        XCTAssertTrue(app.staticTexts["No permission is requested and no workout or health data is saved on this screen."].exists)
        XCTAssertTrue(element("preflight.activity").exists)
        XCTAssertTrue(element("preflight.safety").exists)
        XCTAssertTrue(element("preflight.console-guidance").exists)

        let begin = app.buttons["preflight.begin"]
        scrollTo(begin)
        XCTAssertEqual(begin.label, "Begin workout")
        XCTAssertTrue(begin.isEnabled)
        XCTAssertGreaterThanOrEqual(begin.frame.height, 56)
        XCTAssertFalse(app.buttons["Start workout"].exists)
        begin.tap()

        XCTAssertTrue(element("preflight.waiting.screen").waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Press Start on the treadmill"].exists)
        XCTAssertTrue(app.staticTexts["Warm-up"].exists)
        XCTAssertTrue(app.staticTexts["5.0 km/h"].exists)
        XCTAssertTrue(app.staticTexts["0.0 %"].exists)
        XCTAssertTrue(element("preflight.waiting.target-boundary").exists)
        XCTAssertTrue(statusValue().hasPrefix("Control confirmed."))
        XCTAssertTrue(statusValue().contains("No speed or inclination target has been sent"))
        XCTAssertFalse(app.buttons["preflight.begin"].exists)
    }

    func testBlockedAndTransitionalReadinessStatesRemainDistinctAndDisabled() {
        let scenarios = [
            ("disconnected", "Disconnected."),
            ("preparing", "Preparing."),
            ("unsupported", "Unsupported profile."),
            ("stale", "Treadmill data stale."),
            ("locked", "Readiness locked."),
            ("ready-to-request-control", "Ready to request control."),
            ("requesting", "Requesting control."),
            ("failed", "Preflight failed."),
        ]

        for (scenario, expectedStatus) in scenarios {
            launch(scenario: scenario)
            XCTAssertTrue(
                statusValue().hasPrefix(expectedStatus),
                "Unexpected status for \(scenario): \(statusValue())"
            )
            let begin = app.buttons["preflight.begin"]
            scrollTo(begin)
            XCTAssertTrue(begin.exists)
            XCTAssertFalse(begin.isEnabled, "Begin workout enabled for \(scenario)")
            XCTAssertEqual(begin.label, "Begin workout")
            app.terminate()
        }

        launch(scenario: "waiting-for-physical-start")
        XCTAssertTrue(element("preflight.waiting.screen").exists)
        XCTAssertTrue(app.staticTexts["Press Start on the treadmill"].exists)
        XCTAssertFalse(app.buttons["preflight.begin"].exists)
    }

    func testIntentOnlyConfirmationsUnlockBeginWithoutChangingPlanOrStartingBelt() {
        launch(scenario: "ready-to-request-control")

        let begin = app.buttons["preflight.begin"]
        scrollTo(begin)
        XCTAssertFalse(begin.isEnabled)

        for confirmation in [
            "activity",
            "deckClear",
            "consoleReachable",
            "safetyKeyReachable",
            "physicallyStationary",
        ] {
            let button = app.buttons["preflight.confirmation.\(confirmation)"]
            scrollTo(button)
            XCTAssertEqual(button.value as? String, "Not confirmed")
            button.tap()
            XCTAssertEqual(button.value as? String, "Confirmed")
        }

        scrollTo(begin)
        XCTAssertTrue(begin.isEnabled)
        XCTAssertTrue(statusValue().hasPrefix("Ready to begin."))
        XCTAssertTrue((element("preflight.plan").value as? String)?.contains("18:00") == true)
        XCTAssertFalse(app.staticTexts["Start workout"].exists)
    }

    func testAccessibilityDynamicTypeKeepsOrderedContentScrollableAndPrimaryControlLarge() {
        launch(
            scenario: "ready-to-begin",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        )

        let plan = element("preflight.plan")
        let treadmill = element("preflight.treadmill")
        XCTAssertLessThan(plan.frame.minY, treadmill.frame.minY)

        let begin = app.buttons["preflight.begin"]
        scrollTo(begin)
        XCTAssertTrue(begin.isHittable)
        XCTAssertGreaterThanOrEqual(begin.frame.height, 56)
        XCTAssertEqual(begin.label, "Begin workout")
        XCTAssertTrue((begin.value as? String) == nil || !(begin.value as? String ?? "").contains("Start"))
    }

    func testReducedMotionUsesStaticWaitingGuidanceWithTheSameSafetyMeaning() {
        launch(
            scenario: "waiting-for-physical-start",
            extraEnvironment: ["PACEPROMPT_PREFLIGHT_REDUCE_MOTION": "1"]
        )

        let motion = element("preflight.waiting.motion")
        XCTAssertTrue(motion.exists)
        XCTAssertEqual(motion.value as? String, "Static guidance")
        XCTAssertTrue(app.staticTexts["Press Start on the treadmill"].exists)
        XCTAssertTrue(element("preflight.waiting.safety").exists)
    }

    private func launch(
        scenario: String,
        extraArguments: [String] = [],
        extraEnvironment: [String: String] = [:]
    ) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--paceprompt-preflight-ui-testing"] + extraArguments
        app.launchEnvironment = ["PACEPROMPT_PREFLIGHT_SCENARIO": scenario]
            .merging(extraEnvironment) { _, replacement in replacement }
        app.launch()
        XCTAssertTrue(
            element("preflight.screen").waitForExistence(timeout: 3)
                || element("preflight.waiting.screen").waitForExistence(timeout: 3)
        )
    }

    private func statusValue() -> String {
        element("preflight.treadmill").value as? String ?? ""
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
