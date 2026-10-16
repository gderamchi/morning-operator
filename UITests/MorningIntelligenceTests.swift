import XCTest

@MainActor
final class MorningIntelligenceTests: XCTestCase {
    func testExplicitActivationAndReturnToLocal() { check(french: false, large: false) }
    func testFrenchLargestTextKeepsControlsReachable() { check(french: true, large: true) }

    private func check(french: Bool, large: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved",
            "--ui-testing-workspace=\(UUID().uuidString)", "--theme-phase=night",
            "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        defer { app.terminate() }
        let home = app.buttons["morning.actions"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        home.tap()
        app.buttons["morning.settings"].tap()
        find(app.buttons["setup.intelligence"], in: app).tap()
        find(app.buttons["intelligence.forgetKey"], in: app).tap()
        let field = find(app.secureTextFields["intelligence.apiKey"], in: app)
        field.tap()
        field.typeText("sk-unit-test-synthetic-credential\n")
        // No provider call is made by configuring this synthetic key.
        let consent = find(app.switches["intelligence.consent"], in: app)
        XCTAssertFalse(app.staticTexts["intelligence.issue"].exists)
        XCTAssertFalse(app.buttons["intelligence.enable"].isEnabled)
        consent.tap()
        find(app.buttons["intelligence.enable"], in: app).tap()
        XCTAssertFalse(app.staticTexts["intelligence.issue"].exists)
        let local = find(app.buttons["intelligence.local"], in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = french ? "intelligence-french-largest-text" : "intelligence-openai-explicit"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        local.tap()
        _ = find(app.switches["intelligence.consent"], in: app)
        find(app.buttons["intelligence.forgetKey"], in: app).tap()
    }

    private func find(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<30 {
            if element.exists && element.isHittable { return element }
            app.swipeDown()
        }
        for _ in 0..<40 {
            if element.exists && element.isHittable { return element }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
        return element
    }
}
