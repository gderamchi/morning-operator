import XCTest

/// The preview uses a fixed offer and simulated failures. These journeys never
/// make a purchase, grant a permission, or change the owner's saved routine.
@MainActor
final class MorningWelcomeFlowTests: XCTestCase {
    func testIntroductionSupportsBackSkipAndPurchaseRecoveryWithoutPermissions() {
        let app = launch(french: true)
        let heading = app.staticTexts["onboarding.heading"]
        let firstHeading = heading.label
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding.progress").firstMatch.exists)

        tap("onboarding.next", in: app)
        XCTAssertNotEqual(heading.label, firstHeading)
        tap("onboarding.back", in: app)
        XCTAssertEqual(heading.label, firstHeading)

        var introductions = Set([firstHeading])
        for _ in 0..<2 {
            tap("onboarding.next", in: app)
            introductions.insert(heading.label)
            assertNoPermissionOrHome(in: app)
        }
        XCTAssertEqual(introductions.count, 3, "Each introduction should explain a different part of MORE.")
        tap("onboarding.next", in: app)
        assertOffer(in: app, french: true)

        for (identifier, title) in [("paywall.terms", "Votre abonnement"),
                                    ("paywall.privacy", "Vos données, vos choix.")] {
            tap(identifier, in: app)
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), app.debugDescription)
            let close = app.buttons["Fermer"]
            XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
            close.tap()
            assertOffer(in: app, french: true)
        }

        tap("paywall.subscribe", in: app)
        let notice = app.staticTexts["paywall.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(notice.label.isEmpty)
        let purchaseFailure = notice.label
        assertNoPermissionOrHome(in: app)
        XCTAssertTrue(app.buttons["paywall.subscribe"].isEnabled, "A failed purchase must allow another attempt.")
        tap("paywall.subscribe", in: app)
        XCTAssertTrue(notice.exists)
        assertOffer(in: app, french: true)
        assertNoPermissionOrHome(in: app)

        tap("paywall.restore", in: app)
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertNotEqual(notice.label, purchaseFailure, "Restoring without a purchase needs its own explanation.")
        assertNoPermissionOrHome(in: app)
        attach("onboarding-fr-purchase-recovery", app)
        app.terminate()

        let skipped = launch(french: true)
        tap("onboarding.offer", in: skipped)
        assertOffer(in: skipped, french: true)
        assertNoPermissionOrHome(in: skipped)
        skipped.terminate()
    }

    func testNoTrialUnavailableAndPendingOffersStayHonestAndGated() {
        for flag in ["--preview-onboarding-no-trial", "--preview-onboarding-unavailable", "--preview-onboarding-pending"] {
            let app = launch(extra: [flag])
            tap("onboarding.offer", in: app)
            let subscribe = app.buttons["paywall.subscribe"]
            XCTAssertTrue(subscribe.waitForExistence(timeout: 5), app.debugDescription)
            switch flag {
            case "--preview-onboarding-no-trial":
                assertOffer(in: app, french: false)
                XCTAssertFalse(subscribe.label.contains("7"), "An ineligible account must not be offered a free trial.")
                XCTAssertTrue(subscribe.isEnabled)
            case "--preview-onboarding-unavailable":
                XCTAssertFalse(app.staticTexts["paywall.price"].exists, "An unavailable product must not display a fabricated price.")
                XCTAssertEqual(subscribe.label, "Try again")
                XCTAssertTrue(subscribe.isEnabled)
                reach(subscribe, in: app)
                reach(app.buttons["paywall.restore"], in: app)
                XCTAssertTrue(app.staticTexts["paywall.notice"].exists)
            default:
                assertOffer(in: app, french: false)
                XCTAssertFalse(subscribe.isEnabled, "A pending purchase keeps the ordinary Subscribe action disabled.")
                let notice = app.staticTexts["paywall.notice"]
                XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertFalse(notice.label.isEmpty)
                attach("onboarding-pending-explicit-recovery", app)
                tap("paywall.retryPending", in: app)
                XCTAssertTrue(subscribe.isEnabled, "A declined request has an explicit recovery action.")
                XCTAssertFalse(notice.exists)
            }
            assertNoPermissionOrHome(in: app)
            attach("onboarding-\(flag.dropFirst(2))", app)
            app.terminate()
        }
    }

    func testIntroductionAndOfferAcrossDayNightAndFrenchEnglish() {
        for phase in ["day", "night"] {
            for french in [false, true] {
                let app = launch(phase: phase, french: french)
                let name = "onboarding-\(phase)-\(french ? "fr" : "en")"
                for page in 1...3 {
                    XCTAssertTrue(app.staticTexts["onboarding.heading"].exists)
                    assertNoPermissionOrHome(in: app)
                    attach("\(name)-intro-\(page)", app)
                    tap("onboarding.next", in: app)
                }
                assertOffer(in: app, french: french)
                for identifier in ["paywall.subscribe", "paywall.restore", "paywall.terms", "paywall.privacy"] {
                    XCTAssertTrue(control(identifier, in: app).exists, "Missing \(identifier): \(app.debugDescription)")
                }
                attach("\(name)-paywall", app)
                assertNoPermissionOrHome(in: app)
                app.terminate()
            }
        }
    }

    func testFrenchLargestTextKeepsNavigationAndOfferReachableInPortraitAndLandscape() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(phase: "night", french: true, extra: [
            "--ui-testing-reduce-transparency",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        for page in 1...3 {
            XCTAssertTrue(app.staticTexts["onboarding.heading"].exists)
            attach("onboarding-night-fr-largest-intro-\(page)", app)
            tap("onboarding.next", in: app)
        }
        assertOffer(in: app, french: true)
        reach(app.buttons["paywall.subscribe"], in: app)
        attach("onboarding-night-fr-largest-paywall-portrait", app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertGreaterThan(app.frame.width, app.frame.height, app.debugDescription)
        for identifier in ["paywall.subscribe", "paywall.restore", "paywall.terms", "paywall.privacy"] {
            reach(control(identifier, in: app), in: app)
        }
        attach("onboarding-night-fr-largest-paywall-landscape", app)
        assertNoPermissionOrHome(in: app)
        app.terminate()
    }

    private func launch(phase: String = "day", french: Bool = false, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--preview-onboarding", "--theme-phase=\(phase)",
            "--ui-testing-reduce-motion", "--ui-testing-workspace=\(UUID().uuidString)",
            "-AppleLanguages", french ? "(fr)" : "(en)",
            "-AppleLocale", french ? "fr_FR" : "en_US"
        ] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding.preview").firstMatch
            .waitForExistence(timeout: 10), "This suite requires the isolated preview: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["onboarding.heading"].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }

    private func assertOffer(in app: XCUIApplication, french: Bool) {
        let price = app.staticTexts["paywall.price"]
        XCTAssertTrue(price.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(price.label.contains(french ? "4,99" : "4.99"), price.label)
        XCTAssertTrue(app.buttons["paywall.subscribe"].exists)
    }

    private func assertNoPermissionOrHome(in app: XCUIApplication) {
        XCTAssertEqual(app.alerts.count, 0, "The introduction and failed preview purchases must not request access.")
        XCTAssertEqual(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count, 0)
        XCTAssertFalse(app.buttons["morning.actions"].exists, "A failed or absent purchase must keep the paywall visible.")
        XCTAssertFalse(app.buttons["learn.screenTime"].exists)
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        reach(button, in: app)
        button.tap()
    }

    private func control(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reach(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<10 where !element.isHittable {
            if app.scrollViews.firstMatch.exists {
                let scroll = app.scrollViews.firstMatch
                if element.frame.midY < scroll.frame.minY { scroll.swipeDown() }
                else { scroll.swipeUp() }
            }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "The control must remain reachable: \(app.debugDescription)")
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["MO_ONBOARDING_SCREENSHOT_DIR"] {
            do {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"), options: .atomic)
            } catch { XCTFail("Could not save the synthetic onboarding screenshot: \(error)") }
        }
    }
}
