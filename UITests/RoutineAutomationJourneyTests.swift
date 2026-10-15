import XCTest

/// Synthetic routine/persisted budgets; live-news explicitly uses a real public page.
@MainActor
final class RoutineAutomationJourneyTests: XCTestCase {
    func testNativeRequestReviewAndBackgroundPrivacyUseExplicitSyntheticProvider() {
        let app = launch(["--ui-testing-native-actions", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        tapVisible("nativeMoment.open", in: app)
        let request = app.descendants(matching: .any).matching(identifier: "nativeMoment.request").firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 8))
        request.tap(); request.typeText("Private unsubmitted synthetic request")
        XCUIDevice.shared.press(.home)
        app.activate()
        reveal(app)
        tapVisible("nativeMoment.open", in: app)
        XCTAssertFalse((request.value as? String ?? "").contains("Private unsubmitted"), "Backgrounding must clear even an unsubmitted native request.")
        request.tap(); request.typeText("Reminder: water plants no date")
        tapVisible("nativeMoment.prepare", in: app)
        let confirm = app.buttons["nativeMoment.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["nativeMoment.synthetic"].label.contains("SYNTHETIC"))
        XCTAssertFalse(confirm.isEnabled, "Interrupted spoken review must require explicit screen review before writing.")
        tapVisible("nativeMoment.reviewed", in: app)
        tapVisible("nativeMoment.confirm", in: app)
        let status = app.staticTexts["nativeMoment.status"]
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@", "was added", "water plants", "SYNTHETIC"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 8), .completed)
        XCTAssertFalse(confirm.exists)
        attach("automation-synthetic-native-addition-confirmed", app)
        tapVisible("nativeMoment.cancel", in: app)
        tapVisible("nativeMoment.open", in: app)
        request.tap(); request.typeText("read my reminders")
        tapVisible("nativeMoment.prepare", in: app)
        tapVisible("nativeMoment.reminder.0", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        XCTAssertFalse(confirm.isEnabled)
        tapVisible("nativeMoment.reviewed", in: app)
        tapVisible("nativeMoment.confirm", in: app)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "marked complete", "SYNTHETIC appeler le garage"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 8), .completed)
        XCTAssertFalse(confirm.exists)
        attach("automation-synthetic-observed-reminder-completed", app)
    }

    func testLearnedSuggestionCanBeEditedBeforeDelegationAndRestoresPreviousRoutine() {
        let app = launch(["--ui-testing-approved", "--ui-testing-observation-archive", "--ui-testing-evidence-proposals"])
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.review"].tap()
        tapVisible("learn.refine", in: app)
        XCTAssertTrue(app.textViews["learn.notes"].waitForExistence(timeout: 8))
        tapVisible("learn.savedObservations", in: app)
        XCTAssertTrue(app.buttons["observations.choose"].waitForExistence(timeout: 8))
        app.buttons["observations.choose"].tap()
        tapVisible("observation.select.11111111-1111-4111-8111-111111111111", in: app)
        tapVisible("observation.select.22222222-2222-4222-8222-222222222222", in: app)
        tapVisible("observations.suggestUpdate", in: app)
        XCTAssertTrue(app.buttons["proposal.edit"].waitForExistence(timeout: 15))
        let reason = app.buttons["Why this suggestion?"]
        for _ in 0..<8 where !reason.exists || !reason.isHittable { app.swipeUp() }
        reason.tap()
        let source = "Edited sample A: calendar, water, chess and tea."
        let quote = app.staticTexts["“\(source)”"]
        for _ in 0..<8 where !quote.exists || !quote.isHittable { app.swipeUp() }
        XCTAssertTrue(quote.exists)
        XCTAssertTrue(app.staticTexts["proposal.sources"].label.contains("2 observations"))
        attach("automation-learned-suggestion-before-edit", app)
        app.buttons["proposal.edit"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["proposal.approve"].exists)
        XCTAssertTrue(app.buttons["routine.restore"].exists)
        app.buttons["routine.step.0"].tap()
        XCTAssertTrue(app.buttons["step.save"].waitForExistence(timeout: 8))
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Step details")).firstMatch
        XCTAssertTrue((details.value as? String ?? "").contains(source), "Adopting an editable draft must retain the exact source quotation.")
        let duration = app.steppers["step.duration"]
        let increment = duration.buttons["step.duration-Increment"]
        for _ in 0..<8 where !increment.exists || !increment.isHittable { app.swipeUp() }
        increment.tap()
        XCTAssertEqual(duration.value as? String, "4")
        app.buttons["step.save"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("4 min"))
        attach("automation-learned-edited-draft-awaiting-delegation", app)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-testing-approved" || $0 == "--ui-testing-observation-archive" }
        app.launch()
        reveal(app)
        app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8), "Editing must persist a draft without silently delegating it.")
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("4 min"))
        tapVisible("routine.restore", in: app)
        XCTAssertFalse(app.buttons["routine.approve"].exists)
        XCTAssertTrue(app.buttons["routine.step.3"].exists, "The previous approved routine must remain recoverable.")
        XCTAssertTrue(app.buttons["routine.step.0"].label.contains("Your morning"))
        attach("automation-learned-draft-previous-approved-restored", app)
    }

    func testUnavailableCalendarPausesWithVisibleRecoveryAndNextPreservesTruth() {
        let app = launch(["--ui-testing-native-unavailable", "--ui-testing-approved", "--ui-testing-hands-free", "--ui-testing-read-aloud", "--ui-testing-short-budgets"])
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        let status = app.staticTexts["moment.connectedResult"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertTrue(status.label.contains("Your day is not ready"), status.label)
        XCTAssertTrue(status.label.contains("Your morning is paused"), status.label)
        XCTAssertTrue(status.label.contains("Say resume to retry, next to continue"), status.label)
        XCTAssertTrue(app.buttons["morning.playback"].label.contains("Continue"))
        XCTAssertTrue(app.staticTexts["morning.currentStep"].label.contains("Calendar unavailable"))
        attach("automation-unavailable-calendar-recovery", app)
        tapVisible("morning.next", in: app)
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: 35))
        let recap = app.staticTexts["morning.executionSummary"].label
        XCTAssertTrue(recap.contains("Unavailable: 1"), recap)
        XCTAssertTrue(recap.contains("Timed moments finished: 1"), recap)
        XCTAssertFalse(recap.contains("Verified operations: 2"), recap)
        XCTAssertFalse(status.exists)
        attach("automation-unavailable-calendar-honest-recap", app)
    }

    func testFrenchLargestTextKeepsLearnedProposalActionsReachable() {
        let app = launch(["--ui-testing-approved", "--ui-testing-observation-archive", "--ui-testing-evidence-proposals",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.review"].tap()
        tapVisible("learn.refine", in: app)
        tapVisible("learn.savedObservations", in: app)
        XCTAssertTrue(app.buttons["observations.choose"].waitForExistence(timeout: 8))
        app.buttons["observations.choose"].tap()
        tapVisible("observation.select.11111111-1111-4111-8111-111111111111", in: app)
        tapVisible("observations.suggestUpdate", in: app)
        XCTAssertTrue(app.buttons["proposal.approve"].waitForExistence(timeout: 15))
        let keep = visibleButton("proposal.keepCurrent", in: app)
        XCTAssertTrue(keep.isHittable)
        let edit = visibleButton("proposal.edit", in: app)
        attach("automation-french-largest-learned-proposal-actions", app)
        XCTAssertTrue(edit.isHittable)
        XCTAssertTrue(app.buttons["proposal.approve"].isHittable)
        edit.tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["routine.approve"].isHittable)
    }

    func testFrenchLargestTextKeepsDelegationAndApprovalReachable() {
        let app = launch(["--ui-testing-automation", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], french: true)
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        let approve = app.buttons["routine.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 8))
        XCTAssertTrue(approve.isHittable)
        let step = app.buttons["routine.step.0"]
        // XCTest considers a partly visible cell hittable even when its centre
        // falls under the pinned approval button. Bring the whole row into view.
        for _ in 0..<10 where !step.isHittable || step.frame.maxY > approve.frame.minY { app.swipeUp() }
        XCTAssertTrue(step.isHittable)
        XCTAssertLessThan(step.frame.midY, approve.frame.minY)
        XCTAssertTrue(step.label.contains("1 min"))
        attach("automation-french-largest-review", app)
        step.tap()
        let save = app.buttons["step.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isHittable)
        let duration = app.steppers["step.duration"]
        // The Stepper is a composite accessibility element; its native +/-
        // buttons are the touch targets, even while the parent is nonhittable.
        let increment = duration.buttons["step.duration-Increment"]
        for _ in 0..<8 {
            if increment.exists && increment.isHittable { break }
            app.swipeUp()
        }
        attach("automation-french-largest-edit", app)
        guard increment.exists && increment.isHittable else {
            XCTFail("The native duration increment must remain reachable at the largest text size.")
            return
        }
        increment.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2"), object: duration)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(approve.waitForExistence(timeout: 8))
        XCTAssertTrue(approve.isHittable)
        XCTAssertTrue(step.label.contains("2 min"), "The edited duration must be saved in the reviewed routine.")
        attach("automation-french-largest-saved", app)
    }
    func testDraftRequiresExplicitDelegationBeforeStart() {
        let app = launch(["--ui-testing-automation"], french: true)
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["routine.approve"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["routine.delegation"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attach("automation-french-review-before-start", app)
        app.buttons["routine.approve"].tap()
        reveal(app)
        XCTAssertTrue(app.buttons["morning.begin"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        attach("automation-approved-awaiting-start", app)
    }

    func testTimedRoutineContinuesWithoutNextAndKeepsHonestRecap() {
        let app = launch(["--ui-testing-automation", "--ui-testing-approved", "--ui-testing-hands-free", "--ui-testing-short-budgets"])
        defer { app.terminate() }
        reveal(app)
        app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("Timed moments finished: 2"))
        XCTAssertFalse(app.staticTexts["morning.executionSummary"].label.contains("likes"))
        attach("automation-finished-without-next", app)
        app.terminate(); app.launch(); reveal(app)
        XCTAssertTrue(app.staticTexts["morning.complete"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["morning.executionSummary"].label.contains("Timed moments finished: 2"))
        attach("automation-persisted-recap", app)
    }

    func testNewsPrivacyWallPausesWithoutPretendingContentWasRead() {
        let app = launch(["--ui-testing-live-news", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 35))
        let status = app.staticTexts["web.result"]
        XCTAssertTrue(status.label.contains("privacy"), status.label)
        let remaining = app.staticTexts["web.remaining"].label
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.staticTexts["web.remaining"].label, remaining)
        attach("automation-real-news-privacy-choice", app)
        app.buttons["web.close"].tap()
        reveal(app)
        XCTAssertTrue(app.buttons["morning.playback"].exists)
        XCTAssertTrue(app.staticTexts["morning.currentStep"].label.contains("Le Monde"))
        attach("automation-blocked-moment-preserved", app)
    }

    func testPublicFeedBrowsesAndPauseResumesSameMoment() {
        let app = launch(["--ui-testing-public-feed", "--ui-testing-approved", "--ui-testing-hands-free"])
        defer { app.terminate() }
        reveal(app); app.buttons["morning.begin"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 20))
        let status = app.staticTexts["web.result"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*· ([2-9]|[1-9][0-9]+) contents viewed.*"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 40), .completed)
        attach("automation-real-public-feed", app)
        let beforeExtension = remainingSeconds(app.staticTexts["web.remaining"].label)
        app.buttons["web.extend"].tap()
        XCTAssertGreaterThan(remainingSeconds(app.staticTexts["web.remaining"].label), beforeExtension + 110)
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        let remaining = app.staticTexts["web.remaining"].label
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.staticTexts["web.remaining"].label, remaining)
        attach("automation-real-public-feed-paused", app)
        app.buttons["web.resume"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.reddit.com")
        attach("automation-real-public-feed-resumed", app)
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        let countBeforeClosing = observedContents(status.label)
        XCTAssertGreaterThanOrEqual(countBeforeClosing, 2)
        let positionBeforeClosing = browserDiagnostic(status, key: "viewportY")
        let sourceBeforeClosing = browserDiagnostic(status, key: "sourceIdentity")
        XCTAssertGreaterThan(positionBeforeClosing, 0)
        XCTAssertGreaterThan(browserDiagnostic(status, key: "sourceItems"), 0)
        attach("automation-real-public-feed-before-close", app)
        app.buttons["web.close"].tap()
        reveal(app)
        XCTAssertTrue(app.buttons["morning.playback"].exists)
        app.buttons["morning.playback"].tap()
        XCTAssertTrue(app.buttons["web.pause"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["web.host"].label, "www.reddit.com")
        XCTAssertEqual(observedContents(app.staticTexts["web.result"].label), countBeforeClosing)
        // Freeze this exact restored viewport before the next legitimate dwell/
        // advance, so accessibility-query latency cannot race the next content.
        app.buttons["web.pause"].tap()
        XCTAssertTrue(app.buttons["web.resume"].waitForExistence(timeout: 5))
        XCTAssertEqual(observedContents(status.label), countBeforeClosing)
        XCTAssertLessThanOrEqual(abs(browserDiagnostic(status, key: "viewportY") - positionBeforeClosing), 2)
        XCTAssertEqual(browserDiagnostic(status, key: "sourceIdentity"), sourceBeforeClosing)
        XCTAssertGreaterThan(browserDiagnostic(status, key: "sourceItems"), 0)
        attach("automation-real-public-feed-reopened", app)
    }

    private func launch(_ flags: [String], french: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        let workspace = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-workspace=\(workspace)",
            "--light-preview", "--theme-phase=morning", "-AppleLanguages", french ? "(fr)" : "(en)",
            "-AppleLocale", french ? "fr_FR" : "en_US"] + flags
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) {
            // Xcode 27 sometimes prelaunches the first target without the test's
            // arguments. Verify the isolated workspace before touching any UI.
            app.terminate(); app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(marker.value as? String, workspace)
        return app
    }
    private func reveal(_ app: XCUIApplication) {
        let begin = app.buttons["morning.begin"]
        if !begin.exists && !app.staticTexts["morning.complete"].exists && !app.buttons["morning.playback"].exists {
            let actions = app.buttons["morning.actions"]
            XCTAssertTrue(actions.waitForExistence(timeout: 10)); actions.tap()
        }
    }
    private func tapVisible(_ identifier: String, in app: XCUIApplication) {
        visibleButton(identifier, in: app).tap()
    }
    private func visibleButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<12 where !button.exists || !button.isHittable {
            let scrolls = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            let scroll = scrolls.first { $0.isHittable } ?? app
            if button.exists, button.frame.height > 0, button.frame.midY < scroll.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(button.exists, "Missing control: \(identifier)")
        XCTAssertTrue(button.isHittable, "Unreachable control: \(identifier)")
        return button
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func remainingSeconds(_ label: String) -> Int {
        let components = label.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { XCTFail("Unexpected remaining time: \(label)"); return 0 }
        return components[0] * 60 + components[1]
    }
    private func observedContents(_ label: String) -> Int {
        let count = label.components(separatedBy: "·").last?
            .split(separator: " ").first.flatMap { Int($0) }
        guard let count else { XCTFail("Missing observed-content count: \(label)"); return 0 }
        return count
    }
    private func browserDiagnostic(_ status: XCUIElement, key: String) -> Int {
        let value = status.value as? String ?? ""
        let raw = value.split(separator: " ").first { $0.hasPrefix(key + "=") }
            .flatMap { $0.split(separator: "=", maxSplits: 1).last }
        guard let raw, let number = Int(raw) else {
            XCTFail("Missing browser diagnostic \(key): \(value)"); return 0
        }
        return number
    }
}
