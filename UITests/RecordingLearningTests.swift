import XCTest

/// Owner-assisted hardware test. The person confirms Apple's picker; XCTest never grants access.
@MainActor
final class RecordingLearningTests: XCTestCase {
    func testOwnerApprovedShortRecordingProducesReviewableText() throws {
        guard ProcessInfo.processInfo.environment["MO_RECORDING_TEST_ENABLED"] == "1" else {
            throw XCTSkip("Enable this owner-assisted recording test explicitly; the person must confirm Apple's picker.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode"]
        app.launch()
        tap("learn.refine", in: app)
        tap("learn.record", in: app)
        tap("record.start", in: app)
        // The owner chooses app-only content for this short, synthetic test.
        let stop = app.buttons["record.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 180), "The owner must confirm Apple's picker, and recording must actually start.")
        let elapsed = expectation(description: "Record a short visible sample")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 8)
        stop.tap()
        let use = app.buttons["record.use"]
        XCTAssertTrue(use.waitForExistence(timeout: 35), "Stop must finalize a usable local file.")
        attach("recording-ready-for-review", app: app)
        use.tap()
        let notes = app.textViews["learn.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        let extracted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let text = notes.value as? String else { return false }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20
        }, object: notes)
        XCTAssertEqual(XCTWaiter.wait(for: [extracted], timeout: 90), .completed,
                       "The actual recording must yield reviewable Vision OCR text; no fixture fallback.")
        attach("recording-extracted-text-needs-review", app: app)
        XCTAssertTrue(app.buttons["learn.analyze"].exists, "Extraction does not generate or approve a routine by itself.")
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        for _ in 0..<5 where !button.isHittable {
            let sheet = app.scrollViews.containing(.textView, identifier: "learn.notes").firstMatch
            if sheet.exists { sheet.swipeUp() } else { app.scrollViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    private func attach(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
