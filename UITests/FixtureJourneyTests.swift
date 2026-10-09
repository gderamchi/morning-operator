import XCTest

/// Exercises only Morning Operator's synthetic fixture, never an external inbox.
@MainActor
final class FixtureJourneyTests: XCTestCase {
    func testApproveRunPauseResumeAndStop() throws {
        let app = launchFixture()
        attachScreenshot("fixture-initial-timeline-before-approval", from: app)

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

        tapButton("run.controls", in: app)
        tapButton("run.stop", in: app)
        assertState("stopped", in: app)
        XCTAssertTrue(app.buttons["run.start"].exists, "A stopped routine should offer an explicit restart.")
        attachScreenshot("fixture-stopped", from: app)
    }

    func testDreamIsSavedLocallyAndRetainedAcrossTabNavigation() throws {
        let app = launchFixture()
        let dream = "I dreamed of a blue library above the sea."

        selectTab("Notes", in: app)
        tapButton("capture.open", in: app)
        tapButton("capture.kind.dream", in: app)
        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(dream)
        XCTAssertEqual(accessibleText(editor), dream)
        let dismissKeyboard = app.buttons["input.done"]
        if dismissKeyboard.waitForExistence(timeout: 2) { dismissKeyboard.tap() }

        let save = app.buttons["capture.save"]
        XCTAssertEqual(save.label, "Save my dream", "This fixture must use the local dream path, not a system write.")
        XCTAssertFalse(app.buttons["Add to Reminders"].exists)
        XCTAssertFalse(app.buttons["Add to Calendar"].exists)
        tapButton("capture.save", in: app)
        waitFor(editor, exists: false)
        XCTAssertTrue(app.staticTexts[dream].waitForExistence(timeout: 5))

        // Filtering verifies that the capture was saved as a dream, not merely echoed in the editor.
        tapButton("capture.filter.thought", in: app)
        waitFor(app.staticTexts[dream], exists: false)
        tapButton("capture.filter.dream", in: app)
        XCTAssertTrue(app.staticTexts[dream].waitForExistence(timeout: 5))
        selectTab("Morning", in: app)
        selectTab("Notes", in: app)
        XCTAssertTrue(app.staticTexts[dream].waitForExistence(timeout: 5), "The saved dream must survive leaving its screen.")
        XCTAssertEqual(app.alerts.count, 0, "Local capture must not request external permissions.")
        attachScreenshot("fixture-local-dream", from: app)
    }

    func testSwipingToAnEmptyDayDoesNotInventMorningHistory() throws {
        let app = launchFixture()
        let yesterday = app.buttons["history.day.-1"]
        let today = app.buttons["history.day.0"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isSelected)

        let morning = app.scrollViews.firstMatch
        XCTAssertTrue(morning.exists)
        morning.swipeRight()
        waitForSelection(yesterday)
        XCTAssertTrue(app.staticTexts["A little space in your story."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["routine.approve"].exists, "An empty past day must not show today's draft as history.")
        XCTAssertFalse(app.buttons["run.start"].exists)
        attachScreenshot("fixture-empty-history-day", from: app)

        morning.swipeLeft()
        waitForSelection(today)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A little space in your story."].exists)
    }

    func testEditedDraftRestoresApprovedRoutineAndRunningSessionRecoversAfterRelaunch() throws {
        let app = launchFixture(workspaceID: UUID())
        tapButton("routine.approve", in: app)
        tapButton("routine.step.0", in: app)

        let name = app.textFields["Step name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let originalName = accessibleText(name)
        XCTAssertFalse(originalName.isEmpty)
        name.tap()
        // Insert a harmless marker instead of relying on localized selection menus.
        name.typeText(" test revision")
        let editedName = accessibleText(name)
        XCTAssertNotEqual(editedName, originalName)
        XCTAssertTrue(editedName.contains("test revision"))
        tapButton("Save", in: app)
        waitFor(name, exists: false)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["run.start"].exists, "Editing an approved version creates a draft that cannot start yet.")
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains(editedName))

        // Reuse only this test's UUID under the application's temporary fixture directory.
        // Relaunch must load the existing draft and retained approved version rather than reseed.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains(editedName), "The edited draft must survive relaunch.")
        XCTAssertTrue(app.buttons["routine.restore"].exists, "The previous approved version must also survive relaunch.")
        attachScreenshot("fixture-persisted-draft-before-restore", from: app)
        tapButton("routine.restore", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains(originalName))
        XCTAssertFalse(app.buttons["routine.step.0"].label.contains("test revision"))
        XCTAssertFalse(app.buttons["routine.approve"].exists)

        tapButton("run.start", in: app)
        tapButton("run.next", in: app)
        assertState("running", in: app)
        let interruptedStep = stepTitle(in: app)
        XCTAssertFalse(interruptedStep.isEmpty)
        app.terminate()
        app.launch()
        assertState("paused", in: app)
        XCTAssertEqual(stepTitle(in: app), interruptedStep, "Reopening must preserve the current step and require explicit continuation.")
        XCTAssertTrue(app.buttons["run.resume"].exists)
        attachScreenshot("fixture-recovered-paused-session", from: app)
        tapButton("run.resume", in: app)
        assertState("running", in: app)
        XCTAssertEqual(stepTitle(in: app), interruptedStep)
        tapButton("run.controls", in: app)
        tapButton("run.stop", in: app)
        assertState("stopped", in: app)
    }

    private func launchFixture(workspaceID: UUID? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Each launch uses an isolated temporary workspace and disables speech/automatic progression.
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        if let workspaceID { app.launchArguments.append("--ui-testing-workspace=\(workspaceID.uuidString)") }
        app.launch()
        return app
    }

    private func selectTab(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing native tab: \(title)", file: file, line: line)
        XCTAssertTrue(tab.isHittable, file: file, line: line)
        tab.tap()
    }

    private func attachScreenshot(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitFor(_ element: XCUIElement, exists: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == %@", NSNumber(value: exists)), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func waitForSelection(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
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
