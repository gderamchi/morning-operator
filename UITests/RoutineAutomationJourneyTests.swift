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
        // XCTest considers a partly visible cell hittable even when its centre
        // falls under the pinned approval button. Bring the whole row into view.
        for _ in 0..<10 where !step.isHittable || step.frame.maxY > approve.frame.minY { app.swipeUp() }
        XCTAssertTrue(step.isHittable)
        XCTAssertLessThan(step.frame.midY, approve.frame.minY)
        XCTAssertTrue(step.label.contains("1 min"))
        attach("automation-french-largest-review", app)
        step.tap()
        let save = app.buttons["step.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isHittable)
        let duration = app.descendants(matching: .any).matching(identifier: "step.duration").firstMatch
        for _ in 0..<8 {
            if duration.exists && duration.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(duration.isHittable)
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
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*· ([2-9]|[1-9][0-9]+) contents viewed.*"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 40), .completed)
        attach("automation-real-public-feed", app)
        let beforeExtension = remainingSeconds(app.staticTexts["web.remaining"].label)
        app.buttons["web.extend"].tap()
        XCTAssertGreaterThan(remainingSeconds(app.staticTexts["web.remaining"].label), beforeExtension + 110)
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
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        let countBeforeClosing = observedContents(status.label)
        XCTAssertGreaterThanOrEqual(countBeforeClosing, 2)
        attach("automation-real-public-feed-before-close", app)
        app.buttons["web.close"].tap()
        reveal(app)
        XCTAssertTrue(app.buttons["morning.playback"].exists)
        app.buttons["morning.playback"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.reddit.com")
        XCTAssertEqual(observedContents(app.staticTexts["web.result"].label), countBeforeClosing)
        attach("automation-real-public-feed-reopened", app)
    }

    private func launch(_ flags: [String], french: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        let workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--light-preview", "--theme-phase=morning", "-AppleLanguages", french ? "(fr)" : "(en)",
            "-AppleLocale", french ? "fr_FR" : "en_US"] + flags
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) {
            // Xcode 27 sometimes prelaunches the first target without the test's
            // arguments. Verify the isolated workspace before touching any UI.
            app.terminate(); app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(marker.value as? String, workspace)
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
    private func remainingSeconds(_ label: String) -> Int {
        let components = label.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { XCTFail("Unexpected remaining time: \(label)"); return 0 }
        return components[0] * 60 + components[1]
    }
    private func observedContents(_ label: String) -> Int {
        let count = label.components(separatedBy: "·").last?
            .split(separator: " ").first.flatMap { Int($0) }
        guard let count else { XCTFail("Missing observed-content count: \(label)"); return 0 }
        return count
    }
}
