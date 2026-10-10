import XCTest

/// Isolated synthetic data; no personal recording or external-account access.
@MainActor
final class QuietMorningTests: XCTestCase {
    func testFirstUseKeepsLearningAndSunriseWithoutPermanentTabs() {
        let app = launch(["--ui-testing-empty-workspace"])
        XCTAssertTrue(app.buttons["learn.begin"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["learn.begin"].isHittable)
        XCTAssertTrue(app.buttons["routine.sample"].isHittable)
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertTrue(app.buttons["morning.actions"].isHittable)
        XCTAssertFalse(app.buttons["navigation.setup"].exists)
        XCTAssertFalse(app.buttons["observation.review"].exists)
        XCTAssertEqual(app.scrollViews.count, 0, "Default phone first use must fit without vertical scrolling.")
        attach("more-first-use-one-screen", app)
    }

    func testTenMomentTilesAndSunriseActionsFitWithoutScrolling() {
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["run.start"].exists, "The collapsed sunrise must not leave a large permanent start action.")
        let row = app.buttons["morning.step.9"]
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.isHittable, "The tenth item must be on screen before any scroll.")
        XCTAssertEqual(app.scrollViews.count, 0)
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertFalse(app.buttons["routine.step.0"].exists)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        XCTAssertFalse(app.buttons["navigation.setup"].exists)
        attach("more-ten-moments-one-screen", app)

        row.tap()
        XCTAssertTrue(app.navigationBars["This moment"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["run.detail"].label, "Synthetic layout example.")
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        app.navigationBars["This moment"].buttons["Done"].tap()

        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        for identifier in ["run.start", "morning.update", "morning.review", "morning.learn", "morning.settings"] {
            XCTAssertTrue(app.buttons[identifier].isHittable, "Every sunrise action must be visible: \(identifier)\n\(app.debugDescription)")
        }
        attach("more-expanded-sunrise-actions", app)
        app.buttons["morning.actions"].tap()
        XCTAssertFalse(app.buttons["run.start"].exists)
        MorningUITestNavigation.tapButton("morning.update", in: app)
        XCTAssertTrue(app.buttons["routine.step.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Your routine"].exists)
    }

    func testDraftApprovalBelongsToReviewAndDateOpensHistory() {
        let app = launch([])
        MorningUITestNavigation.revealMorningAction("morning.reviewDraft", in: app)
        let review = app.buttons["morning.reviewDraft"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertTrue(review.isHittable)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        review.tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routine.step.0"].exists)
        attach("more-review-routine-editor", app)
        app.buttons["routine.approve"].tap()
        // Approval closes the review editor and returns to the one-action morning.
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
        app.buttons["morning.actions"].tap()
        app.buttons["morning.date"].tap()
        XCTAssertTrue(app.buttons["review.period"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["navigation.setup"].exists)
        attach("more-weekly-review", app)
    }

    func testActiveMomentKeepsInstructionsAvailableWithoutEditing() {
        let app = launch(["--ui-testing-approved", "--fixture-mode"])
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 10))
        app.buttons["run.start"].tap()
        app.buttons["run.controls"].tap()
        app.buttons["run.about"].tap()
        let instructions = app.staticTexts["run.detail"]
        XCTAssertTrue(instructions.waitForExistence(timeout: 5))
        XCTAssertEqual(instructions.label, "Good morning. Let’s see what’s ahead.")
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        app.navigationBars["This moment"].buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
        XCTAssertTrue(app.buttons["run.pause"].isHittable)
    }

    func testDarkTenMomentMorningRemainsOneScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--dark-preview", "--ui-testing-ten-moments", "--ui-testing-approved"]
        app.launch()
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["morning.step.9"].isHittable)
        XCTAssertEqual(app.scrollViews.count, 0)
        attach("more-ten-moments-dark", app)
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        attach("more-expanded-sunrise-dark", app)
    }

    func testSunriseMenuRemainsReachableInLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        XCTAssertTrue(app.buttons["morning.actions"].waitForExistence(timeout: 10))
        app.buttons["morning.actions"].tap()
        let tray = app.scrollViews["morning.actionsScroll"]
        XCTAssertTrue(tray.waitForExistence(timeout: 5))
        let settings = app.buttons["morning.settings"]
        for _ in 0..<5 where !settings.isHittable { tray.swipeUp() }
        XCTAssertTrue(settings.isHittable, app.debugDescription)
        XCTAssertTrue(app.buttons["morning.actions"].isHittable)
        attach("more-sunrise-landscape", app)
        app.buttons["morning.actions"].tap()
        XCTAssertFalse(app.buttons["morning.settings"].exists)
        XCTAssertTrue(app.buttons["morning.date"].isHittable)
    }

    func testTenActiveMomentsKeepPauseAndLastItemOnOneScreen() {
        let app = launch(["--ui-testing-ten-moments", "--ui-testing-approved"])
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 10))
        app.buttons["run.start"].tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["run.pause"].isHittable)
        let item = app.buttons["morning.step.9"]
        XCTAssertTrue(item.isHittable)
        attach("more-ten-active-moments-one-screen", app)
        XCTAssertEqual(app.scrollViews.count, 0)
    }

    func testVoiceEntryPausesBeforeListeningAndKeepsTouchFallback() {
        let app = launch(["--ui-testing-approved", "--fixture-mode"])
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 10))
        app.buttons["run.start"].tap()
        app.buttons["run.controls"].tap()
        app.buttons["run.speakCommand"].tap()
        XCTAssertTrue(app.buttons["voiceCommand.listen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["voiceCommand.listen"].isHittable)
        XCTAssertEqual(app.alerts.count, 0, "Opening the command sheet must not request microphone access.")
        attach("more-explicit-voice-turn-before-permission", app)
        app.buttons["voiceCommand.close"].tap()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
        app.buttons["run.resume"].tap()
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["run.step"].label, "Your morning")
    }

    func testTileReorderCreatesPersistentDraftAndActiveOrderIsLocked() {
        let workspace = UUID().uuidString
        let app = launch(["--ui-testing-workspace=\(workspace)", "--ui-testing-ten-moments", "--ui-testing-approved"])
        let first = app.buttons["morning.step.0"]
        let second = app.buttons["morning.step.1"]
        assertTitle("Your morning", on: first, in: app)
        assertTitle("The weather", on: second, in: app)
        second.tap()
        XCTAssertTrue(app.navigationBars["This moment"].waitForExistence(timeout: 5), app.debugDescription)
        let earlier = app.buttons["morning.moveEarlier"]
        XCTAssertTrue(earlier.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(earlier.isEnabled)
        earlier.tap()
        assertDetailDismissed(in: app)
        assertTitle("The weather", on: first, in: app)
        assertTitle("Your morning", on: second, in: app)
        MorningUITestNavigation.revealMorningAction("morning.reviewDraft", in: app)
        XCTAssertFalse(app.buttons["run.start"].exists, "Moving an approved moment must require renewed approval.")
        attach("more-tile-reorder-needs-approval", app)

        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-ten-moments" || $0 == "--ui-testing-approved" }
        app.launch()
        assertTitle("The weather", on: first, in: app)
        assertTitle("Your morning", on: second, in: app)
        MorningUITestNavigation.tapButton("morning.reviewDraft", in: app)
        XCTAssertTrue(app.navigationBars["Your routine"].waitForExistence(timeout: 5))
        let restore = app.buttons["routine.restore"]
        // Ten rows can keep a later native List section unmounted. Reveal that
        // section before asserting the preserved approved version is available.
        let lists = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            + app.scrollViews.allElementsBoundByIndex
        guard let list = lists.first(where: { $0.exists && $0.isHittable }) else {
            XCTFail("Your routine has no visible list.\n\(app.debugDescription)")
            return
        }
        for _ in 0..<8 where !restore.exists || !restore.isHittable { list.swipeUp() }
        XCTAssertTrue(restore.exists && restore.isHittable,
                      "The earlier approved order must remain recoverable.\n\(app.debugDescription)")
        MorningUITestNavigation.tapButton("routine.approve", in: app)
        MorningUITestNavigation.selectTab("Morning", in: app)
        MorningUITestNavigation.tapButton("run.start", in: app)
        XCTAssertTrue(app.buttons["run.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["run.step"].label, "The weather")
        first.tap()
        XCTAssertTrue(app.navigationBars["This moment"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.moveEarlier"].exists)
        XCTAssertFalse(app.buttons["morning.moveLater"].exists)
        app.navigationBars["This moment"].buttons["Done"].tap()
        assertDetailDismissed(in: app)
        XCTAssertEqual(app.staticTexts["run.step"].label, "The weather")
        app.buttons["run.pause"].tap()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 5))
        second.tap()
        XCTAssertTrue(app.navigationBars["This moment"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["morning.moveEarlier"].exists)
        XCTAssertFalse(app.buttons["morning.moveLater"].exists)
        attach("more-paused-tile-detail-order-locked", app)
        app.navigationBars["This moment"].buttons["Done"].tap()
        assertDetailDismissed(in: app)
        assertTitle("The weather", on: first, in: app)
        assertTitle("Your morning", on: second, in: app)
        attach("more-paused-tile-order-locked", app)
    }

    func testNativeDragChangesOrderAndPersists() {
        let app = launch(["--ui-testing-workspace=\(UUID().uuidString)", "--ui-testing-ten-moments", "--ui-testing-approved"])
        let first = app.buttons["morning.step.0"]
        let third = app.buttons["morning.step.2"]
        assertTitle("Your morning", on: first, in: app)
        assertTitle("Today's calendar", on: third, in: app)
        XCTAssertTrue(first.isHittable && third.isHittable, app.debugDescription)
        attach("more-native-drag-before", app)

        // A real native lift/drop from the first tile to the third tile's
        // original center moves it after that tile as the native placeholder
        // rearranges. No model, fixture reorder or move button can satisfy this.
        let lift = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let afterThird = third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        lift.press(forDuration: 1.2, thenDragTo: afterThird)
        let expected = ["The weather", "Today's calendar", "Your morning", "Your reminders", "People and messages",
                        "A little reading", "Make some tea", "A moment to move", "A little time to play", "One thought for later"]
        for (index, title) in expected.enumerated() {
            assertTitle(title, on: app.buttons["morning.step.\(index)"], in: app)
        }
        XCTAssertFalse(app.navigationBars["This moment"].exists, "Dragging must not activate the tile's detail button.")
        attach("more-native-drag-changed-order", app)
        MorningUITestNavigation.revealMorningAction("morning.reviewDraft", in: app)
        XCTAssertFalse(app.buttons["run.start"].exists, "A native drag must revoke the old order's approval.")

        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-ten-moments" || $0 == "--ui-testing-approved" }
        app.launch()
        for (index, title) in expected.enumerated() {
            assertTitle(title, on: app.buttons["morning.step.\(index)"], in: app)
        }
        MorningUITestNavigation.revealMorningAction("morning.reviewDraft", in: app)
        XCTAssertFalse(app.buttons["run.start"].exists)
        attach("more-native-drag-order-after-relaunch", app)
    }

    private func assertDetailDismissed(in app: XCUIApplication) {
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.navigationBars["This moment"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, app.debugDescription)
    }

    private func assertTitle(_ title: String, on element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", title), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed, app.debugDescription)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--light-preview"] + arguments
        if !arguments.contains(where: { $0.hasPrefix("--ui-testing-workspace=") }) {
            app.launchArguments.append("--ui-testing-workspace=\(UUID().uuidString)")
        }
        app.launch()
        return app
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MOREGlassMorningScreenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        } catch { XCTFail("Could not retain the synthetic visual check: \(error)") }
    }
}

/// Run separately with the simulator's content_size set to an accessibility size.
@MainActor
final class QuietMorningAccessibilityTests: XCTestCase {
    func testLargeTextKeepsStartAndFullMomentDetailsReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-approved", "--fixture-mode"]
        app.launch()
        let scroll = app.scrollViews["morning.accessibleScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "This check requires actual accessibility text size.")
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        let start = app.buttons["run.start"]
        for _ in 0..<8 where !start.isHittable { scroll.swipeUp() }
        XCTAssertTrue(start.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "more-accessibility-start-reachable"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        start.tap()
        let controls = app.buttons["run.controls"]
        for _ in 0..<8 where !controls.isHittable { scroll.swipeUp() }
        XCTAssertTrue(controls.isHittable)
        controls.tap()
        app.buttons["run.about"].tap()
        XCTAssertTrue(app.staticTexts["run.detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        app.navigationBars["This moment"].buttons["Done"].tap()
        controls.tap()
        app.buttons["run.stop"].tap()
        MorningUITestNavigation.revealMorningAction("run.start", in: app)
        XCTAssertTrue(app.buttons["run.start"].waitForExistence(timeout: 5))
    }
}
