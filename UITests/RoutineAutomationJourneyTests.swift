import XCTest

/// Synthetic routine/persisted budgets; live-news explicitly uses a real public page.
@MainActor
final class RoutineAutomationJourneyTests: XCTestCase {
    func testFrenchLargestTextKeepsDelegationAndApprovalReachable() {
        let app = launch(["--ui-testing-automation", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        let approve = app.buttons["routine.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 8))
        XCTAssertTrue(approve.isHittable)
        let step = app.buttons["routine.step.0"]
        for _ in 0..<10 where !step.isHittable { app.swipeUp() }
        XCTAssertTrue(step.isHittable)
        XCTAssertTrue(step.label.contains("1 min"))
        attach("automation-french-largest-review", app)
        step.tap()
        XCTAssertTrue(app.buttons["step.save"].waitForExistence(timeout: 8))
        attach("automation-french-largest-edit", app)
    }
    func testDraftRequiresExplicitDelegationBeforeStart() {
        let app = launch(["--ui-testing-automation"], french: true)
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("Timed moments finished: 2"))
        XCTAssertFalse(app.staticTexts["morning.executionSummary"].label.contains("likes"))
        attach("automation-finished-without-next", app)
        app.terminate(); app.launch(); reveal(app)
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("Timed moments finished: 2"))
        attach("automation-persisted-recap", app)
    }

    func testNewsPrivacyWallPausesWithoutPretendingContentWasRead() {
        let app = launch(["--ui-testing-live-news", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 35))
        let status = app.staticTexts["web.result"]
        XCTAssertTrue(status.label.contains("privacy"), status.label)
        let remaining = app.staticTexts["web.remaining"].label
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.staticTexts["web.remaining"].label, remaining)
        attach("automation-real-news-privacy-choice", app)
        app.buttons["web.close"].tap()
        reveal(app)
        XCTAssertTrue(app.buttons["morning.playback"].exists)
        XCTAssertTrue(app.staticTexts["morning.currentStep"].label.contains("Le Monde"))
        attach("automation-blocked-moment-preserved", app)
    }

    func testPublicFeedBrowsesAndPauseResumesSameMoment() {
        let app = launch(["--ui-testing-public-feed", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 20))
        let status = app.staticTexts["web.result"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*· [1-9][0-9]* contents viewed.*"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 40), .completed)
        attach("automation-real-public-feed", app)
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        let remaining = app.staticTexts["web.remaining"].label
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.staticTexts["web.remaining"].label, remaining)
        attach("automation-real-public-feed-paused", app)
        app.buttons["web.resume"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.reddit.com")
        attach("automation-real-public-feed-resumed", app)
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
        if !begin.exists && !app.staticTexts["morning.complete"].exists && !app.buttons["morning.playback"].exists {
            let actions = app.buttons["morning.actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        }
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
