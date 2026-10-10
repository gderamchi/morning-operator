import XCTest

/// Isolated synthetic routine only. These checks do not start recording or grant permissions.
@MainActor
final class SunriseDockTests: XCTestCase {
    func testCenteredSunriseExpandsToFourActionsAndBackgroundDismisses() {
        let app = launch(approved: true)
        let sunrise = app.buttons["morning.actions"]
        XCTAssertTrue(sunrise.waitForExistence(timeout: 10))
        XCTAssertEqual(sunrise.frame.midX, app.frame.midX, accuracy: 3)
        XCTAssertGreaterThanOrEqual(sunrise.frame.width, 64)
        XCTAssertGreaterThan(sunrise.frame.minY, app.frame.height * 0.65)
        XCTAssertFalse(app.buttons["run.start"].exists)
        attach("more-centered-sunrise", app)
        sunrise.tap()
        let identifiers = ["run.start", "morning.learn", "morning.review", "morning.settings"]
        let actions = identifiers.map { app.buttons[$0] }
        for action in actions { XCTAssertTrue(action.waitForExistence(timeout: 5)); XCTAssertTrue(action.isHittable) }
        XCTAssertEqual(actions.map(\.label), ["Play", "Learn", "History", "Settings"])
        XCTAssertFalse(app.buttons["morning.update"].exists)
        XCTAssertEqual(app.popovers.count, 0, "The dock expands in place, without a popover.")
        for action in actions.dropFirst() { XCTAssertEqual(action.frame.midY, actions[0].frame.midY, accuracy: 3) }
        XCTAssertLessThan(actions[0].frame.midX, actions[1].frame.midX)
        XCTAssertLessThan(actions[1].frame.midX, actions[2].frame.midX)
        XCTAssertLessThan(actions[2].frame.midX, actions[3].frame.midX)
        attach("more-horizontal-sunrise-actions", app)
        app.buttons["morning.closeActions"].tap()
        XCTAssertTrue(sunrise.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run.start"].exists)
        XCTAssertTrue(app.buttons["morning.date"].isHittable)
    }

    func testDockPlayPauseContinueAndLearnSettingsRoutes() {
        let app = launch(approved: true)
        reveal("morning.learn", in: app)
        app.buttons["morning.learn"].tap()
        XCTAssertTrue(app.navigationBars["Learn my morning"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        app.navigationBars["Learn my morning"].buttons["Done"].tap()
        reveal("morning.settings", in: app)
        app.buttons["morning.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars["Settings"].buttons["Done"].tap()
        reveal("run.start", in: app)
        app.buttons["run.start"].tap()
        XCTAssertTrue(app.staticTexts["morning.ready"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run.pause"].exists, "Play opens a ready state; it must not begin automatically.")
        app.buttons["morning.cancelStart"].tap()
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
        app.buttons["run.start"].tap()
        XCTAssertTrue(app.buttons["morning.confirmStart"].waitForExistence(timeout: 5))
        app.buttons["morning.confirmStart"].tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        reveal("morning.playback", in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Pause")
        XCTAssertFalse(app.buttons["morning.learn"].isEnabled)
        app.buttons["morning.playback"].tap()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 5))
        reveal("morning.playback", in: app)
        XCTAssertEqual(app.buttons["morning.playback"].label, "Continue")
        app.buttons["morning.playback"].tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testDraftDockOpensReviewWithoutStartingOrApproving() {
        let app = launch(approved: false)
        reveal("morning.reviewDraft", in: app)
        XCTAssertEqual(app.buttons["morning.reviewDraft"].label, "Review")
        XCTAssertFalse(app.buttons["run.start"].exists)
        app.buttons["morning.reviewDraft"].tap()
        XCTAssertTrue(app.navigationBars["Your routine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.approve"].exists)
        XCTAssertFalse(app.buttons["run.pause"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func launch(approved: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview",
                               "--ui-testing-workspace=\(UUID().uuidString)"]
        if approved { app.launchArguments.append("--ui-testing-approved") }
        app.launch()
        return app
    }

    private func reveal(_ identifier: String, in app: XCUIApplication) {
        let sunrise = app.buttons["morning.actions"]
        XCTAssertTrue(sunrise.waitForExistence(timeout: 5))
        sunrise.tap()
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[identifier].isHittable)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
