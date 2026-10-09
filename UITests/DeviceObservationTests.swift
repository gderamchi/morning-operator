import XCTest

/// Development-only XCUI capability checks. No coordinate replay, typing or sending.
@MainActor
final class DeviceObservationTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    func testSettingsReadOnlyNavigation() throws {
        try requireDeviceOptIn()
        continueAfterFailure = false
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        attachScreen(settings, named: "settings-before")

        // These are navigation pages only. A non-English device is not relocalized.
        // Use the explicit environment labels for General/About on that device.
        let generalLabel = environment["MO_SETTINGS_GENERAL_LABEL"] ?? "General"
        let aboutLabel = environment["MO_SETTINGS_ABOUT_LABEL"] ?? "About"
        var general = exactElement(in: settings, label: generalLabel)
        for _ in 0..<3 where !general.isHittable {
            settings.swipeUp()
            general = exactElement(in: settings, label: generalLabel)
        }
        guard general.exists, general.isHittable else {
            throw XCTSkip("General is not visible. Supply the actual localized General/About labels; no setting was changed.")
        }
        try tapFreshNavigation(in: settings, label: generalLabel)
        XCTAssertTrue(exactElement(in: settings, label: aboutLabel).waitForExistence(timeout: 5))
        attachScreen(settings, named: "settings-general-verified")
        try tapFreshNavigation(in: settings, label: aboutLabel)
        XCTAssertTrue(settings.navigationBars[aboutLabel].waitForExistence(timeout: 5))
        attachScreen(settings, named: "settings-about-verified")
        // App termination ends this bounded driver; it does not alter a setting.
        settings.terminate()
    }

    func testExplicitExternalAppCaptureAndOptionalNavigation() throws {
        try requireDeviceOptIn()
        continueAfterFailure = false
        guard let bundleID = environment["MO_EXTERNAL_APP_BUNDLE_ID"], !bundleID.isEmpty else {
            throw XCTSkip("No external bundle identifier was explicitly configured.")
        }
        guard bundleID != "com.apple.Preferences", bundleID != "com.gibouu.morningoperator" else {
            throw XCTSkip("Use the dedicated Settings or fixture test for that app.")
        }
        let app = XCUIApplication(bundleIdentifier: bundleID)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try rejectUnexpectedPrompts(in: app)
        attachScreen(app, named: "external-before")

        guard let target = environment["MO_EXTERNAL_NAVIGATION_LABEL"], !target.isEmpty else {
            return // Capture-only is the default; opening never implies action authority.
        }
        // Deliberately finite: no arbitrary button names, coordinates, typing or send.
        let readOnlyNavigationLabels: Set<String> = ["Inbox", "All Inboxes", "Mailboxes", "Chats", "Messages", "Settings", "About"]
        guard readOnlyNavigationLabels.contains(target) else {
            XCTFail("The requested target is not a supported read-only navigation label.")
            return
        }
        guard let expected = environment["MO_EXTERNAL_EXPECTED_LABEL"], !expected.isEmpty else {
            XCTFail("Navigation requires an explicit new-screen postcondition.")
            return
        }
        XCTAssertFalse(exactElement(in: app, label: expected).exists,
                       "The postcondition already exists, so it cannot verify this navigation.")
        try tapFreshNavigation(in: app, label: target)
        try rejectUnexpectedPrompts(in: app)
        XCTAssertTrue(exactElement(in: app, label: expected).waitForExistence(timeout: 5),
                      "Expected navigation result did not appear; no retry is performed.")
        attachScreen(app, named: "external-after-verified")
    }

    func testMissingTargetDoesNotTriggerGesture() throws {
        try requireDeviceOptIn()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        // The executor must reject this target rather than fall back to coordinates.
        XCTAssertThrowsError(try tapFreshNavigation(in: settings, label: "morning-operator-missing-\(UUID().uuidString)"))
        attachScreen(settings, named: "missing-target-stopped-without-tap")
        settings.terminate()
    }

    private func requireDeviceOptIn() throws {
        guard environment["MO_DEVICE_TESTS_ENABLED"] == "1" else {
            throw XCTSkip("External-app tests require explicit device-test opt-in. Fixture tests remain available.")
        }
    }

    private func exactElement(in app: XCUIApplication, label: String) -> XCUIElement {
        // Prefer semantic controls; static text supports navigation rows in some apps.
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
        for query in [app.buttons, app.cells, app.staticTexts] {
            let candidates = query.matching(predicate)
            if candidates.count == 1 { return candidates.element(boundBy: 0) }
            if candidates.count > 1 {
                // An ambiguous match must never silently become a first-match tap.
                return app.otherElements["morning-operator-refused-ambiguous-target"]
            }
        }
        return app.otherElements["morning-operator-no-semantic-target"]
    }

    private func tapFreshNavigation(in app: XCUIApplication, label: String) throws {
        try rejectUnexpectedPrompts(in: app)
        guard app.state == .runningForeground else { throw DriverStop.appNotForeground }
        let capturedAt = Date()
        let target = exactElement(in: app, label: label)
        guard target.exists, target.isHittable else { throw DriverStop.missingOrUnhittableTarget }
        let observedFrame = target.frame
        // Re-query immediately before tapping; never retain a screenshot coordinate.
        let refreshed = exactElement(in: app, label: label)
        guard Date().timeIntervalSince(capturedAt) < 2,
              refreshed.exists, refreshed.isHittable,
              refreshed.frame == observedFrame,
              app.state == .runningForeground else { throw DriverStop.staleTarget }
        try rejectUnexpectedPrompts(in: app)
        refreshed.tap()
    }

    private func rejectUnexpectedPrompts(in app: XCUIApplication) throws {
        guard app.alerts.count == 0, app.sheets.count == 0 else { throw DriverStop.unexpectedPrompt }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard springboard.alerts.count == 0 else { throw DriverStop.unexpectedPrompt }
    }

    private func attachScreen(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if environment["MO_CAPTURE_UI_TREE"] == "1" {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "\(name)-accessibility-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
    }

    private enum DriverStop: Error {
        case appNotForeground, missingOrUnhittableTarget, staleTarget, unexpectedPrompt
    }
}
