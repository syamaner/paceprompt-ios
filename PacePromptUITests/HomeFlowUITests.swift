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

        XCTAssertEqual(status("bluetooth").value as? String, "Available. Radio powered on and authorised for this app.")
        XCTAssertEqual(status("treadmill").value as? String, "Idle. No scan started. Capability is unknown until you scan.")
        let setup = app.buttons["home.setup"]
        XCTAssertTrue(setup.exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.safety"].exists)

        setup.tap()
        XCTAssertTrue(app.navigationBars["Treadmill"].waitForExistence(timeout: 2))
    }

    func testInProgressHomeDoesNotPresentConnectionAsReady() {
        launch(scenario: "in-progress")

        let value = status("treadmill").value as? String
        XCTAssertTrue(value?.hasPrefix("Reading capability.") == true)
        XCTAssertTrue(value?.contains("incomplete") == true)
        XCTAssertFalse(value?.localizedCaseInsensitiveContains("ready") == true)
    }

    func testConnectedHomeShowsOnlySyntheticCurrentReadEvidence() {
        launch(scenario: "connected-evidence")

        let value = status("treadmill").value as? String
        XCTAssertTrue(value?.hasPrefix("Connected.") == true)
        XCTAssertTrue(value?.contains("read range evidence") == true)
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

    private func launch(scenario: String) {
        app = XCUIApplication()
        app.launchArguments = ["--paceprompt-home-ui-testing"]
        app.launchEnvironment = ["PACEPROMPT_HOME_SCENARIO": scenario]
        app.launch()
        XCTAssertTrue(status("bluetooth").waitForExistence(timeout: 3))
        XCTAssertTrue(status("treadmill").waitForExistence(timeout: 3))
    }

    private func status(_ kind: String) -> XCUIElement {
        app.descendants(matching: .any)["home.\(kind).status"]
    }
}
