#if MORE_JURY_DEMO
import XCTest

/// Isolated navigation only. These tests never start a morning, request an iOS
/// authorization, contact the jury backend, or simulate successful microphone use.
@MainActor
final class JuryDemoJourneyTests: XCTestCase {
    func testPreparedMorningUsesTheOrdinaryLandscapeAndSettings() throws {
        let app = try launchDemo()
        defer { app.terminate() }

        let landscape = app.buttons["morning.actions"]
        XCTAssertTrue(landscape.waitForExistence(timeout: 10))
        assertNoSpecialPresentation(app)
        XCTAssertFalse(app.buttons["morning.begin"].exists)
        XCTAssertFalse(app.buttons["morning.settings"].exists)
        XCTAssertEqual(app.navigationBars.count, 0)
        XCTAssertEqual(app.scrollViews.count, 0)

        landscape.tap()
        XCTAssertTrue(app.buttons["morning.settings"].waitForExistence(timeout: 5))
        let buttons = Set(app.buttons.allElementsBoundByIndex.map(\.identifier))
            .subtracting(["morning.actions"])
        XCTAssertEqual(buttons, ["morning.begin", "morning.settings"],
                       "The demo keeps the same two transient Home controls.")

        openSettings(app)
        let routine = app.buttons["setup.routine"]
        XCTAssertTrue(routine.waitForExistence(timeout: 5))
        routine.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "routine.editor")
            .firstMatch.waitForExistence(timeout: 5))
        for (index, title) in ["Mon réveil", "Mes messages", "Mon moment Instagram", "Prêt à partir"].enumerated() {
            let step = app.buttons["routine.step.\(index)"]
            reveal(step, in: app)
            XCTAssertTrue(step.label.contains(title), "The prepared moment stays in the normal routine editor.")
        }
        XCTAssertFalse(app.buttons["routine.step.4"].exists)
        XCTAssertFalse(app.buttons["morning.playback"].exists)
        XCTAssertFalse(app.staticTexts["morning.caption"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        assertNoSpecialPresentation(app)
    }

    func testListeningPreparationShowsRealStatusWithoutStartingMicrophone() throws {
        let app = try launchDemo()
        defer { app.terminate() }
        openSettings(app)
        let listening = app.buttons["setup.voiceAccess"]
        reveal(listening, in: app)
        XCTAssertTrue(listening.isEnabled)
        listening.tap()

        let status = app.staticTexts["voice.access.status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertFalse(status.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(app.buttons["voice.access.refresh"].exists)
        XCTAssertTrue(app.buttons["voice.access.close"].exists)
        XCTAssertFalse(app.staticTexts["voice.access.synthetic"].exists,
                       "Reading the device status must not claim simulated authorization or audio success.")
        XCTAssertFalse(app.buttons["voice.access.begin"].exists)
        XCTAssertFalse(app.buttons["voice.access.withoutListening"].exists)
        XCTAssertFalse(app.staticTexts["morning.caption"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Inspecting access must not request system grants.")

        app.buttons["voice.access.close"].tap()
        XCTAssertTrue(app.buttons["setup.voiceAccess"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["morning.stop"].exists, "No morning was started by visiting voice preparation.")
        assertNoSpecialPresentation(app)
    }

    private func launchDemo() throws -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let testBundle = Bundle(for: JuryDemoJourneyTests.self).bundleIdentifier ?? ""
        guard testBundle.hasSuffix(".uitests") else {
            throw NSError(domain: "JuryDemoJourneyTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The demo UI-test bundle identity is missing."])
        }
        let bundleID = String(testBundle.dropLast(".uitests".count))
        guard bundleID != "com.gibouu.morningoperator", bundleID.lowercased().split(separator: ".").contains("demo") else {
            throw NSError(domain: "JuryDemoJourneyTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Refusing to launch the ordinary MORE app."])
        }
        let workspace = UUID().uuidString
        let app = XCUIApplication(bundleIdentifier: bundleID)
        app.launchArguments = ["--ui-testing", "--ui-testing-empty-workspace",
            "--ui-testing-workspace=\(workspace)", "--ui-testing-reduce-motion", "--theme-phase=day",
            "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]
        app.launch()
        let isolation = app.staticTexts["qa.testWorkspace"]
        XCTAssertTrue(isolation.waitForExistence(timeout: 10), "The launch must use a disposable test workspace.")
        XCTAssertEqual(isolation.value as? String, workspace)
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["morning.settings"]
        if !settings.exists {
            let landscape = app.buttons["morning.actions"]
            XCTAssertTrue(landscape.waitForExistence(timeout: 10))
            landscape.tap()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.buttons["setup.routine"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !(element.exists && element.isHittable) {
            let collection = app.collectionViews.firstMatch
            let container = collection.exists ? collection : app.scrollViews.firstMatch
            XCTAssertTrue(container.exists)
            container.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func assertNoSpecialPresentation(_ app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts["system.qaIdentity"].exists)
        XCTAssertFalse(app.staticTexts["onboarding.heading"].exists)
        XCTAssertFalse(app.buttons["paywall.subscribe"].exists)
        XCTAssertFalse(app.buttons["paywall.restore"].exists)
        XCTAssertFalse(app.staticTexts["morning.currentStep"].exists)
        XCTAssertFalse(app.staticTexts["morning.remaining"].exists)
        XCTAssertFalse(app.staticTexts["morning.previousCaption"].exists)
    }
}
#endif
