import XCTest

@MainActor
final class MorningIntelligenceTests: XCTestCase {
    func testExplicitActivationAndReturnToLocal() { check(french: false, large: false) }
    func testFrenchLargestTextKeepsControlsReachable() { check(french: true, large: true) }

    private func check(french: Bool, large: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fixture-mode", "--ui-testing-approved", "--ui-testing-reduce-motion",
            "--ui-testing-workspace=\(UUID().uuidString)", "--theme-phase=night",
            "-AppleLanguages", french ? "(fr)" : "(en)", "-AppleLocale", french ? "fr_FR" : "en_US",
            "-more.appLanguage", french ? "fr" : "en"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        defer { app.terminate() }
        let home = app.buttons["morning.actions"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        home.tap()
        app.buttons["morning.settings"].tap()
        find(app.buttons["setup.intelligence"], in: app).tap()
        find(app.buttons["intelligence.forgetKey"], in: app).tap()
        let field = find(app.secureTextFields["intelligence.apiKey"], in: app, towardTop: true)
        field.tap()
        field.typeText("sk-unit-test-synthetic-credential\n")
        // No provider call is made by configuring this synthetic key.
        let consent = find(app.switches["intelligence.consent"], in: app)
        XCTAssertFalse(app.staticTexts["intelligence.issue"].exists)
        if !large { XCTAssertFalse(app.buttons["intelligence.enable"].isEnabled) }
        // SwiftUI exposes the labelled row as the switch's frame; tap its thumb.
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(consent.value as? String, "1")
        let enable = find(app.buttons["intelligence.enable"], in: app)
        XCTAssertTrue(enable.isEnabled)
        enable.tap()
        XCTAssertFalse(app.staticTexts["intelligence.issue"].exists)
        let local = find(app.buttons["intelligence.local"], in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = french ? "intelligence-french-largest-text" : "intelligence-openai-explicit"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        local.tap()
        _ = find(app.switches["intelligence.consent"], in: app, towardTop: true)
        find(app.buttons["intelligence.forgetKey"], in: app).tap()
    }

    private func find(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) -> XCUIElement {
        for _ in 0..<30 {
            if element.exists && element.isHittable { return element }
            if towardTop { app.swipeDown() } else { app.swipeUp() }
        }
        for _ in 0..<40 {
            if element.exists && element.isHittable { return element }
            if towardTop { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
        return element
    }
}
