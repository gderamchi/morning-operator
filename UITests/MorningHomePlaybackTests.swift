import XCTest

/// Isolated timed moments; no account, recording or network access is exercised.
@MainActor
final class MorningHomePlaybackTests: XCTestCase {
    private let longPassage = "Take your time this morning. Let the light come into the room while you take a slow breath and prepare for the day ahead. There is nothing to press while MORE reads this passage. You can keep getting ready and return whenever you want to read along. The words should move gently through the landscape, leaving the previous passage visible above the one being spoken. Your routine stays here on the same home screen. If you need a little longer, the small controls remain available at the bottom. When this quiet moment ends, MORE will continue with the next part of your morning."

    func testRealLocalSpeechMovesCaptionsThroughLongEditedText() {
        let app = launch(["--ui-testing-read-aloud"])
        defer { app.terminate() }
        setFirstMomentDetails(longPassage, in: app)
        start(app)
        let caption = app.staticTexts["morning.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        let first = caption.label
        let previous = app.staticTexts["morning.previousCaption"].firstMatch
        XCTAssertTrue(previous.waitForExistence(timeout: 35), "A speech callback must move beyond the first passage.")
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", first), object: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        XCTAssertFalse(previous.label.isEmpty)
        XCTAssertFalse(caption.label.isEmpty)
        XCTAssertLessThan(caption.label.count, longPassage.count, "Spoken captions show the current passage, not the whole note.")
        assertStep("A quiet moment", in: app)
        assertHomePlayback(app)
        attach("home-playback-real-speech-long-text-second-passage", app)
    }

    func testLargestTextLongCaptionBeginsInViewAndScrollKeepsTransportReachable() {
        let app = launch(["--ui-testing-reduce-motion", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        setFirstMomentDetails(longPassage, in: app)
        start(app)
        app.buttons["morning.playback"].tap()
        assertPlaybackLabel("Continue", in: app)
        let caption = app.staticTexts["morning.caption"]
        let viewport = app.scrollViews["morning.captions"]
        XCTAssertEqual(caption.label, longPassage)
        XCTAssertGreaterThanOrEqual(caption.frame.minY, viewport.frame.minY)
        XCTAssertLessThan(caption.frame.minY, viewport.frame.maxY, "The beginning must be visible without scrolling backward.")
        attach("home-playback-largest-long-caption-start", app)
        let transport = app.buttons["morning.playback"].frame
        viewport.swipeUp()
        XCTAssertLessThan(caption.frame.minY, viewport.frame.minY, "The long passage must scroll independently.")
        XCTAssertEqual(app.buttons["morning.playback"].frame, transport)
        for identifier in ["morning.playback", "morning.next", "morning.more"] {
            XCTAssertTrue(app.buttons[identifier].isHittable)
            assertFitsOnScreen(app.buttons[identifier], in: app)
        }
        attach("home-playback-largest-long-caption-scrolled", app)
    }

    func testTimedMorningStaysOnHomeAndContinuesWithoutACompletionTap() {
        let app = launch(["--ui-testing-short-budgets"], night: true)
        defer { app.terminate() }
        start(app)
        assertStep("A quiet moment", in: app)
        assertHomePlayback(app)
        XCTAssertEqual(app.staticTexts["morning.caption"].label, "Take a breath.")
        attach("home-playback-night-first-caption", app)

        assertStep("Get ready", in: app, timeout: 15)
        assertHomePlayback(app)
        XCTAssertEqual(app.staticTexts["morning.caption"].label, "Your next moment.")
        attach("home-playback-night-automatic-next-caption", app)
    }

    func testHomeTransportPausesExtendsContinuesAndStopsTheSameRoutine() {
        let app = launch()
        defer { app.terminate() }
        start(app)
        assertStep("A quiet moment", in: app)
        app.buttons["morning.playback"].tap()
        assertPlaybackLabel("Continue", in: app)
        let remaining = app.staticTexts["morning.remaining"]
        let beforeLabel = remaining.label
        let before = remainingSeconds(in: app)
        app.buttons["morning.more"].tap()
        let extend = app.buttons["morning.extend"]
        XCTAssertTrue(extend.waitForExistence(timeout: 5))
        extend.tap()
        let extended = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", beforeLabel), object: remaining)
        XCTAssertEqual(XCTWaiter.wait(for: [extended], timeout: 5), .completed)
        XCTAssertEqual(remainingSeconds(in: app), before + 120)
        assertStep("A quiet moment", in: app)
        assertPlaybackLabel("Continue", in: app)
        attach("home-playback-paused-extended", app)

        app.buttons["morning.playback"].tap()
        assertPlaybackLabel("Pause", in: app)
        app.buttons["morning.next"].tap()
        assertStep("Get ready", in: app)
        assertHomePlayback(app)
        attach("home-playback-touch-next", app)
        app.buttons["morning.more"].tap()
        let stop = app.buttons["morning.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(app.buttons["morning.playback"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["morning.actions"].isHittable)
        XCTAssertTrue((app.buttons["morning.actions"].value as? String)?.hasPrefix("Morning stopped") == true)
        attach("home-playback-stopped-landscape", app)
    }

    func testInteractionsOpenOnlyFromTheSmallMenuAndReturnToHome() {
        let app = launch()
        defer { app.terminate() }
        start(app)
        assertHomePlayback(app)
        XCTAssertFalse(app.buttons["morning.closeDetails"].exists)
        app.buttons["morning.playback"].tap()
        assertPlaybackLabel("Continue", in: app)
        app.buttons["morning.more"].tap()
        let details = app.buttons["morning.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        let close = app.buttons["morning.closeDetails"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.navigationBars["A quiet moment"].exists)
        attach("home-playback-explicit-interaction", app)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        assertHomePlayback(app)
        assertStep("A quiet moment", in: app)
        assertPlaybackLabel("Continue", in: app)
        attach("home-playback-after-interaction", app)
    }

    func testFrenchLargestTextAndReducedMotionKeepCaptionsAndControlsReachable() {
        let app = launch(["--ui-testing-reduce-motion", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"], french: true, night: true)
        defer { app.terminate() }
        start(app)
        assertHomePlayback(app)
        for identifier in ["morning.currentStep", "morning.caption", "morning.remaining"] {
            let text = app.staticTexts[identifier]
            XCTAssertTrue(text.isHittable, "Largest text must remain readable: \(identifier)")
            assertFitsOnScreen(text, in: app)
        }
        for identifier in ["morning.playback", "morning.next", "morning.more"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable, "Largest text must keep the control reachable: \(identifier)")
            assertFitsOnScreen(button, in: app)
        }
        XCTAssertEqual(app.buttons["morning.next"].label, "Suivant")
        XCTAssertEqual(app.buttons["morning.more"].label, "Plus")
        app.buttons["morning.playback"].tap()
        assertPlaybackLabel("Continuer", in: app)
        attach("home-playback-french-largest-reduced-motion", app)
        app.buttons["morning.playback"].tap()
        assertPlaybackLabel("Pause", in: app)
        app.buttons["morning.next"].tap()
        assertStep("Get ready", in: app)
        assertHomePlayback(app)
        attach("home-playback-french-largest-next-caption", app)
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
        XCTAssertTrue(begin.isHittable)
        begin.tap()
        XCTAssertTrue(app.buttons["morning.playback"].waitForExistence(timeout: 8))
    }

    private func setFirstMomentDetails(_ text: String, in app: XCUIApplication) {
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
        let old = details.value as? String ?? ""
        details.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text)
        XCTAssertEqual(details.value as? String, text)
        app.buttons["step.save"].tap()
        let approve = app.buttons["routine.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        approve.tap()
        if app.buttons["destination.close"].exists { app.buttons["destination.close"].tap() }
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 5))
    }

    private func assertHomePlayback(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.scrollViews["morning.captions"].exists, file: file, line: line)
        XCTAssertTrue(app.staticTexts["morning.caption"].exists, file: file, line: line)
        XCTAssertTrue(app.buttons["morning.playback"].isHittable, file: file, line: line)
        XCTAssertTrue(app.buttons["morning.next"].isHittable, file: file, line: line)
        XCTAssertTrue(app.buttons["morning.more"].isHittable, file: file, line: line)
        XCTAssertFalse(app.buttons["morning.closeActions"].exists, "Playback must stay on the landscape.", file: file, line: line)
        XCTAssertFalse(app.textViews["mail.selfBody"].exists, file: file, line: line)
        XCTAssertFalse(app.textFields["mail.selfBody"].exists, file: file, line: line)
        XCTAssertEqual(app.navigationBars.count, 0, file: file, line: line)
    }

    private func assertStep(_ title: String, in app: XCUIApplication, timeout: TimeInterval = 5,
                            file: StaticString = #filePath, line: UInt = #line) {
        let step = app.staticTexts["morning.currentStep"]
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: step)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: timeout), .completed, file: file, line: line)
    }

    private func assertPlaybackLabel(_ label: String, in app: XCUIApplication,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label),
                                                object: app.buttons["morning.playback"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, file: file, line: line)
    }

    private func remainingSeconds(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Int {
        let remaining = app.staticTexts["morning.remaining"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 5), file: file, line: line)
        let parts = remaining.label.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2, "Expected minutes and seconds: \(remaining.label)", file: file, line: line)
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
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
