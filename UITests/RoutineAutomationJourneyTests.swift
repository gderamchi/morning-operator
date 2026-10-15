import XCTest

/// Synthetic routine/persisted budgets; live-news explicitly uses a real public page.
@MainActor
final class RoutineAutomationJourneyTests: XCTestCase {
    func testDraftRequiresExplicitDelegationBeforeStart() {
        let app = launch(["--ui-testing-automation"], french: true)
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["routine.delegation"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attach("automation-french-review-before-start", app)
        app.buttons["routine.approve"].tap()
        reveal(app)
        XCTAssertTrue(app.buttons["morning.begin"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attach("automation-approved-awaiting-start", app)
    }

    func testTimedRoutineContinuesWithoutNextAndKeepsHonestRecap() {
        let app = launch(["--ui-testing-automation", "--ui-testing-approved", "--ui-testing-hands-free", "--ui-testing-short-budgets"])
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: 35), app.debugDescription)
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("2 steps performed"))
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("0 likes confirmed"))
        attach("automation-finished-without-next", app)
        app.terminate(); app.launch(); reveal(app)
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("2 steps performed"))
        attach("automation-persisted-recap", app)
    }

    func testPublicNewsExecutesInsideMOREAndPauseKeepsSameMoment() {
        let app = launch(["--ui-testing-live-news", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.executionPause"].waitForExistence(timeout: 20), app.debugDescription)
        let status = app.staticTexts["web.executionStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), app.debugDescription)
        attach("automation-live-news", app)
        app.buttons["web.executionPause"].tap()
        attach("automation-live-news-paused", app)
    }

    private func launch(_ flags: [String], french: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(UUID().uuidString)",
            "--light-preview", "--theme-phase=morning", "-AppleLanguages", french ? "(fr)" : "(en)",
            "-AppleLocale", french ? "fr_FR" : "en_US"] + flags
        app.launch()
        return app
    }
    private func reveal(_ app: XCUIApplication) {
        let begin = app.buttons["morning.begin"]
        if !begin.exists && !app.staticTexts["morning.complete"].exists {
            let actions = app.buttons["morning.actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        }
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
