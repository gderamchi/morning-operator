import XCTest

/// Exercises only Morning Operator's synthetic fixture, never an external inbox.
@MainActor
final class FixtureJourneyTests: XCTestCase {
    func testApproveRunPauseResumeAndStop() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        app.launch()

        tapButton("routine.approve", in: app)
        tapButton("run.start", in: app)
        assertState("running", in: app)
        let firstStep = stepTitle(in: app)
        XCTAssertFalse(firstStep.isEmpty)

        tapButton("run.next", in: app)
        let secondStep = stepTitle(in: app)
        XCTAssertFalse(secondStep.isEmpty)
        XCTAssertNotEqual(firstStep, secondStep, "Next must advance the actual fixture run.")

        tapButton("run.pause", in: app)
        assertState("paused", in: app)
        XCTAssertEqual(stepTitle(in: app), secondStep)
        tapButton("run.resume", in: app)
        assertState("running", in: app)
        XCTAssertEqual(stepTitle(in: app), secondStep, "Resuming must preserve the current item.")

        tapButton("run.stop", in: app)
        assertState("stopped", in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "fixture-stopped"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing fixture control: \(identifier)", file: file, line: line)
        for _ in 0..<3 where !button.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.isHittable, "Fixture control is not hittable: \(identifier)", file: file, line: line)
        button.tap()
    }

    private func assertState(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let state = app.staticTexts["run.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5), file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while accessibleText(state) != expected, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(accessibleText(state), expected, file: file, line: line)
    }

    private func stepTitle(in app: XCUIApplication) -> String {
        let step = app.staticTexts["run.step"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        return accessibleText(step)
    }

    private func accessibleText(_ element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }
}
