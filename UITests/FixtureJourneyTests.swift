import XCTest

/// An opt-in audible device check. A passing callback check is not listener confirmation.
@MainActor
final class VoicePlaybackTests: XCTestCase {
    func testSpokenRoutineStepAdvancesOnlyAfterPlayback() throws {
        guard ProcessInfo.processInfo.environment["MO_VOICE_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Opt in before playing a sample routine on the selected phone.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        app.launch()
        let settings = app.buttons["navigation.setup"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let readAloud = app.switches["setup.readAloud"]
        XCTAssertTrue(readAloud.waitForExistence(timeout: 5))
        let sheet = app.scrollViews.containing(.switch, identifier: "setup.readAloud").firstMatch
        for _ in 0..<4 where !readAloud.isHittable { sheet.swipeUp() }
        XCTAssertTrue(readAloud.isHittable)
        readAloud.tap()
        XCTAssertEqual(readAloud.value as? String, "1")
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.buttons["routine.approve"].tap()
        app.buttons["run.start"].tap()
        let step = app.staticTexts["run.step"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        XCTAssertEqual(step.label, "A calm start")
        // The first fixture step is a real spokenNote operation; the next is manual.
        // Enabling automatic progression dispatches the production speech executor.
        let handsFree = app.switches["Hands free"]
        XCTAssertTrue(handsFree.waitForExistence(timeout: 5))
        handsFree.tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "People and messages"), object: step)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 30), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "synthetic-routine-spoken-step-completed-manual-step-waiting"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["run.controls"].tap()
        app.buttons["run.stop"].tap()
        // Does not establish listener audibility, calendar access or cross-app narration.
    }

    func testSystemVoicePreviewStartsAndFinishes() throws {
        guard ProcessInfo.processInfo.environment["MO_VOICE_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Opt in before playing speech on the selected phone.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        app.launch()
        let settings = app.buttons["navigation.setup"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let preview = app.buttons["setup.testVoice"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let sheet = app.scrollViews.containing(.button, identifier: "setup.testVoice").firstMatch
        for _ in 0..<4 where !preview.isHittable { sheet.swipeUp() }
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        let status = app.staticTexts["setup.speechStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "speaking"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 5), .completed)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ AND label == %@", "idle", "Ready to speak"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 25), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "system-voice-preview-completed-listener-confirmation-separate"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// Exercises only Morning Operator's synthetic fixture, never an external inbox.
@MainActor
final class FixtureJourneyTests: XCTestCase {
    func testFirstUseCanStartLearningWithoutScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace", "--ui-testing-workspace=\(UUID().uuidString)"]
        app.launch()
        let begin = app.buttons["learn.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 10))
        XCTAssertTrue(begin.isHittable, "The first-use learning action must be available before any scroll.")
        attachScreenshot("first-use-learning-above-fold", from: app)
        begin.tap()
        XCTAssertTrue(app.navigationBars["Learn my morning"].waitForExistence(timeout: 5))
    }

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

    func testImportedObservationPersistsAndStaysClearedAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let expected = "[Synthetic UI-test observation]\nI check my calendar, drink water, and enjoy ten minutes of chess."
        app.launchArguments = ["--ui-testing", "--fixture-mode",
                               "--ui-testing-workspace=\(UUID().uuidString)",
                               "--ui-testing-import-observation"]
        app.launch()

        // The test hook imports a synthetic UTF-8 file while Learn is presented,
        // through the real async importer and the already-mounted observation editor.
        // This checks observation persistence; it does not exercise screen recording.
        openLearnAndAssertNotes(expected, in: app)
        attachScreenshot("synthetic-import-visible-notes", from: app)
        closeLearn(in: app)
        openLearnAndAssertNotes(expected, in: app)
        closeLearn(in: app)

        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-import-observation" }
        app.launch()
        openLearnAndAssertNotes(expected, in: app)
        attachScreenshot("synthetic-import-restored-without-reimport", from: app)

        let editor = app.textViews["learn.notes"]
        editor.tap()
        editor.typeText(" I also make tea.")
        let corrected = try XCTUnwrap(editor.value as? String)
        XCTAssertNotEqual(corrected, expected)
        XCTAssertTrue(corrected.contains("I also make tea."))
        closeLearn(in: app)
        app.terminate()
        app.launch()
        openLearnAndAssertNotes(corrected, in: app)
        attachScreenshot("corrected-observation-restored-after-relaunch", from: app)

        let clear = app.buttons["learn.clear"]
        let learnScroll = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
        for _ in 0..<3 where !clear.isHittable { learnScroll.swipeUp() }
        XCTAssertTrue(clear.isHittable)
        XCTAssertTrue(clear.isEnabled, "The async import must finish before clearing its saved text.")
        clear.tap()
        assertNotes("", in: app)
        XCTAssertFalse(clear.exists)
        app.terminate()
        app.launch()
        openLearnAndAssertNotes("", in: app)
        XCTAssertFalse(app.buttons["learn.clear"].exists, "Cleared text must not return from disk or a test reimport.")
        attachScreenshot("synthetic-import-cleared-after-relaunch", from: app)
    }

    private func openLearnAndAssertNotes(_ expected: String, in app: XCUIApplication) {
        tapButton("learn.refine", in: app)
        let editor = app.textViews["learn.notes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let learnScroll = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
        for _ in 0..<3 where !editor.isHittable { learnScroll.swipeUp() }
        XCTAssertTrue(editor.isHittable, "The extracted observation must be visible in Learn.")
        assertNotes(expected, in: app)
    }

    private func assertNotes(_ expected: String, in app: XCUIApplication) {
        let editor = app.textViews["learn.notes"]
        // UIKit may expose an empty editor as nil rather than the empty string.
        // Nonempty evidence still requires an exact match; disappearance of Clear
        // and the subsequent relaunch also verify the underlying saved state.
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (editor.value as? String ?? "") == expected
        }, object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
                       "Unexpected observation editor value: \(String(describing: editor.value))")
    }

    private func closeLearn(in app: XCUIApplication) {
        let done = app.navigationBars["Learn my morning"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        waitFor(app.textViews["learn.notes"], exists: false)
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
