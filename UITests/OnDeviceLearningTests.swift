import XCTest

/// Attempts real Foundation Models inference on the selected test device using only synthetic notes.
/// This is separate from deterministic fixture checks: model unavailability is an explicit skip.
@MainActor
final class OnDeviceLearningTests: XCTestCase {
    /// This validates a deterministic evidence guard. It does not claim model inference.
    func testSetupOnlyRecordingDoesNotReplaceTheExistingRoutine() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        app.launch()
        let sampleLabel = app.staticTexts["routine.source"]
        XCTAssertTrue(sampleLabel.waitForExistence(timeout: 10))
        let originalSource = sampleLabel.label
        MorningUITestNavigation.reviewAction("review.learn", in: app)
        let notes = app.textViews["learn.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        revealNotes(in: app)
        XCTAssertEqual(notes.value as? String ?? "", "")
        let observation = """
        [User-selected video: 00:40.3; 3 frames sampled. This is partial visual evidence, not a complete interaction log.]

        [Observed frame at 00:00.0]
        Screen Sharing
        Morning Operator
        Share Screen
        Cancel

        [Observed frame at 00:10.0]
        Less handling. More morning.
        The briefing. The messages. That game of chess. Let's make space for the things you care about.
        Learn my morning

        [Observed frame at 00:20.0]
        App Library
        Suggestions
        Recently Added
        Social
        Entertainment
        """
        notes.tap()
        notes.typeText(observation)
        XCTAssertEqual(notes.value as? String, observation)
        if app.buttons["input.done"].waitForExistence(timeout: 2) { app.buttons["input.done"].tap() }
        let analyze = app.buttons["learn.analyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        guard analyze.isEnabled else {
            throw XCTSkip("The UI analysis action is unavailable on this device; the evidence guard was not exercised through the UI.")
        }
        tapButton("learn.analyze", in: app)
        let message = "Not enough activity evidence yet. Show a real activity or describe what you did; setup screens, sharing controls and app lists do not establish a routine."
        let insufficientEvidence = app.staticTexts.matching(NSPredicate(format: "label == %@", message)).firstMatch
        XCTAssertTrue(insufficientEvidence.waitForExistence(timeout: 15))
        XCTAssertTrue(notes.exists, "Insufficient evidence must leave the observation available to review.")
        XCTAssertEqual(notes.value as? String, observation)
        attachScreenshot("setup-only-observation-rejected", from: app)
        app.navigationBars["Learn my morning"].buttons["Done"].tap()
        MorningUITestNavigation.selectTab("Morning", in: app)
        XCTAssertTrue(sampleLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(sampleLabel.label, originalSource, "An insufficient recording must not replace the existing routine.")
        XCTAssertFalse(app.buttons["run.start"].exists)
        attachScreenshot("setup-only-observation-preserves-routine", from: app)
    }

    func testAvailableLocalModelProducesANewUnapprovedRoutine() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        app.launch()

        let sampleLabel = app.staticTexts["routine.source"]
        XCTAssertTrue(sampleLabel.waitForExistence(timeout: 10), "Start from the explicitly synthetic sample.")
        attachScreenshot("learning-synthetic-start", from: app)
        MorningUITestNavigation.reviewAction("review.learn", in: app)

        let notes = app.textViews["learn.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        revealNotes(in: app)
        XCTAssertTrue(notes.isEnabled, "The isolated fixture must not have an active run or analysis.")
        // Fixture launches create a fresh workspace. Refuse to append to unexpected prior content.
        XCTAssertEqual((notes.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines), "")
        notes.tap()
        let observation = "I check today's calendar for three minutes, then play chess for ten minutes. Keep chess as a ritual."
        notes.typeText(observation)
        XCTAssertEqual(notes.value as? String, observation)
        let dismissKeyboard = app.buttons["input.done"]
        if dismissKeyboard.waitForExistence(timeout: 2) { dismissKeyboard.tap() }

        let analyze = app.buttons["learn.analyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: analyze)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            attachScreenshot("learning-skipped-model-unavailable", from: app)
            throw XCTSkip("Actual on-device learning was not run: Suggest a routine is disabled after valid synthetic input in an idle fixture. The local model is unavailable; no generated result is claimed.")
        }

        tapButton("learn.analyze", in: app)
        // Generation is asynchronous and hardware-dependent. An enabled attempt that fails or
        // times out is a test failure, not a model-unavailable skip or a fixture fallback.
        let sheetDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notes)
        let generationResult = XCTWaiter.wait(for: [sheetDismissed], timeout: 120)
        attachScreenshot("learning-generation-outcome", from: app)
        XCTAssertEqual(generationResult, .completed, "Real inference must return a new draft and dismiss Learn within 120 seconds.")
        XCTAssertTrue(app.buttons["morning.reviewDraft"].waitForExistence(timeout: 5), "A generated routine must return as a draft to review.")
        XCTAssertFalse(sampleLabel.exists, "Successful generation must replace the sample label; a fixture is not an inference result.")
        XCTAssertFalse(app.buttons["run.start"].exists, "Generation must not approve or start the routine.")
        XCTAssertFalse(notes.exists)
        MorningUITestNavigation.openRoutine(in: app)
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5), "A generated routine must still require approval in Review.")
        XCTAssertFalse(app.staticTexts["routine.source"].exists, "The editor must not present the synthetic sample as learned evidence.")
        XCTAssertTrue(app.buttons["routine.step.0"].exists, "The new draft must contain a visible first step.")
        attachScreenshot("learning-generated-draft-needs-approval", from: app)
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) {
        MorningUITestNavigation.tapButton(identifier, in: app, file: file, line: line)
    }

    private func revealNotes(in app: XCUIApplication) {
        let notes = app.textViews["learn.notes"]
        let sheet = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
        XCTAssertTrue(sheet.exists, "The editor must belong to the active Learn sheet.")
        for _ in 0..<4 where !notes.isHittable { sheet.swipeUp() }
        XCTAssertTrue(notes.isHittable, "The observation editor must be visible before typing.")
    }

    private func attachScreenshot(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
