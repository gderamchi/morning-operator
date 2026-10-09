import XCTest

/// Attempts real Foundation Models inference on the selected test device using only synthetic notes.
/// This is separate from deterministic fixture checks: model unavailability is an explicit skip.
@MainActor
final class OnDeviceLearningTests: XCTestCase {
    func testAvailableLocalModelProducesANewUnapprovedRoutine() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        app.launch()

        let sampleLabel = app.staticTexts["routine.source"]
        XCTAssertTrue(sampleLabel.waitForExistence(timeout: 10), "Start from the explicitly synthetic sample.")
        attachScreenshot("learning-synthetic-start", from: app)
        tapButton("learn.refine", in: app)

        let notes = app.textViews["learn.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5), "A generated routine must still require approval.")
        XCTAssertFalse(sampleLabel.exists, "Successful generation must replace the sample label; a fixture is not an inference result.")
        XCTAssertFalse(app.buttons["run.start"].exists, "Generation must not approve or start the routine.")
        XCTAssertFalse(notes.exists)
        XCTAssertTrue(app.buttons["routine.step.0"].exists, "The new draft must contain a visible first step.")
        attachScreenshot("learning-generated-draft-needs-approval", from: app)
    }

    private func tapButton(_ identifier: String, in app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing learning control: \(identifier)", file: file, line: line)
        for _ in 0..<4 where !button.isHittable {
            if identifier == "learn.analyze" {
                let learnSheet = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
                XCTAssertTrue(learnSheet.exists, "Scroll the active Learn sheet rather than the background timeline.", file: file, line: line)
                learnSheet.swipeUp()
            } else {
                app.scrollViews.firstMatch.swipeUp()
            }
        }
        XCTAssertTrue(button.isHittable, "Learning control is not hittable: \(identifier)", file: file, line: line)
        button.tap()
    }

    private func attachScreenshot(_ name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
