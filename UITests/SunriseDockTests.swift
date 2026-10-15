import XCTest

/// Synthetic workspaces only. These checks never access an account, grant a
/// permission, record the screen, or replace the owner's saved morning.
@MainActor
final class SunriseDockTests: XCTestCase {
    func testArrivalShowsOnlyLandscapeAndTapRevealsReachableControls() {
        let app = launch()
        assertQuietArrival(in: app)
        attach("quiet-solar-day-arrival", app)

        reveal(in: app)
        for identifier in ["morning.settings", "morning.review", "morning.begin", "morning.closeActions"] {
            assertReachable(identifier, in: app)
        }
        XCTAssertFalse(app.buttons["morning.playback"].exists,
                       "Revealing controls must not start the saved morning.")
        XCTAssertEqual(app.tabBars.count, 0)
        attach("quiet-solar-day-controls", app)

        app.buttons["morning.closeActions"].tap()
        assertQuietArrival(in: app)
        app.buttons["morning.actions"].tap()
        assertReachable("morning.begin", in: app)
        app.buttons["morning.actions"].tap()
        assertQuietArrival(in: app)
    }

    func testRevealedSettingsAndSavedRoutineOpenTheirDestinations() {
        var app = launch()
        reveal(in: app)
        app.buttons["morning.settings"].tap()
        XCTAssertTrue(app.buttons["setup.briefing"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        app.terminate()

        app = launch()
        reveal(in: app)
        app.buttons["morning.review"].tap()
        let editor = app.descendants(matching: .any).matching(identifier: "routine.editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testEmptyWorkspaceRemainsQuietAndBothEntryActionsOpenLearning() {
        for identifier in ["morning.review", "morning.begin"] {
            let app = launch(empty: true)
            assertQuietArrival(in: app)
            reveal(in: app)
            assertReachable(identifier, in: app)
            app.buttons[identifier].tap()
            XCTAssertTrue(app.buttons["learn.import"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.buttons["morning.playback"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            app.terminate()
        }
    }

    func testSavedMorningCanBeginPauseContinueAndHideItsControls() {
        let app = launch()
        reveal(in: app)
        app.buttons["morning.begin"].tap()
        let playback = app.buttons["morning.playback"]
        XCTAssertTrue(playback.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["morning.currentStep"].exists, app.debugDescription)
        assertReachable("morning.next", in: app)
        XCTAssertEqual(playback.label, "Pause")
        playback.tap()
        XCTAssertEqual(playback.label, "Continue")
        playback.tap()
        XCTAssertEqual(playback.label, "Pause")
        attach("quiet-solar-running-controls", app)

        app.buttons["morning.closeActions"].tap()
        assertQuietArrival(in: app)
        reveal(in: app)
        assertReachable("morning.playback", in: app)
        assertReachable("morning.next", in: app)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testLandscapeAndControlsAcrossLocalDayPhases() {
        for phase in ["dawn", "morning", "day", "evening", "night"] {
            let app = launch(phase: phase)
            assertQuietArrival(in: app)
            attach("quiet-solar-\(phase)-arrival", app)
            reveal(in: app)
            for identifier in ["morning.settings", "morning.review", "morning.begin"] {
                assertReachable(identifier, in: app)
            }
            attach("quiet-solar-\(phase)-controls", app)
            app.terminate()
        }
    }

    func testFrenchLargestTextAndReducedMotionKeepControlsReachable() {
        let app = launch(phase: "night", extra: [
            "--ui-testing-reduce-motion", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        assertQuietArrival(in: app)
        attach("quiet-solar-night-fr-largest-reduced-motion", app)
        reveal(in: app)
        for identifier in ["morning.settings", "morning.review", "morning.begin", "morning.closeActions"] {
            assertReachable(identifier, in: app)
        }
        attach("quiet-solar-night-fr-largest-controls", app)
    }

    private func launch(phase: String = "day", empty: Bool = false, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--fixture-mode", "--ui-testing-briefing-fixture", "--theme-phase=\(phase)",
            "--ui-testing-workspace=\(UUID().uuidString)",
            empty ? "--ui-testing-empty-workspace" : "--ui-testing-approved"
        ] + extra
        if !extra.contains("-AppleLanguages") {
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        }
        app.launch()
        return app
    }

    private func assertQuietArrival(in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(landscape.isHittable, app.debugDescription, file: file, line: line)
        XCTAssertGreaterThanOrEqual(landscape.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(landscape.frame.height, 44, file: file, line: line)
        XCTAssertEqual(landscape.frame.midX, app.frame.midX, accuracy: 3, file: file, line: line)
        for identifier in ["morning.settings", "morning.review", "morning.begin", "morning.closeActions",
                           "morning.playback", "morning.next", "morning.date"] {
            XCTAssertFalse(app.buttons[identifier].exists, identifier, file: file, line: line)
        }
        XCTAssertFalse(app.staticTexts["morning.readyQuestion"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["morning.currentStep"].exists, file: file, line: line)
        XCTAssertEqual(app.tabBars.count, 0, file: file, line: line)
    }

    private func reveal(in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 10), file: file, line: line)
        landscape.tap()
        XCTAssertTrue(app.buttons["morning.closeActions"].waitForExistence(timeout: 5),
                      app.debugDescription, file: file, line: line)
    }

    private func assertReachable(_ identifier: String, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        let controls = app.scrollViews.firstMatch
        for _ in 0..<6 where !button.isHittable && controls.exists {
            if button.frame.midY < controls.frame.midY { controls.swipeDown() }
            else { controls.swipeUp() }
        }
        XCTAssertTrue(button.isHittable, app.debugDescription, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.width, 44, identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44, identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.minX, 0, identifier, file: file, line: line)
        XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX, identifier, file: file, line: line)
        XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.maxY, identifier, file: file, line: line)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            // Runner-local copies survive xcresult attachment export failures.
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let directory = documents.appendingPathComponent("MOREQuietSolarScreenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        } catch { XCTFail("Could not retain the synthetic home screenshot: \(error)") }
    }
}
