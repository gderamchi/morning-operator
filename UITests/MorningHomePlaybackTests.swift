import XCTest

/// Isolated timed moments and local speech; no personal account or recording.
@MainActor
final class MorningHomePlaybackTests: XCTestCase {
    private let longPassage = "Take your time this morning. Let the light come into the room while you take a slow breath and prepare for the day ahead. There is nothing to press while MORE reads this passage. You can keep getting ready and return whenever you want to read along. Each passage should replace the one being spoken before it. Your routine stays here on the same home screen. If you need a little longer, a tap makes the small controls available. When this quiet moment ends, MORE will continue with the next part of your morning."

    func testHomeShowsOnlyCurrentTextAndContinuesAutomatically() {
        let app = launch(["--ui-testing-short-budgets"], night: true)
        defer { app.terminate() }
        start(app)
        assertCaption("Take a breath.", in: app)
        assertPureReading(app)
        attach("home-playback-only-current-text", app)

        assertCaption("Your next moment.", in: app, timeout: 15)
        assertPureReading(app)
        attach("home-playback-automatic-next-text", app)
    }

    func testFrenchLargestTextRevealsPauseAndNextWithOneTap() {
        let app = launch(["--ui-testing-reduce-motion", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"], french: true, night: true)
        defer { app.terminate() }
        start(app)
        assertPureReading(app)
        assertFitsOnScreen(app.staticTexts["morning.caption"], in: app)
        attach("home-playback-french-largest-pure-text", app)
        revealControls(app)
        for identifier in ["morning.playback", "morning.next", "morning.more"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable)
            assertFitsOnScreen(button, in: app)
        }
        XCTAssertEqual(app.buttons["morning.next"].label, "Suivant")
        app.buttons["morning.playback"].tap()
        assertPlaybackLabel("Continuer", in: app)
        attach("home-playback-french-largest-revealed-controls", app)
        app.buttons["morning.next"].tap()
        assertCaption("Your next moment.", in: app)
        assertNoHeaderOrHistory(app)
    }

    func testControlsHideAfterInactivityAndInteractionRestartsTheirLifetime() {
        let app = launch()
        defer { app.terminate() }
        start(app)
        revealControls(app)
        let playback = app.buttons["morning.playback"]
        assertRemainsVisible(playback, for: 3)
        playback.tap()
        assertPlaybackLabel("Continue", in: app)
        assertRemainsVisible(playback, for: 3)
        XCTAssertTrue(playback.waitForNonExistence(timeout: 7), "Controls must disappear after inactivity.")
        assertPureReading(app)
        attach("home-playback-controls-hidden-after-inactivity", app)
        revealControls(app)
        assertPlaybackLabel("Continue", in: app)
    }

    func testRealLocalSpeechReplacesTheSingleCaptionWithoutHistory() {
        let app = launch(["--ui-testing-read-aloud"], night: true)
        defer { app.terminate() }
        let configured = setFirstMomentDetails(longPassage, in: app)
        start(app)
        let caption = app.staticTexts["morning.caption"]
        let firstPassage = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "label CONTAINS %@ AND label.length < %d", "Take your time this morning", configured.count), object: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [firstPassage], timeout: 15), .completed)
        let first = caption.label
        XCTAssertLessThan(first.count, configured.count)
        assertPureReading(app)
        attach("home-playback-real-speech-first-passage", app)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", first), object: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 35), .completed)
        XCTAssertFalse(caption.label.isEmpty)
        XCTAssertLessThan(caption.label.count, configured.count)
        assertPureReading(app)
        attach("home-playback-real-speech-replaced-passage", app)
    }

    private func launch(_ flags: [String] = [], french: Bool = false, night: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
            "--ui-testing-automation", "--ui-testing-hands-free", "--ui-testing-workspace=\(workspace)",
            night ? "--dark-preview" : "--light-preview", night ? "--theme-phase=night" : "--theme-phase=morning",
            "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US"] + flags
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(marker.value as? String, workspace)
        return app
    }

    private func start(_ app: XCUIApplication) {
        let actions = app.buttons["morning.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.tap()
        let begin = app.buttons["morning.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()
        XCTAssertTrue(app.staticTexts["morning.caption"].waitForExistence(timeout: 8))
    }

    private func revealControls(_ app: XCUIApplication) {
        let reveal = app.scrollViews["morning.captions"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        reveal.tap()
        XCTAssertTrue(app.buttons["morning.playback"].waitForExistence(timeout: 5))
    }

    private func setFirstMomentDetails(_ text: String, in app: XCUIApplication) -> String {
        app.buttons["morning.actions"].tap()
        let review = app.buttons["morning.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        let first = app.buttons["routine.step.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Step details")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        details.typeText(text)
        let configured = details.value as? String ?? ""
        XCTAssertTrue(configured.contains(text))
        app.buttons["step.save"].tap()
        let approve = app.buttons["routine.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        approve.tap()
        if app.buttons["destination.close"].exists { app.buttons["destination.close"].tap() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 5))
        return configured
    }

    private func assertPureReading(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.scrollViews["morning.captions"].exists, file: file, line: line)
        XCTAssertEqual(app.staticTexts.matching(identifier: "morning.caption").count, 1, file: file, line: line)
        for identifier in ["morning.playback", "morning.next", "morning.more", "morning.closeActions"] {
            XCTAssertFalse(app.buttons[identifier].exists, "Reading keeps controls hidden: \(identifier)", file: file, line: line)
        }
        assertNoHeaderOrHistory(app, file: file, line: line)
        XCTAssertFalse(app.textViews["mail.selfBody"].exists, file: file, line: line)
        XCTAssertEqual(app.navigationBars.count, 0, file: file, line: line)
    }

    private func assertNoHeaderOrHistory(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for identifier in ["morning.currentStep", "morning.remaining", "morning.previousCaption"] {
            XCTAssertFalse(app.staticTexts[identifier].exists, "Home keeps only the current passage: \(identifier)", file: file, line: line)
        }
    }

    private func assertCaption(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 5,
                               file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text),
                                                object: app.staticTexts["morning.caption"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: timeout), .completed, file: file, line: line)
    }

    private func assertPlaybackLabel(_ label: String, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label),
                                                object: app.buttons["morning.playback"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, file: file, line: line)
    }

    private func assertRemainsVisible(_ element: XCUIElement, for seconds: TimeInterval,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        disappeared.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: seconds), .completed, file: file, line: line)
    }

    private func assertFitsOnScreen(_ element: XCUIElement, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY, file: file, line: line)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
