import XCTest

/// Explanations and persistence only. The explicit isolated flag replaces every
/// system authorization with a synthetic outcome and never changes iOS settings.
@MainActor
final class MorningPermissionSetupTests: XCTestCase {
    func testEachAccessHasAnExplanationBeforeAllowAndPersistsWhenRoutineLearningIsDeferred() {
        let app = launchFixture(denied: true)
        let permissions = ["location", "calendar", "reminders", "screenTime", "speech", "microphone", "notifications", "alarms"]
        for permission in permissions {
            let title = app.staticTexts["permissions.title.\(permission)"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertEqual(app.alerts.count, 0)
            let allow = app.buttons["permissions.allow"]
            reveal(allow, app)
            allow.tap()
        }
        let finish = app.buttons["permissions.finish"]
        reveal(finish, app); finish.tap()
        XCTAssertTrue(finish.waitForNonExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertFalse(app.buttons["permissions.allow"].waitForExistence(timeout: 2), "Access setup must not repeat when routine onboarding was deferred.")
        MorningUITestNavigation.reviewAction("navigation.setup", in: app)
        let revisit = app.buttons["setup.permissions"]
        reveal(revisit, app); revisit.tap()
        XCTAssertTrue(app.staticTexts["permissions.title.location"].waitForExistence(timeout: 5))
    }

    func testSkippingOneAccessStillExplainsTheNextAndSpeechIsSeparateFromMicrophone() {
        let app = launchFixture()
        for permission in ["location", "calendar", "reminders", "screenTime", "speech"] {
            XCTAssertTrue(app.staticTexts["permissions.title.\(permission)"].waitForExistence(timeout: 5))
            let skip = app.buttons["permissions.skip"]
            reveal(skip, app); skip.tap()
        }
        XCTAssertTrue(app.staticTexts["permissions.title.microphone"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "synthetic-permission-explanation-microphone"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func launchFixture(denied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace", "--ui-testing-permissions", "--ui-testing-workspace=\(UUID().uuidString)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if denied { app.launchArguments.append("--ui-testing-permissions-denied") }
        app.launch()
        return app
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }
}
