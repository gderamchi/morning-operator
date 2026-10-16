import XCTest

/// Phone-only spike (docs/SEAMLESS-LEARNING.md): counts MORE's own taps before Apple's
/// screen-sharing picker, and checks whether `more://watch-morning` reaches the picker with
/// no tap inside MORE. It never confirms the picker: that tap is the owner's. Debug build only.
/// Run with TEST_RUNNER_MO_SEAMLESS_SPIKE=1 on a phone with iOS 27.
@MainActor
final class SeamlessLearningSpikeTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["MO_SEAMLESS_SPIKE"] == "1" else {
            throw XCTSkip("Phone-only spike; set MO_SEAMLESS_SPIKE=1.")
        }
        continueAfterFailure = false
    }

    func testOrdinaryPathTapCountBeforeApplesPicker() throws {
        let app = launch()
        var taps = 0
        for identifier in ["morning.actions", "morning.learn", "learn.record", "record.start"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(identifier)")
            for _ in 0..<4 where !button.isHittable { app.swipeUp() }
            button.tap(); taps += 1
        }
        XCTAssertTrue(waitForPickerRequest(in: app), "Apple's picker was not requested after \(taps) taps.")
        print("MO-SPIKE ordinary path: \(taps) taps inside MORE, then Apple's picker")
        attachScreen("ordinary-path-picker")
        app.terminate()
    }

    func testWatchMorningURLRequestsPickerWithoutATapInsideMORE() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 15))
        app.open(URL(string: "more://watch-morning")!)
        let requested = waitForPickerRequest(in: app)
        attachScreen("watch-morning-url")
        print("MO-SPIKE watch-morning URL: picker requested=\(requested), taps inside MORE=0")
        XCTAssertTrue(requested, "The URL did not reach Apple's picker without a tap.")
        app.terminate()
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--light-preview"]
        app.launch()
        return app
    }

    /// The app's own "choosing" message shows the picker was requested. Whether Apple's sheet
    /// is visible on top is read from the screenshot, not from this predicate.
    private func waitForPickerRequest(in app: XCUIApplication) -> Bool {
        let choosing = app.buttons["Cancel recording request"]
        let message = app.staticTexts["Confirm screen sharing in the system picker to begin."]
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if choosing.exists || message.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
