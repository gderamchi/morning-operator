import XCTest

/// Isolated permission explanations, persistence and weather-source selection.
/// Synthetic sources never change iOS authorizations or contact weather providers.
@MainActor
final class MorningPermissionSetupTests: XCTestCase {
    func testEachAccessHasAnExplanationBeforeAllowAndPersistsWhenRoutineLearningIsDeferred() {
        let app = launchFixture(denied: true)
        let permissions = ["location", "calendar", "reminders", "screenTime", "speech", "microphone", "notifications", "alarms"]
        for permission in permissions {
            let title = app.staticTexts["permissions.title.\(permission)"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.staticTexts["Your access choices couldn't be restored. You can still review them; the saved file stays intact."].exists)
            XCTAssertFalse(app.staticTexts["These access choices couldn't be saved. MORE may ask you to review them next time."].exists)
            XCTAssertEqual(app.alerts.count, 0)
            let allow = app.buttons["permissions.allow"]
            reveal(allow, app)
            allow.tap()
        }
        let finish = app.buttons["permissions.finish"]
        reveal(finish, app)
        XCTAssertFalse(app.staticTexts["These access choices couldn't be saved. MORE may ask you to review them next time."].exists)
        finish.tap()
        XCTAssertTrue(finish.waitForNonExistence(timeout: 5))
        app.terminate(); launchConfirmedWorkspace(app)
        XCTAssertFalse(app.buttons["permissions.allow"].waitForExistence(timeout: 2), "Access setup must not repeat when routine onboarding was deferred.")
        openSettingsFromHome(app)
        let revisit = app.buttons["setup.permissions"]
        reveal(revisit, app); revisit.tap()
        XCTAssertTrue(app.staticTexts["permissions.title.location"].waitForExistence(timeout: 5))
    }

    func testSkippingOneAccessStillExplainsTheNextAndSpeechIsSeparateFromMicrophone() {
        let app = launchFixture()
        for permission in ["location", "calendar", "reminders", "screenTime", "speech"] {
            XCTAssertTrue(app.staticTexts["permissions.title.\(permission)"].waitForExistence(timeout: 5))
            let skip = app.buttons["permissions.skip"]
            reveal(skip, app)
            XCTAssertEqual(skip.label, "Not now")
            skip.tap()
        }
        XCTAssertTrue(app.staticTexts["permissions.title.microphone"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["permissions.title.microphone"].label, "Hear you during your morning")
        XCTAssertEqual(app.alerts.count, 0)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "synthetic-permission-explanation-microphone"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFrenchLargestTextExplainsEveryAccessAndReturnsToTopWithoutAnimation() {
        let app = launchFixture(frenchLargestText: true)
        for permission in ["location", "calendar", "reminders", "screenTime", "speech", "microphone", "notifications", "alarms"] {
            XCTAssertTrue(app.staticTexts["permissions.title.\(permission)"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["MORE"].isHittable, "Each new explanation must start at its top, even after scrolling through the previous one.")
            let skip = app.buttons["permissions.skip"]
            reveal(skip, app)
            XCTAssertEqual(skip.label, "Plus tard")
            skip.tap()
        }
        let finish = app.buttons["permissions.finish"]
        reveal(finish, app)
        XCTAssertEqual(finish.label, "Ouvrir MORE")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "synthetic-permissions-french-accessibility-largest-completion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        finish.tap()
        XCTAssertTrue(finish.waitForNonExistence(timeout: 5))
    }

    func testManualCitySelectionFromCurrentLocationSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace", "--ui-testing-briefing-fixture",
            "--ui-testing-workspace=\(UUID().uuidString)", "-more.appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        launchConfirmedWorkspace(app)
        openYourDayFromHome(app)
        MorningUITestNavigation.chooseManualWeatherCity(in: app)
        let search = app.textFields["briefing.citySearch"]
        reveal(search, app)
        search.tap(); search.typeText("Synthetic\n")
        let result = app.buttons["briefing.cityResult.48.0,2.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        reveal(result, app); result.tap()
        assertSelectedCity(in: app)
        XCTAssertEqual(app.alerts.count, 0, "Choosing a manual city must not request GPS access.")
        app.terminate(); launchConfirmedWorkspace(app)
        openYourDayFromHome(app)
        assertSelectedCity(in: app)
        // The search row is offered only in manual mode, so its presence also
        // establishes the stored source choice rather than only a cached label.
        reveal(app.textFields["briefing.citySearch"], app)
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func openSettingsFromHome(_ app: XCUIApplication) {
        let actions = app.buttons["morning.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5), app.debugDescription)
        actions.tap()
        let settings = app.buttons["morning.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
        settings.tap()
        XCTAssertTrue(app.buttons["setup.briefing"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func assertSelectedCity(in app: XCUIApplication) {
        let city = app.descendants(matching: .any).matching(identifier: "briefing.city").firstMatch
        reveal(city, app)
        XCTAssertTrue(city.label.contains("Synthetic City") || (city.value as? String)?.contains("Synthetic City") == true,
                      "The saved city must be exposed by its native labeled row: \(city.debugDescription)")
    }

    private func openYourDayFromHome(_ app: XCUIApplication) {
        openSettingsFromHome(app)
        let briefing = app.buttons["setup.briefing"]
        reveal(briefing, app); briefing.tap()
        XCTAssertTrue(app.staticTexts["briefing.synthetic"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func launchFixture(denied: Bool = false, frenchLargestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace", "--ui-testing-permissions", "--ui-testing-workspace=\(UUID().uuidString)", "-more.appLanguage", frenchLargestText ? "fr" : "en", "-AppleLanguages", frenchLargestText ? "(fr)" : "(en)", "-AppleLocale", frenchLargestText ? "fr_FR" : "en_US"]
        if frenchLargestText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if denied { app.launchArguments.append("--ui-testing-permissions-denied") }
        launchConfirmedWorkspace(app)
        return app
    }
    private func launchConfirmedWorkspace(_ app: XCUIApplication) {
        continueAfterFailure = false
        let prefix = "--ui-testing-workspace="
        let workspace = String(app.launchArguments.first { $0.hasPrefix(prefix) }!.dropFirst(prefix.count))
        app.launch()
        let marker = app.staticTexts["qa.testWorkspace"]
        if !marker.waitForExistence(timeout: 5) || marker.value as? String != workspace {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(marker.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(marker.value as? String, workspace, app.debugDescription)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }
}
