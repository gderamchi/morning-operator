import XCTest

/// Isolated synthetic data; no personal recording or external-account access.
@MainActor
final class QuietMorningTests: XCTestCase {
    func testFirstUseIsOneScreenWithOnlyMorningAndReview() {
        let app = launch(["--ui-testing-empty-workspace"])
        XCTAssertTrue(app.buttons["learn.begin"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["learn.begin"].isHittable)
        XCTAssertTrue(app.buttons["routine.sample"].isHittable)
        XCTAssertEqual(app.tabBars.buttons.count, 2)
        XCTAssertTrue(app.tabBars.buttons["Morning"].exists)
        XCTAssertTrue(app.tabBars.buttons["Review"].exists)
        XCTAssertFalse(app.tabBars.buttons["Notes"].exists)
        XCTAssertFalse(app.buttons["navigation.setup"].exists)
        XCTAssertFalse(app.buttons["observation.review"].exists)
        XCTAssertEqual(app.scrollViews.count, 0, "Default phone first use must fit without vertical scrolling.")
        attach("more-first-use-one-screen", app)
    }

    func testTenMomentMorningFitsWithoutScrollingOrEditing() {
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        let start = app.buttons["run.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isHittable)
        let last = app.otherElements["morning.step.9"]
        XCTAssertTrue(last.exists || app.staticTexts["morning.step.9"].exists)
        let row = last.exists ? last : app.staticTexts["morning.step.9"]
        XCTAssertTrue(row.isHittable, "The tenth item must be on screen before any scroll.")
        XCTAssertEqual(app.scrollViews.count, 0)
        XCTAssertFalse(app.buttons["routine.step.0"].exists, "Morning rows must not open editing.")
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        XCTAssertFalse(app.buttons["navigation.setup"].exists)
        attach("more-ten-moments-one-screen", app)
        app.buttons["morning.update"].tap()
        XCTAssertTrue(app.buttons["routine.step.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Review"].isSelected)
    }

    func testDraftApprovalBelongsToReviewAndDateOpensHistory() {
        let app = launch([])
        let review = app.buttons["morning.reviewDraft"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertTrue(review.isHittable)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        review.tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.step.0"].exists)
        attach("more-review-routine-editor", app)
        app.buttons["routine.approve"].tap()
        // Approval closes the review editor and returns to the one-action morning.
        let morning = app.tabBars.buttons["Morning"]
        if morning.isHittable { morning.tap() }
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
        app.buttons["morning.date"].tap()
        XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["navigation.setup"].exists)
        attach("more-weekly-review", app)
    }

    func testActiveMomentKeepsInstructionsAvailableWithoutEditing() {
        let app = launch(["--ui-testing-approved", "--fixture-mode"])
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 10))
        app.buttons["run.start"].tap()
        app.buttons["run.controls"].tap()
        app.buttons["run.about"].tap()
        let instructions = app.staticTexts["run.detail"]
        XCTAssertTrue(instructions.waitForExistence(timeout: 5))
        XCTAssertEqual(instructions.label, "Take a breath. Let your morning begin at your own pace.")
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        app.navigationBars["This moment"].buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["run.step"].label, "A calm start")
        XCTAssertTrue(app.buttons["run.pause"].isHittable)
    }

    func testDarkTenMomentMorningRemainsOneScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--dark-preview", "--ui-testing-ten-moments", "--ui-testing-approved"]
        app.launch()
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["run.start"].isHittable)
        XCTAssertEqual(app.scrollViews.count, 0)
        attach("more-ten-moments-dark", app)
    }

    func testTenActiveMomentsKeepPauseAndLastItemOnOneScreen() {
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 10))
        app.buttons["run.start"].tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["run.pause"].isHittable)
        let item = app.otherElements["morning.step.9"].exists
            ? app.otherElements["morning.step.9"] : app.staticTexts["morning.step.9"]
        XCTAssertTrue(item.isHittable)
        XCTAssertEqual(app.scrollViews.count, 0)
        attach("more-ten-active-moments-one-screen", app)
    }

    func testVoiceEntryPausesBeforeListeningAndKeepsTouchFallback() {
        let app = launch(["--ui-testing-approved", "--fixture-mode"])
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 10))
        app.buttons["run.start"].tap()
        app.buttons["run.controls"].tap()
        app.buttons["run.speakCommand"].tap()
        XCTAssertTrue(app.buttons["voiceCommand.listen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["voiceCommand.listen"].isHittable)
        XCTAssertEqual(app.alerts.count, 0, "Opening the command sheet must not request microphone access.")
        attach("more-explicit-voice-turn-before-permission", app)
        app.buttons["voiceCommand.close"].tap()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["run.step"].label, "A calm start")
        app.buttons["run.resume"].tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["run.step"].label, "A calm start")
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--light-preview"] + arguments
        app.launch()
        return app
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Run separately with the simulator's content_size set to an accessibility size.
@MainActor
final class QuietMorningAccessibilityTests: XCTestCase {
    func testLargeTextKeepsStartAndFullMomentDetailsReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-approved", "--fixture-mode"]
        app.launch()
        let scroll = app.scrollViews["morning.accessibleScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "This check requires actual accessibility text size.")
        let start = app.buttons["run.start"]
        for _ in 0..<8 where !start.isHittable { scroll.swipeUp() }
        XCTAssertTrue(start.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "more-accessibility-start-reachable"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        start.tap()
        let controls = app.buttons["run.controls"]
        for _ in 0..<8 where !controls.isHittable { scroll.swipeUp() }
        XCTAssertTrue(controls.isHittable)
        controls.tap()
        app.buttons["run.about"].tap()
        XCTAssertTrue(app.staticTexts["run.detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        app.navigationBars["This moment"].buttons["Done"].tap()
        controls.tap()
        app.buttons["run.stop"].tap()
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
    }
}
